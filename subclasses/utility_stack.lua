local utility_stack = {}
utility_stack.__index = utility_stack

-- Create new instance
function utility_stack:new(object)
	local new_stack = {
		parent = object,
		stack = {},

		active_behavior = {},
		active_score = 0,
		active_index = 0,
		varargs = {},

		action_step_queue = {},
		action_stop_queue = {},
		action_front_pointer = 1,
		action_back_pointer = 1
	}

	return setmetatable(new_stack, self)
end

-- Return parent objects luaentity
function utility_stack:parent_entity()
	return self.parent and self.parent:get_luaentity()
end

-- Action Queue
function utility_stack:clear_action_queue()
	self.action_step_queue = {}
	self.action_stop_queue = {}
	self.action_front_pointer = 1
	self.action_back_pointer = 1
end

function utility_stack:add_action_to_queue(action_func, check_func)
	local back = self.action_back_pointer
	self.action_step_queue[back] = action_func
	self.action_stop_queue[back] = check_func
	self.action_back_pointer = back + 1
end

function utility_stack:has_active_action()
	return self.action_front_pointer < self.action_back_pointer
end

-- End current behavior
function utility_stack:end_behavior()
	self.active_behavior = {}
	self.active_score = 0
	self.active_index = 0
	self.varargs = {}

	self:clear_action_queue()
end

-- Add a new behavior to the stack
function utility_stack:add_behavior(name, spec)
	local behavior_spec = creatura.registered_behaviors[name]

	self.stack[#self.stack + 1] = setmetatable(spec or {}, behavior_spec)
end

-- Start behavior
function utility_stack:start_behavior(bh, sc, id, va)
	self.active_behavior = bh
	self.active_score = sc
	self.active_index = id
	self.varargs = va

	if bh and bh.on_start then bh:on_start(self:parent_entity(), unpack(va)) end
end

-- Clear all behaviors from the stack
function utility_stack:clear_behaviors()
	self:end_behavior()
	self.stack = {}
end

-- Perform current behavior every server-step, pick out a new behavior every second or if no behavior is running
function utility_stack:update()
	local parent_entity = self:parent_entity()

	-- Find initial candidate utility
	local candidate_behavior
	local candidate_score = self.active_score
	local candidate_index = self.active_index
	local candidate_varargs

	if not getmetatable(self.active_behavior)
	or parent_entity:timer(1) then
		for index, util in ipairs(self.stack) do
			if not util:is_on_cooldown() then
				local score, varargs = util:get_score(parent_entity)
				if not score then score = 0 end

				if score > 0 -- NEVER initiate with a score of 0
				and (score > candidate_score
				or (score == candidate_score
				and index > candidate_index)) then -- New utility must have a higher score or equal score with higher priority
					candidate_behavior = util
					candidate_score = score
					candidate_index = index
					candidate_varargs = varargs or {}
				end
			end
		end
	end

	if candidate_behavior then
		self:end_behavior()
		self:start_behavior(candidate_behavior, candidate_score, candidate_index, candidate_varargs)
	end

	local current_behavior = self.active_behavior
	if not getmetatable(current_behavior) then return end

	--parent_entity:add_diagnostic("Current Behavior", current_behavior:get_name())

	-- End when can_continue returns false
	if not current_behavior:can_continue(parent_entity, unpack(self.varargs)) then
		current_behavior:on_end(parent_entity, unpack(self.varargs))
		self:end_behavior()
		return
	end

	-- Perform on_step
	local step_result = current_behavior:on_step(parent_entity, unpack(self.varargs))

	-- End when on_step returns "end"
	if step_result == "end" then
		current_behavior:on_end(parent_entity, unpack(self.varargs))
		self:end_behavior()
		return
	end

	-- Execute actions
	local front = self.action_front_pointer
	if front < self.action_back_pointer then
		local action_stop = self.action_stop_queue[front]
		local action_step = self.action_step_queue[front]
		action_step(current_behavior, parent_entity)

		if action_stop(current_behavior, parent_entity) then
			self.action_front_pointer = front + 1
		end
	end
end

return utility_stack
