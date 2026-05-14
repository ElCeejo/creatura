local movement_controller = {}
movement_controller.__index = movement_controller

-- Create new instance
function movement_controller:new(parent, spec)
	local parent_entity = parent and parent:get_luaentity()
	local pos = parent and parent:get_pos()
	local yaw = parent and parent:get_yaw()

	local new_controller = spec or {}

	-- No override
	new_controller.parent = parent
	new_controller.state = "idle"
	new_controller.target_pos = pos
	new_controller.target_yaw = yaw

	-- Defaults
	new_controller.speed = new_controller.speed or parent_entity.speed
	new_controller.can_jump_fences = parent_entity.can_jump_fences or false

	return setmetatable(new_controller, self)
end

local abs = math.abs
local min = math.min
local pi = math.pi
local sqrt = math.sqrt

local gravity = -9.8
local friction = 0.8

local function radians_difference_abs(a, b)
	return abs(math.atan2(math.sin(b - a), math.cos(b - a)))
end

local function interpolate_radians(a, b, w)
	local cs = (1 - w) * math.cos(a) + w * math.cos(b)
	local sn = (1 - w) * math.sin(a) + w * math.sin(b)
	return math.atan2(sn, cs)
end

-- Return parent objects luaentity
function movement_controller:parent_entity()
	return self.parent and self.parent:get_luaentity()
end

function movement_controller:get_parent_attribute(attribute)
	if type("attribute") ~= "string" then return end

	local parent = self.parent
	if not parent:is_valid() then return end

	if attribute == "yaw" then return parent:get_yaw() end
	if attribute == "pos" then return parent:get_pos() end
	if attribute == "vel" then return parent:get_velocity() end
	if attribute == "accel" then return parent:get_acceleration() end

	local entity = parent and parent:get_luaentity()
	if not entity then return end

	return entity[attribute]
end

-- Directly set velocity in current look dir
function movement_controller:set_forward_velocity(speed)
	local vel = self.current_vel
	local yaw = self.current_yaw

	vel.x = -math.sin(yaw) * speed
	vel.z = math.cos(yaw) * speed

	self.parent:set_velocity(vel)
end

function movement_controller:set_vertical_velocity(speed)
	local vel = self.parent:get_velocity()

	vel.y = speed

	self.parent:set_velocity(vel)
end

-- Set desired position and speed
function movement_controller:set_target(pos, speed)
	if self.state == "jump" then return end

	if type(pos) == "userdata" then pos = pos:get_pos() end
	self.target_pos = pos
	self.speed = speed or self.speed

	self.state = "move"
end

function movement_controller:set_look_target(pos)
	if type(pos) == "userdata" then pos = pos:get_pos() end
	self.look_target_pos = pos
end

function movement_controller:unset_look_target()
	self.look_target_pos = nil
end

-- Stop all movement
function movement_controller:stop()
	self.target_pos = self.parent:get_pos()
	self.target_yaw = self.parent:get_yaw()
	if self.state ~= "jump" then
		self.state = "idle"
	end
end

-- Jump at specified angles and power
function movement_controller:jump(_yaw, _pitch, power)
	if self.state == "jump" then return end
	local yaw = _yaw or self.parent:get_yaw()
	local vel = self.parent:get_velocity()

	local pitch = math.rad(_pitch or 60)
	local upward_power = math.sin(pitch) * (power or self.speed)
	local forward_power = math.cos(pitch) * (power or self.speed)

	self.parent:set_velocity({
		x = 0,
		y = vel.y,
		z = 0
	})
	self.parent:add_velocity({
		x = -math.sin(yaw) * forward_power,
		y = -gravity * math.sqrt(upward_power / -gravity),
		z = math.cos(yaw) * forward_power
	})
	self.state = "jump"
end

function movement_controller:check_for_jumpable_obstacle(yaw)
	local parent_entity = self:parent_entity()
	if not parent_entity.touching_ground then return false end

	local pos = self.parent:get_pos()
	local hitbox_edge = creatura.get_hitbox_edge(yaw, parent_entity.width)
	local obstacle_pos = {
		x = pos.x + hitbox_edge.x + -math.sin(yaw) * 0.2,
		y = pos.y + 0.01,
		z = pos.z + hitbox_edge.z + math.cos(yaw) * 0.2
	}

	if not self.can_jump_fences
	and creatura.is_fence(obstacle_pos) then
		return false
	end

	if creatura.is_walkable(obstacle_pos)
	and not creatura.is_walkable(vector.add(obstacle_pos, {x=0,y=1,z=0})) then
		return true
	end

	return false
end

function movement_controller:calculate_jump_power()
	local parent_entity = self:parent_entity()

	local mob_gravity = 9.8
	if parent_entity.physics_controller then
		mob_gravity = abs(parent_entity.physics_controller.gravity)
	end

	return mob_gravity * sqrt((parent_entity.jump_height) / mob_gravity)
end

-- Turn to specified angle
function movement_controller:turn(target_yaw)
	local yaw = target_yaw
	if type(target_yaw) ~= "number" then
		local target_pos = creatura.translate_to_position(target_yaw)

		yaw = minetest.dir_to_yaw(vector.direction(self.parent:get_pos(), target_pos))
	end

	self.target_yaw = yaw
end

-- Update all movement on every server-step
function movement_controller:update()
	local parent = self.parent
	local pos = parent:get_pos()
	local yaw = parent:get_yaw()
	local rot = parent:get_rotation()
	local vel = parent:get_velocity()
	if not pos then return end -- Early exit if parent is invalid

	local parent_entity = self:parent_entity()

	-- Cached for use in yaw/velocity calculation
	self.current_yaw = yaw
	self.current_vel = vel

	local target_yaw
	local target_vel

	-- Motion Driver info
	local driver_name = self:get_parent_attribute("motion_driver") or "creatura:default_walk_driver"
	local driver = creatura.registered_motion_drivers[driver_name]

	if not driver then return end -- TODO: Error?

	-- Moving
	if self.state == "jump" then
		if parent_entity.touching_ground
		and vel.y < 0.1 then
			self.state = "idle"
			vel.x = 0
			vel.z = 0
		end
	elseif self.state == "move" then
		target_vel = driver.calculate_velocity(self, parent_entity)
		if not self.look_target_pos then
			target_yaw =  driver.calculate_yaw(self, parent_entity)
		end

		if parent_entity.stepheight < 1.1
		and parent_entity.stepheight > 0
		and self:check_for_jumpable_obstacle(yaw) then
			self:jump(nil, nil, self:calculate_jump_power(parent_entity.jump_height))
			vel = parent:get_velocity()
			target_vel = nil
			target_yaw = nil
		end

		self.state = "idle"
	else
		self.state = "idle"

		if parent_entity.touching_ground then
			vel.x = vel.x * friction
			vel.z = vel.z * friction
		else
			vel.x = vel.x * 0.7
			vel.z = vel.z * 0.7

			--[[local accel = parent:get_acceleration()
			if accel and accel.y == 0 then
				vel.y = vel.y * 0.7
			end]]
		end
	end

	target_yaw = target_yaw or self.target_yaw

	-- Turning
	local yaw_diff = radians_difference_abs(yaw, target_yaw)
	if yaw_diff > 0.1 then
		local smooth_rate = min(
			parent_entity.dtime * parent_entity.turn_rate,
			yaw_diff % (pi * 2)
		)
		yaw = interpolate_radians(yaw, target_yaw, smooth_rate)
	end

	rot.y = yaw
	parent:set_velocity(target_vel or vel)
	parent:set_rotation(rot)
end

return movement_controller
