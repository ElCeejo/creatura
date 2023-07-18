-----------------
-- Pathfinding --
-----------------

local a_star_alloted_time = tonumber(minetest.settings:get("creatura_a_star_alloted_time")) or 500
local theta_star_alloted_time = tonumber(minetest.settings:get("creatura_theta_star_alloted_time")) or 700

creatura.pathfinder = {}

local max_open = 300

-- Math

local floor = math.floor
local abs = math.abs

local vec_add, vec_dist, vec_new, vec_round = vector.add, vector.distance, vector.new, vector.round

local function vec_raise(v, n)
	return {x = v.x, y = v.y + n, z = v.z}
end

-- Heuristic

local function get_distance(start_pos, end_pos)
	local distX = abs(start_pos.x - end_pos.x)
	local distZ = abs(start_pos.z - end_pos.z)

	if distX > distZ then
		return 14 * distZ + 10 * (distX - distZ)
	else
		return 14 * distX + 10 * (distZ - distX)
	end
end

local function get_distance_to_neighbor(start_pos, end_pos)
	local distX = abs(start_pos.x - end_pos.x)
	local distY = abs(start_pos.y - end_pos.y)
	local distZ = abs(start_pos.z - end_pos.z)

	if distX > distZ then
		return (14 * distZ + 10 * (distX - distZ)) * (distY + 1)
	else
		return (14 * distX + 10 * (distZ - distX)) * (distY + 1)
	end
end

-- Blocked Movement Checks

local is_blocked = creatura.is_blocked

local function get_line_of_sight(a, b)
	local steps = floor(vec_dist(a, b))
	local line = {}

	for i = 0, steps do
		local pos

		if steps > 0 then
			pos = {
				x = a.x + (b.x - a.x) * (i / steps),
				y = a.y + (b.y - a.y) * (i / steps),
				z = a.z + (b.z - a.z) * (i / steps)
			}
		else
			pos = a
		end
		table.insert(line, pos)
	end

	if #line < 1 then
		return false
	else
		for i = 1, #line do
			local node = minetest.get_node(line[i])
			if creatura.get_node_def(node.name).walkable then
				return false
			end
		end
	end
	return true
end

local function is_on_ground(pos)
	local ground = {
		x = pos.x,
		y = pos.y - 1,
		z = pos.z
	}
	if creatura.get_node_def(ground).walkable then
		return true
	end
	return false
end

-- Neighbor Check Grids

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

local neighbor_grid_climb = {
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

local neighbor_grid_3d = {
	-- Central
	{x = 1, y = 0, z = 0},
	{x = 0, y = 0, z = 1},
	{x = -1, y = 0, z = 0},
	{x = 0, y = 0, z = -1},
	-- Directly Up or Down
	{x = 0, y = 1, z = 0},
	{x = 0, y = -1, z = 0}
}

-- Get Neighbors

local function get_neighbors(pos, width, height, open, closed, parent, evaluated)
	local result = {}
	local neighbor
	local can_move
	local hashed_pos
	local step

	for i = 1, #neighbor_grid do
		neighbor = vec_add(pos, neighbor_grid[i])
		can_move = get_line_of_sight({x = pos.x, y = neighbor.y, z = pos.z}, neighbor)
		hashed_pos = minetest.hash_node_position(neighbor)

		if parent
		and vec_dist(parent, neighbor) < vec_dist(pos, neighbor) then
			can_move = false
		end

		if open[hashed_pos]
		or closed[hashed_pos]
		or evaluated[hashed_pos] then
			can_move = false
		elseif can_move then
			can_move = not is_blocked(neighbor, width, height)

			if not can_move then -- Step Up
				step = vec_raise(neighbor, 1)
				can_move = not is_blocked(vec_round(step), width, height)
				neighbor = vec_round(step)
			else
				step = creatura.get_ground_level(vec_new(neighbor), 1)
				if step.y < neighbor.y
				and not is_blocked(vec_round(step), width, height) then
					neighbor = step
				end
			end
		end

		if can_move then
			table.insert(result, neighbor)
		end

		evaluated[hashed_pos] = true
	end
	return result
end

function creatura.pathfinder.get_neighbors_climb(pos, width, height, open, closed)
	local result = {}
	local neighbor
	local can_move
	local hashed_pos
	local step

	for i = 1, #neighbor_grid_climb do
		neighbor = vec_add(pos, neighbor_grid_climb[i])
		can_move = get_line_of_sight({x = pos.x, y = neighbor.y, z = pos.z}, neighbor)
		hashed_pos = minetest.hash_node_position(neighbor)

		if open[hashed_pos]
		or closed[hashed_pos] then
			can_move = false
		elseif can_move then
			can_move = not is_blocked(neighbor, width, height)

			if not can_move then -- Step Up
				step = vec_raise(neighbor, 1)
				can_move = not is_blocked(vec_round(step), width, height)
				neighbor = vec_round(step)
			elseif i < 9 then
				step = creatura.get_ground_level(vec_new(neighbor), 1)
				if step.y < neighbor.y
				and not is_blocked(vec_round(step), width, height) then
					neighbor = step
				end
			end
		end

		if can_move then
			table.insert(result, neighbor)
		end
	end
	return result
end

function creatura.pathfinder.get_neighbors_fly(pos, width, height, open, closed, parent)
	local result = {}
	local neighbor
	local can_move
	local hashed_pos

	for i = 1, #neighbor_grid_3d do
		neighbor = vec_add(pos, neighbor_grid_3d[i])
		can_move = get_line_of_sight({x = pos.x, y = pos.y, z = pos.z}, neighbor)
		hashed_pos = minetest.hash_node_position(neighbor)

		if parent
		and vec_dist(parent, neighbor) < vec_dist(pos, neighbor) then
			can_move = false
		end

		if open[hashed_pos]
		or closed[hashed_pos] then
			can_move = false
		elseif can_move then
			can_move = not is_blocked(neighbor, width, height)
		end

		if can_move then
			table.insert(result, neighbor)
		end
	end
	return result, true
end

function creatura.pathfinder.get_neighbors_swim(pos, width, height, open, closed, parent)
	local result = {}
	local neighbor
	local can_move
	local hashed_pos

	for i = 1, #neighbor_grid_3d do
		neighbor = vec_add(pos, neighbor_grid_3d[i])
		can_move = get_line_of_sight({x = pos.x, y = pos.y, z = pos.z}, neighbor)
		hashed_pos = minetest.hash_node_position(neighbor)

		if (parent
		and vec_dist(parent, neighbor) < vec_dist(pos, neighbor))
		or creatura.get_node_def(neighbor).drawtype ~= "liquid" then
			can_move = false
		end

		if open[hashed_pos]
		or closed[hashed_pos] then
			can_move = false
		elseif can_move then
			can_move = not is_blocked(neighbor, width, height)
		end

		if can_move then
			table.insert(result, neighbor)
		end
	end
	return result, true
end

-- A*

function creatura.pathfinder.find_path(self, pos1, pos2, neighbor_func)
	local us_time = minetest.get_us_time()
	local check_vertical = false
	neighbor_func = neighbor_func or get_neighbors

	local start = self._path_data.start or {
		x = floor(pos1.x + 0.5),
		y = floor(pos1.y + 0.5),
		z = floor(pos1.z + 0.5)
	}
	local goal = {
		x = floor(pos2.x + 0.5),
		y = floor(pos2.y + 0.5),
		z = floor(pos2.z + 0.5)
	}

	self._path_data.start = start

	if goal.x == start.x
	and goal.z == start.z then -- No path can be found
		self._path_data = {}
		return
	end

	local openSet = self._path_data.open or {}
	local closedSet = self._path_data.closed or {}
	local evaluated = {}

	local start_index = minetest.hash_node_position(start)

	openSet[start_index] = {
		pos = start,
		parent = nil,
		gScore = 0,
		fScore = get_distance(start, goal)
	}

	local count = self._path_data.count or 1
	local current_id, current
	local adjacent
	local neighbor

	local temp_gScore
	local new_gScore
	local hCost

	local hashed_pos
	local parent_open
	local parent_closed

	while count > 0 do

		-- Initialize ID and data
		current_id, current = next(openSet)

		-- Find lowest f cost
		for i, v in pairs(openSet) do
			if v.fScore < current.fScore then
				current_id = i
				current = v
			end
		end

		if not current_id then self._path_data = {} return end -- failsafe

		-- Add lowest fScore to closedSet and remove from openSet
		openSet[current_id] = nil
		closedSet[current_id] = current

		if ((check_vertical or is_on_ground(goal))
		and current_id == minetest.hash_node_position(goal))
		or ((not check_vertical and not is_on_ground(goal))
		and goal.x == current.pos.x
		and goal.z == current.pos.z) then
			local path = {}
			local fail_safe = 0

			for _ in pairs(closedSet) do
				fail_safe = fail_safe + 1
			end

			repeat
				if not closedSet[current_id] then self._path_data = {} return end
				table.insert(path, closedSet[current_id].pos)
				current_id = closedSet[current_id].parent
			until current_id == start_index or #path >= fail_safe

			if not closedSet[current_id] then self._path_data = {} return nil end

			table.insert(path, closedSet[current_id].pos)

			local reverse_path = {}
			repeat table.insert(reverse_path, table.remove(path)) until #path == 0

			self._path_data = {}
			return reverse_path
		end

		parent_open = openSet[current.parent]
		parent_closed = closedSet[current.parent]
		adjacent, check_vertical = neighbor_func(
			current.pos,
			self.width,
			self.height,
			openSet,
			closedSet,
			(parent_closed and parent_closed.pos) or (parent_open and parent_open.pos),
			evaluated
		)
		-- Fly, Swim, and Climb all return true for check_vertical to properly check if goal has been reached

		-- Go through neighboring nodes
		for i = 1, #adjacent do
			neighbor = {
				pos = adjacent[i],
				parent = current_id,
				gScore = 0,
				fScore = 0
			}

			temp_gScore = current.gScore + get_distance_to_neighbor(current.pos, neighbor.pos)
			new_gScore = 0

			hashed_pos = minetest.hash_node_position(neighbor.pos)

			if openSet[hashed_pos] then
				new_gScore = openSet[hashed_pos].gScore
			end

			if (temp_gScore < new_gScore
			or not openSet[hashed_pos])
			and not closedSet[hashed_pos] then
				if not openSet[hashed_pos] then
					count = count + 1
				end

				hCost = get_distance_to_neighbor(neighbor.pos, goal)

				neighbor.gScore = temp_gScore
				neighbor.fScore = temp_gScore + hCost
				openSet[hashed_pos] = neighbor
			end
		end

		if minetest.get_us_time() - us_time > a_star_alloted_time then
			self._path_data = {
				start = start,
				open = openSet,
				closed = closedSet,
				count = count
			}
			return
		end

		if count > (max_open or 100) then
			self._path_data = {}
			return
		end
	end
end

-- Theta*

function creatura.pathfinder.find_path_theta(self, pos1, pos2, neighbor_func)
	local us_time = minetest.get_us_time()
	local check_vertical = false
	neighbor_func = neighbor_func or get_neighbors

	local start = self._path_data.start or {
		x = floor(pos1.x + 0.5),
		y = floor(pos1.y + 0.5),
		z = floor(pos1.z + 0.5)
	}
	local goal = {
		x = floor(pos2.x + 0.5),
		y = floor(pos2.y + 0.5),
		z = floor(pos2.z + 0.5)
	}

	self._path_data.start = start

	if goal.x == start.x
	and goal.z == start.z then -- No path can be found
		return
	end

	local openSet = self._path_data.open or {}
	local closedSet = self._path_data.closed or {}
	local evaluated = {}

	local start_index = minetest.hash_node_position(start)

	openSet[start_index] = {
		pos = start,
		parent = nil,
		gScore = 0,
		fScore = get_distance(start, goal)
	}

	local count = self._path_data.count or 1
	local current_id, current
	local current_parent
	local adjacent
	local neighbor

	local temp_gScore
	local new_gScore
	local hCost

	local hashed_pos
	local parent_open
	local parent_closed

	while count > 0 do

		-- Initialize ID and data
		current_id, current = next(openSet)

		-- Find lowest f cost
		for i, v in pairs(openSet) do
			if v.fScore < current.fScore then
				current_id = i
				current = v
			end
		end

		if not current_id then return end -- failsafe

		-- Add lowest fScore to closedSet and remove from openSet
		openSet[current_id] = nil
		closedSet[current_id] = current

		if ((check_vertical or is_on_ground(goal))
		and current_id == minetest.hash_node_position(goal))
		or ((not check_vertical and not is_on_ground(goal))
		and goal.x == current.pos.x
		and goal.z == current.pos.z) then
			local path = {}
			local fail_safe = 0

			for _ in pairs(closedSet) do
				fail_safe = fail_safe + 1
			end

			repeat
				if not closedSet[current_id] then return end
				table.insert(path, closedSet[current_id].pos)
				current_id = closedSet[current_id].parent
			until current_id == start_index or #path >= fail_safe

			if not closedSet[current_id] then self._path_data = {} return nil end

			table.insert(path, closedSet[current_id].pos)

			local reverse_path = {}
			repeat table.insert(reverse_path, table.remove(path)) until #path == 0

			self._path_data = {}
			return reverse_path
		end

		parent_open = openSet[current.parent]
		parent_closed = closedSet[current.parent]
		adjacent, check_vertical = neighbor_func(
			current.pos,
			self.width,
			self.height,
			openSet,
			closedSet,
			(parent_closed and parent_closed.pos) or (parent_open and parent_open.pos),
			evaluated
		)
		-- Fly, Swim, and Climb all return true for check_vertical to properly check if goal has been reached

		-- Go through neighboring nodes
		for i = 1, #adjacent do
			neighbor = {
				pos = adjacent[i],
				parent = current_id,
				gScore = 0,
				fScore = 0
			}

			hashed_pos = minetest.hash_node_position(neighbor.pos)

			if not openSet[hashed_pos]
			and not closedSet[hashed_pos] then
				current_parent = closedSet[current.parent] or closedSet[start_index]
				if not current_parent then
					current_parent = openSet[current.parent] or openSet[start_index]
				end

				if current_parent
				and get_line_of_sight(current_parent.pos, neighbor.pos) then
					temp_gScore = current_parent.gScore + get_distance_to_neighbor(current_parent.pos, neighbor.pos)
					new_gScore = 999

					if openSet[hashed_pos] then
						new_gScore = openSet[hashed_pos].gScore
					end

					if temp_gScore < new_gScore then
						hCost = get_distance_to_neighbor(neighbor.pos, goal)
						neighbor.gScore = temp_gScore
						neighbor.fScore = temp_gScore + hCost
						neighbor.parent = minetest.hash_node_position(current_parent.pos)
						openSet[hashed_pos] = neighbor
						count = count + 1
					end
				else
					temp_gScore = current.gScore + get_distance_to_neighbor(current_parent.pos, neighbor.pos)
					new_gScore = 999

					if openSet[hashed_pos] then
						new_gScore = openSet[hashed_pos].gScore
					end

					if temp_gScore < new_gScore then
						hCost = get_distance_to_neighbor(neighbor.pos, goal)
						neighbor.gScore = temp_gScore
						neighbor.fScore = temp_gScore + hCost

						openSet[hashed_pos] = neighbor
						count = count + 1
					end
				end
			end
		end

		if minetest.get_us_time() - us_time > theta_star_alloted_time then
			self._path_data = {
				start = start,
				open = openSet,
				closed = closedSet,
				count = count
			}
			return
		end

		if count > (max_open or 100) then
			self._path_data = {}
			return
		end
	end
end