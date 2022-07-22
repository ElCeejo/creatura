-------------
-- Methods --
-------------

local pi = math.pi
local abs = math.abs
local ceil = math.ceil
local random = math.random
local atan2 = math.atan2
local sin = math.sin
local cos = math.cos

local function diff(a, b) -- Get difference between 2 angles
	return atan2(sin(b - a), cos(b - a))
end

local function clamp(val, min, max)
	if val < min then
		val = min
	elseif max < val then
		val = max
	end
	return val
end

local vec_dist = vector.distance
local vec_dir = vector.direction
local vec_multi = vector.multiply
local vec_add = vector.add
local yaw2dir = minetest.yaw_to_dir
local dir2yaw = minetest.dir_to_yaw

local function vec_raise(v, n)
	if not v then return end
	return {x = v.x, y = v.y + n, z = v.z}
end

--[[local function debugpart(pos, time, tex)
	minetest.add_particle({
		pos = pos,
		texture = tex or "creatura_particle_red.png",
		expirationtime = time or 3,
		glow = 6,
		size = 12
	})
end]]

---------------------
-- Local Utilities --
---------------------

local function raycast(pos1, pos2, liquid)
	local ray = minetest.raycast(pos1, pos2, false, liquid or false)
	local col = ray:next()
	while col do
		if col.type == "node"
		and creatura.get_node_def(col.under).walkable then
			return col
		end
		col = ray:next()
	end
end

local function get_collision(self, yaw)
	local width = self.width
	local height = self.height
	local total_height = height + self.stepheight
	local pos = self.object:get_pos()
	if not pos then return end
	local ground = creatura.get_ground_level(pos, (self.stepheight or 2))
	if ground.y > pos.y then
		pos = ground
	end
	local pos2 = vec_add(pos, vec_multi(yaw2dir(yaw), width + 3))
	ground = creatura.get_ground_level(pos2, (self.stepheight or 2))
	if ground.y > pos2.y then
		pos2 = ground
	end
	for x = -width, width, width / ceil(width) do
		local step_flag = false
		for y = 0, total_height, total_height / ceil(total_height) do
			if y > height
			and not step_flag then -- if we don't have to step up, no need to check if step is clear
				break
			end
			local vec1 = {
				x = cos(yaw) * ((pos.x + x) - pos.x) + pos.x,
				y = pos.y + y,
				z = sin(yaw) * ((pos.x + x) - pos.x) + pos.z
			}
			local vec2 = {
				x = cos(yaw) * ((pos2.x + x) - pos2.x) + pos2.x,
				y = vec1.y,
				z = sin(yaw) * ((pos2.x + x) - pos2.x) + pos2.z
			}
			local ray = raycast(vec1, vec2, true)
			if ray then
				if y > (self.stepheight or 1.1)
				or y > height then
					return true, ray.intersection_point
				else
					step_flag = true
				end
			end
		end
	end
	return false
end

local function get_avoidance_dir(self)
	local pos = self.object:get_pos()
	if not pos then return end
	local collide, col_pos = get_collision(self, self.object:get_yaw())
	if collide then
		local avoid_dir = vec_dir(col_pos, pos)
		return vec_multi(avoid_dir, self.width)
	end
end

-------------
-- Actions --
-------------

-- Actions are more specific behaviors used
-- to compose a Utility.

-- Move

function creatura.action_move(self, pos2, timeout, method, speed_factor, anim)
	local timer = timeout or 4
	local function func(_self)
		timer = timer - _self.dtime
		self:animate(anim or "walk")
		local safe = true
		if _self.max_fall
		and _self.max_fall > 0 then
			local pos = self.object:get_pos()
			if not pos then return end
			safe = _self:is_pos_safe(pos2)
		end
		if timer <= 0
		or not safe
		or _self:move_to(pos2, method or "creatura:obstacle_avoidance", speed_factor or 0.5) then
			return true
		end
	end
	self:set_action(func)
end

creatura.action_walk = creatura.action_move -- Support for outdated versions

-- Idle

function creatura.action_idle(self, time, anim)
	local timer = time
	local function func(_self)
		_self:set_gravity(-9.8)
		_self:halt()
		_self:animate(anim or "stand")
		timer = timer - _self.dtime
		if timer <= 0 then
			return true
		end
	end
	self:set_action(func)
end

-- Rotate on Z axis in random direction until 90 degree angle is reached

function creatura.action_fallover(self)
	local zrot = 0
	local init = false
	local dir = 1
	local function func(_self)
		if not init then
			_self:animate("stand")
			if random(2) < 2 then
				dir = -1
			end
			init = true
		end
		local rot = _self.object:get_rotation()
		local goal = (pi * 0.5) * dir
		local dif = abs(rot.z - goal)
		zrot = rot.z + (dif * dir) * 0.15
		_self.object:set_rotation({x = rot.x, y = rot.y, z = zrot})
		if (dir > 0 and zrot >= goal)
		or (dir < 0 and zrot <= goal) then return true end
	end
	self:set_action(func)
end

----------------------
-- Movement Methods --
----------------------

-- Pathfinding

creatura.register_movement_method("creatura:pathfind", function(self)
	local path = {}
	local box = clamp(self.width, 0.5, 1.5)
	self:set_gravity(-9.8)
	local function func(_self, goal, speed_factor)
		local pos = _self.object:get_pos()
		if not pos then return end
		pos.y = pos.y + 0.5
		-- Return true when goal is reached
		if vec_dist(pos, goal) < box * 1.33 then
			_self:halt()
			return true
		end
		-- Get movement direction
		local steer_to = get_avoidance_dir(_self, goal, speed_factor)
		local goal_dir = vec_dir(pos, goal)
		if steer_to then
			goal_dir = steer_to
			if #path < 2 then
				path = creatura.find_path(_self, pos, goal, _self.width, _self.height, 200) or {}
			end
		end
		if #path > 1 then
			goal_dir = vec_dir(pos, path[2])
			if vec_dist(pos, path[1]) < box then
				table.remove(path, 1)
			end
		end
		local yaw = _self.object:get_yaw()
		local goal_yaw = dir2yaw(goal_dir)
		local speed = abs(_self.speed or 2) * speed_factor or 0.5
		local turn_rate = abs(_self.turn_rate or 5)
		-- Movement
		local yaw_diff = abs(diff(yaw, goal_yaw))
		if yaw_diff < pi * 0.25
		or steer_to then
			_self:set_forward_velocity(speed)
		else
			_self:set_forward_velocity(speed * 0.33)
		end
		if yaw_diff > 0.1 then
			_self:turn_to(goal_yaw, turn_rate)
		end
	end
	return func
end)

creatura.register_movement_method("creatura:theta_pathfind", function(self)
	local path = {}
	local box = clamp(self.width, 0.5, 1.5)
	self:set_gravity(-9.8)
	local function func(_self, goal, speed_factor)
		local pos = _self.object:get_pos()
		if not pos then return end
		pos.y = pos.y + 0.5
		-- Return true when goal is reached
		if vec_dist(pos, goal) < box * 1.33 then
			_self:halt()
			return true
		end
		-- Get movement direction
		local steer_to = get_avoidance_dir(_self, goal)
		local goal_dir = vec_dir(pos, goal)
		if steer_to then
			goal_dir = steer_to
			if #path < 1 then
				path = creatura.find_theta_path(_self, pos, goal, _self.width, _self.height, 300) or {}
			end
		end
		if #path > 0 then
			goal_dir = vec_dir(pos, path[2] or path[1])
			if vec_dist(pos, path[1]) < box then
				table.remove(path, 1)
			end
		end
		local yaw = _self.object:get_yaw()
		local goal_yaw = dir2yaw(goal_dir)
		local speed = abs(_self.speed or 2) * speed_factor or 0.5
		local turn_rate = abs(_self.turn_rate or 5)
		-- Movement
		local yaw_diff = abs(diff(yaw, goal_yaw))
		if yaw_diff < pi * 0.25
		or steer_to then
			_self:set_forward_velocity(speed)
		else
			_self:set_forward_velocity(speed * 0.33)
		end
		if yaw_diff > 0.1 then
			_self:turn_to(goal_yaw, turn_rate)
		end
	end
	return func
end)

-- Obstacle Avoidance

creatura.register_movement_method("creatura:obstacle_avoidance", function(self)
	local box = clamp(self.width, 0.5, 1.5)
	self:set_gravity(-9.8)
	local function func(_self, goal, speed_factor)
		local pos = _self.object:get_pos()
		if not pos then return end
		goal.y = creatura.get_ground_level(goal, 2).y
		pos.y = creatura.get_ground_level(pos, 2).y
		-- Return true when goal is reached
		if vec_dist(pos, goal) < box * 1.33 then
			_self:halt()
			return true
		end
		local steer_to = get_avoidance_dir(_self, goal)
		-- Get movement direction
		local goal_dir = vec_dir(pos, goal)
		if steer_to then
			goal_dir = steer_to
		end
		local yaw = _self.object:get_yaw()
		local goal_yaw = dir2yaw(goal_dir)
		local speed = abs(_self.speed or 2) * speed_factor or 0.5
		local turn_rate = abs(_self.turn_rate or 5)
		-- Movement
		local yaw_diff = abs(diff(yaw, goal_yaw))
		if yaw_diff < pi * 0.25
		or steer_to then
			_self:set_forward_velocity(speed)
		else
			_self:set_forward_velocity(speed * 0.33)
		end
		if yaw_diff > 0.1 then
			_self:turn_to(goal_yaw, turn_rate)
		end
	end
	return func
end)