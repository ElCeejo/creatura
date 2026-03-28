----------------------
-- Particle Effects --
----------------------

-- TODO: Expand Effects API (Status Effects, Unique Particle Effects)

creatura.particle_effects = {}

local basic_particlespawner_definition = {
	amount = 8,
	time = 1,
	size = 8,
	collisiondetection = false,
	collision_removal = false,
	object_collision = false,
	texture = "image.png",
	--animation = {},
	glow = 7,
}

function creatura.particle_effects.float(pos, texture, size, radius)
	local def = table.copy(basic_particlespawner_definition)

	def.texture = texture

	def.pos = {
		min = vector.subtract(pos, radius or 1),
		max = vector.add(pos, radius or 1)
	}

	def.vel = {
		min = vector.new(-0.5, 1, -0.5),
		max = vector.new(0.5, 2, 0.5)
	}

	def.size = {
		(size or 4) - 1,
		(size or 4) + 1,
	}

	core.add_particlespawner(def)
end

function creatura.particle_effects.splash(pos, texture, size, radius)
	local def = table.copy(basic_particlespawner_definition)

	def.texture = texture

	def.pos = {
		min = vector.subtract(pos, radius),
		max = vector.add(pos, radius)
	}

	def.vel = {
		min = vector.new(-1, 3, -1),
		max = vector.new(1, 5, 1)
	}

	def.acc = {
		min = vector.new(-1, -9.8, -1),
		max = vector.new(1, -9.8, 1)
	}

	def.size = {
		(size or 4) - 1,
		(size or 4) + 1,
	}

	core.add_particlespawner(def)
end

function creatura.particle_effects.feed(pos, texture, size, radius)
	local def = table.copy(basic_particlespawner_definition)

	def.texture = texture

	def.pos = {
		min = vector.subtract(pos, radius),
		max = vector.add(pos, radius)
	}

	def.vel = {
		min = vector.new(-1, 3, -1),
		max = vector.new(1, 5, 1)
	}

	def.acc = {
		min = vector.new(-1, -9.8, -1),
		max = vector.new(1, -9.8, 1)
	}

	def.size = {
		(size or 4) - 1,
		(size or 4) + 1,
	}

	core.add_particlespawner(def)
end
