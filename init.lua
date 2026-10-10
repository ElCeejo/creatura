--------------
-- Creatura --
--------------

creatura = {
	version = "1.0",
}

creatura.paths = {
	CORE = core.get_modpath("creatura") .. "/core",
	COMPONENTS = core.get_modpath("creatura") .. "/components",
	MOB = core.get_modpath("creatura") .. "/mob"
}

creatura.sounds = {
	hit = "creatura_hit"
}

creatura.settings = {
    support_legacy = core.settings:get_bool("creatura_support_legacy", true),
	debug_mode = core.settings:get_bool("creatura_debug_mode", false)
}

--------------
-- Load API --
--------------

function creatura.load_file(folder, name)
	return dofile(creatura.paths[folder] .. "/" .. name .. ".lua")
end

creatura.components = {
	PHYSICS = creatura.load_file("COMPONENTS", "physics"),
	TRAVERSAL = creatura.load_file("COMPONENTS", "traversal"),
	ANIMATION = creatura.load_file("COMPONENTS", "animation"),
	TARGETS = creatura.load_file("COMPONENTS", "targets"),
	UTILITY_STACK = creatura.load_file("COMPONENTS", "utility_stack"),
	BOIDS = creatura.load_file("COMPONENTS", "boids")
}

creatura.load_file("CORE", "utilities")
creatura.load_file("CORE", "register")
creatura.load_file("CORE", "builtin")
creatura.load_file("CORE", "pathfinder")
creatura.load_file("CORE", "spawning")

creatura.load_file("MOB", "base")

-- Legacy support for older Creatura versions
if creatura.settings.support_legacy then
	local path_legacy = core.get_modpath("creatura") .. "/legacy"
	dofile(path_legacy .. "/mob_meta.lua")
	dofile(path_legacy .. "/api.lua")
	dofile(path_legacy .. "/boids.lua")
	dofile(path_legacy .. "/methods.lua")
end

core.log("info", "[API] Creatura " .. creatura.version .. " Loaded")
