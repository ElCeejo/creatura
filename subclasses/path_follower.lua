-- Path Follower

local path_follower = {}
path_follower.__index = path_follower

-- Create new instance

function path_follower:new(parent, spec)
	local parent_entity = parent and parent:get_luaentity()
	local pos = parent and parent:get_pos()

	local new_path_follower = spec or {}

	new_path_follower.parent = parent
	new_path_follower.current_pos = pos
	new_path_follower.target = false
	new_path_follower.target_pos = {}
	new_path_follower.path = {}
	new_path_follower.stuck_timer = 2
	new_path_follower.speed = parent_entity.speed

	return setmetatable(new_path_follower, path_follower)
end

-- Utils

function path_follower:parent_entity()
	return self.parent and self.parent:get_luaentity()
end

function path_follower:get_parent_attribute(attribute)
	if type("attribute") ~= "string" then return end

	local parent = self.parent
	if not parent:is_valid() then return end

	if attribute == "yaw" then return parent:get_yaw() end
	if attribute == "pos" then return parent:get_pos() end
	if attribute == "vel" then return parent:get_velocity() end
	if attribute == "accel" then return parent:get_acceleration() end

	local entity = parent and parent:get_luaentity()
	if not entity then return end

	return entity[attribute]
end

function path_follower:get_squared_dist(pos1, pos2)
	local dx = pos1.x - pos2.x
	local dy = pos1.y - pos2.y
	local dz = pos1.z - pos2.z

	if self:parent_entity().touching_ground and dy < 1 and dy > -1.5 then dy = 0 end

	return dx * dx + dy * dy + dz * dz
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
	self.stuck_timer = 0.5
	self.speed = params.speed or self:parent_entity().speed
	self.arrival_threshold = params.arrival_threshold or nil
	self.get_step = params.get_step or nil

	return true
end

-- Set target and use pathfinding
function path_follower:set_path_target(target, params, ...)
	if not self:set_target(target, params, ...) then return end

	self.pathfinder = creatura.find_path
end

-- Stuck detection
-- TODO: Make this actually work...

function path_follower:on_stuck()
	if self.path[1] then
		local nudge_step = self:get_step() -- This can sometimes help the mob wrap around corners

		if nudge_step then
			self.path[1] = nudge_step
		else
			self.path = {}
		end
	end

	--[[if self.path[1] then
		if not self.stuck_flag then
			local nudge_dir = vector.direction(self.current_pos, vector.round(self.path[1]))
			self.path[1] = vector.add(self.path[1], vector.multiply(nudge_dir, 0.5))
			self.stuck_flag = true
		else
			self.path = {}
			self.stuck_flag = nil
		end
	end]]
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

function path_follower:follow_path()
	if not self.path or #self.path < 1 then return end

	local pos = self.current_pos
	local next_pos = self.path[1]

	if self:parent_entity():has_reached_pos(next_pos) then
		if #self.path > 1 then
			next_pos = self.path[2]
		end

		table.remove(self.path, 1)

		if self:get_squared_dist(pos, self.last_pos) > 0.1 then
			self:tick_stuck_timer() -- Reset stuck timer
		end
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
	and self:parent_entity():has_reached_pos(self.target_pos) then
		self:stop()
		return
	end

	--[[if self.target_pos and self.target_pos.x then
		creatura.particle(self.target_pos)
	end]]

	local path = (self.pathfinder and self.pathfinder(self:parent_entity(), self.target_pos)) or {}
	if #path > 0 then
		self.path = path
	end

	if #self.path == 0 then
		local fallback_step = self:get_step()
		if fallback_step then
			--creatura.particle(fallback_step)
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

	self.get_step = nil

	parent_entity.movement_controller:stop()
end

-- Default Get Step

function path_follower:get_step()
	local target_pos = self.target_pos
	if not target_pos or not target_pos.x then return end

    local pos = vector.round(self.current_pos)
    pos.y = pos.y - 0.49

	-- Check forward direction first
	local target_dir = vector.direction(pos, target_pos):round()
	if self:get_parent_attribute("accel").y ~= 0 then target_dir.y = 0 end
	local target_step_pos = vector.add(pos, target_dir)

	return target_step_pos
end

return path_follower