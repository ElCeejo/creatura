local pathfinder = {}
pathfinder.__index = pathfinder

-- Create new instance
function pathfinder:new(object, spec)
	local new_pathfinder = {
		parent = object,

		start_pos = {},
		target_pos = {},
		path = {},

		open_set = {},
		closed_set = {},
		came_from = {},
		g_score = {},

		finding_path = false,

		recalculate_timer = 0,

		get_neighbors = spec.get_neighbors,
		get_neighbor_grid = spec.get_neighbor_grid
	}

	return setmetatable(new_pathfinder, pathfinder)
end

local abs = math.abs

local neighbor_grid = {
	{x = 1, y = 0, z = 0},
	{x = 1, y = 0, z = 1},
	{x = 0, y = 0, z = 1},
	{x = -1, y = 0, z = 1},
	{x = -1, y = 0, z = 0},
	{x = -1, y = 0, z = -1},
	{x = 0, y = 0, z = -1},
	{x = 1, y = 0, z = -1}
}

function pathfinder:visualize()
	local path = self.path
	if not path or #path < 1 then return end

	for _, pos in ipairs(path) do
		creatura.particle(pos, 1, "creatura_particle_green.png")
	end
end

-- Return parent objects luaentity
function pathfinder:parent_entity()
	return self.parent and self.parent:get_luaentity()
end

function pathfinder:get_heuristic_cost(pos1, pos2)
	local distX = abs(pos1.x - pos2.x)
	local distY = abs(pos1.y - pos2.y)
	local distZ = abs(pos1.z - pos2.z)

	if distX > distZ then
		return (14 * distZ + 10 * (distX - distZ)) * (distY + 1)
	else
		return (14 * distX + 10 * (distZ - distX)) * (distY + 1)
	end
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
		f_cost = self:get_heuristic_cost(self.start_pos, self.target_pos),
		g_score = 0
	})

	self.g_score[self:hash_position(self.start_pos)] = 0
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

function pathfinder:get_path()
	if not self.path or #self.path < 1 then return end

	return self.path
end

-- Clearance check

local test_box = {-0.5, 0, -0.5, 0.5, 1, 0.5}


function pathfinder:is_empty(pos, box)
	--[[if math.abs(box[1]) + math.abs(box[4]) <= 1
	and box[5] <= 1 then -- only check 1 node if box doesn't exceed 1 node in size
		return (not creatura.is_walkable(pos)) and creatura.is_on_ground(pos)
	end]]

	local min_p = {
		x = math.floor(pos.x + 0.5 + box[1]),
		y = math.floor(pos.y + 0.5 + box[2]),
		z = math.floor(pos.z + 0.5 + box[3])
	}

	local max_p = {
		x = math.floor(pos.x + 0.5 + box[4]),
		y = math.floor(pos.y + 0.5 + box[5]),
		z = math.floor(pos.z + 0.5 + box[6])
	}

	local ground_check_passed = false
	for x = min_p.x, max_p.x do
		for y = min_p.y, max_p.y do
			for z = min_p.z, max_p.z do
				if creatura.is_walkable(vector.new(x, y, z)) then
					return false
				end

				if not ground_check_passed
				and y == min_p.y
				and creatura.is_on_ground(vector.new(x, y, z)) then
					ground_check_passed = true
				end
			end
		end
	end

	return ground_check_passed
end

function pathfinder:get_neighbor_grid(pos)
	local p1 = vector.new(pos)
	return {
		p1:add({x = 1, y = 0, z = 0}),
		p1:add({x = 1, y = 0, z = 1}),
		p1:add({x = 0, y = 0, z = 1}),
		p1:add({x = -1, y = 0, z = 1}),
		p1:add({x = -1, y = 0, z = 0}),
		p1:add({x = -1, y = 0, z = -1}),
		p1:add({x = 0, y = 0, z = -1}),
		p1:add({x = 1, y = 0, z = -1})
	}
end

function pathfinder:get_neighbor_grid_3d(pos)
	local p1 = vector.new(pos)
	return {
		p1,
		p1:add({x = 1, y = 0, z = 0}),
		p1:add({x = 1, y = 0, z = 1}),
		p1:add({x = 0, y = 0, z = 1}),
		p1:add({x = -1, y = 0, z = 1}),
		p1:add({x = -1, y = 0, z = 0}),
		p1:add({x = -1, y = 0, z = -1}),
		p1:add({x = 0, y = 0, z = -1}),
		p1:add({x = 1, y = 0, z = -1})
	}
end

function pathfinder:get_neighbors(pos)
	local results = {}
	for i, pos1 in ipairs(self:get_neighbor_grid(pos)) do
		local is_diagonal = math.floor(i) == i
		if self:is_empty(pos1, test_box)
		and (not is_diagonal or creatura.line_of_sight(pos, pos1)) then
			results[#results + 1] = pos1
		elseif self:is_empty(pos1:offset(0, 1, 0), test_box)
		and (not is_diagonal or creatura.line_of_sight(pos:offset(0, 1, 0), pos1:offset(0, 1, 0))) then
			table.insert(results, pos1:offset(0, 1, 0))
		elseif self:is_empty(pos1:offset(0, -1, 0), test_box)
		and (not is_diagonal or creatura.line_of_sight(pos:offset(0, 1, 0), pos1:offset(0, -1, 0))) then
			table.insert(results, pos1:offset(0, -1, 0))
		end
	end
	return results
end

function pathfinder:get_neighbors_3d(pos)
	local results = {}
	for i, pos1 in ipairs(self:get_neighbor_grid(pos)) do
		for y = -1, 1 do
			local is_diagonal = math.floor(i) == i
			local npos = {x = pos1.x, y = pos1.y + y, z = pos1.z}
			if creatura.is_pos_empty(npos, test_box)
			and (not is_diagonal or creatura.line_of_sight(pos, npos)) then
				results[#results + 1] = npos
			end
		end
	end
	return results
end

function pathfinder:get_neighbors_in_liquid(pos)
	local results = {}
	for i, pos1 in ipairs(self:get_neighbor_grid(pos)) do
		for y = -1, 1 do
			local is_diagonal = math.floor(i) == i
			local npos = {x = pos1.x, y = pos1.y + y, z = pos1.z}
			if creatura.is_pos_empty_in_liquid(npos, test_box)
			and (not is_diagonal or creatura.line_of_sight(pos, npos)) then
				results[#results + 1] = npos
			end
		end
	end
	return results
end

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

-- Utils

function pathfinder:hash_position(pos)
	return minetest.hash_node_position(pos)
end

-- A*

function pathfinder:reconstruct_path()
	self.path = {}
	local current = self.current
	local current_hash = self:hash_position(current.pos)

	while self.came_from[current_hash] do
		table.insert(self.path, 1, current.pos)
		current = self.came_from[current_hash]
		current_hash = self:hash_position(current.pos)
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

		local current_hash = self:hash_position(current.pos)
		if not closed_set[current_hash] then
			if current.pos.x == self.target_pos.x and current.pos.z == self.target_pos.z then
				--self.bm_time = (self.bm_time or 0) + minetest.get_us_time() - us
				--self.bm_steps = (self.bm_steps or 0) + 1
				self:reconstruct_path()
				return
			end

			for _, next_pos in ipairs(self:get_neighbors(current.pos)) do
				local next_hash = self:hash_position(next_pos)
				if not closed_set[next_hash] then
					local new_node = {
						pos = next_pos,
						g_score = 0,
						f_cost = 0
					}

					local temp_g_score = current.g_score + self:get_heuristic_cost(current.pos, next_pos)

					if not g_score[next_hash] or temp_g_score < g_score[next_hash] then
						new_node.f_cost = temp_g_score + self:get_heuristic_cost(next_pos, self.target_pos)
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
		--self:visualize()
		local parent_entity = self:parent_entity()
		self.recalculate_timer = self.recalculate_timer - parent_entity.dtime

		if self.recalculate_timer <= 0 then
			self.recalculate_timer = 10
			self.path = {}
		end
		return
	end
	if not self.target_pos or not self.target_pos.x then return end

	self:a_star_step()
end

return pathfinder