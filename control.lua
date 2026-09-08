-- AmbientLife: wildlife whose presence reflects the health of the land nearby.
--
-- Everything here is drawn with LuaRendering rather than spawned as entities:
-- creatures cost nothing when nobody is looking, never collide with a build,
-- and cannot be shot, mined or run over. Each player carries their own small
-- flock, sampled from the terrain immediately around them.

local SAMPLE_TICKS = 120 -- how often a player's surroundings are re-scored
local SAMPLE_RADIUS = 40 -- tiles searched when scoring the local ecology
local TREE_TARGET = 120 -- tree count that reads as a full, healthy forest
local SPAWN_MIN = 12 -- creatures appear no nearer to the player than this
local SPAWN_MAX = 34
local CULL_RADIUS = 50 -- ...and are dropped once they drift beyond it
local SPAWN_BURST = 3 -- new creatures per kind per sample, so flocks build up
local ANCHOR_TRIES = 6 -- attempts to find a tree far enough from the player
local SHADOW_OFFSET = {1.6, 1.9} -- how far a bird's shadow trails it, in tiles

-- Per-kind behaviour. `share` is the slice of the creature budget a kind may
-- claim; `picky` raises a kind's sensitivity to a degraded landscape by
-- exponentiating the vitality score.
local KINDS = {
	bird = {
		setting = "ambientlife-enable-birds",
		share = 0.30,
		picky = 1,
		nocturnal = false,
		lifetime = {900, 1800},
		speed = {0.055, 0.095},
		scale = {1.5, 2.0},
		anchor = 14, -- birds range widest, so they only loosely follow the trees
		shadow = true,
		tints = {
			{r = 0.42, g = 0.38, b = 0.36},
			{r = 0.52, g = 0.44, b = 0.35},
			{r = 0.36, g = 0.36, b = 0.42},
		},
	},
	butterfly = {
		setting = "ambientlife-enable-butterflies",
		share = 0.35,
		picky = 2, -- first to vanish as pollution creeps in
		nocturnal = false,
		lifetime = {600, 1500},
		speed = {0.018, 0.038},
		scale = {0.9, 1.3},
		anchor = 5,
		tints = {
			{r = 0.98, g = 0.82, b = 0.30},
			{r = 0.92, g = 0.55, b = 0.22},
			{r = 0.70, g = 0.80, b = 0.95},
			{r = 0.95, g = 0.95, b = 0.90},
			{r = 0.80, g = 0.45, b = 0.75},
		},
	},
	firefly = {
		setting = "ambientlife-enable-fireflies",
		share = 0.35,
		picky = 1.5,
		nocturnal = true,
		lifetime = {900, 2100},
		speed = {0.008, 0.020},
		scale = {0.55, 0.95},
		anchor = 4,
		tints = {
			{r = 0.85, g = 0.95, b = 0.35},
			{r = 0.95, g = 0.90, b = 0.45},
			{r = 0.70, g = 0.95, b = 0.50},
		},
	},
}

local function clamp(value, low, high)
	if value < low then return low end
	if value > high then return high end
	return value
end

local function pick(list)
	return list[math.random(#list)]
end

local function between(low, high)
	return low + math.random() * (high - low)
end

-- Space platforms have no ground to speak of, and this creature set is
-- distinctly Nauvis-like, so platforms are skipped outright.
local function surface_supports_life(surface)
	return surface.valid and not surface.platform
end

-- Scores the land around a position from 0 (barren or choked) to 1 (deep,
-- clean forest). Counting stops at TREE_TARGET, so a dense forest is cheap to
-- evaluate and only genuinely empty ground pays for a full search.
local function vitality_at(surface, position)
	local trees = surface.count_entities_filtered{
		position = position,
		radius = SAMPLE_RADIUS,
		type = "tree",
		limit = TREE_TARGET,
	}
	local forest = trees / TREE_TARGET

	local limit = settings.global["ambientlife-pollution-limit"].value
	local clean = 1
	if limit > 0 then
		clean = 1 - clamp(surface.get_pollution(position) / limit, 0, 1)
	end

	return forest * clean
end

-- Day and night are given overlapping windows on purpose, so dusk briefly
-- carries the last butterflies and the first fireflies at once.
local function light_factors(surface)
	local darkness = surface.darkness
	local day = 1 - clamp((darkness - 0.15) / 0.35, 0, 1)
	local night = clamp((darkness - 0.30) / 0.35, 0, 1)
	return day, night
end

-- Where a creature of this kind should appear.
--
-- Scoring the land around the player says how much life the area deserves, but
-- says nothing about where to put it, so creatures used to drift over bare
-- rock and concrete. Anchoring each one to a real tree keeps wildlife where
-- there is something to live on. Creatures still have to appear far enough
-- from the player not to pop into view, so a few trees are tried before
-- giving up and letting the next sample try again.
local function spawn_position(player, kind, trees)
	local origin = player.position

	if kind.anchor and trees and #trees > 0 then
		for _ = 1, ANCHOR_TRIES do
			local tree = trees[math.random(#trees)]
			if tree.valid then
				local x = tree.position.x + (math.random() - 0.5) * 2 * kind.anchor
				local y = tree.position.y + (math.random() - 0.5) * 2 * kind.anchor
				local dx, dy = x - origin.x, y - origin.y
				if dx * dx + dy * dy >= SPAWN_MIN * SPAWN_MIN then
					return x, y
				end
			end
		end
		return nil
	end

	local angle = math.random() * 2 * math.pi
	local distance = between(SPAWN_MIN, SPAWN_MAX)
	return origin.x + math.cos(angle) * distance, origin.y + math.sin(angle) * distance
end

local function spawn(player, kind_name, kind, trees)
	local surface = player.surface

	local x, y = spawn_position(player, kind, trees)
	if not x then return nil end

	local critter = {
		kind = kind_name,
		x = x,
		y = y,
		heading = math.random() * 2 * math.pi,
		speed = between(kind.speed[1], kind.speed[2]),
		phase = math.random() * 2 * math.pi,
		life = math.random(kind.lifetime[1], kind.lifetime[2]),
	}

	local scale = between(kind.scale[1], kind.scale[2])
	local tint = pick(kind.tints)
	local frame_offset = math.random(0, 3)
	local flap = between(0.25, 0.6)
	local target = {critter.x, critter.y}

	if kind_name == "firefly" then
		-- The engine blinks the light for us, so a firefly costs nothing per
		-- tick beyond being moved.
		critter.object = rendering.draw_light{
			sprite = "utility/light_small",
			target = target,
			surface = surface,
			players = {player},
			color = tint,
			scale = scale * 1.6,
			intensity = 0.55,
			minimum_darkness = 0.25,
			blink_interval = math.random(24, 70),
			time_to_live = critter.life + 60,
		}
	else
		critter.object = rendering.draw_animation{
			animation = "ambientlife-" .. kind_name,
			target = target,
			surface = surface,
			players = {player},
			tint = tint,
			x_scale = scale,
			y_scale = scale,
			animation_speed = flap,
			animation_offset = frame_offset,
			render_layer = "air-object",
			time_to_live = critter.life + 60,
		}

		if kind.shadow then
			-- Without a shadow a dark shape in a top-down game reads as
			-- something lying on the ground rather than flying over it. The
			-- offset copy below is what makes a bird look airborne.
			critter.shadow = rendering.draw_animation{
				animation = "ambientlife-" .. kind_name,
				target = {critter.x + SHADOW_OFFSET[1], critter.y + SHADOW_OFFSET[2]},
				surface = surface,
				players = {player},
				tint = {r = 0, g = 0, b = 0, a = 0.32},
				x_scale = scale * 0.85,
				y_scale = scale * 0.85,
				animation_speed = flap,
				animation_offset = frame_offset,
				render_layer = "object",
				time_to_live = critter.life + 60,
			}
		end
	end

	return critter
end

-- Movement is per-kind and deliberately cheap: a heading, a nudge, and one
-- target write. North-south travel is squashed to suggest a top-down view.
local function advance(critter)
	local kind = critter.kind

	if kind == "bird" then
		critter.phase = critter.phase + 0.03
		critter.heading = critter.heading + math.sin(critter.phase) * 0.008
	elseif kind == "butterfly" then
		critter.phase = critter.phase + 0.18
		if math.random() < 0.05 then
			critter.heading = math.random() * 2 * math.pi
		end
	else
		critter.heading = critter.heading + (math.random() - 0.5) * 0.5
	end

	local speed = critter.speed
	if kind == "butterfly" then
		-- A pulsing speed reads as a flutter; a constant one reads as a glide.
		speed = speed * (0.6 + 0.35 * (math.sin(critter.phase) + 1))
	end

	critter.x = critter.x + math.cos(critter.heading) * speed
	critter.y = critter.y + math.sin(critter.heading) * speed * 0.65
end

local function retire(critter)
	if critter.object and critter.object.valid then
		critter.object.destroy()
	end
	if critter.shadow and critter.shadow.valid then
		critter.shadow.destroy()
	end
end

-- Re-scores a player's surroundings and tops their flock up toward the target
-- population. Nothing is culled on the spot for being over quota: creatures
-- simply stop being replaced, so land going bad empties out gradually rather
-- than blinking empty.
local function resample(player)
	local flock = storage.flocks[player.index]
	if not flock then
		flock = {}
		storage.flocks[player.index] = flock
	end

	local surface = player.surface
	if not surface_supports_life(surface) then return end

	local budget = settings.global["ambientlife-max-creatures"].value
	local density = settings.global["ambientlife-density"].value
	if budget <= 0 or density <= 0 then return end

	local vitality = vitality_at(surface, player.position)
	if vitality <= 0 then return end

	local day, night = light_factors(surface)

	local counts = {}
	for _, critter in pairs(flock) do
		counts[critter.kind] = (counts[critter.kind] or 0) + 1
	end

	local anchors
	local function anchor_trees()
		if not anchors then
			anchors = surface.find_entities_filtered{
				position = player.position,
				radius = SPAWN_MAX,
				type = "tree",
				limit = 60,
			}
		end
		return anchors
	end

	for kind_name, kind in pairs(KINDS) do
		if settings.global[kind.setting].value then
			local daylight = kind.nocturnal and night or day
			local target = budget * kind.share * density * daylight * (vitality ^ kind.picky)
			local missing = math.floor(target) - (counts[kind_name] or 0)

			for _ = 1, math.min(missing, SPAWN_BURST) do
				-- Checked per spawn rather than per kind: density scales the
				-- share each kind asks for and can push the sum past the
				-- budget, which is the one number players are promised is a
				-- hard limit.
				if #flock >= budget then break end
				-- No usable anchor nearby just means no creature this pass;
				-- the next sample two seconds later tries again.
				local critter = spawn(player, kind_name, kind,
					kind.anchor and anchor_trees() or nil)
				if critter then
					flock[#flock + 1] = critter
				end
			end
		end
	end
end

script.on_nth_tick(SAMPLE_TICKS, function()
	for _, player in pairs(game.connected_players) do
		-- No character means the map editor or a spectator, with no position
		-- worth populating around.
		if player.valid and player.character then
			resample(player)
		end
	end
end)

script.on_event(defines.events.on_tick, function()
	if not storage.flocks then return end

	for player_index, flock in pairs(storage.flocks) do
		local player = game.get_player(player_index)
		local origin = player and player.valid and player.position

		-- Iterating backwards lets a retired creature be removed in place.
		for i = #flock, 1, -1 do
			local critter = flock[i]
			critter.life = critter.life - 1

			local drifted = false
			if origin then
				local dx, dy = critter.x - origin.x, critter.y - origin.y
				drifted = (dx * dx + dy * dy) > (CULL_RADIUS * CULL_RADIUS)
			end

			if not origin or drifted or critter.life <= 0
				or not (critter.object and critter.object.valid) then
				retire(critter)
				table.remove(flock, i)
			else
				advance(critter)
				critter.object.target = {critter.x, critter.y}
				if critter.shadow and critter.shadow.valid then
					critter.shadow.target = {
						critter.x + SHADOW_OFFSET[1],
						critter.y + SHADOW_OFFSET[2],
					}
				end
			end
		end
	end
end)

-- A player who changes surface or dies should not drag their old flock along
-- behind them. A teleport needs no event of its own: the next tick finds every
-- creature beyond the cull radius, which retires the flock anyway.
local function clear_flock(event)
	local flock = storage.flocks[event.player_index]
	if not flock then return end
	for _, critter in pairs(flock) do
		retire(critter)
	end
	storage.flocks[event.player_index] = nil
end

script.on_event(defines.events.on_player_changed_surface, clear_flock)
script.on_event(defines.events.on_player_died, clear_flock)
script.on_event(defines.events.on_player_left_game, clear_flock)

-- Diagnostics. Wildlife that fails to appear is ambiguous by nature: the
-- spawning may be declining to run, or it may be running and drawing something
-- too small or too dark to notice. These two commands separate those cases.

commands.add_command("al-debug", "Report what Ambient Life sees around you", function(cmd)
	local player = game.get_player(cmd.player_index)
	if not player then return end

	local surface = player.surface
	local trees = surface.count_entities_filtered{
		position = player.position,
		radius = SAMPLE_RADIUS,
		type = "tree",
	}
	local pollution = surface.get_pollution(player.position)
	local vitality = vitality_at(surface, player.position)
	local day, night = light_factors(surface)
	local budget = settings.global["ambientlife-max-creatures"].value
	local density = settings.global["ambientlife-density"].value

	local counts = {}
	for _, critter in pairs(storage.flocks[player.index] or {}) do
		counts[critter.kind] = (counts[critter.kind] or 0) + 1
	end

	player.print(string.format(
		"[Ambient Life] surface %s, supports life: %s | character: %s",
		surface.name, tostring(surface_supports_life(surface)),
		tostring(player.character ~= nil)))
	player.print(string.format(
		"  trees within %d tiles: %d (need %d for a full score) | pollution: %.1f",
		SAMPLE_RADIUS, trees, TREE_TARGET, pollution))
	player.print(string.format(
		"  vitality: %.3f | darkness: %.2f -> day %.2f, night %.2f",
		vitality, surface.darkness, day, night))
	player.print(string.format("  budget: %d | density: %.2f", budget, density))

	for kind_name, kind in pairs(KINDS) do
		local daylight = kind.nocturnal and night or day
		local target = budget * kind.share * density * daylight * (vitality ^ kind.picky)
		player.print(string.format(
			"  %-10s enabled %-5s target %5.2f -> %d | alive %d",
			kind_name, tostring(settings.global[kind.setting].value),
			target, math.floor(target), counts[kind_name] or 0))
	end
end)

commands.add_command("al-here", "Spawn Ambient Life creatures beside you for testing", function(cmd)
	local player = game.get_player(cmd.player_index)
	if not player then return end

	storage.flocks[player.index] = storage.flocks[player.index] or {}
	local flock = storage.flocks[player.index]

	for kind_name, kind in pairs(KINDS) do
		for i = 1, 3 do
			local critter = spawn(player, kind_name, kind)
			if critter then
				-- Placed right beside the player so visibility is not in question.
				critter.x = player.position.x + (i - 2) * 2.5
				critter.y = player.position.y - 3
				critter.object.target = {critter.x, critter.y}
				if critter.shadow and critter.shadow.valid then
					critter.shadow.target = {
						critter.x + SHADOW_OFFSET[1],
						critter.y + SHADOW_OFFSET[2],
					}
				end
				flock[#flock + 1] = critter
			end
		end
	end

	player.print("[Ambient Life] Spawned 3 of each kind beside you. "
		.. "Fireflies only show once it is dark.")
end)

local function reset()
	-- Any render object left behind by a previous version is orphaned, so the
	-- whole set is dropped and left to rebuild itself from scratch.
	rendering.clear("AmbientLife")
	storage.flocks = {}
end

script.on_init(reset)
script.on_configuration_changed(reset)
