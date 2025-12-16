local boid_handler = {}
boid_handler.__index = boid_handler

local vec_sub = vector.subtract
local vec_mul = vector.multiply

function boid_handler:new(parent, spec)
	local new_boid_handler = spec or {}

	new_boid_handler.parent = parent
	new_boid_handler.separation = new_boid_handler.separation or 1
	new_boid_handler.alignment = new_boid_handler.alignment or 1
	new_boid_handler.cohesion = new_boid_handler.cohesion or 1
	new_boid_handler.check_interval = 0.3
	new_boid_handler.last_check = core.get_us_time()
	new_boid_handler.radius = new_boid_handler.radius or 3
	new_boid_handler.neighbors = {}

	return setmetatable(new_boid_handler, boid_handler)
end

-- Return parent objects luaentity
function boid_handler:parent_entity()
	return self.parent and self.parent:get_luaentity()
end

-- Get all boid members
function boid_handler:get_neighbors()
	local parent_entity = self:parent_entity()

	-- Only check every x seconds for performance
	local last_ran_seconds = self.last_check / 1000000
	local current_time_seconds = core.get_us_time() / 1000000

	if current_time_seconds - last_ran_seconds < self.check_interval
	and #self.neighbors > 0 then
		return
	end
	self.last_check = core.get_us_time()

	local parent = self.parent
	local pos = parent:get_pos()
	if not pos then return end

	self.neighbors = {}

	for _, object in ipairs(minetest.get_objects_inside_radius(pos, self.radius)) do
		if object ~= parent then
			local ent = object and object:get_luaentity()
			if ent and ent.name == parent_entity.name then
				table.insert(self.neighbors, object)
			end
		end
	end
end

-- Calculate boid direction only when called
function boid_handler:get_direction()
	local parent = self.parent
	local pos = parent:get_pos()
	if not pos then return {x = 0, y = 0, z = 0} end

	self:get_neighbors()

	local count = 0
	local separation = {x = 0, y = 0, z = 0}
	local alignment = {x = 0, y = 0, z = 0}
	local cohesion = {x = 0, y = 0, z = 0}

	for i = #self.neighbors, 1, -1 do -- Iterate backwards to avoid crashes when removing invalid objects
		local object = self.neighbors[i]
		if not object or not object:is_valid() then
			table.remove(self.neighbors, i)
		else
			local neighbor_pos = object:get_pos()
			local diff = vec_sub(pos, neighbor_pos)
			local dist = diff:length()

			separation = separation + vec_mul(diff:normalize(), 1 / dist)
			alignment = alignment + object:get_velocity()
			cohesion = cohesion + neighbor_pos
			count = count + 1
		end
	end

	if count == 0 then return {x = 0, y = 0, z = 0} end

	separation = (separation * (1 / count)) * self.separation
	alignment = (alignment * (1 / count)) * self.alignment
	cohesion = vec_sub((cohesion * (1 / count)), pos) * self.cohesion

	return separation + alignment + cohesion
end

return boid_handler
