local pathfinder = {}
pathfinder.__index = pathfinder

local floor = math.floor
local abs = math.abs

-- Utils

local function hash_position(pos)
	return minetest.hash_node_position(pos)
end

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

-- Clearance checks

--local test_box = {-0.5, 0, -0.5, 0.5, 1, 0.5}

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

local function is_empty(pos, box)
	if abs(box[1]) + abs(box[4]) <= 1 and box[5] <= 1 then
		return (not creatura.is_walkable(pos)) and creatura.is_on_ground(pos)
	end

	local min_x = floor(pos.x + box[1] + 0.01)
	local max_x = floor(pos.x + box[4] - 0.01)
	local min_y = floor(pos.y + box[2] + 0.01)
	local max_y = floor(pos.y + box[5] - 0.01)
	local min_z = floor(pos.z + box[3] + 0.01)
	local max_z = floor(pos.z + box[6] - 0.01)

	local ground_check_passed = false

	local check_pos = {x = 0, y = 0, z = 0}

	for x = min_x, max_x do
		for y = min_y, max_y do
			for z = min_z, max_z do
				check_pos.x, check_pos.y, check_pos.z = x, y, z

				if creatura.is_walkable(check_pos) then
					return false
				end

				if not ground_check_passed and y == min_y and creatura.is_on_ground(check_pos) then
					ground_check_passed = true
				end
			end
		end
	end

	return ground_check_passed
end

local function is_empty_3d(pos, box, liquid)
	local min_x = floor(pos.x + box[1] + 0.01)
	local max_x = floor(pos.x + box[4] - 0.01)
	local min_y = floor(pos.y + box[2] + 0.01)
	local max_y = floor(pos.y + box[5] - 0.01)
	local min_z = floor(pos.z + box[3] + 0.01)
	local max_z = floor(pos.z + box[6] - 0.01)

	local check_pos = {x = 0, y = 0, z = 0}

	for x = min_x, max_x do
		for y = min_y, max_y do
			for z = min_z, max_z do
				check_pos.x, check_pos.y, check_pos.z = x, y, z

				-- 1. Is it a solid wall? (Both birds and fish hate walls)
				if creatura.is_walkable(check_pos) then
					return false
				end

				-- 2. Environmental Checks
				if liquid then
					-- Fish: Must be inside liquid
					if not creatura.is_liquid(check_pos) then return false end
				else
					-- Bird: Must NOT go underwater
					if creatura.is_liquid(check_pos) then return false end
				end
			end
		end
	end

	return true
end

-- Create new instance
function pathfinder:get_ground_pathfinder(parent, spec)
	local new_pathfinder = spec or {}

	new_pathfinder.parent = parent
	new_pathfinder.mob_hitbox = parent:get_properties().collisionbox

	new_pathfinder.start_pos = {}
	new_pathfinder.target_pos = {}
	new_pathfinder.path = {}

	new_pathfinder.open_set = {}
	new_pathfinder.closed_set = {}
	new_pathfinder.came_from = {}
	new_pathfinder.g_score = {}

	new_pathfinder.finding_path = false

	new_pathfinder.recalculate_timer = 0

	local entity = parent:get_luaentity()
	new_pathfinder.can_jump_fences = entity.can_jump_fences

	return setmetatable(new_pathfinder, self)
end

pathfinder.new = pathfinder.get_ground_pathfinder

function pathfinder:get_flight_pathfinder(object, spec)
	local new_pathfinder = self:get_ground_pathfinder(object, spec)
	new_pathfinder.is_valid_expansion = creatura.pathfinder_flight_expansion_check
	new_pathfinder.expand = creatura.pathfinder_expand_3d

	return new_pathfinder
end

function pathfinder:get_swim_pathfinder(object, spec)
	local new_pathfinder = self:get_ground_pathfinder(object, spec)
	new_pathfinder.is_valid_expansion = creatura.pathfinder_swim_expansion_check
	new_pathfinder.expand = creatura.pathfinder_expand_3d

	return new_pathfinder
end

-- TODO: Figure out something other than this ugly mess ^

-- Helpers

function pathfinder:visualize()
	local path = self.path
	if not path or #path < 1 then return end

	for _, pos in ipairs(path) do
		creatura.particle(pos, 1, "creatura_particle_green.png")
	end
end

function pathfinder:parent_entity()
	return self.parent and self.parent:get_luaentity()
end

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

-- Instructions

function pathfinder:set_target(pos2, max_expansions_per_step, recalc_timer)
	local pos1 = self.parent and self.parent:get_pos()
	if not pos1 then return end

	self.start_pos = vector.round(pos1)
	self.target_pos = vector.round(pos2)
	self.open_set = {}
	self.closed_set = {}
	self.came_from = {}
	self.g_score = {}
	self.max_expansions_per_step = max_expansions_per_step or 5
	self.recalculate_timer = recalc_timer or 10

	self:heap_push({
		pos = vector.round(pos1),
		f_cost = get_heuristic_cost(self.start_pos, self.target_pos),
		g_score = 0
	})

	self.g_score[hash_position(self.start_pos)] = 0
	self.finding_path = true
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

function pathfinder:clear_path()
	self:stop()
	self.path = {}
end

function pathfinder:get_path(target_pos)
	if target_pos then
		self:set_target(target_pos)
		return {}
	end

	if not self.path or #self.path < 1 then return {} end

	return self.path
end

-- Expansion

function creatura.pathfinder_ground_expansion_check(self, pos)
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

function creatura.pathfinder_flight_expansion_check(self, pos)
	local box = self:get_parent_attribute("collisionbox")
	if not is_empty_3d(pos, box) then return false end

	return true
end

function creatura.pathfinder_swim_expansion_check(self, pos)
	local box = self:get_parent_attribute("collisionbox")
	if not is_empty_3d(pos, box, true) then return false end

	return true
end

pathfinder.is_valid_expansion = creatura.pathfinder_ground_expansion_check

function creatura.pathfinder_expand(self, pos)
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

			if self:is_valid_expansion(expand_pos) then
				table.insert(expansion_result, vector.round(expand_pos))
				break
			end
		end
	end

	return expansion_result
end

function creatura.pathfinder_expand_3d(self, pos)
	local expansion_result = {}
	local expand_pos = vector.round(pos)
	expand_pos.y = pos.y - 0.49 -- Set y level to the floor for accurate clearance checks
	for i = 1, 10 do
		expand_pos = vector.add(pos, neighbors_3d[i])

		if self:is_valid_expansion(expand_pos) then
			table.insert(expansion_result, vector.round(expand_pos))
		end
	end

	return expansion_result
end

pathfinder.expand = creatura.pathfinder_expand

-- Min Heap

function pathfinder:heap_push(node)
	local open_set = self.open_set

	table.insert(open_set, node)
	local i = #open_set
	while i > 1 do
		local p = math.floor(i / 2)
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

function pathfinder:a_star_step()
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

			for _, next_pos in ipairs(self:expand(current.pos)) do
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

-- Update

function pathfinder:update()
	if self.path
	and #self.path > 0 then
		self:visualize()
		local parent_entity = self:parent_entity()
		self.recalculate_timer = self.recalculate_timer - parent_entity.dtime

		if self.recalculate_timer <= 0 then
			self.recalculate_timer = 10
			self.path = {}
		end
		return true
	end

	if not self.target_pos
	or not self.target_pos.x then
		return false
	else
		self:a_star_step()
		return true
	end
end

creatura.pathfinder = pathfinder
