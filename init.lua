--------------
-- Creatura --
--------------

creatura = {
	version = "1.0"
}

creatura.path_api = minetest.get_modpath("creatura") .. "/api"
creatura.path_mob_class = minetest.get_modpath("creatura") .. "/mob_class"
creatura.path_subclass = minetest.get_modpath("creatura") .. "/subclasses"

creatura.sounds = {
	hit = "creatura_hit"
}

creatura.settings = {
    support_legacy = minetest.settings:get_bool("creatura_support_legacy", true)
}

--------------
-- Load API --
--------------

dofile(creatura.path_api .. "/helper_functions.lua")
dofile(creatura.path_api .. "/register.lua")
dofile(creatura.path_api .. "/builtin.lua")
dofile(creatura.path_api .. "/pathfinder.lua")
dofile(creatura.path_api .. "/spawning.lua")
dofile(creatura.path_mob_class .. "/mob_class.lua")
dofile(creatura.path_subclass .. "/boid_handler.lua")

-- Legacy support for older Creatura versions
if creatura.settings.support_legacy then
	local path_legacy = minetest.get_modpath("creatura") .. "/legacy"
	dofile(path_legacy .. "/mob_meta.lua")
	dofile(path_legacy .. "/api.lua")
	dofile(path_legacy .. "/boids.lua")
	dofile(path_legacy .. "/methods.lua")
end

minetest.log("info", "[API] Creatura " .. creatura.version .. " Loaded")
