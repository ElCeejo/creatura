local target_selector = {}
target_selector.__index = target_selector

-- Create new instance
function target_selector:new(parent)
	local new_selector = {
		parent = parent,
		time_of_last_cache = minetest.get_us_time() / 1000000,
		objects = {},
		stack = {},

		current_target = {},
		current_score = 0,
		closest_player = {},
		owner = {}
	}

	return setmetatable(new_selector, self)
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

	local parent_entity = self:parent_entity()
	local objects = minetest.get_objects_inside_radius(pos, parent_entity.tracking_range or 1) or {}
	if #objects < 1 then
		self.objects = {}
		return
	end

	local tentative_player_dist = math.huge
	local new_objects = {}

	for _, object in ipairs(objects) do
		local entity = object and object:get_luaentity()
		local is_player = object and object:is_player()

		if object ~= self.parent
		and ((entity
		and object:get_armor_groups().fleshy) -- TODO: Allow custom filter to reduce cache sizes
		or is_player) then
			table.insert(new_objects, object)

			if is_player
			and parent_entity:get_distance(object) < tentative_player_dist then
				self.closest_player = object
			end
		end
	end

	self.objects = new_objects

	if parent_entity.owner
	and core.get_player_by_name(parent_entity.owner) then
		self.owner = parent_entity
	end
end

-- Get list of objects
function target_selector:get_cached_objects()
	return self.objects
end

-- Set target predicate
function target_selector:set_predicate(predicate)
	if not predicate or type(predicate) ~= "table" then return {} end

	self.predicate = table.copy(predicate)

	return self.predicate
end

-- Experimental predicate
local default_predicate = {
	check_sight = false,
	include = {},
	exclude = {},
	get_score = function(_target_selector, target)
		local parent = _target_selector.parent
		local obj_pos = parent and parent:get_pos()
		local tgt_pos = target and target:get_pos()
		if not tgt_pos or not obj_pos then return 0 end

		local range = parent:get_luaentity().tracking_range
		local dist = vector.distance(obj_pos, tgt_pos)

		return (range - dist) / range
	end
}

local function to_set(list)
	local set = {}
	for _, i in ipairs(list) do
		set[i] = true
	end
	return set
end

function target_selector:do_predicate(target, tentative_predicate)
	local predicate = tentative_predicate or default_predicate
	local parent = self.parent

	if predicate.check_sight then
		local parent_pos = parent:get_pos()
		local target_pos = target:get_pos()

		if not creatura.line_of_sight(parent_pos, target_pos) then
			return 0
		end
	end

	local target_name
	if target:is_player() then
		target_name = "player"
	else
		target_name = target:get_luaentity().name
	end

	predicate.include = predicate.include or {}
	predicate.exclude = predicate.exclude or {}
	if #predicate.include
	and #predicate.include > 0 then
		predicate.include = to_set(predicate.include)
	end
	if #predicate.exclude
	and #predicate.exclude > 0 then
		predicate.exclude = to_set(predicate.exclude)
	end

	if next(predicate.include) ~= nil then
		local allowed = false

		for name in pairs(predicate.include) do
			if name == target_name then
				allowed = true
				break
			end
		end

		if not allowed then
			return 0
		end
	end

	if next(predicate.exclude) ~= nil then
		for name in pairs(predicate.exclude) do
			if name == target_name then
				return 0
			end
		end
	end

	if predicate.get_score then
		return predicate.get_score(self, target) or 0
	end

	return 0
end

-- Check validity of given target
function target_selector:is_target_valid(target)
	if not target then return false end

	if type(target) ~= "userdata" then return false end

	if not target:is_valid() then return false end

	local distance = self:parent_entity():get_distance(target) or math.huge
	if distance > self:parent_entity().tracking_range then return false end

	local entity = target:get_luaentity()
	if entity then
		local health = entity.health or entity.hp
		if health <= 0 then return false end
	end

	return true
end

-- Find a new target
function target_selector:find_target(predicate)
	self:cache_targets()
	if #self.objects < 1 then return end

	local tentative_predicate = predicate or default_predicate
	local tentative_target = false
	local tentative_score = 0

	--self:parent_entity():add_diagnostic("predicate", dump(predicate))

	for i = #self.objects, 1, -1 do
		local target = self.objects[i]
		if self:is_target_valid(target) then
			local target_score = self:do_predicate(target, tentative_predicate)
			if target_score > tentative_score then
				tentative_target = target
				tentative_score = target_score
			end
		else
			self.objects[i] = nil
		end
	end

	if tentative_score > self.current_score then
		self.predicate = table.copy(tentative_predicate)
		self.target = tentative_target
		self.current_score = tentative_score
	end

	return tentative_target
end

-- Find targets
function target_selector:find_targets(predicate)
	self:cache_targets()
	if #self.objects < 1 then return end
	if predicate then
		predicate = table.copy(predicate)
	else
		predicate = self.predicate
	end
	self:set_predicate(predicate)

	local targets = {}

	for i = #self.objects, 1, -1 do
		local target = self.objects[i]
		if self:is_target_valid(target) then
			local target_score = self:do_predicate(target, predicate)
			if target_score > 0 then
				table.insert(targets)
			end
		else
			self.objects[i] = nil
		end
	end

	return targets
end

-- Get currently selected target/Find a new target if none is selected
function target_selector:get_target()
	if not self:is_target_valid(self.target) then return end

	if self.predicate and self:do_predicate(self.target, self.predicate) <= 0 then return end

	return self.target
end

-- Get closest player
function target_selector:get_closest_player()
	self:cache_targets()

	local closest_player
	local lowest_dist = math.huge

	for _, object in ipairs(self.objects) do
		local is_player = object and object:is_player()
		local dist = self:parent_entity():get_distance(object)

		if dist < lowest_dist
		and is_player then
			closest_player = object
		end
	end

	return closest_player
end

return target_selector
