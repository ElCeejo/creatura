---------------
-- Behaviors --
---------------

-- Built-in behaviors

-- Idle

creatura.register_behavior("creatura:idle", {
	get_score = function(behavior, entity)
		if behavior.no_liquid and entity.in_liquid then return 0 end
		return 0.1
	end,

	on_start = function(_, entity)
		entity.animation_controller:set_animation("stand")
		entity.path_follower:stop()
	end,

	on_step = function(_, entity)
		local animation_controller = entity.animation_controller
		if animation_controller.is_playing then return end

		entity.path_follower:stop()
		animation_controller:set_animation("stand")
	end
})

-- Random Wander

creatura.register_behavior("creatura:random_wander", {
	get_score = function()
		if math.random(3) == 1 then
			return 0.2
		end
	end,

	on_start = function(_, entity)
		entity.path_follower:set_target(creatura.get_wander_pos(entity.object:get_pos(), 4), {speed = 1})
		entity.animation_controller:set_animation("walk")
	end,

	can_continue = function(_, entity)
		if not entity.path_follower.is_active then
			return false
		end

		return true
	end,

	on_end = function(behavior, entity)
		entity.path_follower:stop()
		entity.animation_controller:set_animation("stand")
		behavior:set_cooldown(math.random(4, 6))
	end
})
