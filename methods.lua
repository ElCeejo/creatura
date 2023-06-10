-------------
-- Methods --
-------------

local pi = math.pi
local abs = math.abs
local ceil = math.ceil
local max = math.max
local random = math.random
local atan2 = math.atan2
local sin = math.sin
local cos = math.cos

local function diff(a, b) -- Get difference between 2 angles
	return atan2(sin(b - a), cos(b - a))
end

local function clamp(val, _min, _max)
	if val < _min then
		val = _min
	elseif _max < val then
		val = _max
	end
	return val
end

local vec_add = vector.add
local vec_normal = vector.normalize
local vec_len = vector.length
local vec_dist = vector.distance
local vec_dir = vector.direction
local vec_dot = vector.dot
local vec_multi = vector.multiply
local vec_sub = vector.subtract
local yaw2dir = minetest.yaw_to_dir
local dir2yaw = minetest.dir_to_yaw

--[[local function debugpart(pos, time, tex)
	minetest.add_particle({
		pos = pos,
		texture = tex or "creatura_particle_red.png",
		expirationtime = time or 0.1,
		glow = 16,
		size = 24
	})
end]]

---------------------
-- Local Utilities --
---------------------

local get_node_def = creatura.get_node_def
--local get_node_height = creatura.get_node_height_from_def

function creatura.get_collision(self, dir, range)
	local pos, yaw = self.object:get_pos(), self.object:get_yaw()
	if not pos then return end
	local width, height = self.width or 0.5, self.height or 1

	dir = dir or yaw2dir(yaw)

	pos.x = pos.x + dir.x * width
	pos.z = pos.z + dir.z * width

	local cos_yaw = cos(yaw)
	local sin_yaw = sin(yaw)

	local width_i = width / ceil(width)
	local height_i = height / ceil(height)

	local pos_x, pos_y, pos_z = pos.x, pos.y, pos.z
	local dir_x, dir_y, dir_z = dir.x, dir.y, dir.z

	local pos2 = {x = pos_x, y = pos_y, z = pos_z}
	local collision


	pos.y = pos.y + height * 0.5
	range = range or 4
	local low_score
	for _ = 0, range do
		if collision then return collision end
		pos_x = pos_x + dir_x
		pos_y = pos_y + dir_y
		pos_z = pos_z + dir_z

		pos2.y = pos_y
		for x = -width, width, width_i do
			pos2.x = cos_yaw * ((pos_x + x) - pos_x) + pos_x
			pos2.z = sin_yaw * ((pos_x + x) - pos_x) + pos_z

			for y = height, 0, -height_i do
				if y < self.stepheight or 1.1 then break end
				pos2.y = pos_y + y

				if get_node_def(pos2).walkable then
					local score = abs(pos.y - pos2.y) * vec_dot(dir, vec_dir(pos, pos2))
					if not low_score
					or score < low_score then
						low_score = score
						collision = pos2
					end
				end
			end
		end
	end
end

creatura.get_collision_ranged = creatura.get_collision

local get_collision = creatura.get_collision

local function get_avoidance_dir(self)
	local pos = self.object:get_pos()
	if not pos then return end
	local _, col_pos = get_collision(self)
	if col_pos then
		local vel = self.object:get_velocity()
		vel.y = 0
		local vel_len = vec_len(vel) * (1 + (self.step_delay or 0))
		local ahead = vec_add(pos, vec_normal(vel))
		local avoidance_force = vec_sub(ahead, col_pos)
		avoidance_force.y = 0
		avoidance_force = vec_multi(vec_normal(avoidance_force), (vel_len > 1 and vel_len) or 1)
		return vec_dir(pos, vec_add(ahead, avoidance_force))
	end
end

local function get_collision_single(pos, water)
	local pos2 = {x = pos.x, y = pos.y, z = pos.z}
	local n_def = get_node_def(pos2)
	if n_def.walkable
	or (water and (n_def.groups.liquid or 0) > 0) then
		pos2.y = pos.y + 1
		n_def = get_node_def(pos2)
		local col_max = n_def.walkable or (water and (n_def.groups.liquid or 0) > 0)
		pos2.y = pos.y - 1
		local col_min = col_max and (n_def.walkable or (water and (n_def.groups.liquid or 0) > 0))
		if col_min then
			return pos
		else
			pos2.y = pos.y + 1
			return pos2
		end
	end
end

function creatura.get_avoidance_lift(self, pos2, range)
	range = ceil(max(range or 1, 0.5))
	local height_half = (self.height or 1) * 0.5
	local center_y = pos2.y + height_half
	local check_pos = {x = pos2.x, y = center_y, z = pos2.z}

	-- Find ceiling and floor collisions
	local def
	local ceil_pos
	local floor_pos
	for i = 1, range, 0.5 do -- 0.5 increment increases accuracy
		if ceil_pos and floor_pos then break end
		check_pos.y = center_y + i
		def = creatura.get_node_def(check_pos)
		if not ceil_pos
		and (def.walkable
		or minetest.get_item_group(def.name, "liquid") > 0) then
			ceil_pos = check_pos
		end
		check_pos.y = center_y - i
		def = creatura.get_node_def(check_pos)
		if not floor_pos
		and (def.walkable
		or minetest.get_item_group(def.name, "liquid") > 0) then
			floor_pos = check_pos
		end
	end

	-- Calculate direction to average point of collisions
	check_pos.y = center_y
	local offset = {x = 0, y = height_half + range, z = 0}
	if not ceil_pos then ceil_pos = vec_add(check_pos, offset) end
	if not floor_pos then floor_pos = vec_sub(check_pos, offset) end

	local dist_up = ceil_pos.y - center_y
	local dist_down = floor_pos.y - center_y

	local altitude = (dist_up + dist_down) / 2

	return ((check_pos.y + altitude) - center_y) / range * 2
end

function creatura.get_avoidance_lift_aquatic(self, pos2, range)
	range = ceil(max(range or 1, 0.5))
	local height_half = (self.height or 1) * 0.5
	local center_y = pos2.y + height_half
	local check_pos = {x = pos2.x, y = center_y, z = pos2.z}

	-- Find ceiling and floor collisions
	local ceil_pos
	local floor_pos
	for i = 1, range, 0.5 do -- 0.5 increment increases accuracy
		if ceil_pos and floor_pos then break end
		check_pos.y = center_y + i
		if not ceil_pos
		and minetest.get_item_group(creatura.get_node_def(check_pos).name, "liquid") < 1 then
			ceil_pos = check_pos
		end
		check_pos.y = center_y - i
		if not floor_pos
		and minetest.get_item_group(creatura.get_node_def(check_pos).name, "liquid") < 1 then
			floor_pos = check_pos
		end
	end

	-- Calculate direction to average point of collisions
	check_pos.y = center_y
	local offset = {x = 0, y = height_half + range, z = 0}
	if not ceil_pos then ceil_pos = vec_add(check_pos, offset) end
	if not floor_pos then floor_pos = vec_sub(check_pos, offset) end

	local dist_up = ceil_pos.y - center_y
	local dist_down = floor_pos.y - center_y

	local altitude = (dist_up + dist_down) / 2

	return ((check_pos.y + altitude) - center_y) / range * 2
end

----------------------------
-- Context Based Steering --
----------------------------

local steer_directions = {
	vec_normal({x = 1, y = 0, z = 0}),
	vec_normal({x = 1, y = 0, z = 1}),
	vec_normal({x = 0, y = 0, z = 1}),
	vec_normal({x = -1, y = 0, z = 0}),
	vec_normal({x = -1, y = 0, z = -1}),
	vec_normal({x = 0, y = 0, z = -1}),
	vec_normal({x = 1, y = 0, z = -1}),
	vec_normal({x = -1, y = 0, z = 1})
}

-- Context Methods

function creatura.get_context_default(self, goal, steer_dir, interest, danger, range)
	local pos = self.object:get_pos()
	if not pos then return end
	local width, height = self.width or 0.5, self.height or 1
	local y_offset = math.min(self.stepheight or 1.1, height)
	pos.y = pos.y + y_offset
	local collision

	local ray = minetest.raycast(pos, vec_add(pos, vec_multi(steer_dir, width + range)), false, false)
	local pointed = ray:next()
	if pointed
	and pointed.type == "node"
	and creatura.get_node_def(pointed.under).walkable then
		collision = pointed.under
	end

	if collision then
		local dir2goal = vec_normal(vec_dir(pos, goal))
		local dir2col = vec_normal(vec_dir(pos, collision))
		local dist2col = vec_dist(pos, collision) - width
		local dot_score = vec_dot(dir2col, dir2goal)
		local dist_score = (range - dist2col) / range
		interest = interest - dot_score
		danger = dist_score
	end
	return interest, danger
end

function creatura.get_context_large(self, goal, steer_dir, interest, danger, range)
	local pos = self.object:get_pos()
	if not pos then return end
	local width, height = self.width or 0.5, self.height or 1
	local y_offset = math.min(self.stepheight or height)
	pos.y = pos.y + y_offset
	local collision = creatura.get_collision(self, steer_dir, range)

	if collision then
		local dir2goal = vec_normal(vec_dir(pos, goal))
		local dir2col = vec_normal(vec_dir(pos, collision))
		local dist2col = vec_dist(pos, collision) - width
		local dot_score = vec_dot(dir2col, dir2goal)
		local dist_score = (range - dist2col) / range
		interest = interest - dot_score
		danger = dist_score
	end
	return interest, danger
end

function creatura.get_context_small(self, goal, steer_dir, interest, danger, range)
	local pos = self.object:get_pos()
	if not pos then return end
	pos = vector.round(pos)
	local width = self.width or 0.5
	local collision = get_collision_single(vec_add(pos, steer_dir))

	if collision then
		local dir2goal = vec_normal(vec_dir(pos, goal))
		local dir2col = vec_normal(vec_dir(pos, collision))
		local dist2col = vec_dist(pos, collision) - width
		local dot_score = vec_dot(dir2col, dir2goal)
		local dist_score = (range - dist2col) / range
		interest = interest - dot_score
		danger = dist_score
	end
	return interest, danger
end

function creatura.get_context_small_aquatic(self, goal, steer_dir, interest, danger, range)
	local pos = self.object:get_pos()
	if not pos then return end
	pos = vector.round(pos)
	local width = self.width or 0.5
	local pos2 = vec_add(pos, steer_dir)
	local collision = minetest.get_item_group(get_node_def(pos2).name, "liquid") < 1 and pos2

	if collision then
		local dir2goal = vec_normal(vec_dir(pos, goal))
		local dir2col = vec_normal(vec_dir(pos, collision))
		local dist2col = vec_dist(pos, collision) - width
		local dot_score = vec_dot(dir2col, dir2goal)
		local dist_score = (range - dist2col) / range
		interest = interest - dot_score
		danger = dist_score
	end
	return interest, danger
end

-- Calculate Steering

function creatura.calc_steering(self, goal, get_context, range)
	if not goal then return end
	get_context = get_context or creatura.get_context_default
	local pos, yaw = self.object:get_pos(), self.object:get_yaw()
	if not pos or not yaw then return end
	range = math.max(range or 2, 2)
	local dir2goal = vec_normal(vec_dir(pos, goal))
	local output_dir = {x = 0, y = dir2goal.y, z = 0}

	-- Cached variables
	local dir
	for _, _dir in ipairs(steer_directions) do
		dir = {x = _dir.x, y = dir2goal.y, z = _dir.z}
		local score = vec_dot(dir2goal, dir)
		local interest = clamp(score, 0, 1)
		local danger = 0
		if interest > 0 then -- Direction is within 90 degrees of goal
			interest, danger = get_context(self, goal, dir, interest, danger, range)
		end
		score = interest - danger
		output_dir = vector.add(output_dir, vector.multiply(dir, score))
	end
	return vec_normal(output_dir)
end

-- DEPRECATED

function creatura.get_context_steering(self, goal, range, water)
	local context = creatura.get_context_default
	local width, height = self.width, self.height
	if width > 0.5
	or height > 1 then
		context = creatura.get_context_large
	elseif water then
		context = creatura.get_context_small_aquatic
	end
	return creatura.calc_steering(self, goal, context, range)
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
	local rot = self.object:get_rotation()
	local function func(_self)
		if not init then
			_self:animate("stand")
			if random(2) < 2 then
				dir = -1
			end
			init = true
		end
		rot = _self.object:get_rotation()
		local goal = (pi * 0.5) * dir
		local step = _self.dtime
		if step > 0.5 then step = 0.5 end
		zrot = zrot + (pi * dir) * step
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

--[[local function trim_path(pos, path)
	if #path < 2 then return end
	local trim = false
	local closest
	for i = #path, 1, -1 do
		if not path[i] then break end
		if (closest
		and vec_dist(pos, path[i]) > vec_dist(pos, path[closest]))
		or trim then
			table.remove(path, i)
			trim = true
		else
			closest = i
		end
	end
	return path
end]]

creatura.register_movement_method("creatura:pathfind_theta", function(self)
	local path = {}
	local steer_to
	local steer_int = 0
	local arrival_threshold = clamp(self.width, 0.5, 1)

	self:set_gravity(-9.8)
	local function func(_self, goal, speed_factor)
		local pos = _self.object:get_pos()
		if not pos or not goal then return end

		if vec_dist(pos, goal) < arrival_threshold then
			_self:halt()
			return true
		end

		-- Calculate Movement
		local turn_rate = abs(_self.turn_rate or 5)
		local speed = abs(_self.speed or 2) * speed_factor or 0.5
		local path_dir = #path > 0 and vec_dir(pos, path[2] or path[1])

		steer_int = (steer_int > 0 and steer_int - _self.dtime) or 1 / math.max(speed, 1)
		steer_to = path_dir or (steer_int <= 0 and creatura.calc_steering(_self, goal)) or steer_to

		path = (#path > 0 and path) or (creatura.pathfinder.find_path_theta(_self, pos, goal) or {})

		if path_dir
		and ((path[2] and vec_dist(pos, path[2]) < arrival_threshold)
		or vec_dist(pos, path[1]) < arrival_threshold) then
			table.remove(path, 1)
		end

		-- Apply Movement
		_self:turn_to(dir2yaw(steer_to or vec_dir(pos, goal)), turn_rate)
		_self:set_forward_velocity(speed)
	end
	return func
end)

creatura.register_movement_method("creatura:pathfind", function(self)
	local path = {}
	local steer_to
	local steer_int = 0
	local arrival_threshold = clamp(self.width, 0.5, 1)

	self:set_gravity(-9.8)
	local function func(_self, goal, speed_factor)
		local pos = _self.object:get_pos()
		if not pos or not goal then return end

		if vec_dist(pos, goal) < arrival_threshold then
			_self:halt()
			return true
		end

		-- Calculate Movement
		local turn_rate = abs(_self.turn_rate or 5)
		local speed = abs(_self.speed or 2) * speed_factor or 0.5
		local path_dir = #path > 0 and vec_dir(pos, path[2] or path[1])

		steer_int = (steer_int > 0 and steer_int - _self.dtime) or 1 / math.max(speed, 1)
		steer_to = path_dir or (steer_int <= 0 and creatura.calc_steering(_self, goal)) or steer_to

		path = (#path > 0 and path) or (creatura.pathfinder.find_path(_self, pos, goal) or {})

		if path_dir
		and ((path[2] and vec_dist(pos, path[2]) < arrival_threshold + 0.5)
		or vec_dist(pos, path[1]) < arrival_threshold) then
			table.remove(path, 1)
		end

		-- Apply Movement
		_self:turn_to(dir2yaw(steer_to or vec_dir(pos, goal)), turn_rate)
		_self:set_forward_velocity(speed)
	end
	return func
end)


-- Steering

creatura.register_movement_method("creatura:steer_small", function(self)
	local steer_to
	local steer_int = 0
	self:set_gravity(-9.8)
	local function func(_self, goal, speed_factor)
		local pos = _self.object:get_pos()
		if not pos or not goal then return end
		if vec_dist(pos, goal) < clamp(self.width, 0.5, 1) then
			_self:halt()
			return true
		end
		-- Calculate Movement
		local turn_rate = abs(_self.turn_rate or 5)
		local speed = abs(_self.speed or 2) * speed_factor or 0.5
		steer_int = (steer_int > 0 and steer_int - _self.dtime) or 1 / math.max(speed, 1)
		steer_to = (steer_int <= 0 and creatura.calc_steering(_self, goal)) or steer_to
		-- Apply Movement
		_self:turn_to(dir2yaw(steer_to or vec_dir(pos, goal)), turn_rate)
		_self:set_forward_velocity(speed)
	end
	return func
end)

creatura.register_movement_method("creatura:steer_large", function(self)
	local steer_to
	local steer_int = 0
	self:set_gravity(-9.8)
	local function func(_self, goal, speed_factor)
		local pos = _self.object:get_pos()
		if not pos or not goal then return end
		if vec_dist(pos, goal) < clamp(self.width, 0.5, 1) then
			_self:halt()
			return true
		end
		-- Calculate Movement
		local turn_rate = abs(_self.turn_rate or 5)
		local speed = abs(_self.speed or 2) * speed_factor or 0.5
		steer_int = (steer_int > 0 and steer_int - _self.dtime) or 1 / math.max(speed, 1)
		steer_to = (steer_int <= 0 and creatura.calc_steering(_self, goal, creatura.get_context_large)) or steer_to
		-- Apply Movement
		_self:turn_to(dir2yaw(steer_to or vec_dir(pos, goal)), turn_rate)
		_self:set_forward_velocity(speed)
	end
	return func
end)

creatura.register_movement_method("creatura:walk_simple", function(self)
	self:set_gravity(-9.8)
	local function func(_self, goal, speed_factor)
		local pos = _self.object:get_pos()
		if not pos or not goal then return end
		if vec_dist(pos, goal) < clamp(self.width, 0.5, 1) then
			_self:halt()
			return true
		end
		-- Calculate Movement
		local turn_rate = abs(_self.turn_rate or 5)
		local speed = abs(_self.speed or 2) * speed_factor or 0.5
		-- Apply Movement
		_self:turn_to(dir2yaw(vec_dir(pos, goal)), turn_rate)
		_self:set_forward_velocity(speed)
	end
	return func
end)

-- Deprecated

creatura.register_movement_method("creatura:context_based_steering", function(self)
	local steer_to
	local steer_int = 0
	self:set_gravity(-9.8)
	local function func(_self, goal, speed_factor)
		local pos = _self.object:get_pos()
		if not pos or not goal then return end
		if vec_dist(pos, goal) < clamp(self.width, 0.5, 1) then
			_self:halt()
			return true
		end
		-- Calculate Movement
		local turn_rate = abs(_self.turn_rate or 5)
		local speed = abs(_self.speed or 2) * speed_factor or 0.5
		steer_int = (steer_int > 0 and steer_int - _self.dtime) or 1 / math.max(speed, 1)
		steer_to = (steer_int <= 0 and creatura.calc_steering(_self, goal, creatura.get_context_large)) or steer_to
		-- Apply Movement
		_self:turn_to(dir2yaw(steer_to or vec_dir(pos, goal)), turn_rate)
		_self:set_forward_velocity(speed)
	end
	return func
end)

creatura.register_movement_method("creatura:obstacle_avoidance", function(self)
	local box = clamp(self.width, 0.5, 1.5)
	local steer_to
	local steer_timer = 0.25
	local function func(_self, goal, speed_factor)
		local pos = _self.object:get_pos()
		if not pos then return end
		self:set_gravity(-9.8)
		-- Return true when goal is reached
		if vec_dist(pos, goal) < box * 1.33 then
			_self:halt()
			return true
		end
		steer_timer = (steer_timer > 0 and steer_timer - _self.dtime) or 0.25
		-- Get movement direction
		steer_to = (steer_timer > 0 and steer_to) or (steer_timer <= 0 and get_avoidance_dir(_self))
		local goal_dir = steer_to or vec_dir(pos, goal)
		pos.y = pos.y + goal_dir.y
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
		_self:turn_to(goal_yaw, turn_rate)
	end
	return func
end)


