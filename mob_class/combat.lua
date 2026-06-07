local mob_class = creatura.mob_class
local random = math.random

function mob_class:get_drops()
	local loot = self.loot_table
	if not loot or not loot.items then return {} end

	local drops = {}
	local item_counts = {}
	local rolls = random(loot.min_rolls or 1, loot.max_rolls or #loot.items)

	for _ = 1, rolls do
		local total_weight = 0
		local available_items = {}

		for _, item in ipairs(loot.items) do
			local count = item_counts[item.name] or 0
			if not item.max_rolls or count < item.max_rolls then
				total_weight = total_weight + item.weight
				table.insert(available_items, item)
			end
		end

		if total_weight <= 0 then break end

		local roll = random(1, total_weight)
		local current = 0

		for _, item in ipairs(available_items) do
			current = current + item.weight
			if roll <= current then
				local min_amount = item.min_amount or 1
				local max_amount = item.max_amount or 1

				table.insert(drops, ItemStack(item.name .. " " .. random(min_amount, max_amount)))
				item_counts[item.name] = (item_counts[item.name] or 0) + 1
				break
			end
		end
	end
	return drops
end

function mob_class:drop_item(itemstack)
	local pos = self.object:get_pos()
	if not pos then return end
	local item = minetest.add_item(pos, itemstack)

	if item then
		item:add_velocity({
			x = random(-2, 2),
			y = 1.5,
			z = random(-2, 2)
		})

		return true
	end
	return false
end

function mob_class:drop_loot(loot_table)
	local drops = loot_table or self:get_drops()
	if not drops or type(drops) ~= "table" or #drops < 1 then return end

	for _, itemstack in ipairs(drops) do
		self:drop_item(itemstack)
	end
end

function mob_class:hurt(damage)
	if self.protected then return end
	if not self.health or self.health <= 0 then return end
	self.health = math.max(0, self.health - damage)
	return self.health
end

function mob_class:heal(healing)
	if not self.health or self.health <= 0 then return end
	self.health = math.max(0, self.health + healing)
	return self.health
end

function mob_class:punch_target(target, damage)
	local damage_groups = self.damage_groups or {fleshy = self.damage or 2}
	if damage then
		local damage_type = type(damage)
		if damage_type == "number" then
			damage_groups = {fleshy = self.damage or 2}
		elseif damage_type == "table" then
			damage_groups = damage
		end
	end

	target:punch(self.object, 1.0, {
		full_punch_interval = 1.0,
		damage_groups = damage_groups,
	})

	self.punch_cooldown_timer = self.punch_cooldown or 12
end

function mob_class:apply_knockback(dir, power)
	if not dir then dir = vector.new(0, 1, 0) end
	power = power or 6
	local knockback = vector.multiply(dir, power)
	self.object:add_velocity(knockback)
end

function mob_class:check_environment_damage()
	local pos = self.object:get_pos()
	if not pos then return end
	pos.y = pos.y + 0.01

	local node_at_pos = core.get_node(pos)

	-- Fall Damage
	if self.max_fall > 0 then
		if not self.touching_ground then
			self.fall_start = self.fall_start or pos.y
		elseif self.fall_start then
			local fall_height = self.fall_start - pos.y
			self.fall_start = nil

			if fall_height >= self.max_fall then
				self:hurt(math.floor(fall_height)) -- TODO: Armor groups
				self:indicate_damage()
			end
		end
	end

	-- Fire Damage
	if self:timer(1) then
		local def = core.registered_nodes[node_at_pos.name]

		if def.damage_per_second and def.damage_per_second > 0 then
			self:hurt(def.damage_per_second)
			self:indicate_damage()
		end
	end

	-- Breath
	if core.get_item_group(node_at_pos.name, "liquid") > 0 then
		self.in_liquid = node_at_pos.name

		if self.max_breath > 0
		and self:timer(1) then
			local pos_at_head = vector.offset(pos, 0, self.height or 1, 0)
			local node_at_head = core.get_node(pos_at_head)
			if core.get_item_group(node_at_head.name, "liquid") > 0 then
				if self.breath <= 0 then
					self:hurt(1)
					self:indicate_damage()
				else
					self.breath = (self.breath or self.max_breath) - 1
				end
			else
				self.breath = self.max_breath
			end
		end
	else
		self.in_liquid = false
	end
end
