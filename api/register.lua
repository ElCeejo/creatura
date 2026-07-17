----------------------------
-- Registration functions --
----------------------------

-- Register new behavior

creatura.registered_behaviors = {}

function creatura.register_behavior(name, def)
	local new_behavior = def

	new_behavior.get_score = def.get_score or function() return 0.1 end -- for mobs that use utility stacks

	new_behavior.can_start = def.can_start or function() return true end -- for mobs that use priority queues

	new_behavior.on_start  = def.on_start or nil

	new_behavior.can_continue = def.can_continue or function() return true end

	new_behavior.on_step = def.on_step or function() end

	new_behavior.on_end = def.on_end or function() --[[behavior:set_cooldown(10)]] end

	function new_behavior.get_name()
		return name
	end

	function new_behavior:set_cooldown(time)
		self.cooldown = time
		self.last_ran = core.get_us_time()
	end

	function new_behavior:is_on_cooldown()
		if not self.cooldown or not self.last_ran then return false end

		local last_ran_seconds = self.last_ran / 1000000
		local current_time_seconds = core.get_us_time() / 1000000

		if current_time_seconds - last_ran_seconds > self.cooldown then
			self.cooldown = 0
			self.last_ran = false
			return false
		end

		return true
	end

	new_behavior.__index = new_behavior

	creatura.registered_behaviors[name] = new_behavior
end

-- Register new action

creatura.registered_actions = {}

function creatura.register_action(name, func)
	local current_mod_name = core.get_current_modname()
	assert(
		(name and name:match("^" .. current_mod_name .. ":")),
		"[Creatura] Invalid modname in attempt to register action: " .. name
	)
	assert(
		(creatura.registered_actions[name] == nil),
		"[Creatura] Attempt to override existing action: " .. name
	)
	assert(
		(func and type(func) == "function"),
		"[Creatura] Missing function in attempt to register action: " .. name
	)
	creatura.registered_actions[name] = func
end

-- Register new motion driver

creatura.registered_motion_drivers = {}

function creatura.register_motion_driver(name, def)
	if not name then return end
	assert(
		def.calculate_yaw ~= nil and def.calculate_velocity ~= nil,
		"[Creatura] Missing function in attempt to register motion driver: " .. name
	)
	assert(
		type(def.calculate_yaw) == "function" and type(def.calculate_velocity) == "function",
		"[Creatura] Invalid function in attempt to register motion driver: " .. name
	)

	creatura.registered_motion_drivers[name] = {
		calculate_yaw = def.calculate_yaw or function() -- Expects: traversal, entity, pos, dir
			return math.pi
		end,

		calculate_velocity = def.calculate_velocity or function() -- Expects: traversal, entity, pos, dir
			return vector.new()
		end
	}
end
