-------------------
-- A* Pathfinder --
-------------------

local floor = math.floor
local ceil = math.ceil
local abs = math.abs

local neighbors = {
	{x = 1, y = 0, z = 0},
	{x = 1, y = 0, z = 1},
	{x = 0, y = 0, z = 1},
	{x = -1, y = 0, z = 1},
	{x = -1, y = 0, z = 0},
	{x = -1, y = 0, z = -1},
	{x = 0, y = 0, z = -1},
	{x = 1, y = 0, z = -1}
}

local neighbors_3d = {
	{x = 1, y = 0, z = 0},
	{x = 1, y = 0, z = 1},
	{x = 0, y = 0, z = 1},
	{x = -1, y = 0, z = 1},
	{x = -1, y = 0, z = 0},
	{x = -1, y = 0, z = -1},
	{x = 0, y = 0, z = -1},
	{x = 1, y = 0, z = -1},

	{x = 0, y = 1, z = 0},
	{x = 0, y = -1, z = 0}
}

-- Utils

local hash_position = core.hash_node_position

local function get_heuristic_cost(pos1, pos2)
	local distX = abs(pos1.x - pos2.x)
	local distY = abs(pos1.y - pos2.y)
	local distZ = abs(pos1.z - pos2.z)

	if distX > distZ then
		return (14 * distZ + 10 * (distX - distZ)) * (distY + 1)
	else
		return (14 * distX + 10 * (distZ - distX)) * (distY + 1)
	end
end

local function is_empty(pos, box)
	local total_width = abs(box[1]) + abs(box[4])
	local check_length = total_width / ceil(total_width)
	local total_height = abs(box[2]) + abs(box[5])
	local check_height = total_height / ceil(total_height)

	if total_width <= 1 and total_height <= 1 then
		return (not creatura.is_walkable(pos)) and creatura.is_on_ground(pos)
	end

	local ground_check_passed = false
	local check_pos

	for x = pos.x + box[1], pos.x + box[4], check_length do
		for y = pos.y + box[2], pos.y + box[5], check_height do
			for z = pos.z + box[3], pos.z + box[6], check_length do
				check_pos = {x = x, y = y, z = z}

				if creatura.is_walkable(check_pos) then
					return false
				end

				-- Make sure at least one point of the collisionbox is above solid ground
				if not ground_check_passed
				and y == pos.y + box[2]
				and creatura.is_on_ground(check_pos) then
					ground_check_passed = true
				end
			end
		end
	end

	return ground_check_passed
end

local function is_empty_3d(pos, box, in_liquid)
	local total_width = abs(box[1]) + abs(box[4])
	local check_length = total_width / ceil(total_width)
	local total_height = abs(box[2]) + abs(box[5])
	local check_height = total_height / ceil(total_height)

	if total_width <= 1 and total_height <= 1 then
		if in_liquid then
			return creatura.is_liquid(pos)
		else
			return (not creatura.is_liquid) and (not creatura.is_walkable(pos))
		end
	end

	local check_pos

	for x = pos.x + box[1], pos.x + box[4], check_length do
		for y = pos.y + box[2], pos.y + box[5], check_height do
			for z = pos.z + box[3], pos.z + box[6], check_length do
				check_pos = {x = x, y = y, z = z}
				if creatura.is_walkable(check_pos) then
					return false
				end

				-- Swimming mobs avoid leaving water
				local is_liquid = not creatura.is_liquid(check_pos)
				if in_liquid
				and not is_liquid then
					return false
				end

				-- Flying mobs avoid water
				if not in_liquid
				and is_liquid then
					return false
				end
			end
		end
	end

	return true
end

-- Pathfinder Class

local pathfinder = {}
pathfinder.__index = pathfinder

-- Create a new Pathfinder object

function pathfinder:new(parent)
	local new_pathfinder = {}

	new_pathfinder.parent = parent
	new_pathfinder.finding_path = false

	-- Vector Tables
	new_pathfinder.start_pos = {}
	new_pathfinder.target_pos = {}
	new_pathfinder.path = {}

	-- A* Tables
	new_pathfinder.open_set = {}
	new_pathfinder.closed_set = {}
	new_pathfinder.came_from = {}
	new_pathfinder.g_score = {}

	return setmetatable(new_pathfinder, pathfinder)
end

-- Get Parent Attribute

function pathfinder:get_parent_attribute(attribute)
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


-- Visualize path if available

function pathfinder:visualize()
	local path = self.path
	if not path or #path < 1 then return end

	for _, pos in ipairs(path) do
		creatura.particle(pos, 1, "creatura_particle_green.png")
	end
end

-- Abstracted Instructions

function pathfinder:start(target_pos)
	if not target_pos then return end

	local pos1 = self.parent and self.parent:get_pos()
	if not pos1 then return end

	self.start_pos = vector.round(pos1)
	self.target_pos = vector.round(target_pos)
	self.open_set = {}
	self.closed_set = {}
	self.came_from = {}
	self.g_score = {}
	self.max_expansions_per_step = 5

	self:heap_push({
		pos = vector.round(pos1),
		f_cost = get_heuristic_cost(self.start_pos, self.target_pos),
		g_score = 0
	})

	self.g_score[hash_position(self.start_pos)] = 0
	self.finding_path = true
end

local function can_expand_to(self, pos)
	local box = self:get_parent_attribute("collisionbox")
	if not is_empty(pos, box) then return false end

	local max_fall = self:get_parent_attribute("max_fall") or 2
	if max_fall > 0 then
		local is_above_fall = creatura.is_pos_above_fall(vector.round(pos), max_fall)

		if is_above_fall then
			return false
		end
	end

	return true
end

local function get_ground_expansion(self, pos)
	local expansion_result = {}
	local expand_pos = vector.round(pos)
	for i = 1, 8 do
		expand_pos.x = pos.x + neighbors[i].x
		expand_pos.z = pos.z + neighbors[i].z

		for y = -1, 1 do
			expand_pos.y = pos.y - 0.49 + y

			if y > -1
			and not self.can_jump_fences
			and creatura.is_fence(expand_pos) then
				break
			end

			if can_expand_to(self, expand_pos) then
				table.insert(expansion_result, vector.round(expand_pos))
				break
			end
		end
	end

	return expansion_result
end

local function get_aerial_expansion(self, pos)
	local expansion_result = {}
	local expand_pos = vector.round(pos)
	expand_pos.y = pos.y - 0.49 -- Set y level to the floor for accurate clearance checks
	for i = 1, 10 do
		expand_pos = vector.add(pos, neighbors_3d[i])

		if is_empty_3d(self, expand_pos) then
			table.insert(expansion_result, vector.round(expand_pos))
		end
	end

	return expansion_result
end

local function get_aquatic_expansion(self, pos)
	local expansion_result = {}
	local expand_pos = vector.round(pos)
	expand_pos.y = pos.y - 0.49 -- Set y level to the floor for accurate clearance checks
	for i = 1, 10 do
		expand_pos = vector.add(pos, neighbors_3d[i])

		if is_empty_3d(self, expand_pos, true) then
			table.insert(expansion_result, vector.round(expand_pos))
		end
	end

	return expansion_result
end

function pathfinder:get_path(target_pos)
	if not target_pos or not target_pos.x then self:stop() return end

	-- Target has changed, find a new path.
	if not vector.equals(self.target_pos, vector.round(target_pos)) then
		self:start(target_pos)
		return {}, "waiting"
	end

	-- Path found!
	if self.path
	and #self.path > 0 then
		local path = table.copy(self.path)
		self.path = {}

		return path, "finished"
	end

	-- Begin pathfinding.
	if not self.target_pos
	or not self.target_pos.x then
		self:start(target_pos)
		return {}, "waiting"
	end

	-- Path stil not found.
	if self.finding_path then
		self:main_astar_loop(get_ground_expansion)
		return {}, "waiting"
	end

	return {}, "error"
end

function pathfinder:get_aerial_path(target_pos)
	if not target_pos or not target_pos.x then self:stop() return end

	-- Begin pathfinding.
	if not self.target_pos
	or not self.target_pos.x
	or not vector.equals(vector.round(self.target_pos), vector.round(target_pos)) then
		self:start(target_pos)
		return {}, "waiting"
	end

	-- Path stil not found.
	if self.finding_path then
		self:main_astar_loop(get_aerial_expansion)
		return {}
	end

	-- Path found!
	if self.path
	and #self.path > 0 then
		return self.path
	end

	return {}
end

function pathfinder:get_aquatic_path(target_pos)
	if not target_pos or not target_pos.x then self:stop() return end

	-- Begin pathfinding.
	if not self.target_pos
	or not self.target_pos.x
	or not vector.equals(vector.round(self.target_pos), vector.round(target_pos)) then
		self:start(target_pos)
		return {}, "waiting"
	end

	-- Path stil not found.
	if self.finding_path then
		self:main_astar_loop(get_aquatic_expansion)
		return {}
	end

	-- Path found!
	if self.path
	and #self.path > 0 then
		return self.path
	end

	return {}
end

function pathfinder:stop()
	self.start_pos = {}
	self.target_pos = {}
	self.open_set = {}
	self.closed_set = {}
	self.came_from = {}
	self.g_score = {}
	self.current = nil
	self.finding_path = false
end

-- Min Heap

function pathfinder:heap_push(node)
	local open_set = self.open_set

	table.insert(open_set, node)
	local i = #open_set
	while i > 1 do
		local p = floor(i / 2)
		if open_set[p].f_cost <= open_set[i].f_cost then break end
		open_set[p], open_set[i] = open_set[i], open_set[p]
		i = p
	end
end

function pathfinder:heap_pop()
	local open_set = self.open_set

	if #open_set < 1 then return nil end
	local root = open_set[1]
	open_set[1] = open_set[#open_set]
	open_set[#open_set] = nil

	local i = 1
	while true do
		local child_index_left = i * 2
		local child_index_right = child_index_left + 1
		local lowest = i

		if child_index_left <= #open_set and open_set[child_index_left].f_cost < open_set[lowest].f_cost then
			lowest = child_index_left
		end
		if child_index_right <= #open_set and open_set[child_index_right].f_cost < open_set[lowest].f_cost then
			lowest = child_index_right
		end
		if lowest == i then break end
		open_set[i], open_set[lowest] = open_set[lowest], open_set[i]
		i = lowest
	end

	self.current = root
	return root
end

-- A*

function pathfinder:reconstruct_path()
	self.path = {}
	local current = self.current
	local current_hash = hash_position(current.pos)

	while self.came_from[current_hash] do
		table.insert(self.path, 1, current.pos)
		current = self.came_from[current_hash]
		current_hash = hash_position(current.pos)
	end
	table.insert(self.path, 1, self.start_pos)


	--minetest.chat_send_all("path found in " .. self.bm_time .. " microseconds over " .. self.bm_steps .. " steps")
	--self.bm_time = nil
	--self.bm_steps = nil
	self:stop()
	return self.path
end

function pathfinder:main_astar_loop(get_expansion)
	--local us = minetest.get_us_time()
	local count = 1
	local max_count = self.max_expansions_per_step

	local closed_set = self.closed_set
	local g_score = self.g_score
	local came_from = self.came_from

	while count < max_count do
		local current = self:heap_pop()
		if not current then
			return nil -- no path
		end

		local current_hash = hash_position(current.pos)
		if not closed_set[current_hash] then
			if current.pos.x == self.target_pos.x and current.pos.z == self.target_pos.z then
				--self.bm_time = (self.bm_time or 0) + minetest.get_us_time() - us
				--self.bm_steps = (self.bm_steps or 0) + 1
				self:reconstruct_path()
				return
			end

			for _, next_pos in ipairs(get_expansion(self, current.pos)) do
				local next_hash = hash_position(next_pos)
				if not closed_set[next_hash] then
					local new_node = {
						pos = next_pos,
						g_score = 0,
						f_cost = 0
					}

					local temp_g_score = current.g_score + get_heuristic_cost(current.pos, next_pos)

					if not g_score[next_hash] or temp_g_score < g_score[next_hash] then
						new_node.f_cost = temp_g_score + get_heuristic_cost(next_pos, self.target_pos)
						new_node.g_score = temp_g_score
						g_score[next_hash] = temp_g_score

						self:heap_push(new_node)
						came_from[next_hash] = current
						count = count + 1
					end
				end
			end

			closed_set[current_hash] = true
		end
	end
	--self.bm_time = (self.bm_time or 0) + minetest.get_us_time() - us
	--self.bm_steps = (self.bm_steps or 0) + 1
end

-- Wrappers

function creatura.find_path(entity, target_pos)
	local current_pathfinder = entity.pathfinder
	if not current_pathfinder
	or not current_pathfinder.get_path then
		current_pathfinder = pathfinder:new(entity.object)
		entity.pathfinder = current_pathfinder
	end

	--entity:add_diagnostic("finding_path", "true")
	--current_pathfinder:visualize()
	return current_pathfinder:get_path(target_pos)
end

function creatura.find_aerial_path(entity, target_pos)
	local current_pathfinder = entity.pathfinder
	if not current_pathfinder then
		current_pathfinder = pathfinder:new(entity.object)
		entity.pathfinder = current_pathfinder
	end

	return current_pathfinder:get_aerial_path(target_pos)
end

function creatura.find_aquatic_path(entity, target_pos)
	local current_pathfinder = entity.pathfinder
	if not current_pathfinder then
		current_pathfinder = pathfinder:new(entity.object)
		entity.pathfinder = current_pathfinder
	end

	return current_pathfinder:get_aquatic_path(target_pos)
end
