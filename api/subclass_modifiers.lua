----------------------------
-- Sub-class Modifiers --
----------------------------

-- Math

local function radians_difference_abs(a, b)
	return math.abs(math.atan2(math.sin(b - a), math.cos(b - a)))
end

-- Path Follower

local neighbors = {
	{x = 1, y = 0, z = 0},
	{x = 1, y = 0, z = 1},
	{x = 0, y = 0, z = 1},
	{x = -1, y = 0, z = 1},
	{x = -1, y = 0, z = 0},
	{x = -1, y = 0, z = -1},
	{x = 0, y = 0, z = -1},
	{x = 1, y = 0, z = -1}
}

local function neighbor_shift(neighbor, shift)
	return (8 + neighbor + shift - 1) % 8 + 1
end

function creatura.get_next_step(self)
	local target_position = self.target_pos
	if not target_position or not target_position.x then return end

	local parent_entity = self:parent_entity()
	local pos = vector.round(self.current_pos)
	pos.y = pos.y - 0.49

	local dir_to_target = vector.normalize(vector.direction(pos, target_position))
	dir_to_target.y = 0

	local current_neighbor_index = 1
	local current_dot_score = -2

	-- Find which neighbor is pointing closest to our target position
	for index, neighbor in ipairs(neighbors) do
		local dot = vector.dot(dir_to_target, vector.normalize(neighbor))
		if dot > current_dot_score then
			current_dot_score = dot
			current_neighbor_index = index
		end
	end

	-- Progressively fan out until a suitable direction is found
	local check_sequence = {0, -1, 1, -2, 2, -3, 3}

	for _, shift in ipairs(check_sequence) do
		local check_index = neighbor_shift(current_neighbor_index, shift)
		local check_offset = neighbors[check_index]
		local check_pos = vector.add(pos, check_offset)
		local is_diagonal = check_offset.x ~= 0 and check_offset.z ~= 0

		if parent_entity:is_pos_safe(check_pos)
		and (not is_diagonal or creatura.line_of_sight(pos, check_pos)) then
			return check_pos
		end
	end

	return self.current_pos
end

function creatura.get_flight_step(self)
	local target_pos = self.target_pos
	if not target_pos or not target_pos.x then return end

	local pos = self:get_parent_attribute("pos")
	local box = self:get_parent_attribute("collisionbox")
	local min_x = math.floor(box[1] - 0.5)
	local min_y = math.floor(box[2] - 0.5)
	local min_z = math.floor(box[3] - 0.5)
	local max_x = math.ceil(box[4] + 0.5)
	local max_y = math.ceil(box[5] + 0.5)
	local max_z = math.ceil(box[6] + 0.5)

	-- Align X/Z to global grid. Set Y level to the floor.
	local pos_at_floor = {
		x = math.floor(pos.x + 0.5),
		y = math.floor(pos.y + 0.5) - 0.49,
		z = math.floor(pos.z + 0.5)
	}

	local dir = vector.normalize(vector.direction(pos_at_floor, target_pos))

	local avoidance_i = 0
	local avoidance_force = {x = 0, y = 0, z = 0}

	for x = pos_at_floor.x + min_x, pos_at_floor.x + max_x do
		for y = pos_at_floor.y + min_y, pos_at_floor.y + max_y do
			for z = pos_at_floor.z + min_z, pos_at_floor.z + max_z do
				if not (x == pos_at_floor.x and y == pos_at_floor.y and z == pos_at_floor.z) then -- Skip center node
					local check_pos = {x=x,y=y,z=z}
					local check_offset = vector.normalize(vector.direction(pos_at_floor, check_pos))
					if creatura.is_walkable(check_pos) then
						avoidance_i = avoidance_i + 1
						avoidance_force = vector.subtract(avoidance_force, check_offset)
					else
						local dot = vector.dot(dir, check_offset)

						if dot > 0 then
							avoidance_i = avoidance_i + 1
							local weighted_pull = vector.multiply(check_offset, dot * 2)
							avoidance_force = vector.add(avoidance_force, weighted_pull)
						end
					end
					--creatura.particle(check_pos, 0.5, "creatura_particle_red.png")
				end
			end
		end
	end

	avoidance_force = vector.divide(avoidance_force, avoidance_i)

	local output = vector.add(pos_at_floor, vector.multiply(avoidance_force, 2))
	--creatura.particle(output, 1, "creatura_particle_green.png")
	return output
end

function creatura.get_swim_step(self)
	local target_pos = self.target_pos
	if not target_pos or not target_pos.x then return end

	local pos = self:get_parent_attribute("pos")
	local box = self:get_parent_attribute("collisionbox")
	local min_x = math.floor(box[1] - 0.5)
	local min_y = math.floor(box[2] - 0.5)
	local min_z = math.floor(box[3] - 0.5)
	local max_x = math.ceil(box[4] + 0.5)
	local max_y = math.ceil(box[5] + 0.5)
	local max_z = math.ceil(box[6] + 0.5)

	-- Align X/Z to global grid. Set Y level to the floor.
	local pos_at_floor = {
		x = math.floor(pos.x + 0.5),
		y = math.floor(pos.y + 0.5) - 0.49,
		z = math.floor(pos.z + 0.5)
	}

	local dir = vector.normalize(vector.direction(pos_at_floor, target_pos))

	local avoidance_i = 0
	local avoidance_force = {x = 0, y = 0, z = 0}

	for x = pos_at_floor.x + min_x, pos_at_floor.x + max_x do
		for y = pos_at_floor.y + min_y, pos_at_floor.y + max_y do
			for z = pos_at_floor.z + min_z, pos_at_floor.z + max_z do
				if not (x == pos_at_floor.x and y == pos_at_floor.y and z == pos_at_floor.z) then -- Skip center node
					local check_pos = {x=x,y=y,z=z}
					local check_offset = vector.normalize(vector.direction(pos_at_floor, check_pos))
					if not creatura.is_liquid(check_pos) then
						avoidance_i = avoidance_i + 1
						avoidance_force = vector.subtract(avoidance_force, check_offset)
					else
						local dot = vector.dot(dir, check_offset)

						if dot > 0 then
							avoidance_i = avoidance_i + 1
							local weighted_pull = vector.multiply(check_offset, dot * 2)
							avoidance_force = vector.add(avoidance_force, weighted_pull)
						end
					end
					--creatura.particle(check_pos, 0.5, "creatura_particle_red.png")
				end
			end
		end
	end

	avoidance_force = vector.divide(avoidance_force, avoidance_i)

	local output = vector.add(pos_at_floor, vector.multiply(avoidance_force, 2))
	--creatura.particle(output, 1, "creatura_particle_green.png")
	return output
end

-- Motion Drivers for Movement Controller

creatura.register_motion_driver("creatura:default_walk_driver", {
	calculate_yaw = function(self)
		if not self.target_pos then return end

		local pos = self:get_parent_attribute("pos")
		if not pos then return end

		local dir = vector.direction(pos, self.target_pos)
		return math.atan2(-dir.x, dir.z)
	end,

	calculate_velocity = function(self, entity)
		if not self.target_pos then return end

		local pos = self:get_parent_attribute("pos")
		local vel = self:get_parent_attribute("vel")
		local yaw = self:get_parent_attribute("yaw")

		if not pos or not vel or not yaw then return end

		local target_dir = vector.direction(pos, self.target_pos)
		local target_yaw = math.atan2(-target_dir.x, target_dir.z)

		local yaw_diff = math.max(0, radians_difference_abs(yaw, target_yaw) - (entity.turn_rate * entity.dtime))
		local speed_mod = math.max(0.3, math.cos(yaw_diff))

		return {
			x = -math.sin(yaw) * self.speed * speed_mod,
			y = vel.y,
			z = math.cos(yaw) * self.speed * speed_mod
		}
	end
})

creatura.register_motion_driver("creatura:default_flight_driver", {
	calculate_yaw = function(self)
		if not self.target_pos then return end

		local pos = self:get_parent_attribute("pos")
		if not pos then return end

		local dir = vector.direction(pos, self.target_pos)
		return math.atan2(-dir.x, dir.z)
	end,

	calculate_velocity = function(self, entity)
		if not self.target_pos then return end

		local pos = self:get_parent_attribute("pos")
		local vel = self:get_parent_attribute("vel")
		local yaw = self:get_parent_attribute("yaw")

		if not pos or not vel or not yaw then return end

		local speed = self:get_parent_attribute("speed")
		local in_liquid = self:get_parent_attribute("in_liquid")

		local target_dir = vector.direction(pos, self.target_pos)
		local target_yaw = math.atan2(-target_dir.x, target_dir.z)

		if in_liquid then
			entity.physics_controller:enable_gravity()
			return {
				x = target_dir.x * speed / 2,
				y = 3,
				z = target_dir.z * speed / 2
			}
		else
			entity.physics_controller:disable_gravity()
		end

		local yaw_diff = math.max(0, radians_difference_abs(yaw, target_yaw) - (entity.turn_rate * entity.dtime))
		local speed_mod = math.max(0.3, math.cos(yaw_diff))

		return {
			x = -math.sin(yaw) * speed * speed_mod,
			y = target_dir.y * speed * speed_mod,
			z = math.cos(yaw) * speed * speed_mod
		}
	end
})

creatura.register_motion_driver("creatura:default_swim_driver", {
	calculate_yaw = function(self)
		if not self.target_pos then return end

		local pos = self:get_parent_attribute("pos")
		if not pos then return end

		local dir = vector.direction(pos, self.target_pos)
		return math.atan2(-dir.x, dir.z)
	end,

	calculate_velocity = function(self, entity)
		if not self.target_pos then return end

		local pos = self:get_parent_attribute("pos")
		local vel = self:get_parent_attribute("vel")
		local yaw = self:get_parent_attribute("yaw")

		if not pos or not vel or not yaw then return end

		local speed = self:get_parent_attribute("speed")
		local in_liquid = self:get_parent_attribute("in_liquid")

		local target_dir = vector.direction(pos, self.target_pos)
		local target_yaw = math.atan2(-target_dir.x, target_dir.z)

		if in_liquid then
			entity.physics_controller:disable_gravity()
		else
			entity.physics_controller:enable_gravity()
			return {
				x = target_dir.x * speed / 2,
				y = 3,
				z = target_dir.z * speed / 2
			}
		end

		local yaw_diff = math.max(0, radians_difference_abs(yaw, target_yaw) - (entity.turn_rate * entity.dtime))
		local speed_mod = math.max(0.6, math.cos(yaw_diff))

		return creatura.vector_lerp(vel, {
			x = -math.sin(yaw) * speed * speed_mod,
			y = target_dir.y * speed * speed_mod,
			z = math.cos(yaw) * speed * speed_mod
		}, 0.15)
	end
})
