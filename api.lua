--------------
-- Creatura --
--------------

creatura.api = {}

-- Math --

local pi = math.pi
local pi2 = pi * 2
local abs = math.abs
local floor = math.floor
local random = math.random

local sin = math.sin
local cos = math.cos
local atan2 = math.atan2

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

local vec_dir = vector.direction
local vec_dist = vector.distance
local vec_multi = vector.multiply
local vec_sub = vector.subtract
local vec_add = vector.add

local function vec_center(v)
    return {x = floor(v.x + 0.5), y = floor(v.y + 0.5), z = floor(v.z + 0.5)}
end

local function vec_raise(v, n)
    if not v then return end
    return {x = v.x, y = v.y + n, z = v.z}
end

local function dist_2d(pos1, pos2)
    local a = {x = pos1.x, y = 0, z = pos1.z}
    local b = {x = pos2.x, y = 0, z = pos2.z}
    return vec_dist(a, b)
end

---------------
-- Local API --
---------------

local function indicate_damage(self)
    self.object:set_texture_mod("^[colorize:#FF000040")
    core.after(0.2, function()
        if creatura.is_alive(self) then
            self.object:set_texture_mod("")
        end
    end)
end

local function get_node_height(pos)
    local node = minetest.get_node(pos)
	local def = minetest.registered_nodes[node.name]
	if not def then return nil end
	if def.walkable then
		if def.drawtype == "nodebox" then
			if def.node_box
            and def.node_box.type == "fixed" then
				if type(def.node_box.fixed[1]) == "number" then
					return pos.y + node.node_box.fixed[5]
				elseif type(node.node_box.fixed[1]) == "table" then
					return pos.y + node.node_box.fixed[1][5]
				else
					return pos.y + 0.5
				end		
			elseif node.node_box
            and node.node_box.type == 'leveled' then
				return minetest.get_node_level(pos) / 64 - 0.5 + pos.y
			else
				return pos.y + 0.5
			end
		else
			return pos.y + 0.5
		end
	else
		return pos.y - 0.5
	end
end

local function walkable(pos)
    return minetest.registered_nodes[minetest.get_node(pos).name].walkable
end

local function is_under_solid(pos)
    local pos2 = vector.new(pos.x, pos.y + 1, pos.z)
    return (walkable(pos2) or ((get_node_height(pos2) or 0) < 1.5))
end

local function is_node_walkable(name)
    local def = minetest.registered_nodes[name]
    return def and def.walkable
end

local function is_value_in_table(tbl, val)
    for _, v in pairs(tbl) do
        if v == val then
            return true
        end
    end
    return false
end

-----------------------
-- Utility Functions --
-----------------------

-- Movement Methods --

creatura.registered_movement_methods = {}

function creatura.register_movement_method(name, func)
    creatura.registered_movement_methods[name] = func
end

-- Utility Behaviors --

creatura.registered_utilities = {}

function creatura.register_utility(name, func)
    creatura.registered_utilities[name] = func
end

-- Sensors --

function creatura.is_pos_moveable(pos, width, height)
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
    for x = pos1.x, pos2.x do
        for z = pos1.z, pos2.z do
            local pos3 = {x = x, y = (pos.y + height), z = z}
            local pos4 = {x = pos3.x, y = pos.y, z = pos3.z}
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

local moveable = creatura.is_pos_moveable

function creatura.fast_ray_sight(pos1, pos2, water)
    local ray = minetest.raycast(pos1, pos2, false, water or false)
    for pointed_thing in ray do
        if pointed_thing.type == "node" then
            return false, vec_dist(pos1, pointed_thing.intersection_point), pointed_thing.ref
        end
    end
    return true, vec_dist(pos1, pos2)
end

local fast_ray_sight = creatura.fast_ray_sight

function creatura.get_next_move(self, pos2)
    local last_move = self._movement_data.last_move
    local width = self.width
    local height = self.height
    local scan_width = width * 2
    local pos = self.object:get_pos()
    pos.y = floor(pos.y + 0.5)
    if last_move
    and last_move.pos then
        local last_call = minetest.get_position_from_hash(last_move.pos)
        local last_move = minetest.get_position_from_hash(last_move.move)
        if vector.equals(vec_center(last_call), vec_center(pos)) then
            return last_move
        end
    end
    local neighbors = {
        vec_add(pos, {x = 1, y = 0, z = 0}),
        vec_add(pos, {x = 1, y = 0, z = 1}),
        vec_add(pos, {x = 0, y = 0, z = 1}),
        vec_add(pos, {x = -1, y = 0, z = 1}),
        vec_add(pos, {x = -1, y = 0, z = 0}),
        vec_add(pos, {x = -1, y = 0, z = -1}),
        vec_add(pos, {x = 0, y = 0, z = -1}),
        vec_add(pos, {x = 1, y = 0, z = -1})
    }
    local next
    table.sort(neighbors, function(a, b)
        return vec_dist(a, pos2) < vec_dist(b, pos2)
    end)
    for i = 1, #neighbors do
        local neighbor = neighbors[i]
        local can_move = fast_ray_sight({x = pos.x, y = neighbor.y, z = pos.z}, neighbor)
        if vector.equals(neighbor, pos2) then
            can_move = true
        end
        if not self:is_pos_safe(vec_raise(neighbor, 0.6)) then
            can_move = false
        end
        if can_move
        and not moveable(vec_raise(neighbor, 0.6), width, height) then
            can_move = false
        end
        local dist = vec_dist(neighbor, pos2)
        if can_move then
            next = neighbor
            break
        end
    end
    if next then
        self._movement_data.last_move = {
            pos = minetest.hash_node_position(pos),
            move = minetest.hash_node_position(next)
        }
    end
    return next
end

function creatura.get_next_move_3d(self, pos2)
    local last_move = self._movement_data.last_move
    local width = self.width
    local height = self.height
    local scan_width = width * 2
    local pos = self.object:get_pos()
    pos.y = pos.y + 0.5
    if last_move
    and last_move.pos then
        local last_call = minetest.get_position_from_hash(last_move.pos)
        local last_move = minetest.get_position_from_hash(last_move.move)
        if vector.equals(vec_center(last_call), vec_center(pos)) then
            return last_move
        end
    end
    local neighbors = {
        vec_add(pos, {x = scan_width, y = 0, z = 0}),
        vec_add(pos, {x = scan_width, y = 0, z = scan_width}),
        vec_add(pos, {x = 0, y = 0, z = scan_width}),
        vec_add(pos, {x = -scan_width, y = 0, z = scan_width}),
        vec_add(pos, {x = -scan_width, y = 0, z = 0}),
        vec_add(pos, {x = -scan_width, y = 0, z = -scan_width}),
        vec_add(pos, {x = 0, y = 0, z = -scan_width}),
        vec_add(pos, {x = scan_width, y = 0, z = -scan_width})
    }
    local next
    table.sort(neighbors, function(a, b)
        return vec_dist(a, pos2) < vec_dist(b, pos2)
    end)
    for i = 1, #neighbors do
        local neighbor = neighbors[i]
        local can_move = fast_ray_sight({x = pos.x, y = neighbor.y, z = pos.z}, neighbor)
        if not moveable(vec_raise(neighbor, 0.6), width, height) then
            can_move = false
        end
        if vector.equals(neighbor, pos2) then
            can_move = true
        end
        local dist = vec_dist(neighbor, pos2)
        if can_move then
            next = neighbor
            break
        end
    end
    if next then
        self._movement_data.last_move = {
            pos = minetest.hash_node_position(pos),
            move = minetest.hash_node_position(next)
        }
    end
    return vec_raise(next, clamp((pos2.y - pos.y) + -0.6, -1, 1))
end

function creatura.sensor_floor(self, range, water)
    local pos = self.object:get_pos()
    local pos2 = vec_raise(pos, -range)
    local _, dist, node = fast_ray_sight(pos, pos2, water or false)
    return dist, node
end

function creatura.sensor_ceil(self, range, water)
    local pos = vec_raise(self.object:get_pos(), self.height)
    local pos2 = vec_raise(pos, range)
    local _, dist, node = fast_ray_sight(pos, pos2, water or false)
    return dist, node
end

-- Misc

function creatura.is_valid(mob)
	if not mob then return false end
	if type(mob) == "table" then mob = mob.object end
	if type(mob) == "userdata" then 
		if mob:is_player() then
			if mob:get_look_horizontal() then return mob end 
		else
			if mob:get_yaw() then return mob end
		end
	end
    return false
end

function creatura.is_alive(mob)
    if not creatura.is_valid(mob) then
        return false
    end
    if type(mob) == "table" then
        return mob.hp > 0
    end
    if mob:is_player() then
        return mob:get_hp() > 0
    else
        local ent = mob:get_luaentity()
        return ent and ent.hp and ent.hp > 0
    end
end

function creatura.get_nearby_player(self)
    local objects = minetest.get_objects_inside_radius(self:get_center_pos(), self.tracking_range)
	for _, object in ipairs(objects) do
		if object:is_player()
        and creatura.is_alive(object) then
            return object
        end
	end
end

function creatura.get_nearby_players(self)
    local objects = minetest.get_objects_inside_radius(self:get_center_pos(), self.tracking_range)
    local nearby = {}
	for _, object in ipairs(objects) do
		if object:is_player()
        and creatura.is_alive(object) then
            table.insert(nearby, object)
        end
	end
	return nearby
end

function creatura.get_nearby_entity(self, name)
    local objects = minetest.get_objects_inside_radius(self:get_center_pos(), self.tracking_range)
	for _, object in ipairs(objects) do
		if creatura.is_alive(object)
        and not object:is_player()
        and object ~= self.object
        and object:get_luaentity().name == name then
            return object
        end
	end
	return
end

function creatura.get_nearby_entities(self, name)
    local objects = minetest.get_objects_inside_radius(self:get_center_pos(), self.tracking_range)
    local nearby = {}
	for _, object in ipairs(objects) do
		if creatura.is_alive(object)
        and not object:is_player()
        and object ~= self.object
        and object:get_luaentity().name == name then
            table.insert(nearby, object)
        end
	end
	return nearby
end

function creatura.get_node_def(pos)
    local def = minetest.registered_nodes[minetest.get_node(pos).name]
    return def
end

--------------------
-- Global Mob API --
--------------------

-- Drops --

function creatura.drop_items(self)
    if not self.drops then return end
    for i = 1, #self.drops do
        local drop_def = self.drops[i]
        local name = drop_def.name
        if not name then return end
        local min_amount = drop_def.min or 1
        local max_amount = drop_def.max or 2
        local chance = drop_def.chance or 1
        local amount = random(min_amount, max_amount)
        if random(chance) < 2 then
            local pos = self.object:get_pos()
            local item = minetest.add_item(pos, ItemStack(name .. " " .. amount))
            if item then
                item:add_velocity({
                    x = random(-2, 2),
                    y = 1.5,
                    z = random(-2, 2)
                })
            end
        end
    end
end

-- On Punch --

function creatura.basic_punch_func(self, puncher, time_from_last_punch, tool_capabilities, direction, damage)
    if not puncher then return end
    local tool = ""
    if puncher:is_player() then
        tool = puncher:get_wielded_item():get_name()
    end
    if (self.immune_to
    and is_value_in_table(self.immune_to, tool)) then
        return
    end
    local dir = vec_dir(puncher:get_pos(), self:get_center_pos())
    self:apply_knockback(dir)
    self:hurt(tool_capabilities.damage_groups.fleshy or 2)
    if random(4) < 2 then
        self:play_sound("hurt")
    end
    if time_from_last_punch > 0.5 then
        self:play_sound("hit")
    end
    indicate_damage(self)
end

local path = minetest.get_modpath("creatura")

dofile(path.."/mob_meta.lua")