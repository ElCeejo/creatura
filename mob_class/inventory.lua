local mob_class = creatura.mob_class

-- Helpers

local active_ids = {}
local function generate_id()
	local function generate()
		local str = ""
		for _ = 0, 6 do str = str .. math.random(0, 9) end
		return str
	end

	local _id = generate()

	while active_ids[_id] do
		_id = generate()
	end

	active_ids[_id] = true

	return _id
end

local function serialize_list(list)
	local serialized_list = {}

	for i, stack in ipairs(list) do
		serialized_list[i] = stack:to_string()
	end

	return core.serialize(serialized_list)
end

local function deserialize_list(list, list_name, inventory)
	local saved_list = core.deserialize(list) or {}
	for i, itemstring in ipairs(saved_list) do
		if itemstring then inventory:set_stack(list_name, i, itemstring) end
	end
end

-- API

local default_callbacks = {
	allow_move = function(_, _, _, _, _, count)
		return count
	end,
	allow_put = function(_, _, _, stack)
		return stack:get_count()
	end,
	allow_take = function(_, _, _, stack)
		return stack:get_count()
	end,
}

function mob_class:create_detached_inventory(callbacks, player_name)
	local inventory_name = table.concat({
		self.name,
		"inventory",
		generate_id(),
		os.time()
	}, "_")

	local base_callbacks = callbacks or default_callbacks
	local new_callbacks = table.copy(base_callbacks)
	new_callbacks.on_move = function(...)
		if base_callbacks.on_move then base_callbacks.on_move(...) end
		self:serialize_inventory()
	end
	new_callbacks.on_put = function(...)
		if base_callbacks.on_put then base_callbacks.on_put(...) end
		self:serialize_inventory()
	end
	new_callbacks.on_take = function(...)
		if base_callbacks.on_take then base_callbacks.on_take(...) end
		self:serialize_inventory()
	end


	local inv_data = self._detached_inventory
	local inventory = core.create_detached_inventory(inventory_name, new_callbacks, player_name)
	inv_data._ref = inventory
	inv_data._name = inventory_name

	if inv_data._lists
	and inv_data._list_sizes then
		for list_name, list in pairs(inv_data._lists) do
			if list_name and inv_data._list_sizes[list_name] then
				inventory:set_size(list_name, inv_data._list_sizes[list_name])
				deserialize_list(list, list_name, inventory)
			end
		end
	end

	return inventory
end

-- Get InvRef or  list
function mob_class:get_detached_inventory(list)
	local inv_data = self._detached_inventory
	if not inv_data._ref then return end
	local inventory = inv_data._ref
	if list and type(list) == "string" then
		return inventory:get_list(list)
	else
		return inventory, inv_data._name
	end
end

-- Add a new list to detached inventory
function mob_class:add_list_to_detached_inventory(list_name, list_size)
	local inventory = self:get_detached_inventory()
	if not inventory then return end

	inventory:set_size(list_name, list_size)
	self._detached_inventory._list_sizes[list_name] = list_size

	local old_list = self._detached_inventory._lists[list_name]
	if old_list then -- Apply any existing data
		deserialize_list(list_name, inventory)
	else
		self._detached_inventory._lists[list_name] = ""
	end
end

function mob_class:serialize_inventory()
	local inv_data = self._detached_inventory
	if not inv_data._ref then return end

	local inventory = inv_data._ref
	local lists = inventory:get_lists()
	if not lists then return end

	for name, list in pairs(lists) do
		inv_data._lists[name] = serialize_list(list)
	end
end

function mob_class:drop_inventory(listname)
	local pos = self.object:get_pos()
	if not pos then return end

	local inv = self:get_detached_inventory()
	if not inv then return end

	if listname then -- Only drop specified list
		local list = inv:get_list(listname)
		if not list then return end

		for i = 1, #list do
			if list[i] then
				self:drop_item(inv:get_stack(listname, i))
				inv:set_stack(listname, i, nil)
			end
		end
	else -- Drop all lists
		local lists = inv:get_lists()
		if not lists then return end

		for _, list in pairs(lists) do
			for i = 1, #list do
				if list[i] then
					self:drop_item(inv:get_stack(listname, i))
					inv:set_stack(listname, i, nil)
				end
			end
		end
	end

	self:serialize_inventory()
end