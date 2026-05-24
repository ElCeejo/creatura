---------------
-- Traversal --
---------------

-- Math

local abs = math.abs
local min = math.min
local pi = math.pi
local sqrt = math.sqrt

local function radians_difference_abs(a, b)
	return abs(math.atan2(math.sin(b - a), math.cos(b - a)))
end

local function interpolate_radians(a, b, w)
	local cs = (1 - w) * math.cos(a) + w * math.cos(b)
	local sn = (1 - w) * math.sin(a) + w * math.sin(b)
	return math.atan2(sn, cs)
end

-- Traversal Class

local gravity = -9.8

local traversal = {}
traversal.__index = traversal

-- Initiate a new traversal agent

function traversal:initiate(entity)
	entity.traversal = {
		entity = entity,
		current_pos = entity.object:get_pos(),
		target_pos = vector.zero(),
		move_dir = vector.zero(),

		is_walking = false,
		is_running = false,
		is_strafing = false,
		is_pathfinding = false,
		is_jumping = false,
		is_stepping = false,
		is_flying = false,

		motion_timer = 0.125,
		step_up_timer = 0.425
	}

	-- Speed
	local walk_speed = entity.walk_speed or (entity.speed / 2)
	local run_speed = entity.run_speed or entity.speed
	entity.traversal.walk_speed = walk_speed
	entity.traversal.run_speed = run_speed

	setmetatable(entity.traversal, self)
end

-- Get variables from parent mob

function traversal:get_parent_attribute(attribute)
	if type("attribute") ~= "string" then return end

	local object = self.entity.object
	if not object:is_valid() then return end

	if attribute == "yaw" then return object:get_yaw() end
	if attribute == "pos" then return object:get_pos() end
	if attribute == "vel" then return object:get_velocity() end
	if attribute == "accel" then return object:get_acceleration() end

	return self.entity[attribute]
end

-- Switch to flying state

function traversal:set_flying(bool)
	self.is_flying = (bool ~= nil and bool) or true
end

-- Get speeds

function traversal:set_walk_speed(speed)
	if type(speed) ~= "number" then return end

	self.walk_speed = speed
end

function traversal:get_walk_speed()
	return self.walk_speed or self:get_parent_attribute("speed") / 2
end

function traversal:set_run_speed(speed)
	if type(speed) ~= "number" then return end

	self.run_speed = speed
end

function traversal:get_run_speed()
	return self.run_speed or self:get_parent_attribute("speed")
end

function traversal:get_speed()
	if self.is_walking then return self:get_walk_speed() end
	if self.is_running then return self:get_run_speed() end

	return 0
end

-- Move directly forward

function traversal:walk_forward()
	self:stop()

	local yaw = self.current_yaw
	local dir = {
		x = -math.sin(yaw),
		y = 0,
		z = math.cos(yaw)
	}

	self.is_walking = true
	self.move_dir = dir
end

function traversal:run_forward()
	self:stop()

	local yaw = self.current_yaw
	local dir = {
		x = -math.sin(yaw),
		y = 0,
		z = math.cos(yaw)
	}

	self.is_running = true
	self.move_dir = dir
end

-- Move in specified direction

function traversal:walk_in_direction(dir)
	self:stop()

	self.is_walking = true
	self.move_dir = dir
end

function traversal:run_in_direction(dir)
	self:stop()

	self.is_running = true
	self.move_dir = dir
end

-- Walk to specified position

function traversal:walk_to_pos(pos)
	self:stop()

	self.is_walking = true
	self.target_pos = pos
end

function traversal:run_to_pos(pos)
	self:stop()

	self.is_running = true
	self.target_pos = pos
end

-- Find a path to specified position and follow it

function traversal:walk_along_path(pos, pathfinder)
	self:stop()

	self.target_pos = pos
	self.is_pathfinding = true
	self.current_pathfinder = pathfinder or creatura.find_path
	self.is_walking = true
end

function traversal:run_along_path(pos, pathfinder)
	self:stop()

	self.target_pos = pos
	self.is_pathfinding = true
	self.current_pathfinder = pathfinder or creatura.find_path
	self.is_running = true
end

-- Jump

function traversal:jump(target_yaw, target_pitch, power)
	if self.is_jumping then return end
	local yaw = target_yaw or self:get_parent_attribute("yaw")
	local vel = self:get_parent_attribute("vel")

	local pitch = math.rad(target_pitch or 60)
	local upward_power = math.sin(pitch) * (power or self:get_speed())
	local forward_power = math.cos(pitch) * (power or self:get_speed())

	self.entity.object:set_velocity({
		x = 0,
		y = vel.y,
		z = 0
	})
	self.entity.object:add_velocity({
		x = -math.sin(yaw) * forward_power,
		y = -gravity * math.sqrt(upward_power / -gravity),
		z = math.cos(yaw) * forward_power
	})
	self.is_jumping = true
end

-- Set target (mob, position) to face towards constantly

function traversal:set_strafe_target(target)
	if not target then return end
	if type(target) == "userdata" then
		self.is_strafing = true
		self.strafe_pos = target:get_pos()
		self.strafe_target = target
	elseif type(target) ~= "table" then
		return
	end

	self.is_strafing = true
	self.strafe_pos = target
end

function traversal:get_strafe_pos()
	local target = self.strafe_target
	if target
	and type(target) == "userdata" then
		self.strafe_pos = self.strafe_target:get_pos()
	end

	return self.strafe_pos
end

-- Stop all processes

function traversal:stop()
	self.target_pos = vector.new()
	self.move_dir = vector.new()
	self.next_pos = nil
	self.path = nil
	self.current_pathfinder = nil

	self.is_walking = false
	self.is_running = false
	--self.is_strafing = false
	self.is_pathfinding = false
	self.is_jumping = false
end

-- Check if traversal is currently active

function traversal:is_active()
	return self.is_walking or self.is_running or false
end

-- Process movement via motion drivers

function traversal:get_driver()
	local driver = self:get_parent_attribute("motion_driver") or "creatura:default_walk_driver"

	return creatura.registered_motion_drivers[driver]
end

function traversal:update_driver(target_pos, target_dir)
	local driver = self:get_driver()
	local output_velocity = driver.calculate_velocity(self, self.entity, target_pos, target_dir)
	local output_yaw
	if not self.is_strafing then
		output_yaw = driver.calculate_yaw(self, self.entity, target_pos, target_dir)
	end
	return output_velocity, output_yaw
end

-- Quick squared dist check for arrival

function traversal:has_reached_pos(target_pos)
	local pos = self.current_pos
	local diff_x = target_pos.x - pos.x
	local diff_y = target_pos.y - pos.y
	local diff_z = target_pos.z - pos.z
	local squared_dist = (diff_x * diff_x) + (diff_z * diff_z) + (diff_y * diff_y)

	return squared_dist <= 0.5
end

-- Step up nodes in front of mob

function traversal:check_for_steps()
	if self.is_stepping then return end

	local max_step_level = math.floor(self.current_pos.y + 0.5) + 0.4

	local moveresult = self.entity.moveresult
	if moveresult.touching_ground
	and moveresult.collides then
		for _, collide in ipairs(moveresult.collisions) do
			if collide.node_pos
			and collide.axis ~= "y"
			and collide.node_pos.y < max_step_level then
				-- Get dot product
				local dir = vector.direction(self.current_pos, collide.node_pos):normalize()
				local heading = vector.normalize({x = -math.sin(self.current_yaw), y = 0, z = math.cos(self.current_yaw)})
				local dot = vector.dot(heading, dir)

				-- check if node is within forward plane
				if dot > 0.49 then
					-- begin stepping
					self.is_stepping = true
					self.step_start = self.current_pos.y
				end
			end
		end
	end
end

function traversal:step_up_node(dtime)
	self.step_up_timer = (self.step_up_timer or 0) - dtime
	if self.step_up_timer <= 0 then
		self:check_for_steps()
		self.step_up_timer = 0.4
	end

	if self.step_start then
		local vel = self.current_vel
		local diff = self.current_pos.y - self.step_start

		if diff > self.entity.jump_height
		or diff < 0 then
			self.is_stepping = false
			self.step_start = nil
			vel.y = 0
		else
			vel.y = 9.8 * sqrt((self.entity.jump_height) / 9.8)
		end

		self.entity.object:set_velocity(vel)
	end
end

-- Update every server step

function traversal:on_step(dtime)
	local pos = self.entity.object:get_pos()
	local rotation = self.entity.object:get_rotation()
	local velocity = self.entity.object:get_velocity()
	local yaw = self.entity.object:get_yaw()

	self.current_pos = pos
	self.current_vel = velocity
	self.current_yaw = yaw

	local target_yaw = yaw

	--self:get_step()
	local step_height = self:get_parent_attribute("stepheight") or 0
	if step_height < 1.1
	and step_height > 0 then
		self:step_up_node(dtime)
	end

	if self:is_active() then
		local goal = self.target_pos -- Move directly toward target

		if self.is_pathfinding then
			if not self.path or #self.path < 1 then
				local find_path = self.current_pathfinder
				self.path = find_path(self.entity, goal)
			end

			if self.path and #self.path > 1 then
				goal = self.path[1]
			end
		end

		self.motion_timer = (self.motion_timer or 0) - dtime
		if self.motion_timer <= 0 then
			if self:has_reached_pos(goal) then
				if self.path and self.path[1] then
					table.remove(self.path, 1)
					if self.path[1] then
						goal = self.path[1]
					else
						self:stop()
						goal = nil
					end
				else
					self:stop()
					goal = nil
				end
			end

			if goal then
				local move_dir = self.move_dir
				if vector.length(move_dir) == 0 then
					move_dir = nil
				elseif vector.length(goal) == 0 then
					goal = nil
				end
				velocity, target_yaw = self:update_driver(goal, move_dir)
			end
			self.motion_timer = 0.125
			dtime = 0.125
		end
	elseif self.entity.touching_ground then
		velocity.x, velocity.z = velocity.x * 0.4, velocity.z * 0.4
	end

	if self.is_jumping
	and self:get_parent_attribute("touching_ground") then
		self.is_jumping = false
	end

	-- Strafing
	if self.is_strafing then
		local strafe_pos = self:get_strafe_pos()
		if strafe_pos then
			local target_dir = vector.direction(pos, strafe_pos)
			target_yaw = math.atan2(-target_dir.x, target_dir.z)
		end
	end

	-- Calculate turning
	local yaw_diff = radians_difference_abs(yaw, target_yaw or yaw)
	if yaw_diff > 0.1 then
		local smooth_rate = min(dtime * self.entity.turn_rate, yaw_diff % (pi * 2))
		yaw = interpolate_radians(yaw, target_yaw, smooth_rate)
	end
	rotation.y = yaw

	-- Apply velocity and turning
	self.entity.object:set_velocity(velocity)
	self.entity.object:set_rotation(rotation)
end

return traversal
