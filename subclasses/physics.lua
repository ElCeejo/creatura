-------------
-- Physics --
-------------

local physics = {}
physics.__index = physics

-- Create new instance
function physics:initiate(entity)
	local new_controller = {
		entity = entity,
		gravity = -9.8,
		friction = 0.4,

		has_gravity = true,
		has_friction = true,
		is_flying = false,
		is_swimming = false
	}

	entity.physics = setmetatable(new_controller, self)
end

function physics:get_parent_attribute(attribute)
	if type("attribute") ~= "string" then return end

	local object = self.entity.object
	if not object:is_valid() then return end

	if attribute == "yaw" then return object:get_yaw() end
	if attribute == "pos" then return object:get_pos() end
	if attribute == "vel" then return object:get_velocity() end
	if attribute == "accel" then return object:get_acceleration() end

	return self.entity[attribute]
end

-- Gravity settings

function physics:set_flying(fly)
	if fly == false then
		self.is_flying = false
	else
		self.is_flying = true
		self.is_swimming = false
	end
end

function physics:set_swimming(swim)
	if swim == false then
		self.is_swimming = false
	else
		self.is_swimming = true
		self.is_flying = false
	end
end

-- Enable gravity and specifify force to be used (optional)
function physics:enable_gravity(gravity)
	self.has_gravity = true
	self.gravity = gravity or self.gravity
end

-- Disable gravity
function physics:disable_gravity()
	self.has_gravity = false
end

-- Floating Physics

function physics:calculate_bouyancy(acceleration, velocity, current_pos, current_node)	
	local visc = math.min(core.registered_nodes[current_node.name].liquid_viscosity, 7) + 1
	acceleration.y = -1.2 / visc
	
	-- Check higher portion of hitbox
	current_pos.y = current_pos.y + (self.entity.height * (self.entity.hitbox_submergence or 0.5))
	current_node = core.get_node(current_pos)
	
	local in_deep_water = core.get_item_group(current_node.name, "liquid") ~= 0
	if in_deep_water then
		local sink_rate = math.max(0, -velocity.y)
		acceleration.y = 2 + sink_rate * 3
	end

	return acceleration
end

-- Calculate physics every server-step
function physics:on_step(dtime)
	local accel = self.entity.object:get_acceleration()
	local vel = self.entity.object:get_velocity()

	accel.y = -9.81 -- Basic gravity

	local current_pos = self.entity.object:get_pos()
	local current_node = core.get_node(current_pos)
	local in_liquid = core.get_item_group(current_node.name, "liquid") ~= 0

	if in_liquid then
		if self.is_swimming then
			accel.x = -vel.x * 0.4
			accel.y = -vel.y * 0.4
			accel.z = -vel.z * 0.4
		else
			accel = self:calculate_bouyancy(accel, vel, current_pos, current_node)
		end

	elseif self.is_flying then
		accel.x = -vel.x
		accel.y = -vel.y
		accel.z = -vel.z
	end

	if (self.has_friction
	and self.entity.touching_ground)
	or in_liquid then
		vel.x = vel.x * (1 - dtime * 2)
		vel.z = vel.z * (1 - dtime * 2)
	end

	self.entity.object:set_acceleration(accel)
	self.entity.object:set_velocity(vel)
end

return physics
