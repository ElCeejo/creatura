--------------
-- Creatura --
--------------

creatura.api = {}

-- Math --

local floor = math.floor
local random = math.random

local function clamp(val, min, max)
	if val < min then
		val = min
	elseif max < val then
		val = max
	end
	return val
end

local vec_dist = vector.distance
local vec_multi = vector.multiply
local vec_equals = vector.equals
local vec_add = vector.add

local function vec_center(v)
	return {x = floor(v.x + 0.5), y = floor(v.y + 0.5), z = floor(v.z + 0.5)}
end

local function vec_raise(v, n)
	if not v then return end
	return {x = v.x, y = v.y + n, z = v.z}
end

---------------
-- Local API --
---------------

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

local default_node_def = {walkable = true} -- both ignore and unknown nodes are walkable

function creatura.get_node_height_from_def(name)
	local def = minetest.registered_nodes[name] or default_node_def
	if not def then return 0.5 end
	if def.walkable then
		if def.drawtype == "nodebox" then
			if def.node_box
			and def.node_box.type == "fixed" then
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

function creatura.get_node_def(node) -- Node can be name or pos
	if type(node) == "table" then
		node = minetest.get_node(node).name
	end
	local def = minetest.registered_nodes[node] or default_node_def
	if def.walkable
	and creatura.get_node_height_from_def(node) < 0.26 then
		def.walkable = false -- workaround for nodes like snow
	end
	return def
end

function creatura.get_ground_level(pos2, max_diff)
	local node = minetest.get_node(pos2)
	local node_under = minetest.get_node({
		x = pos2.x,
		y = pos2.y - 1,
		z = pos2.z
	})
	local walkable = creatura.get_node_def(node_under.name).walkable and not creatura.get_node_def(node.name).walkable
	if walkable then
		return pos2
	end
	if not creatura.get_node_def(node_under.name).walkable then
		for _ = 1, max_diff do
			pos2.y = pos2.y - 1
			node = minetest.get_node(pos2)
			node_under = minetest.get_node({
				x = pos2.x,
				y = pos2.y - 1,
				z = pos2.z
			})
			walkable = creatura.get_node_def(node_under.name).walkable and not creatura.get_node_def(node.name).walkable
			if walkable then break end
		end
	else
		for _ = 1, max_diff do
			pos2.y = pos2.y + 1
			node = minetest.get_node(pos2)
			node_under = minetest.get_node({
				x = pos2.x,
				y = pos2.y - 1,
				z = pos2.z
			})
			walkable = creatura.get_node_def(node_under.name).walkable and not creatura.get_node_def(node.name).walkable
			if walkable then break end
		end
	end
	return pos2
end

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
	for z = pos1.z, pos2.z do
		for x = pos1.x, pos2.x do
			local pos3 = {x = x, y = pos.y + height, z = z}
			local pos4 = {x = x, y = pos.y + 0.01, z = z}
			local ray = minetest.raycast(pos3, pos4, false, false)
			for pointed_thing in ray do
				if pointed_thing.type == "node" then
					local name = minetest.get_node(pointed_thing.under).name
					if creatura.get_node_def(name).walkable then
						return false
					end
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
	local pos = self.object:get_pos()
	pos = {
		x = floor(pos.x),
		y = pos.y + 0.01,
		z = floor(pos.z)
	}
	pos.y = pos.y + 0.01
	if last_move
	and last_move.pos then
		local last_call = minetest.get_position_from_hash(last_move.pos)
		last_move = minetest.get_position_from_hash(last_move.move)
		if vec_equals(vec_center(last_call), vec_center(pos)) then
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
	local _next
	table.sort(neighbors, function(a, b)
		return vec_dist(a, pos2) < vec_dist(b, pos2)
	end)
	for i = 1, #neighbors do
		local neighbor = neighbors[i]
		local can_move = fast_ray_sight(pos, neighbor)
		if vec_equals(neighbor, pos2) then
			can_move = true
		end
		if can_move
		and not moveable(neighbor, width, height) then
			can_move = false
			if moveable(vec_raise(neighbor, 0.5), width, height) then
				can_move = true
			end
		end
		if can_move
		and not self:is_pos_safe(neighbor) then
			can_move = false
		end
		if can_move then
			_next = vec_raise(neighbor, 0.1)
			break
		end
	end
	if _next then
		self._movement_data.last_move = {
			pos = minetest.hash_node_position(pos),
			move = minetest.hash_node_position(_next)
		}
		_next = {
			x = floor(_next.x),
			y = _next.y,
			z = floor(_next.z)
		}
	end
	return _next
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
		last_move = minetest.get_position_from_hash(last_move.move)
		if vec_equals(vec_center(last_call), vec_center(pos)) then
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
		if vec_equals(neighbor, pos2) then
			can_move = true
		end
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
	local dir = vec_multi(direction, -1)
	self:apply_knockback(dir)
	self:hurt((tool_capabilities.damage_groups.fleshy or damage) or 2)
	if random(4) < 2 then
		self:play_sound("hurt")
	end
	if time_from_last_punch > 0.5 then
		self:play_sound("hit")
	end
	self:indicate_damage()
end

local path = minetest.get_modpath("creatura")

dofile(path.."/mob_meta.lua")
