creatura = {
	path_partis = minetest.get_modpath("creatura") .. "/partis",
	path_subclass = minetest.get_modpath("creatura") .. "/subclasses",
}

-- Sounds
creatura.sounds = {
	hit = "creatura_hit"
}

-- Load API
dofile(creatura.path_partis .. "/register.lua")
dofile(creatura.path_partis .. "/spawning.lua")
dofile(creatura.path_partis .. "/particle_effects.lua")
dofile(creatura.path_partis .. "/helper_functions.lua")
dofile(creatura.path_partis .. "/mob_class.lua")

-- Antiquus (Support for mods still dependant on out-of-date Creatura versions)
local path_antiquus = minetest.get_modpath("creatura") .. "/antiquus"
dofile(path_antiquus .. "/mob_meta.lua")
dofile(path_antiquus .. "/api.lua")
dofile(path_antiquus .. "/boids.lua")
dofile(path_antiquus .. "/methods.lua")
