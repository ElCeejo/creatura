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
		varargs = {}
	}

	return setmetatable(new_stack, utility_stack)
end

-- Return parent objects luaentity
function utility_stack:parent_entity()
	return self.parent and self.parent:get_luaentity()
end

-- End current behavior
function utility_stack:end_behavior()
	self.active_behavior = {}
	self.active_score = 0
	self.active_index = 0
	self.varargs = {}
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

				if score > candidate_score
				or (score == candidate_score
				and index > candidate_index) then -- New utility must have a higher score or equal score with higher priority
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

	if current_behavior:can_continue(parent_entity, unpack(self.varargs)) then
		local step_result = current_behavior:on_step(parent_entity, unpack(self.varargs))

		if step_result == "end" then
			current_behavior:on_end(parent_entity, unpack(self.varargs))
			self:end_behavior()
		end
	else
		current_behavior:on_end(parent_entity, unpack(self.varargs))
		self:end_behavior()
	end

	return nil
end

return utility_stack
