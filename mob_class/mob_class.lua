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

local mob_class = {
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
	_action_queue = {
		_front_pointer = 1,
		_back_pointer = 1,
		_actions = {},
		_args = {}
	},
	_detached_inventory = {
		_name = ",",
		_ref = {},
		_lists = {},
		_list_sizes = {}
	}
}

mob_class.__index = mob_class
creatura.mob_class = mob_class

-- Subclasses

local path_subclass = creatura.path_subclass

local animation = dofile(path_subclass .. "/animation.lua")
local physics = dofile(path_subclass .. "/physics.lua")
local traversal = dofile(path_subclass .. "/traversal.lua")
local targets = dofile(path_subclass .. "/targets.lua")
local utility_stack = dofile(path_subclass .. "/utility_stack.lua")

-- Main Class

local path_mob_class = creatura.path_mob_class

dofile(path_mob_class .. "/combat.lua")
dofile(path_mob_class .. "/taming.lua")
dofile(path_mob_class .. "/breeding.lua")
dofile(path_mob_class .. "/mounting.lua")
dofile(path_mob_class .. "/inventory.lua")

-- DEPRECATED

function mob_class:indicate_damage()
	self._original_texture_mod = self._original_texture_mod or self.object:get_texture_mod()
	self.object:set_texture_mod(self._original_texture_mod .. "^[multiply:#FF000040")
	minetest.after(0.2, function()
		if creatura.is_alive(self) then
			self.object:set_texture_mod(self._original_texture_mod)
		end
	end)
end

-- Debugging
function mob_class:add_diagnostic(k, v)
	if not self._diag_array then self._diag_array = {} end

	self._diag_array[k] = v
end

function mob_class:parse_diagnostic_array()
	local array = {}

	for k, v in pairs(self._diag_array) do
		table.insert(array, k .. " = " .. v .. "\n")
	end

	self.object:set_properties({
		nametag = table.concat(array, "")
	})
end

function mob_class:get_definition()
	return core.registered_entities[self.name]
end

-- Physics

local function is_node_traversable(pos)
	local node = core.get_node_or_nil(pos)
	if not node or node.name == "ignore" then return false end

	local def = core.registered_nodes[node.name]
	if not def or def.walkable then return false end -- liquidtype ~= "none" to check for water?

	return true
end

local function can_large_hitbox_fit(self, target_pos)
	local box = self.collisionbox -- todo: get box from properties to insure accuracy

	local min_p = {
		x = target_pos.x + (box[1] + 0.01),
		y = target_pos.y + (box[2] + 0.01),
		z = target_pos.z + (box[3] + 0.01)
	}

	local max_p = {
		x = target_pos.x + (box[4] - 0.01),
		y = target_pos.y + (box[5] - 0.01),
		z = target_pos.z + (box[6] - 0.01)
	}


	for x = min_p.x, max_p.x do
		for z = min_p.z, max_p.z do
			local max_y = max_p.y
			local current_y = min_p.y

			while current_y < max_y do
				local check_pos = {x = x, y = current_y, z = z}

				if not is_node_traversable(check_pos) then
					if current_y == min_p.y then
						max_y = max_y + math.floor(self.jump_height)
					else
						return false
					end
				end
			end
		end
	end

	return true
end

local function can_small_hitbox_fit(self, target_pos)
	local pos = self.object:get_pos()
	if not pos then return end

	if not is_node_traversable(target_pos) then
		local jump_height = math.floor(self.jump_height)

		if jump_height < 1 then
			return false
		else
			return is_node_traversable({
				x = target_pos.x,
				y = target_pos.y + jump_height,
				z = target_pos.z
			})
		end
	end

	return true
end

function mob_class:is_pos_safe(pos)
	local box = self.collisionbox or {-0.5, 0, -0.5, 0.5, 1, 0.5}

	local space_check = can_large_hitbox_fit
	if math.abs(box[1]) + math.abs(box[2]) < 1 then
		space_check = can_small_hitbox_fit
	end

	if not space_check(self, pos) then
		return false
	end

	if (self.max_fall or 0) > 0 then
		local is_above_all = creatura.is_pos_above_fall(vector.round(pos), self.max_fall)

		if is_above_all then
			return false
		end
	end

	return true
end

function mob_class:calculate_mob_collision()
	if not creatura.is_alive(self)
	or self.fancy_collide == false then return end
	local pos = self.object:get_pos()
	local width = self.width * 0.5
	local objects = minetest.get_objects_in_area(vector.subtract(pos, width), vector.add(pos, width))
	if #objects < 2 then return end
	local pos2
	local dir
	local vel, vel2
	for i = 2, #objects do
		local object = objects[i]
		if creatura.is_alive(object)
		and not self.object:get_attach()
		and not object:get_attach() then
			if i > 5 then break end
			pos2 = object:get_pos()
			dir = vector.direction(pos, pos2)
			dir.y = 0
			if dir.x == 0 and dir.z == 0 then
				dir = vector.new(random(-1, 1) * random(), 0,
								 random(-1, 1) * random())
			end
			vel = vector.multiply(dir, 1.5)
			vel2 = vector.multiply(dir, -1.2) -- multiplying by -2 accounts for friction
			self.object:add_velocity(vel2)
			object:add_velocity(vel)
		end
	end
end

function mob_class:set_scale(scale)
	local size = self.visual_size or {}
	local old_box = self.collisionbox or {-0.5, 0, -0.5, 0.5, 1, 0.5}
	local new_box = {}
	for k, v in ipairs(old_box) do
		new_box[k] = v * scale
	end
	self.object:set_properties({
		visual_size = {
			x = (size.x or 10) * scale,
			y = (size.y or 10) * scale,
			z = (size.z or 10) * scale
		},
		collisionbox = new_box
	})
end

function mob_class:get_hitbox_scale()
	local props = self.object:get_properties()
	local box = props.collisionbox

	return math.abs(box[1]) + box[4], box[5] - box[2]
end

-- Sounds
function mob_class:play_sound(sound)
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
function mob_class:get_props()
	local props = self.properties or self.object and self.object:get_properties()
	self.properties = props
	return props
end

-- Fixes scale relative to parent
function mob_class:fix_attached_scale(parent)
	local scale = self:get_visual_size()
	local parent_size = parent:get_properties().visual_size
	self.object:set_properties({
		visual_size = {
			x = scale.x / parent_size.x,
			y = scale.y / parent_size.y
		},
	})
end

-- Textures
function mob_class:set_texture_table(texture_table)
	if type(texture_table) == "string" then
		texture_table = self[texture_table]
	end

	local reset_texture_no = false
	if not self._custom_texture_table
	or #texture_table ~= #self._custom_texture_table then
		reset_texture_no = true
	end

	self._custom_texture_table = table.copy(texture_table)
	self.textures = self._custom_texture_table
	if reset_texture_no then
		self.texture_no = random(#self.textures)
	end


	self.object:set_properties({
		textures = {self.textures[self.texture_no]}
	})
end

-- Meshes
function mob_class:set_mesh(new_mesh)
	if type(new_mesh) == "number"
	or (not new_mesh and self.meshes ~= nil) then -- `new_mesh` is an index for self.meshes
		local meshes = self.meshes or {self.mesh}
		local mesh_no = new_mesh or self.mesh_no

		if not mesh_no
		or not meshes[mesh_no] then -- Pick a new index if the given index is invalid
			mesh_no = random(#meshes)
			self.mesh_no = mesh_no
		end

		local mesh = meshes[mesh_no]

		self.object:set_properties({
			mesh = mesh
		})

		if self.textures[mesh] then
			self:set_texture_table(self.textures[mesh])
		end
		return
	end

	self.object:set_properties({
		mesh = new_mesh
	})
	self.mesh_no = 1
end

-- Action Queue

local registered_actions = creatura.registered_actions

function mob_class:add_action_to_queue(name, ...)
	local back_pointer = self._action_queue._back_pointer
	local action = registered_actions[name]

    self._action_queue._actions[back_pointer] = action
	self._action_queue._args[back_pointer] = { ... }
    self._action_queue._back_pointer = back_pointer + 1
end

function mob_class:has_active_action()
	return self._action_queue._front_pointer < self._action_queue._back_pointer
end

function mob_class:clear_action_queue()
	self._action_queue = {
		_front_pointer = 1,
		_back_pointer = 1,
		_actions = {},
		_args = {}
	}
end

function mob_class:get_action_queue()
	return self._action_queue
end

-- Staticdata

function mob_class:memorize(id, val)
	self.perm_data[id] = val
	return self.perm_data[id]
end

function mob_class:forget(id)
	self.perm_data[id] = nil
end

function mob_class:recall(id)
	return self.perm_data[id]
end

function mob_class:get_staticdata()
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

	data._detached_inventory = {}
	data._detached_inventory._lists = self._detached_inventory._lists
	data._detached_inventory._list_sizes = self._detached_inventory._list_sizes

	data.active_time = self.active_time or 0
	return core.serialize(data)
end

-- On Activate
function mob_class:on_activate(staticdata, dtime)

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
function mob_class:on_step(dtime, moveresult)
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
function mob_class:on_punch(puncher, time_from_last_punch, tool_capabilities, dir, _damage)
	if not puncher then return end
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
function mob_class:on_rightclick(clicker)
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
function mob_class:on_deactivate(removal)
	if self._detached_inventory
	and self._detached_inventory._name then
		core.remove_detached_inventory(self._detached_inventory._name)
	end

	local func = self.deactivate_func
	if func then func(self, removal) end
end

-- Timer
function mob_class:timer(n)
	local t1 = math.floor(self.active_time)
	local t2 = math.floor(self.active_time + self.dtime)
	if t2 > t1 and t2%n == 0 then return true end
end

-- Distance checks
function mob_class:get_chebyshev_distance(target)
	if not target then return end
	if type(target) == "userdata" then
		target = target:get_pos()
	end
	local pos = self.object:get_pos()

	return math.max(
		math.abs(pos.z - target.z),
		--math.abs(pos.y - target.y),
		math.abs(pos.x - target.x)
	)
end

function mob_class:get_distance(target)
	if target
	and type(target) == "userdata" then
		target = target:get_pos()
	end

	local pos = self.object:get_pos()
	if not target or not pos then return self.tracking_range + 1 end

	return vector.distance(self.object:get_pos(), target)
end

function mob_class:has_reached_or_passed(pos2)
	local pos = self.object:get_pos()
	local dir = vector.direction(pos, pos2)

	local to_dest = vector.normalize({
		x = pos2.x - pos.x,
		y = 0,
		z = pos2.z - pos.z
	})

	return (dir.x * to_dest.x + dir.z * to_dest.z) < 0
end

local abs = math.abs

function mob_class:has_reached_pos(target_pos)
	local pos = self.object:get_pos()
	local vel = self.object:get_velocity() or {x = 0, y = 0, z = 0}
	local mob_traversal = self.traversal

	local vertical_threshold = 0.51
	if mob_traversal
	and mob_traversal.is_jumping then
		vertical_threshold = 1
	end

	local diff_y = target_pos.y - pos.y
	if abs(diff_y) > vertical_threshold then return false end

	local diff_x = target_pos.x - pos.x
	local diff_z = target_pos.z - pos.z
	local squared_dist = (diff_x * diff_x) + (diff_z * diff_z)
	local speed = math.sqrt((vel.x * vel.x) + (vel.z * vel.z))

	local dynamic_radius = math.min(0.4 + (speed * 0.15), 1.5)
	if squared_dist <= (dynamic_radius * dynamic_radius) then
		return true
	end

	if squared_dist < 4 and speed > 0.5 then
		local dot = (diff_x * vel.x) + (diff_z * vel.z)
		if dot <= 0 then
			return true
		end
	end

	return false
end

-- Register Mob
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
			self.utility_stack = utility_stack:new(self.object)

			init_util_stack(self, self.utility_stack)

			self.utility_stack:update()
		end
	end

	def._creatura_mob = true
	def.is_creatura_mob = true -- In-line with new conventions, denotes post-Nova mob

	core.register_entity(name, setmetatable(def, mob_class))
end

return mob_class
