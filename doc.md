


# Creatura: Nova

**Creatura: Nova** is a ground-up rework of the Creatura mob API with a renewed focus on rich features and object-oriented code.

# Mob Methods

Used by `creatura.register_mob`.
The mob definition is an extension of the entity definition used in `core.register_entity` which itself is a metatable used by all instances of the entity in question.

```lua
{
		initial_properties = {}, -- All initial_properties are the same as entity definition

		-- Properties used by Creatura
		max_health =  20,
		max_breath =  20,
		max_feed_count =  5, -- Max feed count before feed count is reset to 0
		max_fall =  3,
		armor_groups = {fleshy =  100},
		turn_rate =  3.14, -- Radians/Second
		tempted_by = {}, -- List of itemnames and groups
		sounds = {
			random = { -- Mob sound definition
				name =  "mob_random", -- File name
				gain =  1.0,
				distance =  8
			},
			...
		},
	
		-- Most methods used in entity definition are overwritten by the API
		-- and now have separate handles.
		-- Refer to the "Registered entities" section for explanations
		activate_func = function() end, -- Replaces on_activate, uses same params.
		step_func = function(self, dtime, moveresult) end, -- Replaces on_step, uses same params.
		on_hit = function(s) end, -- Replaces on_punch, uses same params.
		on_interact = function(self, clicker) end, -- Replaces on_rightclick, uses same params.
}
```

# Mob Methods

Functions receive a "luaentity" table as `self`:

* It has the member `name`, which is the registered name `("mod:thing")`
* It has the member `object`, which is an `ObjectRef` pointing to the object
* The original prototype is visible directly via a metatable

Functions
-------------------------------------------------------------------------------------------

* `get_definition()`: Returns the mobs entity definition

* `play_sound(sound)`: Plays `sound` from `entity` sounds
    * See Mob sound definition in Mob Definition

* `get_props()`: Same as `object:get_properties` but caches result for subsequent use within the same server-step

* `set_scale(x)`: Scales entity mesh and collisionbox by a factor of `x`
    * Works off of defined scale, not the luaentities current scale.

* `get_hitbox_scale()`: Returns hitbox as 2 numbers `hitbox.width, hitbox.height`

* `set_texture_table(texture_table)`: Sets `texture_table` as the mobs main texture table
    * Textures will be pulled from this table on all subsequent initiations

* `set_mesh(new_mesh)`: Accepts `number` or `string` as an argument
    * `new_mesh` number: Index of `entity_definition.meshes`
    * `new_mesh` string: File name of new mesh

* `hurt(damage)`: Directly subtracts `damage` from `health`. Bypasses armor groups

* `heal(healing)`: Directly adds `healing` to `health`

* `punch_target(target)`: Punches ObjectRef `target`

* `apply_knockback(dir, power)`: Calculates knockback in `dir`. Scales by `power`

* `set_protection()`: Protects mob from damage and despawning

* `set_owner(player)`: Sets `player` as owner of mob
	* `player`: PlayerRef or Player name

* `is_tempted_by(stack)`: Returns `true` if `stack` is in `entity_definition.tempted_by`

* `set_child()`: Reduces mob scale by 50%
	* sets `self.is_child` to `true`
	* effects will be undone after 5 minutes

* `timer(n)`: Returns `true` every `n` seconds

* `memorize(k, v)`: Store a key, value pair to be remembered between initiations

* `recall(k)`: Returns stored value of `k` as set by `memorize()`

* `forget(k)`: Removes stored value of `k` as set by `memorize()`

# Sub-Classes - Docs coming soon
