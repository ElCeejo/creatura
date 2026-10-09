---------------
-- Animation --
---------------

local animation = {}
animation.__index = animation

-- Create new instance
function animation:initiate(entity)
	local new_animation = {
		entity = entity,

		current_animation = "",

		length_frames = 0,
		animation_speed = 0,
		blend_delay = 0,
		current_frame = 0,

		is_playing = false,
		is_looping = false,

		frame_actions = {},
		end_action = {}
	}

	entity.animation = setmetatable(new_animation, self)
end

-- Update animation data every server-step
function animation:on_step()
	if not self.is_playing then return end -- No need to track frames if the animation isn't playing

	-- Delay frame tracking until frame blending has completed.
	if self.blend_delay > 0 then
		self.blend_delay = self.blend_delay - self.entity.dtime

		if self.blend_delay <= 0 then
			self.current_frame = self.animation_speed * math.abs(self.blend_delay)
			self.blend_delay = 0
		else
			return -- If the animation blend is still going frames can't be tracked
		end
	end

	self.current_frame = self.current_frame + (self.animation_speed * self.entity.dtime)

	local i = 1
    while i <= #self.frame_actions do
        local action = self.frame_actions[i]
        if self.current_frame >= action.frame then
            if action.action then action.action(unpack(action.args)) end
            table.remove(self.frame_actions, i) -- Remove so it only fires once
        else
            i = i + 1
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

-- Set Animation
function animation:play(name, ...)
	local parent = self.entity.object
	if not parent or not parent:is_valid() then return end

	-- Don't waste time on resetting the current animation
	if self.current_animation == name and self.is_playing then return end

	local animation_def = self.entity.animations[name]
	if not animation_def then return end -- TODO: Send an error to the log

	self.current_animation = name

	local animation_range = animation_def.range or {x = 0, y = 30}
	local length_frames = animation_range.y - animation_range.x
	self.length_frames = length_frames
	self.animation_speed = animation_def.speed or 30
	self.blend_delay = animation_def.frame_blend or 0
	self.current_frame = 0

	self.is_playing = true
	self.is_looping = animation_def.loop

	self.on_step = animation_def.on_step
	self.args = { ... }
	self.end_action = {}

	parent:set_animation(animation_def.range, animation_def.speed, animation_def.frame_blend, animation_def.loop)
end

animation.set_animation = animation.play

-- Attempt to set new animation (will only succeed if the current animation can't loop and has finished playing)
function animation:attempt_to_play(name)
	if self.is_playing or self.current_animation == name then return false end

	self:play(name)
	return true
end

animation.attempt_animation = animation.attempt_to_play

-- Return current animation name and current frame
function animation:get_animation()
	return (self.current_animation or ""), (self.current_frame or 0)
end

-- Stop current animation
function animation:end_animation()
	self.current_animation = ""
	self.length_frames = 0
	self.animation_speed = 0
	self.blend_delay = 0
	self.current_frame = 0
	self.is_playing = false
	self.is_looping = false
	self.end_action = {}
end

function animation:on_frame(frame, func, ...)
    table.insert(self.frame_actions, {
        frame = frame,
        action = func,
        args = { ... }
    })
end

-- Perform an action when the animation ends
function animation:on_end(func, ...)
	self.end_action = {
		action = func,
		args = { ... }
	}
end

return animation
