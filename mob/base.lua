---------------
-- Mob Class --
---------------
-- Math

local random = math.random

local function clamp(val, _min, _max)
	if val < _min then
		val = _min
	elseif _max < val then
		val = _max
	end
	return val
end

-- Main Class

local mob_base = {
	-- Initial properties
	hp_max = 10,
	physical = true,
	collide_with_objects = false,
	collisionbox = {-0.5, 0, -0.5, 0.5, 1, 0.5},
	--selectionbox = {-0.5, 0, -0.5, 0.5, 1, 0.5},
	pointable = true,
	visual = "mesh",
	visual_size = {x = 1, y = 1, z = 1},
	mesh = "model.b3d",
	textures = {},
	use_texture_alpha = true,
	is_visible = true,
	makes_footstep_sound = true,
	stepheight = 1.1,
	backface_culling = false,
	glow = 0,
	static_save = true,
	damage_texture_modifier = "^[colorize:#FF0000",
	shaded = true,
	show_on_minimap = false,

	-- Creatura properties
	max_health = 20,
	max_breath = 20,
	max_feed_count = 5,
	max_fall = 3,
	armor_groups = {
		fleshy = 100,
		fall = 100
	},
	turn_rate = 3.14,
	jump_height = 1.1,
	tempted_by = {},

	-- Internal properties
	_is_child = false,
	_time_until_grown = 0,

}

mob_base.__index = mob_base
creatura.mob_base = mob_base

local physics = creatura.components.PHYSICS
local animation = creatura.components.ANIMATION
local traversal = creatura.components.TRAVERSAL
local targets = creatura.components.TARGETS
local senses = creatura.components.SENSES

creatura.load_file("MOB", "spatial")
creatura.load_file("MOB", "visuals")
creatura.load_file("MOB", "combat")
creatura.load_file("MOB", "taming")
creatura.load_file("MOB", "mounting")
creatura.load_file("MOB", "inventory")

-- DEPRECATED

function mob_base:indicate_damage()
	self._original_texture_mod = self._original_texture_mod or self.object:get_texture_mod()
	self.object:set_texture_mod(self._original_texture_mod .. "^[multiply:#FF000040")
	minetest.after(0.2, function()
		if creatura.is_alive(self) then
			self.object:set_texture_mod(self._original_texture_mod)
		end
	end)
end

-- Debugging
function mob_base:add_diagnostic(k, v)
	if not self._diag_array then self._diag_array = {} end

	self._diag_array[k] = v
end

function mob_base:parse_diagnostic_array()
	local array = {}

	for k, v in pairs(self._diag_array) do
		table.insert(array, k .. " = " .. v .. "\n")
	end

	self.object:set_properties({
		nametag = table.concat(array, "")
	})
end

function mob_base:get_definition()
	return core.registered_entities[self.name]
end

-- Sounds
function mob_base:play_sound(sound)
	local spec = self.sounds and self.sounds[sound] or creatura.sounds[sound]
	if not spec then return end

	local parameters = {object = self.object}

	if type(spec) == "table" then
		local name = spec.name
		local pitch = 1.0

		pitch = pitch - (random(-10, 10) * 0.005)

		parameters.gain = spec.gain or 1.0
		parameters.max_hear_distance = spec.distance or 8
		parameters.fade = spec.fade or 1.0
		parameters.pitch = pitch
		return minetest.sound_play(name, parameters)
	end
	return minetest.sound_play(spec, parameters)
end

-- Cache properties
function mob_base:get_props()
	local props = self.properties or self.object and self.object:get_properties()
	self.properties = props
	return props
end

-- Action Queue

local registered_actions = creatura.registered_actions

function mob_base:add_action_to_queue(name, ...)
	local back_pointer = self._action_queue._back_pointer
	local action = registered_actions[name]

    self._action_queue._actions[back_pointer] = action
	self._action_queue._args[back_pointer] = { ... }
    self._action_queue._back_pointer = back_pointer + 1

	if creatura.settings.debug_mode then
		self:add_diagnostic("Last action added to queue", name)
	end
end

function mob_base:has_active_action()
	return self._action_queue._front_pointer < self._action_queue._back_pointer
end

function mob_base:clear_action_queue()
	self._action_queue = {
		_front_pointer = 1,
		_back_pointer = 1,
		_actions = {},
		_args = {}
	}
end

function mob_base:get_action_queue()
	return self._action_queue
end

-- Staticdata

function mob_base:memorize(id, val)
	self.perm_data[id] = val
	return self.perm_data[id]
end

function mob_base:forget(id)
	self.perm_data[id] = nil
end

function mob_base:recall(id)
	return self.perm_data[id]
end

function mob_base:get_staticdata()
	local data = {}
	data.perm_data = self.perm_data
	data.health = self.health or self.hp or self.max_health
	self.hp = data.health -- backward compatability
	data._breath = self._breath or self.max_breath

	data._custom_texture_table = self._custom_texture_table
	data.textures = self._custom_texture_table or self.textures
	if not #self.textures then self.texture_no = 1 end
	data.texture_no = self.texture_no or random(#self.textures)
	data.mesh_no = self.mesh_no or (self.meshes and random(#self.meshes))

	data._is_child = self._is_child or false
	data._time_until_grown = self._time_until_grown or 0

	data._protected = self._protected
	data._owner = self._owner
	data._feed_count = self._feed_count or 0

	local detached_inv = self._detached_inventory or {}
	data._detached_inventory = {}
	data._detached_inventory._lists = detached_inv._lists or {}
	data._detached_inventory._list_sizes = detached_inv._list_sizes or {}

	data.active_time = self.active_time or 0
	return core.serialize(data)
end

-- On Activate
function mob_base:on_activate(staticdata, dtime)
	-- Load staticdata
	if staticdata == "" then staticdata = self:get_staticdata() end
	local data = core.deserialize(staticdata)
	if data then
		local tp
		for k, v in pairs(data) do
			tp = type(v)
			if tp ~= "function"
			and tp ~= "nil"
			and tp ~= "userdata" then
				self[k] = v
			end
		end
	end

	self.perm_data = self.perm_data or {}

	self._action_queue = {
		_front_pointer = 1,
		_back_pointer = 1,
		_actions = {},
		_args = {}
	}

	local inv_data = self._detached_inventory or {}
	self._detached_inventory = {
		_lists = inv_data._lists or {},
		_list_sizes = inv_data._list_sizes or {}
	}

	self.is_child = nil
	if self:is_child() then
		self:set_child()
	end

	-- Visuals
	if self.meshes then
		self:set_mesh(self.mesh_no)
	end

	local textures = self.textures[self.texture_no]
	if textures then
		if type(textures) == "table" then
			self.object:set_properties({
				textures = textures
			})
		else
			self.object:set_properties({
				textures = {textures}
			})
		end
	end

	self.width, self.height = self:get_hitbox_scale()

	senses:initiate(self)
	targets:initiate(self)
	animation:initiate(self)
	physics:initiate(self)
	traversal:initiate(self)

	self.dtime = dtime
	self.active_time = (self.active_time or 0) + dtime

	-- Handle despawning
	if self:recall("despawn_after") ~= nil then
		self.despawn_after = self:recall("despawn_after")
	end
	self._despawn = self:recall("_despawn") or nil

	if self._despawn
	and self.despawn_after
	and self.object then
		self.object:remove()
		return
	end

	self.punch_cooldown_timer = 0

	-- Initiate mob vitals
	if type(self.armor_groups) ~= "table" then
		self.armor_groups = {} -- TODO: default fleshy to given number if type() == "number"
	end
	self.armor_groups.immortal = 1 -- Ignore Luanti hp, Creatura uses it's own method.
	self.object:set_armor_groups(self.armor_groups)

	if self.activate_func then self:activate_func(staticdata, dtime) end

	if self.initialize_utility_stack then
		self:initialize_utility_stack()
	end
end

-- On Step
function mob_base:on_step(dtime, moveresult)
	self.width, self.height = self:get_hitbox_scale()

	self.punch_cooldown_timer = math.max(self.punch_cooldown_timer - dtime, 0)

	self.dtime = dtime
	self.moveresult = moveresult
	self.touching_ground = moveresult and moveresult.touching_ground or false
	self.stand_pos = self.object:get_pos()

	self:check_environment_damage()
	self:growth_step()

	self._diag_array = self._diag_array or {}

	self.physics:on_step(dtime)
	self.traversal:on_step(dtime)

	if (self.health or self.hp) <= 0 then
		if self.utility_stack then self.utility_stack:end_behavior() end
		if self.traversal then self.traversal:stop() end
		if self:on_death() then
			self.object:remove()
			return
		end

		return
	end

	if self.utility_stack then self.utility_stack:update() end
	self.animation:on_step()

	self:parse_diagnostic_array()

	if self.step_func then self:step_func(dtime, moveresult) end

	if self.sounds
	and self:timer(5)
	and self.sounds["random"]
	and random(3) == 1 then
		self:play_sound("random")
	end

	self.properties = nil
	self.active_time = self.active_time + dtime

	if self.despawn_after then
		local despawn = math.floor(self.active_time / self.despawn_after)
		if despawn > 1 then self.object:remove() return end
		if despawn > 0
		and not self._despawn then
			self._despawn = self:memorize("_despawn", true)
		end
	end
end

-- On Punch
function mob_base:on_punch(puncher, time_from_last_punch, tool_capabilities, dir, _damage)
	if not puncher or puncher == self.object then return end
	self.last_puncher = puncher

	-- Get info from player and the players tool
	local tool
	--local tool_name = ""
	local add_wear = false
	if puncher:is_player() then
		tool = puncher:get_wielded_item()
		--tool_name = tool:get_name()
		add_wear = not minetest.is_creative_enabled(puncher:get_player_name())
	end

	local damage = 0

	-- Calculate final damage number
	local armor_groups = self.object:get_armor_groups() or self.armor_groups or {}
	for group, val in pairs(tool_capabilities.damage_groups or {}) do
		local damage_mod = time_from_last_punch / (tool_capabilities.full_punch_interval or 1.4)
		damage = damage + val * clamp(damage_mod, 0, 1) * ((armor_groups[group] or 0) / 100.0)
	end

	-- Apply damage
	if damage > 0 then
		local pos = self.object:get_pos()
		local puncher_pos = puncher:get_pos()
		if not pos or not puncher_pos then return end
		local dist = vector.distance(pos, puncher_pos)
		dir.y = 0.2
		if self.touching_ground then
			local power = clamp((damage / dist) * 8, 0, 8)
			self:apply_knockback(dir, power)
		end
		self:hurt(damage)
		self:indicate_damage()
	end

	-- Add wear to players tool if applicable
	if add_wear then
		local wear = math.floor((tool_capabilities.full_punch_interval / 75) * 9000)
		tool:add_wear(wear)
		puncher:set_wielded_item(tool)
	end

	-- Play sounds
	--[[if (time_from_last_punch or 0) > 0.5 then
		if random(2) < 2 then
			self:play_sound("hurt")
		end
		self:play_sound("hit")
	end]]

	if self.on_hit then
		self:on_hit(puncher, time_from_last_punch, tool_capabilities, dir, _damage)
	end
end

-- On Rightclick
function mob_base:on_rightclick(clicker)
	local wielded_item = clicker and clicker:is_player() and clicker:get_wielded_item()
	local feed_count = self._feed_count or 0

	-- Feed mob
	if self:is_tempted_by(wielded_item) then
		feed_count = feed_count + 1
		wielded_item = (self.on_fed and self:on_fed(clicker, wielded_item, feed_count)) or wielded_item

		if feed_count > (self.max_feed_count or 5) then
			feed_count = 0
		end
		self._feed_count = feed_count
	end

	clicker:set_wielded_item(wielded_item)

	if self.on_interact then
		self:on_interact(clicker)
	end
end

-- On Deactivate
function mob_base:on_deactivate(removal)
	if self._detached_inventory
	and self._detached_inventory._name then
		core.remove_detached_inventory(self._detached_inventory._name)
	end

	local func = self.deactivate_func
	if func then func(self, removal) end
end

-- Timer
function mob_base:timer(n)
	local t1 = math.floor(self.active_time)
	local t2 = math.floor(self.active_time + self.dtime)
	if t2 > t1 and t2%n == 0 then return true end
end

return mob_base
