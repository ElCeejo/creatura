-------------
-- Methods --
-------------

local pi = math.pi
local pi2 = pi * 2
local abs = math.abs
local floor = math.floor
local random = math.random
local rad = math.rad

local function diff(a, b) -- Get difference between 2 angles
    return math.atan2(math.sin(b - a), math.cos(b - a))
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

local function vec_raise(v, n)
    return {x = v.x, y = v.y + n, z = v.z}
end

local vec_dir = vector.direction
local vec_dist = vector.distance
local vec_multi = vector.multiply
local vec_add = vector.add
local yaw2dir = minetest.yaw_to_dir

-------------
-- Actions --
-------------

-- Actions are more specific behaviors used
-- to compose a Utility.

-- Walk

function creatura.action_walk(self, pos2, timeout, method, speed_factor, anim)
    local timer = timeout or 4
    local move_init = false
    local function func(self)
        if not pos2
        or (move_init
        and not self._movement_data.goal) then return true end
        local pos = self.object:get_pos()
        timer = timer - self.dtime
        if timer <= 0
        or self:pos_in_box({x = pos2.x, y = pos.y + 0.1, z = pos2.z}) then
            self:halt()
            return true
        end
        self:move(pos2, method or "creatura:neighbors", speed_factor or 0.5, anim)
        move_init = true
    end
    self:set_action(func)
end

function creatura.action_fly(self, pos2, timeout, method, speed_factor, anim)
    local timer = timeout or 4
    local move_init = false
    local function func(self)
        if not pos2
        or (move_init
        and not self._movement_data.goal) then return true end
        local pos = self.object:get_pos()
        timer = timer - self.dtime
        if timer <= 0
        or self:pos_in_box(pos2) then
            self:halt()
            return true
        end
        self:move(pos2, method, speed_factor or 0.5, anim)
        move_init = true
    end
    self:set_action(func)
end

-- Idle

function creatura.action_idle(self, time, anim)
    local timer = time
    local function func(self)
        self:set_gravity(-9.8)
        self:halt()
        self:animate(anim or "stand")
        timer = timer - self.dtime
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
	local function func(self)
		if not init then
			self:animate("stand")
            if random(2) < 2 then
                dir = -1
            end
			init = true
		end
		local rot = self.object:get_rotation()
        local goal = (pi * 0.5) * dir
        local dif = abs(rot.z - goal)
        zrot = rot.z + (dif * dir) * 0.15
		self.object:set_rotation({x = rot.x, y = rot.y, z = zrot})
		if (dir > 0 and zrot >= goal)
        or (dir < 0 and zrot <= goal) then return true end
	end
	self:set_action(func)
end

----------------------
-- Movement Methods --
----------------------

-- Pathfinding

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

local function movement_theta_pathfind(self, pos2, speed)
    local pos = self.object:get_pos()
    self._path = self._path or {}
    local temp_goal = self._movement_data.temp_goal
    if not temp_goal
    or self:pos_in_box({x = temp_goal.x, y = pos.y + self.height * 0.5, z = temp_goal.z}) then
        self._movement_data.temp_goal = creatura.get_next_move(self, pos2)
        temp_goal = self._movement_data.temp_goal
    end
    if #self._path < 1 then
        self._path = creatura.find_theta_path(self, self.object:get_pos(), pos2, self.width, self.height, 500) or {}
    else
        temp_goal = self._path[2] or self._path[1]
        if self:pos_in_box({x = temp_goal.x, y = pos.y + self.height * 0.5, z = temp_goal.z}) then
            table.remove(self._path, 1)
        end
    end
    local dir = vector.direction(self.object:get_pos(), pos2)
    local tyaw = minetest.dir_to_yaw(dir)
    local turn_rate = self.turn_rate or 10
    if temp_goal then
        dir = vector.direction(self.object:get_pos(), temp_goal)
        tyaw = minetest.dir_to_yaw(dir)
        if #self._path < 1
        and not self:is_pos_safe(temp_goal) then
            self:animate("walk")
            self:set_forward_velocity(0)
            self:halt()
            return
        end
    end
    self:turn_to(tyaw, turn_rate)
    self:animate("walk")
    self:set_gravity(-9.8)
    self:set_forward_velocity(speed or 2)
    if self:pos_in_box(pos2) then
        self:halt()
    end
end

creatura.register_movement_method("creatura:theta_pathfind", movement_theta_pathfind)

local function movement_pathfind(self, pos2, speed)
    local pos = self.object:get_pos()
    local temp_goal = self._movement_data.temp_goal
    self._path = self._path or {}
    if (not temp_goal
    or self:pos_in_box({x = temp_goal.x, y = pos.y + self.height * 0.5, z = temp_goal.z}))
    and #self._path < 1 then
        self._movement_data.temp_goal = creatura.get_next_move(self, pos2)
        temp_goal = self._movement_data.temp_goal
    end
    if #self._path < 2 then
        self._path = creatura.find_path(self, self.object:get_pos(), pos2, self.width, self.height, 100) or {}
    else
        temp_goal = self._path[2]
        if self:pos_in_box({x = temp_goal.x, y = pos.y + self.height * 0.5, z = temp_goal.z}) then
            table.remove(self._path, 1)
        end
    end
    local dir = vector.direction(self.object:get_pos(), pos2)
    local tyaw = minetest.dir_to_yaw(dir)
    local turn_rate = self.turn_rate or 10
    if temp_goal then
        dir = vector.direction(self.object:get_pos(), temp_goal)
        tyaw = minetest.dir_to_yaw(dir)
        if #self._path < 2
        and not self:is_pos_safe(temp_goal) then
            self:animate("walk")
            self:set_forward_velocity(0)
            self:halt()
            return
        end
    end
    self:turn_to(tyaw, turn_rate)
    self:animate("walk")
    self:set_gravity(-9.8)
    self:set_forward_velocity(speed or 2)
    if self:pos_in_box(pos2) then
        self:halt()
    end
end

creatura.register_movement_method("creatura:pathfind", movement_pathfind)

-- Obstacle Avoidance

local function moveable(pos, width, height)
    local pos1 = {
        x = pos.x - (width + 0.2),
        y = pos.y,
        z = pos.z - (width + 0.2),
    }
    local pos2 = {
        x = pos.x + (width + 0.2),
        y = pos.y,
        z = pos.z + (width + 0.2),
    }
    for z = pos1.z, pos2.z do
        for x = pos1.x, pos2.x do
            local pos3 = {x = x, y = (pos.y + height), z = z}
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

local function get_obstacle_avoidance(self, pos2)
    local pos = self.object:get_pos()
    local yaw = minetest.dir_to_yaw(vec_dir(pos, pos2))
    pos.y = pos.y + self.stepheight
    local height = self.height
    local width = self.width
    local outset = vec_center(vec_add(pos, vec_multi(yaw2dir(yaw), width + 0.2)))
    local pos2
    if not moveable(outset, width, height) then
        yaw = self.object:get_yaw()
        for i = 1, 89, 45 do
            angle = rad(i)
            dir = vec_multi(yaw2dir(yaw + angle), width + 0.2)
            pos2 = vec_center(vec_add(pos, dir))
            if moveable(pos2, width, height) then
                break
            end
            angle = -rad(i)
            dir = vec_multi(yaw2dir(yaw + angle), width + 0.2)
            pos2 = vec_center(vec_add(pos, dir))
            if moveable(pos2, width, height) then
                break
            end
        end
    end
    return pos2
end

local function movement_obstacle_avoidance(self, pos2, speed)
    local pos = self.object:get_pos()
    local temp_goal = self._movement_data.temp_goal
    if not temp_goal
    or self:pos_in_box(temp_goal) then
        self._movement_data.temp_goal = get_obstacle_avoidance(self, pos2)
        temp_goal = self._movement_data.temp_goal
        if temp_goal then
            temp_goal.y = floor(pos.y + self.height * 0.5)
        end
    end
    pos2.y = floor(pos2.y + 0.5)
    local dir = vector.direction(pos, pos2)
    local tyaw = minetest.dir_to_yaw(dir)
    local turn_rate = self.turn_rate or 10
    if temp_goal then
        dir = vector.direction(pos, temp_goal)
        tyaw = minetest.dir_to_yaw(dir)
    end
    local turn_diff = abs(diff(self.object:get_yaw(), tyaw))
    self:turn_to(tyaw, turn_rate)
    self:animate("walk")
    self:set_gravity(-9.8)
    self:set_forward_velocity(speed - clamp(turn_diff, 0, speed * 0.66))
    if self:pos_in_box({x = pos2.x, y = pos.y + 0.1, z = pos2.z})
    or (temp_goal
    and not self:is_pos_safe(temp_goal)) then
        self:halt()
    end
end

creatura.register_movement_method("creatura:obstacle_avoidance", movement_obstacle_avoidance)

-- Neighbors

local function movement_neighbors(self, pos2, speed)
    local pos = self.object:get_pos()
    local temp_goal = self._movement_data.temp_goal
    local width = clamp(self.width, 0.5, 1.5)
    if not temp_goal
    or self:pos_in_box(temp_goal) then
        self._movement_data.temp_goal = creatura.get_next_move(self, pos2)
        temp_goal = self._movement_data.temp_goal
    end
    pos2.y = pos.y + self.height * 0.5
    local yaw = self.object:get_yaw()
    local dir = vector.direction(self.object:get_pos(), pos2)
    local tyaw = minetest.dir_to_yaw(dir)
    local turn_rate = self.turn_rate or 10
    if temp_goal then
        temp_goal.x = math.floor(temp_goal.x + 0.5)
        temp_goal.z = math.floor(temp_goal.z + 0.5)
        temp_goal.y = pos.y + self.height * 0.5
        dir = vector.direction(self.object:get_pos(), temp_goal)
        tyaw = minetest.dir_to_yaw(dir)
        if not self:is_pos_safe(temp_goal) then
            self:set_forward_velocity(0)
            self:halt()
            return
        end
    end
    local yaw_diff = abs(diff(yaw, tyaw))
    self:turn_to(tyaw, turn_rate)
    self:set_gravity(-9.8)
    if yaw_diff < pi then
        self:animate("walk")
        self:set_forward_velocity(speed)
    end
    if self:pos_in_box(pos2) then
        self:halt()
    end
end

creatura.register_movement_method("creatura:neighbors", movement_neighbors)

