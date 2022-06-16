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

-------------
-- Actions --
-------------

-- Actions are more specific behaviors used
-- to compose a Utility.

-- Walk

function creatura.action_walk(self, pos2, timeout, method, speed_factor, anim)
	local timer = timeout or 4
	local move_init = false
	local function func(_self)
		if not pos2
		or (move_init
		and not _self._movement_data.goal) then return true end
		local pos = _self.object:get_pos()
		timer = timer - _self.dtime
		if timer <= 0
		or _self:pos_in_box({x = pos2.x, y = pos.y + 0.1, z = pos2.z}) then
			_self:halt()
			return true
		end
		_self:move(pos2, method or "creatura:neighbors", speed_factor or 0.5, anim)
		move_init = true
	end
	self:set_action(func)
end

function creatura.action_fly(self, pos2, timeout, method, speed_factor, anim)
	local timer = timeout or 4
	local move_init = false
	local function func(_self)
		if not pos2
		or (move_init
		and not _self._movement_data.goal) then return true end
		timer = timer - _self.dtime
		if timer <= 0
		or _self:pos_in_box(pos2) then
			_self:halt()
			return true
		end
		_self:move(pos2, method, speed_factor or 0.5, anim)
		move_init = true
	end
	self:set_action(func)
end

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

creatura.register_movement_method("creatura:pathfind", function(self, pos2)
	-- Movement Data
	local pos = self.object:get_pos()
	local movement_data = self._movement_data
	local waypoint = movement_data.waypoint
	local speed = movement_data.speed or 5
	local path = self._path
	if not path or #path < 2 then
		if get_collision(self, dir2yaw(vec_dir(pos, pos2))) then
			self._path = creatura.find_path(self, pos, pos2, self.width, self.height, 200) or {}
		end
	else
		waypoint = self._path[2]
		if self:pos_in_box({x = waypoint.x, y = pos.y + self.height * 0.5, z = waypoint.z}) then
			-- Waypoint Y axis is raised to avoid large mobs spinning over downward slopes
			table.remove(self._path, 1)
		end
	end
	if not waypoint
	or self:pos_in_box({x = waypoint.x, y = pos.y + self.height * 0.5, z = waypoint.z}) then
		waypoint = creatura.get_next_move(self, pos2)
		self._movement_data.waypoint = waypoint
	end
	-- Turning
	local dir2waypoint = vec_dir(pos, pos2)
	if waypoint then
		dir2waypoint = vec_dir(pos, waypoint)
	end
	local yaw = self.object:get_yaw()
	local tgt_yaw = dir2yaw(dir2waypoint)
	local turn_rate = abs(self.turn_rate or 5)
	local yaw_diff = abs(diff(yaw, tgt_yaw))
	-- Moving
	self:set_gravity(-9.8)
	if yaw_diff < pi * (turn_rate * 0.1) then
		self:set_forward_velocity(speed)
	else
		self:set_forward_velocity(speed * 0.5)
		turn_rate = turn_rate * 1.5
	end
	self:animate(movement_data.anim or "walk")
	self:turn_to(tgt_yaw, turn_rate)
	if self:pos_in_box(pos2)
	or (waypoint
	and not self:is_pos_safe(waypoint)) then
		self:halt()
	end
end)

creatura.register_movement_method("creatura:theta_pathfind", function(self, pos2)
	-- Movement Data
	local pos = self.object:get_pos()
	local movement_data = self._movement_data
	local waypoint = movement_data.waypoint
	local speed = movement_data.speed or 5
	local path = self._path
	if not path or #path < 1 then
		self._path = creatura.find_theta_path(self, pos, pos2, self.width, self.height, 300) or {}
	else
		waypoint = self._path[2] or self._path[1]
		if self:pos_in_box({x = waypoint.x, y = pos.y + self.height * 0.5, z = waypoint.z}) then
			-- Waypoint Y axis is raised to avoid large mobs spinning over downward slopes
			table.remove(self._path, 1)
		end
	end
	if not waypoint
	or self:pos_in_box({x = waypoint.x, y = pos.y + self.height * 0.5, z = waypoint.z}) then
		waypoint = creatura.get_next_move(self, pos2)
		self._movement_data.waypoint = waypoint
	end
	-- Turning
	local dir2waypoint = vec_dir(pos, pos2)
	if waypoint then
		dir2waypoint = vec_dir(pos, waypoint)
	end
	local yaw = self.object:get_yaw()
	local tgt_yaw = dir2yaw(dir2waypoint)
	local turn_rate = abs(self.turn_rate or 5)
	local yaw_diff = abs(diff(yaw, tgt_yaw))
	-- Moving
	self:set_gravity(-9.8)
	if yaw_diff < pi * (turn_rate * 0.1) then
		self:set_forward_velocity(speed)
	else
		self:set_forward_velocity(speed * 0.5)
		turn_rate = turn_rate * 1.5
	end
	self:animate(movement_data.anim or "walk")
	self:turn_to(tgt_yaw, turn_rate)
	if self:pos_in_box(pos2)
	or (waypoint
	and not self:is_pos_safe(waypoint)) then
		self:halt()
	end
end)

-- Neighbors

creatura.register_movement_method("creatura:neighbors", function(self, pos2)
	-- Movement Data
	local pos = self.object:get_pos()
	local movement_data = self._movement_data
	local waypoint = movement_data.waypoint
	local speed = movement_data.speed or 5
	if not waypoint
	or self:pos_in_box({x = waypoint.x, y = pos.y + self.height * 0.5, z = waypoint.z}, clamp(self.width, 0.5, 1)) then
		-- Waypoint Y axis is raised to avoid large mobs spinning over downward slopes
		waypoint = creatura.get_next_move(self, pos2)
		self._movement_data.waypoint = waypoint
	end
	-- Turning
	local dir2waypoint = vec_dir(pos, pos2)
	if waypoint then
		dir2waypoint = vec_dir(pos, waypoint)
	end
	local yaw = self.object:get_yaw()
	local tgt_yaw = dir2yaw(dir2waypoint)
	local turn_rate = abs(self.turn_rate or 5)
	local yaw_diff = abs(diff(yaw, tgt_yaw))
	-- Moving
	self:set_gravity(-9.8)
	if yaw_diff < pi * 0.25 then
		self:set_forward_velocity(speed)
	else
		self:set_forward_velocity(speed * 0.5)
		turn_rate = turn_rate * 1.5
	end
	self:animate(movement_data.anim or "walk")
	self:turn_to(tgt_yaw, turn_rate)
	if self:pos_in_box(pos2)
	or (waypoint
	and not self:is_pos_safe(waypoint)) then
		self:halt()
	end
end)

-- Obstacle Avoidance

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
	if col_pos.y - (pos.y + height * 0.5) > 1 then
		avd_pos.y = avd_pos.y - 3
	elseif (pos.y + height * 0.5) - col_pos.y > 1 then
		avd_pos.y = avd_pos.y + 3
	end
	return avd_pos
end

creatura.register_movement_method("creatura:obstacle_avoidance", function(self, pos2)
	-- Movement Data
	local pos = self.object:get_pos()
	local movement_data = self._movement_data
	local waypoint = movement_data.waypoint
	local speed = movement_data.speed or 5
	if not waypoint
	or self:pos_in_box({x = waypoint.x, y = pos.y + self.height * 0.5, z = waypoint.z}, clamp(self.width, 0.5, 1)) then
		-- Waypoint Y axis is raised to avoid large mobs spinning over downward slopes
		waypoint = get_obstacle_avoidance(self, pos2)
		self._movement_data.waypoint = waypoint
	end
	-- Turning
	local dir2waypoint = vec_dir(pos, pos2)
	if waypoint then
		dir2waypoint = vec_dir(pos, waypoint)
	end
	local yaw = self.object:get_yaw()
	local tgt_yaw = dir2yaw(dir2waypoint)
	local turn_rate = abs(self.turn_rate or 5)
	local yaw_diff = abs(diff(yaw, tgt_yaw))
	-- Moving
	self:set_gravity(-9.8)
	if yaw_diff < pi * 0.25 then
		self:set_forward_velocity(speed)
	else
		self:set_forward_velocity(speed * 0.5)
		turn_rate = turn_rate * 1.5
	end
	self:animate(movement_data.anim or "walk")
	self:turn_to(tgt_yaw, turn_rate)
	if self:pos_in_box(pos2)
	or (waypoint
	and not self:is_pos_safe(waypoint)) then
		self:halt()
	end
end)