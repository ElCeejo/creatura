creatura = {
	path_mob_class = minetest.get_modpath("creatura") .. "/mob_class",
	path_api = minetest.get_modpath("creatura") .. "/api",
	path_subclass = minetest.get_modpath("creatura") .. "/subclasses",
}

-- Sounds
creatura.sounds = {
	hit = "creatura_hit"
}

-- Load API
creatura.boid_handler = dofile(creatura.path_subclass .. "/boid_handler.lua")

dofile(creatura.path_api .. "/register.lua")
dofile(creatura.path_api .. "/spawning.lua")
dofile(creatura.path_api .. "/helper_functions.lua")
dofile(creatura.path_api .. "/builtin.lua")
dofile(creatura.path_api .. "/pathfinder.lua")
dofile(creatura.path_mob_class .. "/mob_class.lua")


-- Legacy support for older Creatura versions
local path_legacy = minetest.get_modpath("creatura") .. "/legacy"
dofile(path_legacy .. "/mob_meta.lua")
dofile(path_legacy .. "/api.lua")
dofile(path_legacy .. "/boids.lua")
dofile(path_legacy .. "/methods.lua")
