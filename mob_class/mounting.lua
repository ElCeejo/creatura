local mob_class = creatura.mob_class

creatura.attached_players = {}


local default_mount_settings = {
	bone = "",
	attachment_rotation = vector.zero(),
	attachment_point = vector.zero(),
	eye_offset = vector.zero()
}

local function dismount(player)
	local mounted_mob = player:get_attach()
	if not mounted_mob then return end

	local entity = mounted_mob:get_luaentity()
	if entity._rider and entity._rider == player then entity._rider = nil end
	creatura.attached_players[player:get_player_name()] = false

	player:set_detach()
	player:set_eye_offset(vector.zero(), vector.zero())
	player:set_properties({visual_size = {x = 1, y = 1}})
end

function mob_class:mount_player(player)
	dismount(player) -- Calling dismount ensures we start with a clean slate

	local mount_settings = self.mount_settings or default_mount_settings

	-- Attach Player
	self._rider = player
	creatura.attached_players[player:get_player_name()] = true
	player:set_attach(
		self.object,
		mount_settings.bone,
		mount_settings.attachment_point,
		mount_settings.attachment_rotation
	)
	player:set_eye_offset(mount_settings.eye_offset, vector.zero())

	-- Resize Player
	local player_scale = player:get_properties().visual_size
	local mob_scale = self.object:get_properties().visual_size
	player:set_properties({
		visual_size = mount_settings.attachment_scale or vector.divide(player_scale, mob_scale)
	})

	-- On Mount Callback
	if self.on_mounted then self:on_mounted(player) end
end

function mob_class:dismount_player(_player)
	local player = _player or self._rider
	if not player then return end

	dismount(player)

	-- On Mount Callback
	if self.on_dismounted then self:on_dismounted(player) end
end

function mob_class:has_rider()
	return self._rider and self._rider:is_valid()
end

function mob_class:get_rider()
	return self._rider ~= nil and self._rider
end

function mob_class:get_rider_control()
	local player = self:get_rider()
	if not player then return {} end

	return player:get_player_control()
end

function mob_class:get_rider_control_bits()
	local player = self:get_rider()
	if not player then return {} end

	return player:get_player_control_bits()
end

function mob_class:get_rider_yaw()
	local player = self:get_rider()
	if not player then return math.random(math.pi) end

	return player:get_look_horizontal()
end
