local mob_class = creatura.mob_class

function mob_class:disable_despawning()
	self.despawn_after = self:memorize("despawn_after", false)
	self._despawn = self:memorize("_despawn", false)
end

function mob_class:set_protection()
	self._protected = true
	self:disable_despawning()
end

function mob_class:set_owner(player)
	if type(player) == "userdata" then player = player:get_player_name() end

	self._owner = player

	if self.on_tamed then self:on_tamed(core.get_player_by_name(player)) end
end

function mob_class:get_owner()
	return self._owner and self._owner ~= "" and core.get_player_by_name(self._owner)
end

function mob_class:is_owner(target)
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

function mob_class:is_tamed()
	return self._owner and self._owner ~= ""
end

function mob_class:is_tempted_by(stack)
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

function mob_class:get_feed_count()
	return self._feed_count or 0
end

function mob_class:get_nearby_dropped_food()
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

function mob_class:eat_dropped_item(object)
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
	self:on_fed(nil, nil, self._feed_count)
	if self._feed_count >= self.max_feed_count then
		self._feed_count = 0
	end
end
