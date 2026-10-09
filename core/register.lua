----------------------------
-- Registration functions --
----------------------------

-- Register New Mob

function creatura.register_mob(name, def)
	-- Register old Creatura mob
	if def.utility_stack then
		creatura.register_mob_antiquus(name, def)
		return
	end

	if getmetatable(def) then
		-- TODO: Error message
		return
	end

	-- Default mesh to first mesh in def.meshes to avoid breaking things
	def.mesh = def.mesh or (def.meshes and def.meshes[1])

	-- Quick equal-sided hitbox definition
	local box_width = def.hitbox and def.hitbox.width or 0.5
	local box_height = def.hitbox and def.hitbox.height or 1
	local hitbox = {-box_width, 0, -box_width, box_width, box_height, box_width}
	def.collisionbox = hitbox

	-- Overwrite on_rightclick if needed
	local old_rightclick
	if def.on_rightclick then
		old_rightclick = def.on_rightclick
		def.on_interact = old_rightclick
		def.on_rightclick = nil
	end

	-- Overwrite on_punch if needed
	local old_punch
	if def.on_punch then
		old_punch = def.on_punch
		def.on_hit = old_punch
		def.on_punch = nil
	end

	if def.on_deactivate then
		def.deactivate_func = def.on_deactivate
		def.on_deactivate = nil
	end

	-- Mortality.
	def.on_death = def.on_death or function(self)
		self._death_timer = (self._death_timer or 2) - self.dtime

		if not self.animation:attempt_to_play("die") then
			local rot = self.object:get_rotation()
			local goal = math.pi * 0.5
			local step = self.dtime
			if step > 0.5 then step = 0.5 end

			if rot.z < goal then
				rot.z = rot.z + math.pi * step
				self.object:set_rotation(rot)
			end
		end

		if self._death_timer <= 0 then
			local pos = self.stand_pos
			creatura.particle_spawner("float", {
				minpos = {x = pos.x - 0.1, y = pos.y, z = pos.z - 0.1},
				maxpos = {x = pos.x + 0.1, y = pos.y + 0.1, z = pos.z + 0.1},
				texture = "creatura_smoke_particle.png",
				animation = {
					type = 'vertical_frames',
					aspect_w = 4,
					aspect_h = 4,
					length = 1,
				},
				glow = 1
			})
			self:drop_loot()
			return true
		end
	end

	if def.initialize_utility_stack then
		local init_util_stack = def.initialize_utility_stack

		def.initialize_utility_stack = function(self)
			self.utility_stack = creatura.components.UTILITY_STACK:new(self.object)

			init_util_stack(self, self.utility_stack)

			self.utility_stack:update()
		end
	end

	def._creatura_mob = true
	def.is_creatura_mob = true -- In-line with new conventions, denotes post-Nova mob

	core.register_entity(name, setmetatable(def, creatura.mob_base))
end

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
