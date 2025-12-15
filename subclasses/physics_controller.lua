local physics_controller = {}
physics_controller.__index = physics_controller

-- Create new instance
function physics_controller:new(object)
	local new_controller = {
		parent = object,
		is_gravity_enabled = true,
		gravity = -9.8
	}

	return setmetatable(new_controller, physics_controller)
end

-- Enable gravity and specifify force to be used (optional)
function physics_controller:enable_gravity(gravity)
	self.is_gravity_enabled = true
	self.gravity = gravity or self.gravity
end

-- Disable gravity
function physics_controller:disable_gravity()
	self.is_gravity_enabled = false
end

-- Calculate physics every server-step
function physics_controller:update()
	local parent = self.parent
	local accel = parent:get_acceleration()
	local vel = parent:get_velocity()

	-- Gravity
	accel.x, accel.z = 0, 0
	if self.is_gravity_enabled then
		accel.y = self.gravity
	else
		accel.y = 0
	end

	-- Floating Physics
	local current_pos = parent:get_pos()
	local current_node = minetest.get_node(current_pos)
	local in_water = minetest.get_item_group(current_node.name, "liquid") ~= 0

	if in_water then
		local visc = math.min(minetest.registered_nodes[current_node.name].liquid_viscosity, 7) + 1
		accel.y = -1.2 / visc

		-- Check higher portion of hitbox
		current_pos.y = current_pos.y + 0.5
		current_node = minetest.get_node(current_pos)

		local in_deep_water = minetest.get_item_group(current_node.name, "liquid") ~= 0
		if in_deep_water then
			local sink_rate = math.max(0, -vel.y)
			accel.y = 2 + sink_rate * 3
		end
		accel.x = -vel.x * 0.8
		accel.z = -vel.z * 0.8
	end

	parent:set_acceleration(accel)
end

return physics_controller
