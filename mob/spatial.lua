local mob_base = creatura.mob_base

local abs = math.abs
local floor = math.floor
local min = math.min
local max = math.max
local random = math.random
local sqrt = math.sqrt

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
						max_y = max_y + floor(self.jump_height)
					else
						return false
					end
				end

				current_y = current_y + 1
			end
		end
	end

	return true
end

local function can_small_hitbox_fit(self, target_pos)
	local pos = self.object:get_pos()
	if not pos then return end

	if not is_node_traversable(target_pos) then
		local jump_height = floor(self.jump_height)

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

function mob_base:is_pos_safe(pos)
	local box = self.collisionbox or {-0.5, 0, -0.5, 0.5, 1, 0.5}

	local space_check = can_large_hitbox_fit
	if abs(box[1]) + abs(box[2]) < 1 then
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

function mob_base:calculate_mob_collision()
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

function mob_base:get_chebyshev_distance(target)
	if not target then return end
	if type(target) == "userdata" then
		target = target:get_pos()
	end
	local pos = self.object:get_pos()

	return max(
		abs(pos.z - target.z),
		--abs(pos.y - target.y),
		abs(pos.x - target.x)
	)
end

function mob_base:get_distance(target)
	if target
	and type(target) == "userdata" then
		target = target:get_pos()
	end

	local pos = self.object:get_pos()
	if not target or not pos then return self.tracking_range + 1 end

	return vector.distance(self.object:get_pos(), target)
end

function mob_base:has_reached_or_passed(pos2)
	local pos = self.object:get_pos()
	local dir = vector.direction(pos, pos2)

	local to_dest = vector.normalize({
		x = pos2.x - pos.x,
		y = 0,
		z = pos2.z - pos.z
	})

	return (dir.x * to_dest.x + dir.z * to_dest.z) < 0
end

function mob_base:has_reached_pos(target_pos)
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
	local speed = sqrt((vel.x * vel.x) + (vel.z * vel.z))

	local dynamic_radius = min(0.4 + (speed * 0.15), 1.5)
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