-----------------
-- Pathfinding --
-----------------

local a_star_alloted_time = tonumber(minetest.settings:get("creatura_a_star_alloted_time")) or 500
local theta_star_alloted_time = tonumber(minetest.settings:get("creatura_theta_star_alloted_time")) or 700

local floor = math.floor
local abs = math.abs

local function is_node_walkable(name)
    local def = minetest.registered_nodes[name]
    return def and def.walkable
end

local function is_node_liquid(name)
    local def = minetest.registered_nodes[name]
    return def and def.drawtype == "liquid"
end

local function moveable(pos, width, height)
    local pos1 = {
        x = pos.x - width,
        y = pos.y,
        z = pos.z - width,
    }
    local pos2 = {
        x = pos.x + width,
        y = pos.y,
        z = pos.z + width,
    }
    for z = pos1.z, pos2.z do
        for x = pos1.x, pos2.x do
            local pos3 = {x = x, y = pos.y + height, z = z}
            local pos4 = {x = x, y = pos.y, z = z}
            local ray = minetest.raycast(pos3, pos4, false, false)
            for pointed_thing in ray do
                if pointed_thing.type == "node" then
                    return false
                end
            end
        end
    end
    return true
end

creatura.get_node_height = function(name, force_node_box)
    local def = minetest.registered_nodes[name]
    if not def then return 0.5 end
    if def.walkable then
        if def.drawtype == "nodebox" then
            if def.collision_box and not force_node_box
            and (def.collision_box.type == "fixed" or def.collision_box.type == "connected") then
                if type(def.collision_box.fixed[1]) == "number" then
                    return 0.5 + def.collision_box.fixed[5]
                elseif type(def.collision_box.fixed[1]) == "table" then
                    return 0.5 + def.collision_box.fixed[1][5]
                else
                    return 1
                end
            elseif def.node_box
            and (def.node_box.type == "fixed" or def.node_box.type == "connected") then
                if type(def.node_box.fixed[1]) == "number" then
                    return 0.5 + def.node_box.fixed[5]
                elseif type(def.node_box.fixed[1]) == "table" then
                    return 0.5 + def.node_box.fixed[1][5]
                else
                    return 1
                end
            else
                return 1
            end
        else
            return 1
        end
    else
        return 1
    end
end

creatura.get_ground_level = function(pos, max_up, max_down, current_node_height)
    for y = math.ceil(max_up) + 1, -(math.ceil(max_down)) - 1, -1 do
        local pos2 = vector.new(pos.x, pos.y + y, pos.z)
        local node = minetest.get_node(pos2)
        local node_under = minetest.get_node(pos2 + vector.new(0, -1, 0))

        if not is_node_walkable(node.name) and is_node_walkable(node_under.name) then
            local node_height = creatura.get_node_height(node_under.name)
            local y_diff = y - 1 + node_height - current_node_height
            if y_diff <= max_up and y_diff >= (-max_down) then
                return pos2
            end
        end
    end
    return nil
end

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

local function is_on_ground(pos)
    local ground = {
        x = pos.x,
        y = pos.y - 1,
        z = pos.z
    }
    if is_node_walkable(minetest.get_node(ground).name) then
        return true
    end
    return false
end

local function vec_raise(v, n)
    return {x = v.x, y = v.y + n, z = v.z}
end

-- Find a path from start to goal

local function get_neighbors(self, pos, goal, swim, fly, climb, tbl, open, closed)
    local width = self.width
    local height = self.height
    local result = {}
    local max_up = self.stepheight or 1
    local max_down = self.max_fall or 1

    local node_name = minetest.get_node(pos).name
    -- Get the height of the node collision box (and of its node box, if different)
    local node_height = 0
    local node_height_node_box = 0
    if is_node_walkable(node_name) then
        node_height = creatura.get_node_height(node_name)
        node_height_node_box = creatura.get_node_height(node_name, true)
    else
        node_height = creatura.get_node_height(minetest.get_node(pos + vector.new(0, -1, 0)).name) - 1
        node_height_node_box = creatura.get_node_height(minetest.get_node(pos + vector.new(0, -1, 0)).name, true) - 1
    end
    -- Calculate the height difference between the collision and node boxes
    -- (This is because the mob will be standing on the collision box, but the
    --  raycast checks will collide with the node box, so we must avoid it)
    local node_height_diff = node_height_node_box - node_height

    for i = 1, #tbl do
        local neighbor = vector.add(pos, tbl[i])
        if not open[minetest.hash_node_position(neighbor)]
        and not closed[minetest.hash_node_position(neighbor)] then

            local neighbor_x
            local neighbor_z

            if tbl[i].y == 0
            and not fly
            and not swim then
                neighbor = creatura.get_ground_level(neighbor, max_up, max_down, node_height)
                if neighbor and tbl[i].x ~= 0 and tbl[i].z ~= 0 then
                    -- This is a diagonal, check both corners are clear and same Y
                    neighbor_x = creatura.get_ground_level(vector.new(neighbor.x, neighbor.y, pos.z), max_up, max_down, node_height)
                    neighbor_z = creatura.get_ground_level(vector.new(pos.x, neighbor.y, neighbor.z), max_up, max_down, node_height)
                    if not neighbor_x or not neighbor_z
                    or neighbor_x.y ~= neighbor.y
                    or neighbor_z.y ~= neighbor.y then
                        neighbor = nil
                    end
                end
            end
            if neighbor then
                local can_move = true
                if swim then
                    local neighbor_node = minetest.get_node(neighbor)
                    can_move = is_node_liquid(neighbor_node.name)
                end

                -- Adjust entity Y in clearance check by this much
                local y_adjustment = -0.49
                -- Adjust entity height in clearance check by this much
                local h_adjustment = -0.02
                -- Get the height of the node collision box, and the difference to the node box
                local neighbor_height = creatura.get_node_height(minetest.get_node(neighbor + vector.new(0, -1, 0)).name) - 1
                local neighbor_height_node_box = creatura.get_node_height(minetest.get_node(neighbor + vector.new(0, -1, 0)).name, true) - 1
                local neighbor_height_diff = neighbor_height_node_box - neighbor_height
                -- Check there is enough vertical clearance to move to this node
                local height_clearance = math.max(pos.y + node_height - neighbor.y - neighbor_height, 0)
                if not moveable(vec_raise(neighbor, y_adjustment + neighbor_height + neighbor_height_diff), width, height + h_adjustment + height_clearance - neighbor_height_diff) then
                    can_move = false
                end
                if tbl[i].x ~= 0 and tbl[i].z ~= 0 then
                    -- If target node is diagonal, check the orthogonal nodes too
                    if not moveable(vec_raise(neighbor_x, y_adjustment + neighbor_height + neighbor_height_diff), width, height + h_adjustment + height_clearance + neighbor_height_diff)
                    or not moveable(vec_raise(neighbor_z, y_adjustment + neighbor_height + neighbor_height_diff), width, height + h_adjustment + height_clearance + neighbor_height_diff) then
                        can_move = false
                    end
                end
                -- If we're going upwards, check there's enough clearance above our head
                height_clearance = math.max(neighbor.y + neighbor_height - pos.y - node_height, 0)
                if height_clearance > 0 and not moveable(vec_raise(pos, y_adjustment + node_height + node_height_diff), width, height + h_adjustment + height_clearance - node_height_diff) then
                    can_move = false
                end

                if (can_move
                    or (climb
                        and neighbor.x == pos.x
                        and neighbor.z == pos.z))
                and (not swim
                    or is_node_liquid(minetest.get_node(neighbor).name)) then
                    table.insert(result, neighbor)
                end
            end
        end
    end
    return result
end

function creatura.find_path(self, start, goal, obj_width, obj_height, max_open, climb, fly, swim)
    climb = climb or false
    fly = fly or false
    swim = swim or false

    start = self._path_data.start or start

    self._path_data.start = start

    local path_neighbors = {
        {x = 1, y = 0, z = 0},
        {x = 1, y = 0, z = 1},
        {x = 0, y = 0, z = 1},
        {x = -1, y = 0, z = 1},
        {x = -1, y = 0, z = 0},
        {x = -1, y = 0, z = -1},
        {x = 0, y = 0, z = -1},
        {x = 1, y = 0, z = -1}
    }

    if climb then
        table.insert(path_neighbors, {x = 0, y = 1, z = 0})
    end

    if fly
    or swim then
        path_neighbors = {
            -- Central
            {x = 1, y = 0, z = 0},
            {x = 0, y = 0, z = 1},
            {x = -1, y = 0, z = 0},
            {x = 0, y = 0, z = -1},
            -- Directly Up or Down
            {x = 0, y = 1, z = 0},
            {x = 0, y = -1, z = 0}
        }
    end

    local function find_path(self, start, goal)
        local us_time = minetest.get_us_time()

        start = {
            x = floor(start.x + 0.5),
            y = floor(start.y + 0.5),
            z = floor(start.z + 0.5)
        }

        goal = {
            x = floor(goal.x + 0.5),
            y = floor(goal.y + 0.5),
            z = floor(goal.z + 0.5)
        }

        if goal.x == start.x
        and goal.z == start.z then -- No path can be found
            return nil
        end

        local openSet = self._path_data.open or {}

        local closedSet = self._path_data.closed or {}

        local start_index = minetest.hash_node_position(start)

        openSet[start_index] = {
            pos = start,
            parent = nil,
            gScore = 0,
            fScore = get_distance(start, goal)
        }

        local count = self._path_data.count or 1

        while count > 0 do
            if minetest.get_us_time() - us_time > a_star_alloted_time then
                self._path_data = {
                    start = start,
                    open = openSet,
                    closed = closedSet,
                    count = count
                }
                return
            end
            -- Initialize ID and data
            local current_id
            local current

            -- Get an initial id in open set
            for i, v in pairs(openSet) do
                current_id = i
                current = v
                break
            end

            -- Find lowest f cost
            for i, v in pairs(openSet) do
                if v.fScore < current.fScore then
                    current_id = i
                    current = v
                end
            end

            -- Add lowest fScore to closedSet and remove from openSet
            openSet[current_id] = nil
            closedSet[current_id] = current

            self._path_data.open = openSet
            self._path_data.closedSet = closedSet

            -- Reconstruct path if end is reached
            if ((is_on_ground(goal)
            or fly)
            and current_id == minetest.hash_node_position(goal))
            or (not fly
            and not is_on_ground(goal)
            and goal.x == current.pos.x
            and goal.z == current.pos.z) then
                local path = {}
                local fail_safe = 0
                for k, v in pairs(closedSet) do
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

            count = count - 1

            local adjacent = get_neighbors(self, current.pos, goal, swim, fly, climb, path_neighbors, openSet, closedSet)

            -- Go through neighboring nodes
            for i = 1, #adjacent do
                local neighbor = {
                    pos = adjacent[i],
                    parent = current_id,
                    gScore = 0,
                    fScore = 0
                }
                local neighbor_id = minetest.hash_node_position(neighbor.pos)
                local neighbour_gScore = current.gScore + get_distance_to_neighbor(current.pos, neighbor.pos)
                if (not openSet[neighbor_id]
                    or neighbour_gScore < openSet[neighbor_id].gScore)
                and not closedSet[neighbor_id] then
                    if not openSet[neighbor_id] then
                        count = count + 1
                    end
                    local hCost = get_distance_to_neighbor(neighbor.pos, goal)
                    neighbor.gScore = neighbour_gScore
                    neighbor.fScore = neighbour_gScore + hCost
                    openSet[neighbor_id] = neighbor
                end
            end
            if count > (max_open or 100) then
                self._path_data = {}
                return
            end
        end
        self._path_data = {}
        return nil
    end
    return find_path(self, start, goal)
end


------------
-- Theta* --
------------

function get_line_of_sight(a, b)
    local steps = floor(vector.distance(a, b))
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
            if minetest.registered_nodes[node.name].walkable then
                return false
            end
        end
    end
    return true
end

function creatura.find_theta_path(self, start, goal, obj_width, obj_height, max_open, climb, fly, swim)
    climb = climb or false
    fly = fly or false
    swim = swim or false

    start = self._path_data.start or start

    self._path_data.start = start

    local path_neighbors = {
        {x = 1, y = 0, z = 0},
        {x = 0, y = 0, z = 1},
        {x = -1, y = 0, z = 0},
        {x = 0, y = 0, z = -1},
    }

    if climb then
        table.insert(path_neighbors, {x = 0, y = 1, z = 0})
    end

    if fly
    or swim then
        path_neighbors = {
            -- Central
            {x = 1, y = 0, z = 0},
            {x = 0, y = 0, z = 1},
            {x = -1, y = 0, z = 0},
            {x = 0, y = 0, z = -1},
            -- Directly Up or Down
            {x = 0, y = 1, z = 0},
            {x = 0, y = -1, z = 0}
        }
    end

    local function find_path(self, start, goal)
        local us_time = minetest.get_us_time()

        start = {
            x = floor(start.x + 0.5),
            y = floor(start.y + 0.5),
            z = floor(start.z + 0.5)
        }

        goal = {
            x = floor(goal.x + 0.5),
            y = floor(goal.y + 0.5),
            z = floor(goal.z + 0.5)
        }

        if goal.x == start.x
        and goal.z == start.z then -- No path can be found
            return nil
        end

        local openSet = self._path_data.open or {}

        local closedSet = self._path_data.closed or {}

        local start_index = minetest.hash_node_position(start)

        openSet[start_index] = {
            pos = start,
            parent = nil,
            gScore = 0,
            fScore = get_distance(start, goal)
        }

        local count = self._path_data.count or 1

        while count > 0 do
            if minetest.get_us_time() - us_time > theta_star_alloted_time then
                self._path_data = {
                    start = start,
                    open = openSet,
                    closed = closedSet,
                    count = count
                }
                return
            end

            -- Initialize ID and data
            local current_id
            local current

            -- Get an initial id in open set
            for i, v in pairs(openSet) do
                current_id = i
                current = v
                break
            end

            -- Find lowest f cost
            for i, v in pairs(openSet) do
                if v.fScore < current.fScore then
                    current_id = i
                    current = v
                end
            end

            -- Add lowest fScore to closedSet and remove from openSet
            openSet[current_id] = nil
            closedSet[current_id] = current

            -- Reconstruct path if end is reached
            if (is_on_ground(goal)
            and current_id == minetest.hash_node_position(goal))
            or (not is_on_ground(goal)
            and goal.x == current.pos.x
            and goal.z == current.pos.z) then
                local path = {}
                local fail_safe = 0
                for k, v in pairs(closedSet) do
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

            count = count - 1

            local adjacent = get_neighbors(self, current.pos, goal, swim, fly, climb, path_neighbors, openSet, closedSet)

            -- Go through neighboring nodes
            for i = 1, #adjacent do
                local neighbor = {
                    pos = adjacent[i],
                    parent = current_id,
                    gScore = 0,
                    fScore = 0
                }
                if not openSet[minetest.hash_node_position(neighbor.pos)]
                and not closedSet[minetest.hash_node_position(neighbor.pos)] then
                    local current_parent = closedSet[current.parent] or closedSet[start_index]
                    if not current_parent then
                        current_parent = openSet[current.parent] or openSet[start_index]
                    end
                    if current_parent
                    and get_line_of_sight(current_parent.pos, neighbor.pos) then
                        local temp_gScore = current_parent.gScore + get_distance_to_neighbor(current_parent.pos, neighbor.pos)
                        local new_gScore = 999
                        if openSet[minetest.hash_node_position(neighbor.pos)] then
                            new_gScore = openSet[minetest.hash_node_position(neighbor.pos)].gScore
                        end
                        if temp_gScore < new_gScore then
                            local hCost = get_distance_to_neighbor(neighbor.pos, goal)
                            neighbor.gScore = temp_gScore
                            neighbor.fScore = temp_gScore + hCost
                            neighbor.parent = minetest.hash_node_position(current_parent.pos)
                            if openSet[minetest.hash_node_position(neighbor.pos)] then
                                openSet[minetest.hash_node_position(neighbor.pos)] = nil
                            end
                            openSet[minetest.hash_node_position(neighbor.pos)] = neighbor
                            count = count + 1
                        end
                    else
                        local temp_gScore = current.gScore + get_distance_to_neighbor(current_parent.pos, neighbor.pos)
                        local new_gScore = 999
                        if openSet[minetest.hash_node_position(neighbor.pos)] then
                            new_gScore = openSet[minetest.hash_node_position(neighbor.pos)].gScore
                        end
                        if temp_gScore < new_gScore then
                            local hCost = get_distance_to_neighbor(neighbor.pos, goal)
                            neighbor.gScore = temp_gScore
                            neighbor.fScore = temp_gScore + hCost
                            if openSet[minetest.hash_node_position(neighbor.pos)] then
                                openSet[minetest.hash_node_position(neighbor.pos)] = nil
                            end
                            openSet[minetest.hash_node_position(neighbor.pos)] = neighbor
                            count = count + 1
                        end
                    end
                end
            end
            if count > (max_open or 100) then
                self._path_data = {}
                return
            end
        end
        self._path_data = {}
        return nil
    end
    return find_path(self, start, goal)
end