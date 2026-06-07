local mob_class = creatura.mob_class

function mob_class:get_player_holding_food()
	local pos = self.object:get_pos()
	if not pos then return end

	for _, player in ipairs(core.get_connected_players()) do
		local player_pos = player and player:get_pos()

		if player_pos
		and vector.distance(pos, player_pos) < self.tracking_range
		and self:is_tempted_by(player:get_wielded_item()) then
			return player
		end
	end
end


function mob_class:set_child()
	self:set_scale(0.5)
	self.is_child = true
	self.time_until_grown = 300
	if self.child_textures then
		self:set_texture_table(self.child_textures)
	end
end

function mob_class:growth_step()
	local time_until_grown = self.time_until_grown or 0
	time_until_grown = time_until_grown - self.dtime

	if time_until_grown <= 0
	and self.is_child then
		self:set_scale(1)
		self.is_child = false
		time_until_grown = 0

		if self.on_grown then
			self:on_grown()
		else
			local textures = self:get_definition().textures
			self:set_texture_table(textures)
		end
	end

	self.time_until_grown = time_until_grown
end