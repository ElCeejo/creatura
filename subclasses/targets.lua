

local targets = {}
targets.__index = targets

function targets:initiate(entity)
	local new_targets = {
		entity = entity,
		time_of_last_cache = core.get_us_time() / 1000000,
		cached_objects = {}
	}

	entity.targets = setmetatable(new_targets, targets)
end

function targets:is_target_valid(target)
	if not target then return false end

	if type(target) ~= "userdata" then return false end

	if not target:is_valid() then return false end

	local parent_entity = self.entity
	local distance = parent_entity:get_distance(target) or math.huge
	if distance > parent_entity.tracking_range then return false end

	local entity = target:get_luaentity()
	if entity then
		local health = entity.health or entity.hp or 0
		if health <= 0 then return false end
	end

	return true
end

function targets:cache_nearby_objects()
	local parent = self.entity.object
	local pos = parent and parent:get_pos()
	if not pos then return end

	local current_time = core.get_us_time() / 1000000

	if current_time - self.time_of_last_cache < 10
	and #self.cached_objects > 0 then
		return
	end

	local parent_entity = self.entity
	local objects = core.get_objects_inside_radius(pos, parent_entity.tracking_range or 1) or {}
	if #objects < 1 then
		self.cached_objects = {}
		return
	end

	local new_objects = {}

	for _, object in ipairs(objects) do
		if object ~= self.entity.object
		and self:is_target_valid(object) then
			table.insert(new_objects, object)
		end
	end

	self.cached_objects = new_objects

	if parent_entity.owner
	and core.get_player_by_name(parent_entity.owner) then
		self.owner = parent_entity
	end
end

function targets:get_nearest_player(predicate)
	self:cache_nearby_objects()

	local pos = self.entity.object:get_pos()

	local target
	local current_dist
	for _, candidate in ipairs(self.cached_objects) do
		local pos2 = candidate and candidate:get_pos()

		if pos2
		and candidate:is_player()
		and candidate:get_player_name() ~= self.entity.owner
		and (not predicate or predicate(self.entity, candidate))
		and (not current_dist
		or vector.distance(pos, pos2) < current_dist) then
			target = candidate
			current_dist = vector.distance(pos, pos2)
		end
	end

	return target
end

local function is_name_valid(mob_names, name)
	for _, mob_name in ipairs(mob_names) do
		if mob_name == name then return true end
	end

	return false
end

function targets:get_nearest_mob(mob_names, predicate)
	self:cache_nearby_objects()

	local pos = self.entity.object:get_pos()

	if type(mob_names) == "string" then mob_names = {mob_names} end

	local target
	local current_dist
	for _, candidate in ipairs(self.cached_objects) do
		local pos2 = candidate and candidate:get_pos()
		local name
		if candidate:get_luaentity() then
			name = candidate:get_luaentity().name
		else
			name = "player"
		end

		if pos2
		and is_name_valid(mob_names, name)
		and (not predicate
		or (self.current_predicate ~= predicate
		and predicate(self.entity, candidate)))
		and (not current_dist
		or vector.distance(pos, pos2) < current_dist) then
			target = candidate
			current_dist = vector.distance(pos, pos2)
		end
	end

	if target then self.current_predicate = predicate or {} end

	return target
end

return targets
