-- Path Follower

local path_follower = {}
path_follower.__index = path_follower

local a_star_pathfinder = creatura.a_star_pathfinder

-- Create new instance
function path_follower:new(parent, spec)
	local parent_entity = parent and parent:get_luaentity()
	local pos = parent and parent:get_pos()

	local proto = spec or {}

	proto.parent = parent
	proto.current_pos = pos
	proto.target = false
	proto.target_pos = {}
	proto.path = {}
	proto.stuck_timer = 2
	proto.speed = parent_entity.speed

	proto.navigation_type = "ground"
	proto.pathfinder = a_star_pathfinder:new(parent)
	proto.get_step = path_follower.get_ground_step

	return setmetatable(proto, path_follower)
end

-- Utils

function path_follower:parent_entity()
	return self.parent and self.parent:get_luaentity()
end

function path_follower:get_squared_dist(pos1, pos2)
	local dx = pos1.x - pos2.x
	local dy = pos1.y - pos2.y
	local dz = pos1.z - pos2.z

	return dx * dx + dy * dy + dz * dz
end

-- Set navigation state
function path_follower:set_state(state)
	local movement_control = self:parent_entity().movement_controller

	if not state
	or type(state) ~= "string"
	or state == "ground" then
		self.navigation_type = "ground"
		movement_control.movement_type = "ground"
		self.pathfinder = a_star_pathfinder:new(self.parent)
		self.get_step = path_follower.get_ground_step
		return
	end

	if state == "fly" then
		self.navigation_type = "fly"
		movement_control.movement_type = "fly"
		self.pathfinder = a_star_pathfinder:new(self.parent, {
			get_neighbors = a_star_pathfinder.get_neighbors_3d,
			get_neighbor_grid = a_star_pathfinder.get_neighbor_grid_3d
		})
		self.get_step = path_follower.get_flight_step
		return
	end

	if state == "swim" then
		self.navigation_type = "swim"
		movement_control.movement_type = "swim"
		self.pathfinder = a_star_pathfinder:new(self.parent, {
			get_neighbors = a_star_pathfinder.get_neighbors_3d,
			get_neighbor_grid = a_star_pathfinder.get_neighbor_grid_3d
		})
		self.get_step = path_follower.get_swim_step
		return
	end
end

-- Set target
function path_follower:set_target(target, params)
	if not target then self:stop() return end
	if not params then params = {} end

	if type(target) == "userdata"
	and target:is_valid() then
		self.target = target
		self.target_pos = target:get_pos()
	elseif type(target) == "table"
	and target.x
	and target.y
	and target.z then
		self.target = false
		self.target_pos = target
	end

	self.is_active = true
	self.stuck_timer = 2
	self.speed = params.speed or self:parent_entity().speed
	--self.timeout = params.timeout or 10
	return true
end

-- Set target and use pathfinding
function path_follower:set_path_target(target, params, ...)
	if not self:set_target(target, params, ...) then return end

	local pathfinder = self.pathfinder
	if not pathfinder then return end

	pathfinder:set_target(self.target_pos, ...)
end

-- Stuck detection

function path_follower:on_stuck()
	if self.path[1] then
		local nudge_step = self:get_step(self.target_pos) -- This can sometimes help the mob wrap around corners

		if nudge_step then
			self.path[1] = nudge_step
		else
			self.path = {}
		end
	end
end

function path_follower:tick_stuck_timer(dtime)
	local stuck_timer = self.stuck_timer

	if stuck_timer <= 0 then
		stuck_timer = 2

		self:on_stuck()
	elseif dtime then
		stuck_timer = stuck_timer - dtime
	else
		stuck_timer = 2 -- Reset timer if no dtime is given
	end

	self.stuck_timer = stuck_timer
end

-- Path following

function path_follower:get_arrival_threshold(dtime)
	return math.max(0.4, vector.length(self.parent:get_velocity()) * dtime * 1.5)
end

function path_follower:follow_path(dtime)
	if not self.path or #self.path < 1 then return end

	local pos = self.current_pos
	local next_pos = self.path[1]

	local to_target = next_pos and vector.direction(pos, next_pos)
	local dot = vector.dot(to_target, vector.normalize(self.parent:get_velocity()))

	if self:get_squared_dist(pos, next_pos) < self:get_arrival_threshold(dtime)
	or dot < 0 then
		if #self.path > 1 then
			next_pos = self.path[2]
		end

		table.remove(self.path, 1)
		self:tick_stuck_timer() -- Reset stuck timer
	end

	local movement_controller = self:parent_entity().movement_controller
	movement_controller:set_target(next_pos, self.speed)
end

-- Update
function path_follower:update()
	local parent_entity = self:parent_entity()
	if not parent_entity then return end

	self.last_pos = table.copy(self.current_pos)
	self.current_pos = self.parent:get_pos()
	self.current_pos.y = self.current_pos.y + 0.01
	local dtime = parent_entity.dtime

	if self.target_pos and self.target_pos.x
	and self:get_squared_dist(self.current_pos, self.target_pos) < self:get_arrival_threshold(dtime) then
		self:stop()
		return
	end

	local pathfinder = self.pathfinder
	if pathfinder and pathfinder:update() then
		local new_path = pathfinder:get_path()
		if #new_path > 0 then
			self.path = new_path
		end
	end

	if #self.path == 0 then
		local fallback_step = self:get_step(self.parent, self.target_pos)
		if fallback_step then
			self.path = {fallback_step}
		end
	end

	if self.is_active
	and #self.path > 0 then
		self:follow_path(dtime)
		self:tick_stuck_timer(dtime)
	end
end

function path_follower:stop()
	local parent_entity = self:parent_entity()

	self.target = false
	self.target_pos = {}
	self.path = {}
	self.is_active = false
	self.stuck_timer = 2
	self.speed = parent_entity.speed

	if self.pathfinder and self.pathfinder.clear_path then
		self.pathfinder:clear_path()
	end

	parent_entity.movement_controller:stop()
end

--

local test_box = {-0.5, 0, -0.5, 0.5, 1, 0.5} -- For testing purposes, most mob hitboxes will be larger

-- Get next step
function path_follower:get_ground_step()
	if not self.target_pos or not self.target_pos.x then return end

	local pos = vector.new({
		x = math.floor(self.current_pos.x + 0.5),
		y = self.current_pos.y,
		z = math.floor(self.current_pos.z + 0.5)
	})
	local valid_steps = {}

	for _, pos1 in ipairs(creatura.get_neighbor_grid(pos)) do
		local dir_x = math.abs(pos1.x - pos.x)
		local dir_z = math.abs(pos1.z - pos.z)
		local is_diagonal = dir_x > 0.1 and dir_z > 0.1

		if creatura.is_pos_empty(pos1, test_box)
		and (not is_diagonal or creatura.line_of_sight(pos, pos1)) then
			valid_steps[#valid_steps + 1] = pos1
		elseif creatura.is_pos_empty(pos1:offset(0, 1, 0), test_box)
		and (not is_diagonal or creatura.line_of_sight(pos:offset(0, 1, 0), pos1:offset(0, 1, 0))) then
			table.insert(valid_steps, pos1:offset(0, 1, 0))
		elseif creatura.is_pos_empty(pos1:offset(0, -1, 0), test_box)
		and (not is_diagonal or creatura.line_of_sight(pos:offset(0, 1, 0), pos1:offset(0, -1, 0))) then
			table.insert(valid_steps, pos1:offset(0, -1, 0))
		end
	end

	local output = table.copy(self.target_pos)
	if #valid_steps < 1 then return output end

	local cost = math.huge
	for _, pos2 in ipairs(valid_steps) do
		if self:get_squared_dist(pos2, self.target_pos) < cost then
			cost = self:get_squared_dist(pos2, self.target_pos)
			output = pos2
		end
	end
	return output
end

-- Get next step on 3 axis'
function path_follower:get_flight_step()
	if not self.target_pos or not self.target_pos.x then return end

	local pos = vector.new({
		x = math.floor(self.current_pos.x + 0.5),
		y = self.current_pos.y,
		z = math.floor(self.current_pos.z + 0.5)
	})
	local valid_steps = {}

	for _, pos1 in ipairs(creatura.get_neighbor_grid_3d(pos)) do
		for y = -1, 1 do
			local dir_x = math.abs(pos1.x - pos.x)
			local dir_z = math.abs(pos1.z - pos.z)
			local is_diagonal = dir_x > 0.1 and dir_z > 0.1

			local npos = {x = pos1.x, y = pos1.y + y, z = pos1.z}
			if creatura.is_pos_empty(npos, test_box)
			and (not is_diagonal or creatura.line_of_sight(pos, npos)) then
				valid_steps[#valid_steps + 1] = npos
			end
		end
	end

	local output = table.copy(self.target_pos)
	if #valid_steps < 1 then return output end

	local cost = math.huge
	for _, pos2 in ipairs(valid_steps) do
		if self:get_squared_dist(pos2, self.target_pos) < cost then
			cost = self:get_squared_dist(pos2, self.target_pos)
			output = pos2
		end
	end

	return output
end


-- Get next step on 3 axis' while constrained to water
function path_follower:get_swim_step()
	if not self.target_pos or not self.target_pos.x then return end

	local pos = vector.new({
		x = math.floor(self.current_pos.x + 0.5),
		y = self.current_pos.y,
		z = math.floor(self.current_pos.z + 0.5)
	})
	local valid_steps = {}

	for _, pos1 in ipairs(creatura.get_neighbor_grid_3d(pos)) do
		for y = -1, 1 do
			local dir_x = math.abs(pos1.x - pos.x)
			local dir_z = math.abs(pos1.z - pos.z)
			local is_diagonal = dir_x > 0.1 and dir_z > 0.1

			local npos = {x = pos1.x, y = pos1.y + y, z = pos1.z}
			if creatura.is_pos_empty_in_liquid(npos, test_box)
			and (not is_diagonal or creatura.line_of_sight(pos, npos)) then
				valid_steps[#valid_steps + 1] = npos
			end
		end
	end

	local output = table.copy(self.target_pos)
	if #valid_steps < 1 then return output end

	local cost = math.huge
	for _, pos2 in ipairs(valid_steps) do
		if self:get_squared_dist(pos2, self.target_pos) < cost then
			cost = self:get_squared_dist(pos2, self.target_pos)
			output = pos2
		end
	end

	return output
end

return path_follower