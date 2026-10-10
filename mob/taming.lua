local mob_base = creatura.mob_base

function mob_base:disable_despawning()
	self.despawn_after = self:memorize("despawn_after", false)
	self._despawn = self:memorize("_despawn", false)
end

function mob_base:set_protection()
	self._protected = true
	self:disable_despawning()
end

function mob_base:set_owner(player)
	if type(player) == "userdata" then player = player:get_player_name() end

	self._owner = player

	if self.on_tamed then self:on_tamed(core.get_player_by_name(player)) end
end

function mob_base:get_owner()
	return self._owner and self._owner ~= "" and core.get_player_by_name(self._owner)
end

function mob_base:is_owner(target)
	if not self._owner then return end
	if not target then return end

	if type(target) == "userdata" then
		if target:is_player() then
			target = target:get_player_name()
		else
			local entity = target:get_luaentity()

			if entity
			and entity._owner
			and entity._owner == self._owner then
				return true
			end
		end
	end

	return target == self._owner
end

function mob_base:is_tamed()
	return self._owner and self._owner ~= ""
end

function mob_base:is_tempted_by(stack)
	if not stack then return false end
	local stack_name = stack
	if type(stack) == "userdata" then stack_name = stack:get_name() end
	if type(self.tempted_by) == "string" then
		return stack_name == self.tempted_by -- TODO: Allow groups
	end

	for _, tempted_by in ipairs(self.tempted_by) do
		if stack_name == tempted_by
		or minetest.get_item_group(stack_name, tempted_by:split(":")[2]) > 0 then
			return true
		end
	end

	return false
end

function mob_base:get_feed_count()
	return self._feed_count or 0
end

function mob_base:get_nearby_dropped_food()
	local pos = self.object:get_pos()
	if not pos then return end

	local objects = core.get_objects_inside_radius(pos, self.tracking_range or 4)

	for _, object in ipairs(objects) do
		local entity = object and object:get_luaentity()

		if entity
		and entity.name
		and entity.name == "__builtin:item"
		and entity.itemstring
		and self:is_tempted_by(ItemStack(entity.itemstring)) then
			return object
		end
	end
end

function mob_base:eat_dropped_item(object)
	local entity = object and object:get_luaentity()
	if not entity or not entity.name or entity.name ~= "__builtin:item" then return end
	local stack = entity.itemstring and ItemStack(entity.itemstring)
	if not stack then return end

	if stack:get_count() > 1 then
		stack:take_item()
		entity.itemstring = stack:to_string()
	else
		object:remove()
	end

	self._feed_count = (self._feed_count or 0) + 1
	if self.on_fed then self:on_fed(nil, nil, self._feed_count) end
	if self._feed_count >= self.max_feed_count then
		self._feed_count = 0
	end
end

function mob_base:get_player_holding_food()
	local pos = self.object:get_pos()
	if not pos then return end

	for _, player in ipairs(core.get_connected_players()) do
		local player_pos = player and player:get_pos()

		if player_pos
		and vector.distance(pos, player_pos) < self.tracking_range
		and self:is_tempted_by(player:get_wielded_item()) then
			return player
		end
	end
end

function mob_base:set_child()
	self:set_scale(0.5)
	self._is_child = true
	self._time_until_grown = 300
	if self.child_textures then
		self:set_texture_table(self.child_textures)
	end
end

function mob_base:is_child()
	return self._is_child, self._time_until_grown
end

function mob_base:growth_step()
	local time_until_grown = self._time_until_grown or 0
	time_until_grown = time_until_grown - self.dtime

	if time_until_grown <= 0
	and self._is_child then
		self:set_scale(1)
		self._is_child = false
		time_until_grown = 0

		if self.on_grown then
			self:on_grown()
		else
			local textures = self:get_definition().textures
			self:set_texture_table(textures)
		end
	end

	self._time_until_grown = time_until_grown
end

function mob_base:can_breed()
	return not self:is_child() and (not self.breeding_cooldown or self.breeding_cooldown == 0)
end

function mob_base:spawn_child()
	local obj = core.add_entity(self.object:get_pos(), self.name)
	obj:get_luaentity():set_child()
end
