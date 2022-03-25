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

creatura.register_movement_method("creatura:pathfind", function(self, pos2)
    -- Movement Data
    local pos = self.object:get_pos()
    local movement_data = self._movement_data
    local waypoint = movement_data.waypoint
    local speed = movement_data.speed or 5
    local path = self._path
    if not path or #path < 2 then
        self._path = creatura.find_path(self, pos, pos2, self.width, self.height, 200) or {}
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
    local turn_rate = abs(self.turn_rate) or 5
    local yaw_diff = abs(diff(yaw, tgt_yaw))
    -- Moving
    self:set_gravity(-9.8)
    if yaw_diff < pi * (turn_rate * 0.1) then
        self:animate(movement_data.anim or "walk")
        self:set_forward_velocity(speed)
    else
        self:set_forward_velocity(speed * 0.5)
        turn_rate = turn_rate * 1.5
    end
    self:turn_to(tgt_yaw, turn_rate)
    if self:pos_in_box(pos2) then
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
    local turn_rate = abs(self.turn_rate) or 5
    local yaw_diff = abs(diff(yaw, tgt_yaw))
    -- Moving
    self:set_gravity(-9.8)
    if yaw_diff < pi * (turn_rate * 0.1) then
        self:animate(movement_data.anim or "walk")
        self:set_forward_velocity(speed)
    else
        self:set_forward_velocity(speed * 0.5)
        turn_rate = turn_rate * 1.5
    end
    self:turn_to(tgt_yaw, turn_rate)
    if self:pos_in_box(pos2) then
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
    local turn_rate = self.turn_rate or 5
    local yaw_diff = abs(diff(yaw, tgt_yaw))
    -- Moving
    self:set_gravity(-9.8)
    if yaw_diff < pi * 0.25 then
        self:animate(movement_data.anim or "walk")
        self:set_forward_velocity(speed)
    else
        self:set_forward_velocity(speed * 0.5)
        turn_rate = turn_rate * 1.5
    end
    self:turn_to(tgt_yaw, turn_rate)
    if self:pos_in_box(pos2) then
        self:halt()
    end
end)

-- Obstacle Avoidance

local moveable = creatura.is_pos_moveable

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
    local turn_rate = self.turn_rate or 5
    local yaw_diff = abs(diff(yaw, tgt_yaw))
    -- Moving
    self:set_gravity(-9.8)
    if yaw_diff < pi * 0.25 then
        self:animate(movement_data.anim or "walk")
        self:set_forward_velocity(speed)
    else
        self:set_forward_velocity(speed * 0.5)
        turn_rate = turn_rate * 1.5
    end
    self:turn_to(tgt_yaw, turn_rate)
    if self:pos_in_box(pos2) then
        self:halt()
    end
end)