local animation_controller = {}
animation_controller.__index = animation_controller

-- Create new instance
function animation_controller:new(object)
	local new_animator = {
		parent = object,

		current_animation = "",

		length_frames = 0,
		animation_speed = 0,
		blend_delay = 0,
		current_frame = 0,

		is_playing = false,
		is_looping = false,

		end_action = {}
	}

	return setmetatable(new_animator, animation_controller)
end


-- Update animation_controller data every server-step
function animation_controller:update()
	local parent_entity = self:parent_entity()
	if not parent_entity then return end -- Abort if parent isn't is_valid

	if not self.is_playing then return end -- No need to track frames if the animation isn't playing

	-- Delay frame tracking until frame blending has completed.
	if self.blend_delay > 0 then
		self.blend_delay = self.blend_delay - parent_entity.dtime

		if self.blend_delay <= 0 then
			self.current_frame = self.animation_speed * math.abs(self.blend_delay)
			self.blend_delay = 0
		else
			return -- If the animation blend is still going frames can't be tracked
		end
	end

	self.current_frame = self.current_frame + (self.animation_speed * parent_entity.dtime)

	if self.on_step
	and self.is_playing then
		if self:on_step(self.parent, unpack(self.args)) then
			self.on_step = nil
		end
	end

	if self.current_frame >= self.length_frames then
		if self.is_looping then
			self.current_frame = self.current_frame - self.length_frames
		else
			self.current_frame = self.length_frames
			self.is_playing = false
			self.current_animation = ""
		end

		if self.end_action.action then self.end_action.action(unpack(self.end_action.args)) end
	end
end

-- Return parent objects luaentity
function animation_controller:parent_entity()
	return self.parent and self.parent:get_luaentity()
end

-- Set Animation
function animation_controller:set_animation(name, ...)
	local parent_entity = self:parent_entity()
	if not parent_entity then return end -- Early exit if parent doesn't exist

	if self.current_animation == name then return end -- Don't waste time on resetting the current animation

	local animation_def = parent_entity.animations[name]
	if not animation_def then return end -- TODO: Send an error to the log

	self.current_animation = name

	local length_frames = animation_def.range.y - animation_def.range.x
	self.length_frames = length_frames
	self.animation_speed = animation_def.speed
	self.blend_delay = animation_def.frame_blend
	self.current_frame = 0

	self.is_playing = true
	self.is_looping = animation_def.loop

	self.on_step = animation_def.on_step
	self.args = { ... }
	self.end_action = {}

	self.parent:set_animation(animation_def.range, animation_def.speed, animation_def.frame_blend, animation_def.loop)
end

-- Attempt to set new animation (will only succeed if the current animation can't loop and has finished playing)
function animation_controller:attempt_animation(name)
	if self.is_playing or self.current_animation == name then return false end

	self:set_animation(name)
	return true
end

-- Return current animation name and current frame
function animation_controller:get_animation()
	return (self.current_animation or ""), (self.current_frame or 0)
end

-- Stop current animation
function animation_controller:end_animation()
	self.current_animation = ""
	self.length_frames = 0
	self.animation_speed = 0
	self.blend_delay = 0
	self.current_frame = 0
	self.is_playing = false
	self.is_looping = false
	self.end_action = {}
end

-- Perform an action when the animation ends
function animation_controller:on_end(func, ...)
	self.end_action = {
		action = func,
		args = { ... }
	}
end

return animation_controller