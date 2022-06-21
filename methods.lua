-------------
-- Methods --
-------------

local pi = math.pi
local abs = math.abs
local ceil = math.ceil
local floor = math.floor
local random = math.random
local rad = math.rad
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

local function vec_center(v)
	return {x = floor(v.x + 0.5), y = floor(v.y + 0.5), z = floor(v.z + 0.5)}
end

local vec_dir = vector.direction
local vec_multi = vector.multiply
local vec_add = vector.add
local yaw2dir = minetest.yaw_to_dir
local dir2yaw = minetest.dir_to_yaw

local function debugpart(pos, time, tex)
	minetest.add_particle({
		pos = pos,
		texture = tex or "creatura_particle_red.png",
		expirationtime = time or 3,
		glow = 6,
		size = 12
	})
end

---------------------
-- Local Utilities --
---------------------

local function get_collision(self, yaw)
	local width = self.width
	local height = self.height
	local pos = self.object:get_pos()
	pos.y = pos.y + 1
	local pos2 = vec_add(pos, vec_multi(yaw2dir(yaw), width + 5))
	for x = -width, width, width / ceil(width) do
		for y = 0, height, height / ceil(height) do
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
			local ray = minetest.raycast(vec1, vec2, false, true)
			for pointed_thing in ray do
				if pointed_thing
				and pointed_thing.type == "node" then
					return true, pointed_thing.intersection_point
				end
			end
		end
	end
	return false
end

local function get_obstacle_avoidance(self, goal)
	local width = self.width
	local height = self.height
	local pos = self.object:get_pos()
	pos.y = pos.y + 1
	local yaw2goal = dir2yaw(vec_dir(pos, goal))
	local collide, col_pos = get_collision(self, yaw2goal)
	if not collide then return end
	local avd_pos
	for i = 45, 180, 45 do
		local angle = rad(i)
		local dir = vec_multi(yaw2dir(yaw2goal + angle), width)
		avd_pos = vec_center(vec_add(pos, dir))
		if not get_collision(self, yaw2goal) then
			break
		end
		angle = -rad(i)
		dir = vec_multi(yaw2dir(yaw2goal + angle), width)
		avd_pos = vec_center(vec_add(pos, dir))
		if not get_collision(self, yaw2goal) then
			break
		end
	end
	return avd_pos
end

-------------
-- Actions --
-------------

-- Actions are more specific behaviors used
-- to compose a Utility.

-- Walk

function creatura.action_move(self, pos2, timeout, method, speed_factor, anim)
	local timer = timeout or 4
	local function func(_self)
		timer = timer - _self.dtime
		self:animate(anim or "walk")
		if timer <= 0
		or _self:move_to(pos2, method or "creatura:obstacle_avoidance", speed_factor or 0.5) then
			return true
		end
	end
	self:set_action(func)
end

creatura.action_walk = creatura.action_move

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

creatura.register_movement_method("creatura:pathfind", function(self, goal)
	local path = {}
	local waypoint
	local tick = 0.15
	local box = clamp(self.width, 0.5, 1)
	self:set_gravity(-9.8)
	local function func(self)
		local pos = self.object:get_pos()
		if not pos then return end
		-- Return true when goal is reached
		if self:pos_in_box(goal, box) then
			self:halt()
			return true
		end
		tick = tick - self.dtime
		if tick <= 0 then
			if not waypoint
			or self:pos_in_box({x = waypoint.x, y = pos.y + box * 0.5, z = waypoint.z}, box) then
				-- Waypoint Y axis is raised to avoid large mobs spinning over downward slopes
				waypoint = get_obstacle_avoidance(self, goal)
			end
			tick = 0.15
		end
		-- Get movement direction
		local goal_dir = vec_dir(pos, goal)
		if waypoint then
			-- There's an obstruction, time to find a path
			if #path < 2 then
				path = creatura.find_path(self, pos, goal, self.width, self.height, 200) or {}
			else
				waypoint = path[2]
				if self:pos_in_box(path[1], box) then
					table.remove(path, 1)
				end
			end
			goal_dir = vec_dir(pos, waypoint)
			debugpart(waypoint)
		end
		local yaw = self.object:get_yaw()
		local goal_yaw = dir2yaw(goal_dir)
		local speed = abs(self.speed or 2)
		local turn_rate = abs(self.turn_rate or 5)
		-- Movement
		local yaw_diff = abs(diff(yaw, goal_yaw))
		if yaw_diff < pi * 0.25 then
			self:set_forward_velocity(speed)
		else
			self:set_forward_velocity(speed * 0.5)
			turn_rate = turn_rate * 1.5
		end
		if yaw_diff > 0.1 then
			self:turn_to(goal_yaw, turn_rate)
		end
	end
	return func
end)

creatura.register_movement_method("creatura:theta_pathfind", function(self, goal)
	local path = {}
	local waypoint
	local tick = 0.15
	local box = clamp(self.width, 0.5, 1)
	self:set_gravity(-9.8)
	local function func(self)
		local pos = self.object:get_pos()
		if not pos then return end
		tick = tick - self.dtime
		if tick <= 0 then
			if not waypoint
			or self:pos_in_box({x = waypoint.x, y = pos.y + self.height * 0.5, z = waypoint.z}, box) then
				-- Waypoint Y axis is raised to avoid large mobs spinning over downward slopes
				waypoint = get_obstacle_avoidance(self, goal)
			end
			tick = 0.15
		end
		-- Get movement direction
		local goal_dir = vec_dir(pos, goal)
		if waypoint then
			-- There's an obstruction, time to find a path
			if #path < 1 then
				path = creatura.find_path(self, pos, goal, self.width, self.height, 300) or {}
			else
				waypoint = path[2] or path[1]
			end
			goal_dir = vec_dir(pos, waypoint)
		end
		local yaw = self.object:get_yaw()
		local goal_yaw = dir2yaw(goal_dir)
		if abs(yaw - goal_yaw) > 0.1 then
			self:turn_to(goal_yaw, self.turn_rate or 6)
		end
		-- Set Velocity
		self:set_forward_velocity(self.speed or 2)
		-- Return true when goal is reached
		if self:pos_in_box(goal, box) then
			self:halt()
			return true
		end
	end
	return func
end)

-- Obstacle Avoidance

creatura.register_movement_method("creatura:obstacle_avoidance", function(self, goal)
	local waypoint
	local tick = 0.15
	local box = clamp(self.width, 0.5, 1)
	self:set_gravity(-9.8)
	local function func(self)
		local pos = self.object:get_pos()
		if not pos then return end
		tick = tick - self.dtime
		if tick <= 0 then
			if not waypoint
			or self:pos_in_box({x = waypoint.x, y = pos.y + self.height * 0.5, z = waypoint.z}, box) then
				-- Waypoint Y axis is raised to avoid large mobs spinning over downward slopes
				waypoint = get_obstacle_avoidance(self, goal)
			end
			tick = 0.15
		end
		-- Get movement direction
		local goal_dir = vec_dir(pos, goal)
		if waypoint then
			goal_dir = vec_dir(pos, waypoint)
		end
		local yaw = self.object:get_yaw()
		local goal_yaw = dir2yaw(goal_dir)
		if abs(yaw - goal_yaw) > 0.1 then
			self:turn_to(goal_yaw, self.turn_rate or 6)
		end
		-- Set Velocity
		self:set_forward_velocity(self.speed or 2)
		-- Return true when goal is reached
		if self:pos_in_box(goal, box) then
			self:halt()
			return true
		end
	end
	return func
end)