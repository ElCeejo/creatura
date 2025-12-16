local movement_controller = {}
movement_controller.__index = movement_controller

local boid_handler = dofile(creatura.path_subclass .. "/boid_handler.lua")

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
	new_controller.movement_type = new_controller.movement_type or "ground"
	new_controller.speed = new_controller.speed or parent_entity.speed

	return setmetatable(new_controller, movement_controller)
end

local abs = math.abs
local min = math.min
local pi = math.pi

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

local function lerp(a, b, t)
	return a + (b - a) * t
end

local function get_yaw_to_pos(pos1, pos2)
	local x = pos2.x - pos1.x
	local z = pos2.z - pos1.z
	return math.atan2(z, x) - pi / 2
end

-- Return parent objects luaentity
function movement_controller:parent_entity()
	return self.parent and self.parent:get_luaentity()
end

function movement_controller:initiate_boids()
	self.is_boid = true
	self.boid_handler = boid_handler:new(self.parent)
end

-- Directly set velocity in current look dir
function movement_controller:set_forward_velocity(speed)
	local vel = self.current_vel
	local yaw = self.current_yaw

	vel.x = -math.sin(yaw) * speed
	vel.z = math.cos(yaw) * speed

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

	local pitch = math.rad(_pitch)
	local upward_power = math.sin(pitch) * power
	local forward_power = math.cos(pitch) * power

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

-- Turn to specified angle
function movement_controller:turn(target_yaw)
	self.target_yaw = target_yaw
end

-- Default movement calculation
function movement_controller:ground_move(obj, tgt_pos, sp)
	local target_pos = tgt_pos or self.target_pos
	local speed = sp or self.speed

	local entity = obj:get_luaentity()
	local pos = obj:get_pos()
	local yaw = self.current_yaw
	local vel = self.current_vel
	local target_yaw = get_yaw_to_pos(pos, target_pos)

	local yaw_diff = math.max(0, radians_difference_abs(yaw, target_yaw) - (entity.turn_rate * entity.dtime))
	--local speed_mod = lerp(math.cos(yaw_diff), 1, 0.1)
	local speed_mod = math.max(0, math.cos(yaw_diff)) -- Slow down when facing away from target

	vel.x = -math.sin(yaw) * speed * speed_mod
	vel.z = math.cos(yaw) * speed * speed_mod

	return vel, target_yaw
end

function movement_controller:flying_move(obj, tgt_pos, sp)
	local target_pos = tgt_pos or self.target_pos
	local speed = sp or self.speed

	local entity = obj:get_luaentity()
	local pos = obj:get_pos()
	local yaw = self.current_yaw
	local vel = self.current_vel

	local target_dir = vector.normalize(vector.direction(pos, target_pos))
	local target_yaw = get_yaw_to_pos(pos, target_pos)

	local yaw_diff = radians_difference_abs(yaw, target_yaw)
	local speed_mod = math.max(0.2, math.cos(yaw_diff))

	if self.is_boid then
		target_dir = vector.add(target_dir, self.boid_handler:get_direction())
	end

	local desired_vel = {
		x = target_dir.x * speed * speed_mod,
		y = target_dir.y * speed * 0.7,
		z = target_dir.z * speed * speed_mod,
	}

	vel.x = lerp(vel.x, desired_vel.x, 0.5)
	vel.y = lerp(vel.y, desired_vel.y, 0.5)
	vel.z = lerp(vel.z, desired_vel.z, 0.5)

	if entity.in_liquid then
		entity.physics_controller:enable_gravity()
		vel.x = vel.x * 0.5
		vel.y = 1
		vel.z = vel.z * 0.5
	else
		entity.physics_controller:disable_gravity()
	end

	return vel, target_yaw
end

function movement_controller:swimming_move(obj, tgt_pos, sp)
	local target_pos = tgt_pos or self.target_pos
	local speed = sp or self.speed

	local entity = obj:get_luaentity()
	local pos = obj:get_pos()
	local yaw = self.current_yaw
	local vel = self.current_vel
	local target_dir = vector.direction(pos, target_pos)
	local target_yaw = get_yaw_to_pos(pos, target_pos)

	local yaw_diff = radians_difference_abs(yaw, target_yaw)
	local speed_mod = math.max(0.6, math.cos(yaw_diff))

	if self.is_boid then
		local boid_dir = self.boid_handler:get_direction()
		if vector.length(boid_dir) ~= 0 then
			target_dir = vector.divide(vector.add(target_dir, boid_dir), 2)
			target_yaw = minetest.dir_to_yaw(target_dir)
		end
	end

	vel.z = math.cos(yaw) * speed * speed_mod
	vel.y = target_dir.y * speed * speed_mod
	vel.x = -math.sin(yaw) * speed * speed_mod

	if entity.physics_controller then
		if entity.in_liquid then
			entity.physics_controller:disable_gravity()
		else
			entity.physics_controller:enable_gravity()
			vel.x = vel.x * 0.5
			vel.y = -1
			vel.z = vel.z * 0.5
		end
	end

	return vel, target_yaw
end

function movement_controller:move(object, target_pos, speed)
	if self.movement_type == "ground" then
		return self:ground_move(object, target_pos, speed)
	elseif self.movement_type == "fly" then
		return self:flying_move(object, target_pos, speed)
	elseif self.movement_type == "swim" then
		return self:swimming_move(object, target_pos, speed)
	end
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

	-- Cached for use in self:move
	self.current_yaw = yaw
	self.current_vel = vel

	local target_yaw
	local target_vel

	-- Moving
	if self.state == "jump" then
		if parent_entity.touching_ground
		and vel.y < 0.1 then
			self.state = "idle"
			vel.x = 0
			vel.y = (self.is_flying and 0) or vel.y
			vel.z = 0
		end
	elseif self.state == "move" then
		target_vel, target_yaw = self:move(self.parent, self.target_pos, self.speed)

		self.state = "idle"
		--entity:add_diagnostic("target_yaw", target_yaw)
	else
		self.state = "idle"

		if parent_entity.touching_ground then
			vel.x = vel.x * friction
			vel.y = vel.y
			vel.z = vel.z * friction
		elseif self.movement_type == "fly" then
			vel.x = vel.x * 0.7
			vel.y = vel.y * 0.7
			vel.z = vel.z * 0.7
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
