----------------------------
-- Registration functions --
----------------------------

-- Register new behavior

creatura.registered_behaviors = {}

function creatura.register_behavior(name, def)
	local new_behavior = {
		get_score = def.get_score or function() return 0.1 end, -- for mobs that use utility stacks

		can_start = def.can_start or function() return true end, -- for mobs that use priority queues

		on_start = def.on_start or nil,

		can_continue = def.can_continue or function() return true end,

		on_step = def.on_step or function() end,

		on_end = def.on_end or function() --[[behavior:set_cooldown(10)]] end
	}

	function new_behavior:get_name()
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
