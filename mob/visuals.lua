local mob_base = creatura.mob_base

local abs = math.abs
local random = math.random

-- Sets both visual and physical (hitbox) scale to `mob.visual_size` * `scale`
function mob_base:set_scale(scale)
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

-- Returns total physical mob width as `width`, `height`
function mob_base:get_hitbox_scale()
	local props = self.object:get_properties()
	local box = props.collisionbox

	return abs(box[1]) + box[4], box[5] - box[2]
end

-- Returns the mobs current `visual_size` in table form
function mob_base:get_visual_size()
	if not self:get_props() then return end
	return self:get_props().visual_size
end

-- Fixes scale of child relative to parent
-- 	Luanti has a long-standing issue where a mismatch in visual_size between parent
-- 	and child results in the child scaling incorrectly.
function mob_base:fix_attached_scale(parent)
	local scale = self:get_visual_size()
	local parent_size = parent:get_properties().visual_size
	self.object:set_properties({
		visual_size = {
			x = scale.x / parent_size.x,
			y = scale.y / parent_size.y,
			z = scale.z / parent_size.z
		},
	})
end

-- Sets the textures the object has available
function mob_base:set_texture_table(texture_table)
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

-- Sets the mesh to `mesh` from the mob definition or `new_mesh` if specified
-- Also works similar to random texture selection if mob definition uses `meshes`
function mob_base:set_mesh(new_mesh)
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
