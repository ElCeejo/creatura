
local senses = {}
senses.__index = senses

local random = math.random

local scan_cooldown = 2
local default_memory_timeout = 8 -- TODO: Allow queries to specify a timeout
local line_of_sight_cooldown = 1

function senses:initiate(entity)
	local new_senses = {
		entity = entity,

		-- Scanning
		object_lists = {mobs = {}, players = {}, items = {}},
		last_scan_time = self:get_time() - random() * scan_cooldown,

		-- Tracking
		current_target = nil,
		target_last_seen_pos = nil,
		target_last_seen_time = 0,
		last_sight_check_time = 0
	}

	entity.senses = setmetatable(new_senses, senses)
end

-- Internal

function senses:scan()
	local pos = self.entity.object:get_pos()
	if not pos then return end

	local time = self:get_time()
	if time - self.last_scan_time < scan_cooldown then
		return
	end

	self.last_scan_time = time

	local range = self.entity.tracking_range or 8
	local object_lists = {mobs = {}, players = {}, items = {}}

	local objects = core.get_objects_inside_radius(pos, range)

	for _, object in ipairs(objects) do
		if object ~= self.entity.object then
			local object_pos = object:get_pos()

			if object_pos then
				local entry = {
					name = "",
					object = object,
					distance = vector.distance(pos, object_pos)
				}

				if object:is_player() then
					entry.name = object:get_player_name() or ""
					table.insert(object_lists.players, entry)
				else
					local entity = object:get_luaentity()

					if entity and entity.name and entity.name == "__builtin:item" then
						entry.name = ItemStack(entity.itemstring):get_name()
						table.insert(object_lists.items, entry)
					elseif self:is_valid(object) then
						entry.name = entity.name
						table.insert(object_lists.mobs, entry)
					end
				end
			end
		end
	end

	self.object_lists = object_lists
	self:sort_lists()
end

function senses:find(query)
	query = query or {}

	local search_from = query.search_from or "players"
	local range = query.range or self.entity.tracking_range or 8
	local name_matches = search_from == "items"
		and creatura.check_item
		or function(a, b) return self:is_name_valid(a, b) end

	self:scan()
	for _, entry in ipairs(self:get_list(search_from)) do
		local object = entry.object
		local dist = entry.distance

		if dist > range then break end

		if self:is_valid(object)
		and (not query.names or name_matches(entry.name, query.names))
		and (not query.line_of_sight or self:line_of_sight(object))
		and (not query.held_items or (object:is_player()
		and creatura.check_item(object:get_wielded_item():get_name(), query.held_items)))
		and (not query.filter or query.filter(self.entity, object))
		and (not query.check_claims or not self:is_object_claimed(object))
		and (not query.ignore_creative or not (object:is_player() and core.is_creative_enabled(object:get_player_name())))
		and (not query.ignore_owner or not self.entity:is_owner(object)) then
			return object
		end
	end
end

-- Targets

function senses:find_target(query) -- TODO: This name overlaps with find() but doesn't communicate the difference
	local target = self:find(query)
	if not target then return end

	self:set_target(target)
	return target
end

function senses:set_target(object)
	local pos = object and object:get_pos()
	if not pos then return false end

	self.current_target = object
	self.target_last_seen_pos = pos
	self.target_last_seen_time = self:get_time()
	self.last_sight_check_time = 0
	self.target_visible = false
	return true
end

function senses:clear_target()
	self.current_target = nil
	self.target_last_seen_pos = nil
	self.target_last_seen_time = self:get_time()
end

function senses:get_current_target()
	local target = self.current_target

	if not target or not self:is_valid(target) then self:clear_target() return end

	local pos = self.entity.object:get_pos()
	local target_pos = target:get_pos()
	if not pos or not target_pos then self:clear_target() return end

	local time = self:get_time()
	local range = self.entity.tracking_range or 8
	local dist = vector.distance(pos, target_pos)
	local in_range = dist <= range

	if in_range
	and not self:is_los_on_cooldown() then
		self.target_visible = self:line_of_sight(target_pos)
		self.last_sight_check_time = time
	end

	if in_range
	and self.target_visible then
		self.target_last_seen_pos = target_pos
		self.target_last_seen_time = time
	else
		if time - self.target_last_seen_time > default_memory_timeout then self:clear_target() return end
	end

	return target
end

-- Claims

local claims = setmetatable({}, {__mode = "k"})

function senses:claim_object(object)
	claims[object] = self.entity.object
end

function senses:unclaim_object(object)
	if claims[object] == self.entity.object then claims[object] = nil end
end

function senses:is_object_claimed(object)
	local claimer = claims[object]

	return claimer ~= nil and claimer ~= self.entity.object and creatura.is_alive(claimer)
end

-- Utilities

function senses:is_valid(object)
	if not object:is_valid() then return false end

	local ent = object:get_luaentity()
	if ent and ent.name == "__builtin:item" then return true end

	return creatura.is_alive(object)
end

function senses:is_name_valid(name, list)
	if not list then return true end

	for _, check_name in ipairs(list) do
		if name == check_name then return true end
	end

	return false
end

function senses:is_focused()
	return self.current_target and self:is_valid(self.current_target)
end

function senses:get_list(list_name)
	assert(self.object_lists[list_name], "[Creatura] [component.SENSES] " .. list_name .. " is not a valid object list.")

	return self.object_lists[list_name]
end

function senses:sort_lists()
	local sort_func = function(a, b)
		return a.distance < b.distance
	end

	table.sort(self.object_lists["mobs"], sort_func)
	table.sort(self.object_lists["players"], sort_func)
	table.sort(self.object_lists["items"], sort_func)
end

function senses:get_time()
	return core.get_us_time() / 1000000
end

function senses:line_of_sight(target)
	local pos = self.entity.object:get_pos()
	local target_pos = type(target) == "userdata" and target:get_pos() or target
	if not pos or not target_pos then return false end
	local eye_height = (self.entity.height or 1) * 0.8
	return creatura.line_of_sight(vector.offset(pos, 0, eye_height, 0), vector.offset(target_pos, 0, 0.5, 0))
end

function senses:is_los_on_cooldown()
	return self:get_time() - self.last_sight_check_time < line_of_sight_cooldown
end

return senses