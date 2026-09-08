# Ambient Life (AmbientLife)

For Factorio 2.0 / Space Age. Works with or without the Space Age expansion.
Purely cosmetic — it adds no items, recipes or technologies, and changes no
game balance.

## What it does

Wildlife appears around you in proportion to how healthy the local land is.
Every two seconds the mod scores the ground within 40 tiles of each player by
counting living trees and reading the pollution there, then tops the local
population up toward that score.

- **Birds.** Dark silhouettes that wheel over wooded ground by day, banking
  slowly as they cross.
- **Butterflies.** Coloured, erratic, daytime. They are the pickiest of the
  three, so they thin out first as pollution creeps in — usually the earliest
  visible sign that a factory is starting to cost something.
- **Fireflies.** Points of warm light that drift and blink through forests
  after dark. The engine handles the blinking, so they are nearly free.

Dusk and dawn overlap deliberately: for a few minutes the last butterflies and
the first fireflies share the air.

## How it decides

The score is `forest × cleanliness`, each from 0 to 1:

- **forest** — living trees within 40 tiles, against a target of 120. Counting
  stops once the target is reached, so dense forest is cheap to evaluate.
- **cleanliness** — falls to 0 as local pollution approaches the configurable
  limit (60 by default).

Because it reads the trees actually standing on the ground, it responds on its
own to anything that changes them — clear-cutting, creeping pollution, or a
regrowth mod replanting. No mod-to-mod dependency is involved.

## Performance

Creatures are drawn with `LuaRendering` rather than spawned as entities. They
have no collision box, no health and no AI: they cannot be shot, mined, run
over, or caught in a blueprint, and they cost nothing on surfaces nobody is
standing on. Each player carries their own flock, capped by a setting
(40 by default).

If you are chasing UPS, lower **Maximum creatures per player**, or set it to 0
to disable the mod without removing it.

## Settings

All under *Settings → Mod settings → Map*, so they can be changed mid-game.

| Setting | Default | Effect |
| --- | --- | --- |
| Birds / Butterflies / Fireflies | on | Enable each creature type |
| Maximum creatures per player | 40 | Hard cap on creatures around one player |
| Wildlife density | 1.0 | Scales how full a healthy landscape looks |
| Pollution that drives life away | 60 | Pollution at which wildlife abandons an area; 0 ignores pollution |

## Diagnostics

Two console commands, for when wildlife is not showing up and it is unclear
whether the cause is the spawning rules or the drawing:

- `/al-debug` — prints what the mod sees where you stand: tree count,
  pollution, the vitality score, day/night factors, and the population target
  and live count for each kind.
- `/al-here` — spawns three of each kind right beside you, bypassing the
  spawning rules entirely. If these are visible but nothing appears normally,
  the landscape is scoring too low. If even these are invisible, the problem is
  in the drawing. Fireflies only show once it is dark.

Using a command disables achievements in that save, so test in a scratch map if
you care about those.

## Install

Drop `AmbientLife_0.1.1.zip` into `%APPDATA%\Factorio\mods`.

## Quick test

Stand in deep forest in daylight and birds and butterflies should build up
within ten or twenty seconds. Wait for night in the same spot for fireflies.
To see the response to damage, raise **Wildlife density** to 3, then clear-cut
around yourself — the flock stops being replaced and empties out over the next
minute rather than vanishing all at once.

## Building from source

```
python tools/make_graphics.py   # regenerate sprites from AmbientLife/tools
python ../tools/pack.py --deploy AmbientLife
```
