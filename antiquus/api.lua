--
-- API antiquus
--

-- Old helper functions from pre-Creatura Nova

-- Math --

local abs = math.abs
local floor = math.floor
local random = math.random

local function clamp(val, min_n, max_n)
	if val < min_n then
		val = min_n
	elseif max_n < val then
		val = max_n
	end
	return val
end

local vec_dist = vector.distance

local function vec_raise(v, n)
	if not v then return end
	return {x = v.x, y = v.y + n, z = v.z}
end

creatura.registered_movement_methods = {}

function creatura.register_movement_method(name, func)
	creatura.registered_movement_methods[name] = func
end

creatura.registered_utilities = {}

function creatura.register_utility(name, func)
	creatura.registered_utilities[name] = func
end

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
		return (mob.hp or mob.health or 0) > 0
	end
	if mob:is_player() then
		return mob:get_hp() > 0
	else
		local ent = mob:get_luaentity()
		return ent and (ent.hp or ent.health or 0) > 0
	end
end

-- Environment check translation

function creatura.is_pos_moveable(pos, width, height)
	local hitbox = {-width, 0, -width, width, height, width}

	return mob_engine.is_pos_empty(pos, hitbox)
end

function creatura.is_blocked(pos, width, height)
	local hitbox = {-width, 0, -width, width, height, width}

	return not mob_engine.is_pos_empty(pos, hitbox)
end

-- Target Selector translation

function creatura.get_nearby_player(self)
	return self.target_selector:get_nearest_player()
end

function creatura.get_nearby_players(self)
	return self.target_selector:get_players() or {}
end

function creatura.get_nearby_object(self, name)
	local filter
	if name then
		filter = function(object, target)
			local name = object and object:get_luaentity() and object:get_luaentity().name
			local target_name = target and target:get_luaentity() and target:get_luaentity().name

			if name == target_name then return 1 end
			return 0
		end
	end

	return self.target_selector:get_nearest_mob(filter)
end

function creatura.get_nearby_objects(self, name)
	local filter
	if name then
		filter = function(object, target)
			local name = object and object:get_luaentity() and object:get_luaentity().name
			local target_name = target and target:get_luaentity() and target:get_luaentity().name

			if name == target_name then return 1 end
			return 0
		end
	end

	return self.target_selector:get_mobs(filter) or {}
end

creatura.get_nearby_entity = creatura.get_nearby_object
creatura.get_nearby_entities = creatura.get_nearby_objects

-- Global API

function creatura.default_water_physics(self)
	local pos = self.stand_pos
	local stand_node = self.stand_node
	if not pos or not stand_node then return end
	local gravity = self._movement_data.gravity or -9.8
	local submergence = self.liquid_submergence or 0.25
	local drag = self.liquid_drag or 0.7

	if minetest.get_item_group(stand_node.name, "liquid") > 0 then -- In Liquid
		local vel = self.object:get_velocity()
		if not vel then return end

		self.in_liquid = stand_node.name

		if submergence < 1 then
			local mob_level = pos.y + (self.height * submergence)

			-- Find Water Surface
			local nodes = minetest.find_nodes_in_area_under_air(
				{x = pos.x, y = pos.y, z = pos.z},
				{x = pos.x, y = pos.y + 3, z = pos.z},
				"group:liquid"
			) or {}

			local surface_level = (#nodes > 0 and nodes[#nodes].y or pos.y + self.height + 3)
			surface_level = floor(surface_level + 0.9)

			local height_diff = mob_level - surface_level

			-- Apply Bouyancy
			if height_diff <= 0 then
				local displacement = clamp(abs(height_diff) / submergence, 0.5, 1) * self.width

				self.object:set_acceleration({x = 0, y = displacement, z = 0})
			else
				self.object:set_acceleration({x = 0, y = gravity, z = 0})
			end
		end

		-- Apply Drag
		self.object:set_velocity({
			x = vel.x * (1 - self.dtime * drag),
			y = vel.y * (1 - self.dtime * drag),
			z = vel.z * (1 - self.dtime * drag)
		})
	else
		self.in_liquid = nil

		self.object:set_acceleration({x = 0, y = gravity, z = 0})
	end
end

function creatura.default_vitals(self)
	local pos = self.stand_pos
	local node = self.stand_node
	if not pos or node then return end

	local max_fall = self.max_fall or 3
	local in_liquid = self.in_liquid
	local on_ground = self.touching_ground
	local damage = 0

	-- Fall Damage
	if max_fall > 0
	and not in_liquid then
		local fall_start = self._fall_start or (not on_ground and pos.y)
		if fall_start
		and on_ground then
			damage = floor(fall_start - pos.y)
			if damage < max_fall then
				damage = 0
			else
				local resist = self.fall_resistance or 0
				damage = damage - damage * resist
			end
			fall_start = nil
		end
		self._fall_start = fall_start
	end

	-- Environment Damage
	if self:timer(1) then
		local stand_def = creatura.get_node_def(node.name)
		local max_breath = self.max_breath or 0

		-- Suffocation
		if max_breath > 0 then
			local head_pos = {x = pos.x, y = pos.y + self.height, z = pos.z}
			local head_def = creatura.get_node_def(head_pos)
			if head_def.groups
			and (minetest.get_item_group(head_def.name, "water") > 0
			or (head_def.walkable
			and head_def.groups.disable_suffocation ~= 1
			and head_def.drawtype == "normal")) then
				local breath = self._breath
				if breath <= 0 then
					damage = damage + 1
				else
					self._breath = breath - 1
					self:memorize("_breath", breath)
				end
			end
		end

		-- Burning
		local fire_resist = self.fire_resistance or 0
		if fire_resist < 1
		and minetest.get_item_group(stand_def.name, "igniter") > 0
		and stand_def.damage_per_second then
			damage = (damage or 0) + stand_def.damage_per_second * fire_resist
		end
	end

	-- Apply Damage
	if damage > 0 then
		self:hurt(damage)
		self:indicate_damage()
		if random(4) < 2 then
			self:play_sound("hurt")
		end
	end

	-- Entity Cramming
	if self:timer(5) then
		local objects = minetest.get_objects_inside_radius(pos, 0.2)
		if #objects > 10 then
			self:indicate_damage()
			self.hp = self:memorize("hp", -1)
			self:death_func()
		end
	end
end

function creatura.drop_items(self)
	if not self.drops then return end
	local pos = self.object:get_pos()
	if not pos then return end

	local drop_def, item_name, min_items, max_items, chance, amount, drop_pos
	for i = 1, #self.drops do
		drop_def = self.drops[i]
		item_name = drop_def.name
		if not item_name then return end
		chance = drop_def.chance or 1

		if random(chance) < 2 then
			min_items = drop_def.min or 1
			max_items = drop_def.max or 2
			amount = random(min_items, max_items)
			drop_pos = {
				x = pos.x + random(-5, 5) * 0.1,
				y = pos.y,
				z = pos.z + random(-5, 5) * 0.1
			}

			local item = minetest.add_item(drop_pos, ItemStack(item_name .. " " .. amount))
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

function creatura.basic_punch_func(self, puncher, tflp, tool_caps, dir)
	if not puncher then return end
	local tool
	local tool_name = ""
	local add_wear = false
	if puncher:is_player() then
		tool = puncher:get_wielded_item()
		tool_name = tool:get_name()
		add_wear = not minetest.is_creative_enabled(puncher:get_player_name())
	end
	if (self.immune_to
	and contains_val(self.immune_to, tool_name)) then
		return
	end
	local damage = 0
	local armor_grps = self.object:get_armor_groups() or self.armor_groups or {}
	for group, val in pairs(tool_caps.damage_groups or {}) do
		local dmg_x = tflp / (tool_caps.full_punch_interval or 1.4)
		damage = damage + val * clamp(dmg_x, 0, 1) * ((armor_grps[group] or 0) / 100.0)
	end
	if damage > 0 then
		local dist = vec_dist(self.object:get_pos(), puncher:get_pos())
		dir.y = 0.2
		if self.touching_ground then
			local power = clamp((damage / dist) * 8, 0, 8)
			self:apply_knockback(dir, power)
		end
		self:hurt(damage)
	end
	if add_wear then
		local wear = floor((tool_caps.full_punch_interval / 75) * 9000)
		tool:add_wear(wear)
		puncher:set_wielded_item(tool)
	end
	if random(2) < 2 then
		self:play_sound("hurt")
	end
	if (tflp or 0) > 0.5 then
		self:play_sound("hit")
	end
	self:indicate_damage()
end
