local navigator = {}
navigator.__index = navigator

-- Create new instance
function navigator:new(parent, spec)
	local parent_entity = parent and parent:get_luaentity()
	local pos = parent and parent:get_pos()

	local new_navigator = spec or {}

	-- No override
	new_navigator.parent = parent
	new_navigator.speed = parent_entity.speed
	new_navigator.path = {}
	new_navigator.stuck_tick = 0
	new_navigator.stuck_timeout = 300
	new_navigator.old_pos = pos
	new_navigator.current_pos = pos
	new_navigator.target_pos = {}
	new_navigator.use_pathfinding = false
	new_navigator.is_active = false

	return setmetatable(new_navigator, navigator)
end

-- Return parent objects luaentity
function navigator:parent_entity()
	return self.parent and self.parent:get_luaentity()
end

-- Calculate distance to consider a mob as "arrived" at it's destination
function navigator:get_arrival_threshold()
	local parent_entity = self:parent_entity()
	return (parent_entity.width > 0.75 and parent_entity.width / 2.0) or (0.75 - parent_entity.width / 2.0)
end

-- Specify a pathfinder to use
function navigator:set_pathfinder(pathfinder, def)
	self.pathfinder = pathfinder:new(self.parent, def)
end

-- Enable use of pathfinding
function navigator:enable_pathfinding()
	self.use_pathfinding = true
end

-- Disable use of pathfinding
function navigator:disable_pathfinding()
	self.use_pathfinding = false
end

-- Set desired position and speed
function navigator:set_target(target, speed)
	self.target_pos = target
	self.speed = speed or self:parent_entity().speed
	self.is_active = true

	if self.pathfinder then
		self.pathfinder:set_target(target)
	end
end

-- Stop moving and pathfinding to desired position
function navigator:stop()
	self.path = {}
	self.speed = self:parent_entity().speed
	self.target_pos = {}
	self.is_active = false

	if self.pathfinder then self.pathfinder:stop() end
	self:parent_entity().movement_controller:stop()
end

-- Update pathfinding and instructions to movement controller on every server-step
function navigator:update()
	local parent = self.parent
	local pos = parent and parent:get_pos()
	if not pos then return end

	self.old_pos = table.copy(self.current_pos)
	self.current_pos = pos

	if not self.target_pos.x then
		self.is_active = false
		return
	end

	local parent_entity = self:parent_entity()

	-- Pathfinding
	local pathfinder = self.use_pathfinding and self.pathfinder
	if pathfinder then
		pathfinder:update()
		local path = pathfinder:get_path()
		if path then
			self.path = path
		end
	end

	-- Recalculate if we've reached the end of the path
	if #self.path < 1 then
		self:get_next_pos(self.target_pos)
	end

	-- Move to next position
	if self.path[1] then
		local movement_controller = self:parent_entity().movement_controller

		movement_controller:set_target(self.path[1], self.speed)
		self.is_active = true
	else
		return
	end

	-- Advance through current path
	if parent_entity:get_chebyshev_distance(self.target_pos) < 0.5
	or parent_entity:has_reached_or_passed(self.target_pos) then
		self:stop()
	elseif parent_entity:get_chebyshev_distance(self.path[1]) < 0.5
	or parent_entity:has_reached_or_passed(self.path[1]) then
		table.remove(self.path, 1)
	end
end

-- Create a 3x3 grid around specified position
function navigator:get_neighbor_grid(pos)
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

-- Checks for clearance at a given angle relative to the specified position
function navigator:check_angle_for_clearance(yaw, pos)
	local parent_entity = self:parent_entity()
	if not parent_entity then return end

	local dir_x = -math.sin(yaw) * 1.2
	local dir_z = math.cos(yaw) * 1.2

	local current_pos = vector.add(pos or self.current_pos, {x = dir_x, y = 0, z = dir_z})
	local current_height = 0
	while current_height <= parent_entity.stepheight do
		if creatura.is_pos_empty(current_pos, parent_entity.collisionbox) then
			if creatura.is_pos_above_fall(current_pos, parent_entity.max_fall) then
				return nil
			end
			return current_pos
		end

		current_height = current_height + 1
		current_pos.y = current_pos.y + 1
	end

	return nil
end

-- Finds the ideal position to reach specified position while avoiding obstacles
-- This does not have long-term context and can't consider obstacles far away
-- Proper pathfinding must be used to avoid this.
function navigator:get_next_pos(target_pos)
	-- Check forward for clearance first
	local target_yaw = creatura.get_yaw_to_pos(self.current_pos, target_pos)
	local next_pos = self:check_angle_for_clearance(target_yaw)
	if next_pos then
		self.path = {next_pos}
		return next_pos
	end

	-- If forward check fails, incrementally check in left and right directions
	local angle_gap = math.pi / 3 -- 60 degrees
	for i = 1, 2 do -- Check 2 stages in each direction
		local left_pos = self:check_angle_for_clearance(target_yaw + angle_gap * i)
		if left_pos then
			self.path = {left_pos}
			return left_pos
		end

		local right_pos = self:check_angle_for_clearance(target_yaw - angle_gap * i)
		if right_pos then
			self.path = {right_pos}
			return right_pos
		end
	end

	-- If nothing is found, backtrack
	local backtrack_pos = vector.subtract(self.current_pos, {x = -math.sin(target_yaw), y = 0, z = math.cos(target_yaw)})
	self.path = {backtrack_pos}
	return backtrack_pos
end

-- Same as above, but can move vertically
function navigator:get_next_pos_3d(target_pos)
	local lowest_cost
	local closest_pos
	for i, pos1 in ipairs(self:get_neighbor_grid(self.current_pos)) do
		for y = -1, 1 do
			local is_diagonal = math.floor(i) == i
			local npos = {x = pos1.x, y = pos1.y + y, z = pos1.z}
			if (not closest_pos
			or vector.distance(npos, target_pos) < lowest_cost)
			and creatura.is_pos_empty(npos, self:parent_entity().collisionbox)
			and (not is_diagonal or creatura.line_of_sight(self.current_pos, npos)) then
				lowest_cost = vector.distance(npos, target_pos)
				closest_pos = npos
			end
		end
	end

	local backtrack_pos = vector.subtract(self.current_pos, vector.direction(self.current_pos, target_pos))
	self.path[1] = closest_pos or backtrack_pos
	return closest_pos or backtrack_pos
end

-- Same as above, but only works in water
function navigator:get_next_pos_in_liquid(target_pos)
	local lowest_cost
	local closest_pos
	for i, pos1 in ipairs(self:get_neighbor_grid(self.current_pos)) do
		for y = -1, 1 do
			local is_diagonal = math.floor(i) == i
			local npos = {x = pos1.x, y = pos1.y + y, z = pos1.z}
			if (not closest_pos
			or vector.distance(npos, target_pos) < lowest_cost)
			and creatura.is_pos_empty_in_liquid(npos, self:parent_entity().collisionbox)
			and (not is_diagonal or creatura.line_of_sight(self.current_pos, npos)) then
				lowest_cost = vector.distance(npos, target_pos)
				closest_pos = npos
			end
		end
	end

	local backtrack_pos = vector.subtract(self.current_pos, vector.direction(self.current_pos, target_pos))
	self.path[1] = closest_pos or backtrack_pos
	return closest_pos or backtrack_pos
end

return navigator
