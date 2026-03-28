-- Helper functions

-- Math

local pi = math.pi
local random = math.random

local vec_dist, vec_offset = vector.distance, vector.offset

local vec_raise = function(v, n)
	return vec_offset(v, 0, n, 0)
end

function creatura.radians_difference_abs(a, b)
	return math.abs(math.atan2(math.sin(b - a), math.cos(b - a)))
end

function creatura.lerp(a, b, w)
	return a * (1 - w) + b * w
end

function creatura.get_yaw_to_pos(pos1, pos2)
	local p1_x, p1_z = pos1.x, pos1.z
	local p2_x, p2_z = pos2.x, pos2.z

	local x = p2_x - p1_x
	local z = p2_z - p1_z
	return math.atan2(z, x) - pi / 2
end

function creatura.is_value_in_table(tbl, val)
	for _, v in pairs(tbl) do
		if v == val then
			return true
		end
	end
	return false
end

function creatura.get_squared_dist(pos1, pos2)
    local dx = pos1.x - pos2.x
    local dy = pos1.y - pos2.y
    local dz = pos1.z - pos2.z

    return dx * dx + dy * dy + dz * dz
end

-- Debugging

function creatura.particle(pos, time, tex)
	minetest.add_particle({
		pos = pos,
		texture = tex or "creatura_particle_red.png",
		expirationtime = time or 1,
		glow = 16,
		size = 6
	})
end

--
--
--
--
--

function creatura.get_neighbor_grid(pos)
	local p1 = vector.new(pos)
	return {
		p1:add({x = 1, y = 0, z = 0}),
		p1:add({x = 1, y = 0, z = 1}),
		p1:add({x = 0, y = 0, z = 1}),
		p1:add({x = -1, y = 0, z = 1}),
		p1:add({x = -1, y = 0, z = 0}),
		p1:add({x = -1, y = 0, z = -1}),
		p1:add({x = 0, y = 0, z = -1}),
		p1:add({x = 1, y = 0, z = -1})
	}
end

function creatura.get_neighbor_grid_3d(pos)
	local p1 = vector.new(pos)
	return {
		p1,
		p1:add({x = 1, y = 0, z = 0}),
		p1:add({x = 1, y = 0, z = 1}),
		p1:add({x = 0, y = 0, z = 1}),
		p1:add({x = -1, y = 0, z = 1}),
		p1:add({x = -1, y = 0, z = 0}),
		p1:add({x = -1, y = 0, z = -1}),
		p1:add({x = 0, y = 0, z = -1}),
		p1:add({x = 1, y = 0, z = -1})
	}
end

function creatura.get_wander_pos(pos, range)
	local random_offset = {
		x = (random() * 2-1) * range,
		y = 0,
		z = (random() * 2-1) * range
	}
	local wander_pos = vector.add(pos, random_offset)

	if creatura.is_walkable(wander_pos) then
		vec_offset(wander_pos, 0, 1, 0)
	elseif not creatura.is_on_ground(wander_pos) then
		vec_offset(wander_pos, 0, -1, 0)
	end

	if creatura.is_walkable(wander_pos)
	or not creatura.is_on_ground(wander_pos) then
		return pos
	end

	return wander_pos
end

function creatura.get_hitbox_edge(yaw, width)
	local dir_x = -math.sin(yaw)
	local dir_z = math.cos(yaw)

	local scale_x = width / math.abs(dir_x)
	local scale_z = width / math.abs(dir_z)
	local scale = math.min(scale_x, scale_z)

	return {
		x = dir_x * scale,
		y = 0,
		z = dir_z * scale
	}
end

local default_node_def = {walkable = true} -- both ignore and unknown nodes are walkable

function creatura.get_node_def(node) -- Node can be name or pos
	if type(node) == "table" then
		node = core.get_node_or_nil(node)
		if not node or not node.name then return default_node_def end
		node = node.name
	end
	local def = minetest.registered_nodes[node] or default_node_def
	if def.walkable
	and creatura.get_node_height_from_def(node) < 0.26 then
		def.walkable = false -- workaround for nodes like snow
	end
	return def
end

function creatura.get_node_height_from_def(name)
	local def = minetest.registered_nodes[name] or default_node_def
	if not def then return 0.5 end
	if def.walkable then
		if def.drawtype == "nodebox" then
			if def.node_box
			and def.node_box.type == "fixed" then
				if type(def.node_box.fixed[1]) == "number" then
					return 0.5 + def.node_box.fixed[5]
				elseif type(def.node_box.fixed[1]) == "table" then
					return 0.5 + def.node_box.fixed[1][5]
				else
					return 1
				end
			else
				return 1
			end
		else
			return 1
		end
	else
		return 1
	end
end

creatura.pathfinding_ignore = {
	["default:snow"] = true
}

function creatura.is_walkable(pos)
	local node = minetest.get_node_or_nil(pos)
	if not node or not node.name then return false end
	if creatura.pathfinding_ignore[node.name] then return false end
	if minetest.registered_nodes[node.name].walkable then
		return creatura.get_node_height_from_def(node.name) > 0.125
	end
end

function creatura.is_liquid(pos)
	local node = minetest.get_node_or_nil(pos)
	if not node or not node.name then return false end
	if core.get_item_group(node.name, "liquid") > 0 then
		return true
	end
end

function creatura.get_obstacles(pos1, pos2)
	local raycast = minetest.raycast(pos1, pos2, false, false)

	for pointed_thing in raycast do
		if pointed_thing.type == "node"
		and creatura.is_walkable(pointed_thing.under) then
			return vector.round(pointed_thing.under), vector.distance(pos1, pointed_thing.intersection_point)
		end
	end

	return nil, vector.distance(pos1, pos2)
end

function creatura.line_of_sight(pos1, pos2, liquids)
	local raycast = minetest.raycast(pos1, pos2, false, liquids)

	for pointed_thing in raycast do
		if pointed_thing.type == "node"
		and creatura.is_walkable(pointed_thing.under) then
			return false, vector.distance(pos1, pointed_thing.intersection_point)
		end
	end

	return true, vector.distance(pos1, pos2)
end

function creatura.is_on_ground(pos)
	local ground = {
		x = pos.x,
		y = pos.y - 1,
		z = pos.z
	}
	if creatura.get_node_def(ground).walkable then
		return true
	end
	return false
end

-- Check for dangerous fall

function creatura.is_pos_above_fall(pos, max_fall)
	local fall_check = core.line_of_sight(pos, vector.offset(pos, 0, -max_fall, 0))
	if fall_check then return true end
end

-- Check for enough clear space to fit a collisionbox

local function is_node_traversable(pos)
    local node = core.get_node_or_nil(pos)
    if not node or node.name == "ignore" then return false end

    local def = core.registered_nodes[node.name]
    if not def or def.walkable then return false end -- liquidtype ~= "none" to check for water?

    return true
end

function creatura.is_pos_empty(pos, box, liquid)
	--[[if math.abs(box[1]) + math.abs(box[4]) <= 1
	and box[5] <= 1 then -- only check 1 node if box doesn't exceed 1 node in size
		return is_node_traversable(pos)
	end]]

	local min_p = {
		x = pos.x + (box[1] + 0.01),
		y = pos.y + (box[2] + 0.01),
		z = pos.z + (box[3] + 0.01)
	}

	local max_p = {
		x = pos.x + (box[4] - 0.01),
		y = pos.y + (box[5] - 0.01),
		z = pos.z + (box[6] - 0.01)
	}

	for x = min_p.x, max_p.x do
		for y = min_p.y, max_p.y do
			for z = min_p.z, max_p.z do
				if (liquid and not creatura.is_liquid(vector.new(x, y, z)))
				or not is_node_traversable(vector.new(x, y, z)) then
					--creatura.particle(vector.new(x, y, z))
					return false
				end
			end
		end
	end

	return true
end

function creatura.is_pos_empty_in_liquid(pos, box)
	--[[if math.abs(box[1]) + math.abs(box[4]) <= 1
	and box[5] <= 1 then -- only check 1 node if box doesn't exceed 1 node in size
		return is_node_traversable(pos)
	end]]

	local min_p = {
		x = math.floor(pos.x + 0.5 + box[1]),
		y = math.floor(pos.y + 0.5 + box[2]),
		z = math.floor(pos.z + 0.5 + box[3])
	}

	local max_p = {
		x = math.floor(pos.x + 0.5 + box[4]),
		y = math.floor(pos.y + 0.5 + box[5]),
		z = math.floor(pos.z + 0.5 + box[6])
	}

	for x = min_p.x, max_p.x do
		for y = min_p.y, max_p.y do
			for z = min_p.z, max_p.z do
				if not creatura.is_liquid(vector.new(x, y, z)) then
					return false
				end
			end
		end
	end

	return true
end

function creatura.translate_to_position(pos)
	if type(pos) == "userdata" then
		if pos:is_valid() then return pos:get_pos() end
		return vector.zero()
	end

	return pos
end

-- DEPRECATED

function creatura.fast_ray_sight(pos1, pos2, water)
	local ray = minetest.raycast(pos1, pos2, false, water or false)
	local pointed_thing = ray:next()
	while pointed_thing do
		if pointed_thing.type == "node"
		and creatura.get_node_def(pointed_thing.under).walkable then
			return false, vec_dist(pos1, pointed_thing.intersection_point), pointed_thing.ref, pointed_thing.intersection_point
		end
		pointed_thing = ray:next()
	end
	return true, vec_dist(pos1, pos2), false, pos2
end

local fast_ray_sight = creatura.fast_ray_sight

function creatura.sensor_floor(self, range, water)
	local pos = self.object:get_pos()
	local pos2 = vec_raise(pos, -range)
	local _, dist, node = fast_ray_sight(pos, pos2, water or false)
	return dist, node
end

function creatura.sensor_ceil(self, range, water)
	local pos = vec_raise(self.object:get_pos(), self.height)
	local pos2 = vec_raise(pos, range)
	local _, dist, node = fast_ray_sight(pos, pos2, water or false)
	return dist, node
end

local get_node_def = creatura.get_node_def

function creatura.get_ground_level(pos, range)
	range = range or 2
	local above = vector.round(pos)
	local under = {x = above.x, y = above.y - 1, z = above.z}
	if not get_node_def(above).walkable and get_node_def(under).walkable then return above end
	if get_node_def(above).walkable then
		for _ = 1, range do
			under = above
			above = {x = above.x, y = above.y + 1, z = above.z}
			if not get_node_def(above).walkable and get_node_def(under).walkable then return above end
		end
	end
	if not get_node_def(under).walkable then
		for _ = 1, range do
			above = under
			under = {x = under.x, y = under.y - 1, z = under.z}
			if not get_node_def(above).walkable and get_node_def(under).walkable then return above end
		end
	end
	return above
end
