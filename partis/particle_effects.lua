----------------------
-- Particle Effects --
----------------------

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
		min = vector.subtract(pos, radius),
		max = vector.add(pos, radius)
	}

	def.vel = {
		min = vector.new(-1, 3, -1),
		max = vector.new(1, 6, 1)
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
		min = vector.new(-3, 3, -3),
		max = vector.new(3, 5, 3)
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
