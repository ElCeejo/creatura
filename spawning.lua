--------------
-- Spawning --
--------------

creatura.registered_mob_spawns = {}

local walkable_nodes = {}

minetest.register_on_mods_loaded(function()
	for name in pairs(minetest.registered_nodes) do
		if name ~= "air" and name ~= "ignore" then
			if minetest.registered_nodes[name].walkable then
				table.insert(walkable_nodes, name)
			end
		end
	end
end)

-- Math --

local abs = math.abs
local pi = math.pi
local random = math.random

local function vec_raise(v, n)
	return {x = v.x, y = v.y + n, z = v.z}
end

-- Registration --

local creative = minetest.settings:get_bool("creative_mode")

local function format_name(str)
	if str then
		if str:match(":") then str = str:split(":")[2] end
		return (string.gsub(" " .. str, "%W%l", string.upper):sub(2):gsub("_", " "))
	end
end

function creatura.register_spawn_egg(name, col1, col2, inventory_image) -- deprecated
	if col1 and col2 then
		local base = "(creatura_spawning_crystal.png^[multiply:#" .. col1 .. ")"
		local spots = "(creatura_spawning_crystal_overlay.png^[multiply:#" .. col2 .. ")"
		inventory_image = base .. "^" .. spots
	end
	local mod_name = name:split(":")[1]
	local mob_name = name:split(":")[2]
	minetest.register_craftitem(mod_name .. ":spawn_" .. mob_name, {
		description = "Spawn " .. format_name(name),
		inventory_image = inventory_image,
		stack_max = 99,
		on_place = function(itemstack, _, pointed_thing)
			local mobdef = minetest.registered_entities[name]
			local spawn_offset = abs(mobdef.collisionbox[2])
			local pos = minetest.get_pointed_thing_position(pointed_thing, true)
			pos.y = (pos.y - 0.49) + spawn_offset
			local object = minetest.add_entity(pos, name)
			if object then
				object:set_yaw(random(1, 6))
				object:get_luaentity().last_yaw = object:get_yaw()
			end
			if not creative then
				itemstack:take_item()
				return itemstack
			end
		end
	})
end

function creatura.register_spawn_item(name, def)
	local inventory_image
	if not def.inventory_image
	and def.col1 and def.col2 then
		local base = "(creatura_spawning_crystal.png^[multiply:#" .. def.col1 .. ")"
		local spots = "(creatura_spawning_crystal_overlay.png^[multiply:#" .. def.col2 .. ")"
		inventory_image = base .. "^" .. spots
	end
	local mod_name = name:split(":")[1]
	local mob_name = name:split(":")[2]
	minetest.register_craftitem(mod_name .. ":spawn_" .. mob_name, {
		description = def.description or "Spawn " .. format_name(name),
		inventory_image = def.inventory_image or inventory_image,
		on_place = function(itemstack, player, pointed_thing)
			local mobdef = minetest.registered_entities[name]
			local spawn_offset = abs(mobdef.collisionbox[2])
			local pos = minetest.get_pointed_thing_position(pointed_thing, true)
			pos.y = (pos.y - 0.49) + spawn_offset
			local object = minetest.add_entity(pos, name)
			if object then
				object:set_yaw(random(0, pi * 2))
				object:get_luaentity().last_yaw = object:get_yaw()
			end
			if not minetest.is_creative_enabled(player:get_player_name()) then
				itemstack:take_item()
				return itemstack
			end
		end
	})
end

function creatura.register_mob_spawn(name, def)
	local spawn = {
		chance = def.chance or 5,
		min_height = def.min_height or 0,
		max_height = def.max_height or 128,
		min_light = def.min_light or 6,
		max_light = def.max_light or 15,
		min_group = def.min_group or 1,
		max_group = def.max_group or 4,
		nodes = def.nodes or nil,
		biomes = def.biomes or nil,
		spawn_cluster = def.spawn_cluster or false,
		spawn_in_nodes = def.spawn_in_nodes or false,
		spawn_cap = def.spawn_cap or 5,
		send_debug = def.send_debug or false
	}
	creatura.registered_mob_spawns[name] = spawn
end

creatura.registered_on_spawns = {}

function creatura.register_on_spawn(name, func)
	if not creatura.registered_on_spawns[name] then
		creatura.registered_on_spawns[name] = {}
	end
	table.insert(creatura.registered_on_spawns[name], func)
end


-- Utility Functions --

local function is_value_in_table(tbl, val)
	for _, v in pairs(tbl) do
		if v == val then
			return true
		end
	end
	return false
end

local function get_biome_name(pos)
	if not pos then return end
	return minetest.get_biome_name(minetest.get_biome_data(pos).biome)
end

local function get_spawnable_mobs(pos)
	local biome = get_biome_name(pos)
	if not biome then biome = "_nil" end
	local spawnable = {}
	for k, v in pairs(creatura.registered_mob_spawns) do
		if not v.biomes
		or is_value_in_table(v.biomes, biome) then
			table.insert(spawnable, k)
		end
	end
	return spawnable
end

-- Spawning Function --

local min_spawn_radius = 32
local max_spawn_radius = 128

local function execute_spawns(player)
	if not player:get_pos() then return end
	local pos = player:get_pos()

	local spawn_pos_center = {
		x = pos.x + random(-max_spawn_radius, max_spawn_radius),
		y = pos.y,
		z = pos.z + random(-max_spawn_radius, max_spawn_radius)
	}

	local spawnable_mobs = get_spawnable_mobs(spawn_pos_center)
	if spawnable_mobs
	and #spawnable_mobs > 0 then
		local mob = spawnable_mobs[random(#spawnable_mobs)]
		local spawn = creatura.registered_mob_spawns[mob]
		if not spawn
		or random(spawn.chance) > 1 then return end

		-- Spawn cap check
		local objects = minetest.get_objects_inside_radius(pos, max_spawn_radius)
		local object_count = 0
		for _, object in ipairs(objects) do
			if creatura.is_alive(object)
			and not object:is_player()
			and object:get_luaentity().name == mob then
				object_count = object_count + 1
			end
		end
		if object_count >= spawn.spawn_cap then
			return
		end

		local index_func
		if spawn.spawn_in_nodes then
			index_func = minetest.find_nodes_in_area
		else
			index_func = minetest.find_nodes_in_area_under_air
		end
		local spawn_on = spawn.nodes or walkable_nodes
		if type(spawn_on) == "string" then
			spawn_on = {spawn_on}
		end
		local spawn_y_array = index_func(
			vec_raise(spawn_pos_center, -max_spawn_radius),
			vec_raise(spawn_pos_center, max_spawn_radius),
			spawn_on)
		if spawn_y_array[1] then
			local spawn_pos = spawn_y_array[1]
			local dist = vector.distance(pos, spawn_pos)
			if dist < min_spawn_radius or dist > max_spawn_radius then
				return
			end

			if spawn_pos.y > spawn.max_height
			or spawn_pos.y < spawn.min_height then
				return
			end

			if not spawn.spawn_in_nodes then
				spawn_pos = vec_raise(spawn_pos, 1)
			end

			local light = minetest.get_node_light(spawn_pos) or 7

			if light > spawn.max_light
			or light < spawn.min_light then
				return
			end

			local group_size = random(spawn.min_group, spawn.max_group)

			if spawn.spawn_cluster then
				minetest.add_node(spawn_pos, {name = "creatura:spawn_node"})
				local meta = minetest.get_meta(spawn_pos)
				meta:set_string("mob", mob)
				meta:set_int("cluster", group_size)
			else
				for _ = 1, group_size do
					spawn_pos = {
						x = spawn_pos.x + random(-3, 3),
						y = spawn_pos.y,
						z = spawn_pos.z + random(-3, 3)
					}
					spawn_pos = creatura.get_ground_level(spawn_pos, 4)
					minetest.add_node(spawn_pos, {name = "creatura:spawn_node"})
					local meta = minetest.get_meta(spawn_pos)
					meta:set_string("mob", mob)
				end
			end
			if spawn.send_debug then
				minetest.chat_send_all(mob .. " spawned at " .. minetest.pos_to_string(spawn_pos))
			end
		end
	end
end

local spawn_step = tonumber(minetest.settings:get("creatura_spawn_step")) or 15

local spawn_tick = 0

minetest.register_globalstep(function(dtime)
	spawn_tick = spawn_tick - dtime
	if spawn_tick <= 0 then
		for _, player in ipairs(minetest.get_connected_players()) do
			execute_spawns(player)
		end
		spawn_tick = spawn_step
	end
end)

-- Node --

minetest.register_node("creatura:spawn_node", {
	drawtype = "airlike",
	groups = {not_in_creative_inventory = 1}
})

local spawn_interval = tonumber(minetest.settings:get("creatura_spawn_interval")) or 10

minetest.register_abm({
	label = "Creatura Spawning",
	nodenames = {"creatura:spawn_node"},
	interval = spawn_interval,
	chance = 1,
	action = function(pos)
		local meta = minetest.get_meta(pos)
		local name = meta:get_string("mob")
		local amount = meta:get_int("cluster")
		local obj
		if amount > 0 then
			for _ = 1, amount do
				obj = minetest.add_entity(pos, name)
			end
		else
			obj = minetest.add_entity(pos, name)
		end
		minetest.remove_node(pos)
		if obj
		and creatura.registered_on_spawns[name]
		and #creatura.registered_on_spawns[name] > 0 then
			for i = 1, #creatura.registered_on_spawns[name] do
				local func = creatura.registered_on_spawns[name][i]
				func(obj:get_luaentity(), pos)
			end
		end
	end,
})

--[[minetest.register_lbm({
	name = "creatura:spawning",
	nodenames = {"creatura:spawn_node"},
	run_at_every_load = true,
	action = function(pos)
		local meta = minetest.get_meta(pos)
		local name = meta:get_string("mob")
		local amount = meta:get_int("cluster")
		local obj
		if amount > 0 then
			for i = 1, amount do
				obj = minetest.add_entity(pos, name)
			end
		else
			obj = minetest.add_entity(pos, name)
		end
		minetest.remove_node(pos)
		if obj
		and creatura.registered_on_spawns[name]
		and #creatura.registered_on_spawns[name] > 0 then
			for i = 1, #creatura.registered_on_spawns[name] do
				local func = creatura.registered_on_spawns[name][i]
				func(obj:get_luaentity(), pos)
			end
		end
	end,
})]]