--------------
-- Spawning --
--------------

creatura.registered_mob_spawns = {}
creatura.registered_on_spawns = {}

-- Math --

local abs = math.abs
local ceil = math.ceil
local pi = math.pi
local random = math.random
local min = math.min

local vec_add, vec_dist, vec_sub = vector.add, vector.distance, vector.subtract

-- Utility Functions --

local function format_name(str)
	if str then
		if str:match(":") then str = str:split(":")[2] end
		return (string.gsub(" " .. str, "%W%l", string.upper):sub(2):gsub("_", " "))
	end
end

local function table_contains(tbl, val)
	for _, v in pairs(tbl) do
		if v == val then
			return true
		end
	end
	return false
end

local function pos_meets_params(pos, def)
	if not minetest.find_nodes_in_area(pos, pos, def.nodes) then return false end
	if not minetest.find_node_near(pos, 1, def.neighbors) then return false end

	return true
end

local function can_spawn(pos, width, height)
	local pos2
	local w_iter = width / ceil(width)
	for y = 0, height, height / ceil(height) do
		for z = -width, width, w_iter do
			for x = -width, width, w_iter do
				pos2 = {x = pos.x + x, y = pos.y + y, z = pos.z + z}
				local def = creatura.get_node_def(pos2)
				if def.walkable then return false end
			end
		end
	end
	return true
end

local function do_on_spawn(pos, obj)
	local name = obj and obj:get_luaentity().name
	if not name then return end
	local spawn_functions = creatura.registered_on_spawns[name] or {}

	if #spawn_functions > 0 then
		for _, func in ipairs(spawn_functions) do
			func(obj:get_luaentity(), pos)
			if not obj:get_yaw() then break end
		end
	end
end

----------------
-- Spawn Item --
----------------

local creative = minetest.settings:get_bool("creative_mode")

function creatura.register_spawn_item(name, def)
	local inventory_image
	if not def.inventory_image
	and ((def.col1 and def.col2)
	or (def.hex_primary and def.hex_secondary)) then
		local primary = def.col1 or def.hex_primary
		local secondary = def.col2 or def.hex_secondary
		local base = "(creatura_spawning_crystal_primary.png^[multiply:#" .. primary .. ")"
		local spots = "(creatura_spawning_crystal_secondary.png^[multiply:#" .. secondary .. ")"
		inventory_image = base .. "^" .. spots
	end
	local mod_name = name:split(":")[1]
	local mob_name = name:split(":")[2]
	def.description = def.description or "Spawn " .. format_name(name)
	def.inventory_image = def.inventory_image or inventory_image
	def.on_place = function(itemstack, player, pointed_thing)
		-- If the player right-clicks something like a chest or item frame then
		-- run the node's on_rightclick callback
		local under = pointed_thing.under
		local node = minetest.get_node(under)
		local node_def = minetest.registered_nodes[node.name]
		if node_def and node_def.on_rightclick and
				not (player and player:is_player() and
				player:get_player_control().sneak) then
			return node_def.on_rightclick(under, node, player, itemstack,
				pointed_thing) or itemstack
		end

		-- Otherwise spawn the mob
		local pos = minetest.get_pointed_thing_position(pointed_thing, true)
		if minetest.is_protected(pos, player and player:get_player_name() or "") then return end
		local mobdef = minetest.registered_entities[name]
		local spawn_offset = abs(mobdef.collisionbox[2])
		pos.y = (pos.y - 0.49) + spawn_offset
		if def.antispam then
			local objs = minetest.get_objects_in_area(vec_sub(pos, 0.51), vec_add(pos, 0.51))
			for _, obj in ipairs(objs) do
				if obj
				and obj:get_luaentity()
				and obj:get_luaentity().name == name then
					return
				end
			end
		end
		local object = minetest.add_entity(pos, name)
		if object then
			object:set_yaw(random(0, pi * 2))
			object:get_luaentity().last_yaw = object:get_yaw()
			if def.on_spawn then
				def.on_spawn(object:get_luaentity(), player)
			end
		end
		if not minetest.is_creative_enabled(player:get_player_name())
		or def.consume_in_creative then
			itemstack:take_item()
			return itemstack
		end
	end
	minetest.register_craftitem(def.itemstring or (mod_name .. ":spawn_" .. mob_name), def)
end

function creatura.register_on_spawn(name, func)
	if not creatura.registered_on_spawns[name] then
		creatura.registered_on_spawns[name] = {}
	end
	table.insert(creatura.registered_on_spawns[name], func)
end

--------------
-- Spawning --
--------------

--[[creatura.register_abm_spawn("mymod:mymob", {
	chance = 3000,
	interval = 30,
	min_height = 0,
	max_height = 128,
	min_light = 1,
	max_light = 15,
	min_group = 1,
	max_group = 4,
	nodes = {"group:soil", "group:stone"},
	neighbors = {"air"},
	spawn_on_load = false,
	spawn_in_nodes = false,
	spawn_cap = 5
})]]

local protected_spawn = minetest.settings:get_bool("creatura_protected_spawn", true)
local abr = (tonumber(minetest.get_mapgen_setting("active_block_range")) or 4) * 16
local max_per_block = tonumber(minetest.settings:get("creatura_mapblock_limit")) or 12
local max_in_abr = tonumber(minetest.settings:get("creatura_abr_limit")) or 24
local min_abm_dist = min(abr / 2, tonumber(minetest.settings:get("creatura_min_abm_dist")) or 32)

local mobs_spawn = minetest.settings:get_bool("mobs_spawn") ~= false

local mapgen_mobs = {}

function creatura.register_abm_spawn(mob, def)
	local chance = def.chance or 3000
	local interval = def.interval or 30
	local min_height = def.min_height or 0
	local max_height = def.max_height or 128
	local min_time = def.min_time or 0
	local max_time = def.max_time or 24000
	local min_light = def.min_light or 1
	local max_light = def.max_light or 15
	local min_group = def.min_group or 1
	local max_group = def.max_group or 4
	local block_protected = def.block_protected_spawn or false
	local biomes = def.biomes or {}
	local nodes = def.nodes or {"group:soil", "group:stone"}
	local neighbors = def.neighbors or {"air"}
	local spawn_on_load = def.spawn_on_load or false
	local spawn_in_nodes = def.spawn_in_nodes or false
	local spawn_cap = def.spawn_cap or 5

	local function spawn_func(pos, aocw)

		if not mobs_spawn then
			return
		end

		if not spawn_in_nodes then
			pos.y = pos.y + 1
		end

		if (not protected_spawn
		or block_protected)
		and minetest.is_protected(pos, "") then
			return
		end

		local tod = (minetest.get_timeofday() or 0) * 24000

		local bounds_in = tod >= min_time and tod <= max_time
		local bounds_ex = tod >= max_time or tod <= min_time

		if (max_time > min_time and not bounds_in)
		or (min_time > max_time and not bounds_ex) then
			return
		end

		local light = minetest.get_node_light(pos) or 7

		if light > max_light
		or light < min_light then
			return
		end

		if aocw
		and aocw >= max_per_block then
			return
		end

		if biomes
		and #biomes > 0 then
			local biome_id = minetest.get_biome_data(pos).biome
			local biome_name = minetest.get_biome_name(biome_id)
			local is_spawn_biome = false
			for _, biome in ipairs(biomes) do
				if biome:match("^" .. biome_name) then
					is_spawn_biome = true
					break
				end
			end
			if not is_spawn_biome then return end
		end

		local mob_count = 0
		local plyr_found = false

		local objects = minetest.get_objects_inside_radius(pos, abr)

		for _, object in ipairs(objects) do
			local ent = object:get_luaentity()
			if ent
			and ent.name == mob then
				mob_count = mob_count + 1
				if mob_count > spawn_cap
				or mob_count > max_in_abr then
					return
				end
			end
			if object:is_player() then
				plyr_found = true
				if vec_dist(pos, object:get_pos()) < min_abm_dist then
					return
				end
			end
		end

		if not plyr_found then
			return
		end

		local mob_def = minetest.registered_entities[mob]
		local mob_width = mob_def.collisionbox[4]
		local mob_height = mob_def.collisionbox[5]

		if not can_spawn(pos, mob_width, mob_height) then
			return
		end

		local group_size = random(min_group or 1, max_group or 1)
		local obj

		if group_size > 1 then
			local offset
			local spawn_pos
			for _ = 1, group_size do
				offset = ceil(mob_width)
				spawn_pos = creatura.get_ground_level({
					x = pos.x + random(-offset, offset),
					y = pos.y,
					z = pos.z + random(-offset, offset)
				}, 3)
				if not can_spawn(spawn_pos, mob_width, mob_height) then
					spawn_pos = pos
				end
				obj = minetest.add_entity(spawn_pos, mob)
				do_on_spawn(spawn_pos, obj)
			end
		else
			obj = minetest.add_entity(pos, mob)
			do_on_spawn(pos, obj)
		end

		minetest.log("action",
			"[Creatura] [ABM Spawning] Spawned " .. group_size .. " " .. mob .. " at " .. minetest.pos_to_string(pos))

	end

	minetest.register_abm({
		label = mob .. " spawning",
		nodenames = nodes,
		neighbors = neighbors,
		interval = interval,
		chance = chance,
		min_y = min_height,
		max_y = max_height,
		catch_up = false,
		action = function(pos, _, _, aocw)
			spawn_func(pos, aocw)
		end
	})

	if spawn_on_load then
		table.insert(mapgen_mobs, mob)
	end

	creatura.registered_mob_spawns[mob] = {
		chance = def.chance or 3000,
		interval = def.interval or 30,
		min_height = def.min_height or 0,
		max_height = def.max_height or 128,
		min_time = def.min_time or 0,
		max_time = def.max_time or 24000,
		min_light = def.min_light or 1,
		max_light = def.max_light or 15,
		min_group = def.min_group or 1,
		max_group = def.max_group or 4,
		block_protected = def.block_protected_spawn or false,
		biomes = def.biomes or {},
		nodes = def.nodes or {"group:soil", "group:stone"},
		neighbors = def.neighbors or {"air"},
		spawn_on_load = def.spawn_on_load or false,
		spawn_in_nodes = def.spawn_in_nodes or false,
		spawn_cap = def.spawn_cap or 5
	}
end

----------------
-- DEPRECATED --
----------------


-- Mapgen --

minetest.register_node("creatura:spawn_node", {
	drawtype = "airlike",
	groups = {not_in_creative_inventory = 1},
	walkable = false
})

local mapgen_spawning = false
local mapgen_spawning_int = tonumber(minetest.settings:get("creatura_mapgen_spawn_interval")) or 64

if mapgen_spawning then
	local chunk_delay = 0
	local c_air = minetest.get_content_id("air")
	local c_spawn = minetest.get_content_id("creatura:spawn_node")

	minetest.register_on_generated(function(minp, maxp)
		if chunk_delay > 0 then chunk_delay = chunk_delay - 1 end
		local meta_queue = {}

		local vm, emin, emax = minetest.get_mapgen_object("voxelmanip")
		local area = VoxelArea:new{MinEdge = emin, MaxEdge = emax}
		local data = vm:get_data()

		local min_x, max_x = minp.x, maxp.x
		local min_y, max_y = minp.y, maxp.y
		local min_z, max_z = minp.z, maxp.z

		local def
		local center

		local current_biome
		local spawn_biomes

		local current_pos

		for _, mob_name in ipairs(mapgen_mobs) do
			local mob_spawned = false

			def = creatura.registered_mob_spawns[mob_name]

			center = {
				x = min_x + (max_x - min_x) * 0.5,
				y = min_y + (max_y - min_y) * 0.5,
				z = min_z + (max_z - min_z) * 0.5
			}

			current_biome = minetest.get_biome_name(minetest.get_biome_data(center).biome)
			spawn_biomes = def.biomes

			if not mob_spawned
			and (not spawn_biomes
			or table_contains(spawn_biomes, current_biome)) then
				for z = min_z + 8, max_z - 7, 8 do
					if mob_spawned then break end
					for x = min_x + 8, max_x - 7, 8 do
						if mob_spawned then break end
						for y = min_y, max_y do
							local vi = area:index(x, y, z)

							if data[vi] == c_air
							or data[vi] == c_spawn then
								break
							end

							-- Check if position is outside of vertical bounds
							if y > def.max_height
							or y < def.min_height then
								break
							end

							current_pos = vector.new(x, y, z)

							-- Check if position has required nodes
							if not pos_meets_params(current_pos, def) then
								break
							end

							if def.spawn_in_nodes then
								-- Add Spawn Node to Map
								data[vi] = c_spawn

								local group_size = random(def.min_group or 1, def.max_group or 1)
								table.insert(meta_queue, {pos = current_pos, mob = mob_name, cluster = group_size})

								mob_spawned = true
								break
							elseif data[area:index(x, y + 1, z)] == c_air then
								vi = area:index(x, y + 1, z)
								current_pos = vector.new(x, y + 1, z)

								-- Add Spawn Node to Map
								data[vi] = c_spawn

								local group_size = random(def.min_group or 1, def.max_group or 1)
								table.insert(meta_queue, {pos = current_pos, mob = mob_name, cluster = group_size})

								mob_spawned = true
								break
							end
						end
					end
				end
			end
		end

		if #meta_queue > 0 then
			vm:set_data(data)
			vm:write_to_map()

			for _, unset_meta in ipairs(meta_queue) do
				local pos = unset_meta.pos
				local mob = unset_meta.mob
				local cluster = unset_meta.cluster

				local meta = minetest.get_meta(pos)
				meta:set_string("mob", mob)
				meta:set_int("cluster", cluster)
			end

			chunk_delay = mapgen_spawning_int
		end
	end)

	local spawn_interval = tonumber(minetest.settings:get("creatura_spawn_interval")) or 10

	minetest.register_abm({
		label = "Creatura Spawning",
		nodenames = {"creatura:spawn_node"},
		interval = spawn_interval,
		chance = 1,
		action = function(pos)
			local plyr_found = false
			local objects = minetest.get_objects_inside_radius(pos, abr)

			for _, object in ipairs(objects) do
				if object:is_player() then
					plyr_found = true
					break
				end
			end

			if not plyr_found then return end

			local meta = minetest.get_meta(pos)
			local name = meta:get_string("mob") or ""
			if name == "" then minetest.remove_node(pos) return end
			local amount = meta:get_int("cluster")
			local obj
			if amount > 0 then
				for _ = 1, amount do
					obj = minetest.add_entity(pos, name)
					do_on_spawn(pos, obj)
				end
				minetest.log("action",
					"[Creatura] Spawned " .. amount .. " " .. name .. " at " .. minetest.pos_to_string(pos))
			else
				obj = minetest.add_entity(pos, name)
				do_on_spawn(pos, obj)
				minetest.log("action",
					"[Creatura] Spawned a " .. name .. " at " .. minetest.pos_to_string(pos))
			end
			minetest.remove_node(pos)
		end,
	})
end

function creatura.register_mob_spawn(name, def)
	local spawn_def = {
		chance = def.chance or 5,
		min_height = def.min_height or 0,
		max_height = def.max_height or 128,
		min_time = def.min_time or 0,
		max_time = def.max_time or 24000,
		min_light = def.min_light or 6,
		max_light = def.max_light or 15,
		min_group = def.min_group or 1,
		max_group = def.max_group or 4,
		nodes = def.nodes or nil,
		biomes = def.biomes or nil,
		--spawn_cluster = def.spawn_cluster or false,
		spawn_on_load = def.spawn_on_gen or false,
		spawn_in_nodes = def.spawn_in_nodes or false,
		spawn_cap = def.spawn_cap or 5,
		--send_debug = def.send_debug or false
	}
	--creatura.registered_mob_spawns[name] = spawn_def

	creatura.register_abm_spawn(name, spawn_def)
end

function creatura.register_spawn_egg(name, col1, col2, inventory_image)
	if col1 and col2 then
		local base = "(creatura_spawning_crystal_primary.png^[multiply:#" .. col1 .. ")"
		local spots = "(creatura_spawning_crystal_secondary.png^[multiply:#" .. col2 .. ")"
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
			pos.y = (pos.y - 0.4) + spawn_offset
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
