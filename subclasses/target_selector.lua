local target_selector = {}
target_selector.__index = target_selector

-- Create new instance
function target_selector:new(parent)
	local new_selector = {
		parent = parent,
		time_of_last_cache = minetest.get_us_time() / 1000000,
		objects = {}
	}

	return setmetatable(new_selector, target_selector)
end

-- Return parent objects luaentity
function target_selector:parent_entity()
	return self.parent and self.parent:get_luaentity()
end

-- Cache nearby objects
-- won't check for new objects if called less than 10 seconds from last check
function target_selector:cache_targets()
	local parent = self.parent
	local pos = parent and parent:get_pos()
	if not pos then return end

	local current_time = minetest.get_us_time() / 1000000

	if current_time - self.time_of_last_cache < 10
	and #self.objects > 0 then
		return
	end

	local objects = minetest.get_objects_inside_radius(pos, self:parent_entity().tracking_range or 1) or {}
	if #objects < 1 then
		self.objects = {}
		return
	end

	local new_objects = {}

	for _, object in ipairs(objects) do
		local entity = object and object:get_luaentity()
		local is_player = object and object:is_player()

		if object ~= self.parent
		and ((entity
		and object:get_armor_groups().fleshy)
		or is_player) then
			table.insert(new_objects, object)
		end
	end

	self.objects = new_objects
end

-- Check "validity" of target
function target_selector:is_target_valid(target)
	-- TODO: Default to currently selected target if none is specified

	-- Early exit and return false if the ObjRef isn't valid
	if not target or not target:get_hp() then return false end

	-- Don't attack a target that we can't "see"
	local distance = self:parent_entity():get_distance(target:get_pos()) or math.huge
	if distance > self:parent_entity().tracking_range then return false end

	-- Don't beat a dead horse
	local entity = target:get_luaentity()
	if entity then
		local health = entity.health or entity.hp
		if health <= 0 then return false end
	end

	-- TODO: Support for a blacklist?

	return true
end

-- Logic for deciding which targets to single outset
function target_selector:priority_filter(target)
	return 1 / self:parent_entity():get_distance(target)
end

-- Get current target
-- if the current target is invalid this will automatically check
-- for a new one based on the last filter given to the selector
function target_selector:get_target()
	if not self.target or not self:is_target_valid(self.target) then
		return self:find_target()
	end

	return self.target
end

-- Return nearest player from cached objects
-- optional: specify a function to filter which player should be returned first
function target_selector:get_nearest_player(filter)
	self:cache_targets()
	if #self.objects < 1 then return end

	local pos = self.parent and self.parent:get_pos()
	if not pos then return end

	local nearest_player
	local lowest_dist = 100

	for _, player in ipairs(self.objects) do
		if player and player:is_player() then
			local player_pos = player and player:get_pos()

			if player_pos then
				local dist = vector.distance(pos, player_pos)

				if dist < lowest_dist
				and (not filter
				or filter(self.parent, player)) then
					nearest_player = player
					lowest_dist = dist
				end
			end
		end
	end

	return nearest_player
end

-- Return list of players from cached objects
-- optional: specify a function to filter which players should be returned
function target_selector:get_players(filter)
	self:cache_targets()
	if #self.objects < 1 then return end

	local pos = self.parent and self.parent:get_pos()
	if not pos then return end

	local result = {}

	for _, player in ipairs(self.objects) do
		if player and player:is_player() then
			if not filter
			or filter(self.parent, player) then
				table.insert(result, player)
			end
		end
	end

	return result
end

-- Return nearest mob from cached objects
-- optional: specify a function to filter which mob should be returned first
function target_selector:get_nearest_mob(filter)
	self:cache_targets()
	if #self.objects < 1 then return end

	local pos = self.parent and self.parent:get_pos()
	if not pos then return end

	local nearest_mob
	local lowest_dist = 100

	for _, object in ipairs(self.objects) do
		local object_pos = object and object:get_pos()
		local entity = object and object:get_luaentity()

		if entity
		and (not filter or filter(self.parent, object)) then
			local dist = vector.distance(pos, object_pos)

			if dist < lowest_dist then
				nearest_mob = object
				lowest_dist = dist
			end
		end
	end

	return nearest_mob
end

-- Return list of mobs from cached objects
-- optional: specify a function to filter which mobs should be returned
function target_selector:get_mobs(filter)
	self:cache_targets()
	if #self.objects < 1 then return end

	local pos = self.parent and self.parent:get_pos()
	if not pos then return end

	local result = {}

	for _, object in ipairs(self.objects) do
		local object_pos = object and object:get_pos()
		local entity = object and object:get_luaentity()

		if entity
		and (not filter or filter(self.parent, object)) then
			table.insert(result, object)
		end
	end

	return result
end

-- Find a new target
-- optional: specify a function to filter which target should be singled out
function target_selector:find_target(priority_filter)
    local pos = self.parent:get_pos()

	if priority_filter then self.priority_filter = priority_filter end
	self:cache_targets()
    local objects = self.objects
    local target = nil
    local highest_priority = 0

    for _, obj in ipairs(objects) do
		if self:is_target_valid(obj)
		and self:priority_filter(obj) > highest_priority then
			target = obj
		end
    end
    return target
end

return target_selector
