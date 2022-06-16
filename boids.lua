-----------
-- Boids --
-----------

local random = math.random

local function average(tbl)
	local sum = 0
	for _,v in pairs(tbl) do -- Get the sum of all numbers in t
	  sum = sum + v
	end
	return sum / #tbl
end

local function average_angle(tbl)
	local sum_sin, sum_cos = 0, 0
	for _, v in pairs(tbl) do
		sum_sin = sum_sin + math.sin(v)
		sum_cos = sum_cos + math.cos(v)
	end
	return math.atan2(sum_sin, sum_cos)
end

local vec_dist = vector.distance
local vec_dir = vector.direction
local vec_add = vector.add
local vec_normal = vector.normalize
local vec_divide = vector.divide

local function get_average_pos(vectors)
	local sum = {x = 0, y = 0, z = 0}
	for _, vec in pairs(vectors) do sum = vec_add(sum, vec) end
	return vec_divide(sum, #vectors)
end

local function dist_2d(pos1, pos2)
	local a = vector.new(
		pos1.x,
		0,
		pos1.z
	)
	local b = vector.new(
		pos2.x,
		0,
		pos2.z
	)
	return vec_dist(a, b)
end

local yaw2dir = minetest.yaw_to_dir
local dir2yaw = minetest.dir_to_yaw

-- Get Boid Members --

-- This function scans within
-- a set radius for potential
-- boid members, and assigns
-- a leader. A new leader
-- is only assigned every 12
-- seconds or if a new mob
-- is in the boid.

function creatura.get_boid_members(pos, radius, name)
	local objects = minetest.get_objects_inside_radius(pos, radius)
	if #objects < 2 then return {} end
	local members = {}
	local max_boid = minetest.registered_entities[name].max_boids or 7
	for i = 1, #objects do
		if #members > max_boid then break end
		local object = objects[i]
		if object:get_luaentity()
		and object:get_luaentity().name == name then
			object:get_luaentity().boid_heading = math.rad(random(360))
			table.insert(members, object)
		end
	end
	return members
end

-- Calculate Boid angles and offsets.

function creatura.get_boid_angle(self, _boids, range)
	local pos = self.object:get_pos()
	local boids = _boids or creatura.get_boid_members(pos, range or 4, self.name)
	if #boids < 3 then return end
	local yaw = self.object:get_yaw()
	local lift = self.object:get_velocity().y
	-- Add Boid data to tables
	local closest_pos
	local positions = {}
	local angles = {}
	local lifts = {}
	for i = 1, #boids do
		local boid = boids[i]
		if boid:get_pos() then
			local boid_pos = boid:get_pos()
			table.insert(positions, boid_pos)
			if boid ~= self.object then
				table.insert(lifts, vec_normal(boid:get_velocity()).y)
				table.insert(angles, boid:get_yaw())
				if not closest_pos
				or vec_dist(pos, boid_pos) < vec_dist(pos, closest_pos) then
					closest_pos = boid_pos
				end
			end
		end
	end
	if #positions < 3 then return end
	local center = get_average_pos(positions)
	local dir2closest = vec_dir(pos, closest_pos)
	-- Calculate Parameters
	local alignment = average_angle(angles)
	center = vec_add(center, yaw2dir(alignment))
	local dir2center = vec_dir(pos, center)
	local seperation = yaw + -(dir2yaw(dir2closest) - yaw)
	local cohesion = dir2yaw(dir2center)
	local params = {alignment}
	if self.boid_heading then
		table.insert(params, yaw + self.boid_heading)
	end
	if dist_2d(pos, closest_pos) < (self.boid_seperation or self.width * 3) then
		table.insert(params, seperation)
	elseif dist_2d(pos, center) > (#boids * 0.33) * (self.boid_seperation or self.width * 3) then
		table.insert(params, cohesion)
	end
	-- Vertical Params
	local vert_alignment = average(lifts)
	local vert_seperation = (self.speed or 2) * -dir2closest.y
	local vert_cohesion = (self.speed or 2) * dir2center.y
	local vert_params = {vert_alignment}
	if math.abs(pos.y - closest_pos.y) < (self.boid_seperation or self.width * 3) then
		table.insert(vert_params, vert_seperation)
	elseif math.abs(pos.y - closest_pos.y) > 1.5 * (self.boid_seperation or self.width * 3) then
		table.insert(vert_params, vert_cohesion + (lift - vert_cohesion) * 0.1)
	end
	self.boid_heading = nil
	return average_angle(params), average_angle(vert_params)
end