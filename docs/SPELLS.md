# Spell Dictionary

Wordcraft Arena v1 has 40 spells across 10 levels. Players start with the three ⭐ spells and unlock the rest by leveling up. In a match, any spell can also show up as a draft card, even one you haven't unlocked yet.

> **Source of truth:** [`src/shared/Spells/SpellDefinitions.luau`](../src/shared/Spells/SpellDefinitions.luau).
> This table is generated from it (see "Regenerating" below). Don't hand-edit numbers here.

## How words are matched

`WordMatcher` lowercases the input, strips punctuation, and then tries these in order:

1. **Exact alias match**: "Fire-ball!" → `fireball` → Fireball. Multi-word aliases also match without spaces, so `waterlock` works.
2. **Typo tolerance**: up to 1 typo for words with 5–8 letters, and 2 for words with 9 or more. If two spells tie, the word fizzles instead of guessing.
3. **Voice transcripts**: `findInText` scans a sentence for the first spell word. Two-word spells win, so "give me a rock wall" → Rock Wall.

Normal chat that isn't a spell word passes through untouched. Chat messages that *are* spell words are consumed, which keeps chat readable during fights.

## Rarity

| Rarity | Glyph | Draft weight | Color |
|---|---|---|---|
| Common | ● | 60% | grey |
| Rare | ◆ | 28% | blue |
| Epic | ★ | 10% | purple |
| Legendary | ✦ | 2% | gold |

Each glyph is a different shape, so rarity is readable without relying on color (colorblind-friendly).

## Spells

| Lvl | Spell | Say or type | Archetype | Rarity | Cooldown | What it does |
|---|---|---|---|---|---|---|
| 1 | **Fireball** ⭐ | fireball, fire, flame, blaze | Projectile | Common | 1.2s | Hurl a ball of fire that burns players and structures. |
| 1 | **Water Lock** ⭐ | water lock, waterlock, water, bubble, trap | Control | Common | 6s | Trap an enemy in a bubble so they can't move for 2 seconds. |
| 1 | **Rock Wall** ⭐ | rock wall, rockwall, wall, rock, stone | Placeable | Common | 5s | Raise a sturdy stone wall that blocks spells. |
| 2 | **Wind Gust** | wind gust, wind, gust, push | Projectile | Common | 3s | A blast of wind that shoves enemies away. |
| 2 | **Wooden Crate** | wooden crate, crate, box | Placeable | Common | 2.5s | Drop a crate to hide behind or climb on. |
| 2 | **Heal Leaf** | heal leaf, heal, leaf, medicine | Buff | Common | 10s | Restore some of your health. |
| 2 | **Spark** | spark, zap | Projectile | Common | 0.5s | A quick little zap. Low damage, fast fire. |
| 3 | **Ice Shard** | ice shard, ice, shard, freeze | Projectile | Common | 2s | An icy spike that slows whoever it hits. |
| 3 | **Bounce Pad** | bounce pad, trampoline, spring, bounce | Placeable | Common | 4s | A springy pad that launches anyone who steps on it. |
| 3 | **Mud Puddle** | mud puddle, mud, swamp | Zone | Common | 7s | A sticky puddle that slows enemies inside it. |
| 3 | **Shield** | shield, barrier, protect | Buff | Rare | 14s | A bubble that absorbs the next 40 damage. |
| 4 | **Lightning** | lightning, thunder, bolt | Projectile | Rare | 4s | A bolt that chains to a nearby enemy. Double damage on bubbled foes! |
| 4 | **Ladder** | ladder, stairs, steps | Placeable | Common | 3s | Climbable steps to reach high ground. |
| 4 | **Dash** | dash, sprint, zoom, run | Movement | Common | 4s | Zoom forward in a burst of speed. |
| 4 | **Cannon** | cannon, turret | Placeable | Rare | 12s | A cannon that fires at the closest enemy. |
| 5 | **Tornado** | tornado, twister, cyclone | Zone | Rare | 12s | A swirling twister that pulls enemies in. |
| 5 | **Snowman** | snowman, decoy | Summon | Rare | 12s | A snowman decoy that cannons and summons target first. |
| 5 | **Bridge** | bridge, plank | Placeable | Common | 5s | A long plank to cross gaps. |
| 5 | **Banana Peel** | banana peel, banana, slip | Placeable | Common | 6s | A sneaky peel. Enemies who step on it slip and slide. |
| 6 | **Meteor** | meteor, comet, asteroid | Zone | Epic | 14s | Call down a meteor. Big boom after a short warning. |
| 6 | **Teleport** | teleport, blink, warp | Movement | Rare | 8s | Blink to where you're aiming. |
| 6 | **Vine Snare** | vine snare, vine, vines, roots | Control | Rare | 8s | Roots grab every enemy in a small area. |
| 6 | **Tower** | tower, fort, watchtower | Placeable | Rare | 14s | A tall tower for high ground. |
| 7 | **Dragon** | dragon, wyvern | Summon | Epic | 20s | A baby dragon that flies at enemies and breathes fire. |
| 7 | **Black Ice** | black ice, frost, glacier, icy | Zone | Rare | 10s | Super slippery ice. Enemies slide around helplessly. |
| 7 | **Magnet** | magnet, pull, attract | Control | Rare | 9s | Yank the enemy you hit toward you. |
| 7 | **Balloon** | balloon, float, fly | Movement | Common | 7s | Float upward to escape or get the high ground. |
| 8 | **Volcano** | volcano, lava, magma | Placeable | Epic | 18s | A mini volcano that burns enemies nearby. |
| 8 | **Mirror** | mirror, reflect | Buff | Epic | 16s | For 3 seconds, projectiles that hit you bounce back. |
| 8 | **Robot** | robot, golem, bot | Summon | Epic | 20s | A clunky robot buddy that punches enemies. |
| 8 | **Giant** | giant, grow, big, huge | Buff | Rare | 18s | Grow huge: bigger, tougher, and harder to knock back. |
| 9 | **Black Hole** | black hole, blackhole, vortex, void | Zone | Legendary | 24s | A tiny black hole that drags everything in and crushes it. |
| 9 | **Castle** | castle, fortress | Placeable | Epic | 22s | A big castle wall. Very hard to break. |
| 9 | **Shrink** | shrink, tiny, small, mini | Control | Epic | 14s | Shrink an enemy so they're tiny and weak for 4 seconds. |
| 9 | **Rainbow** | rainbow | Zone | Rare | 18s | A rainbow that heals you and your teammates inside it. |
| 10 | **Phoenix** | phoenix, rebirth, revive | Buff | Legendary | 40s | If you're knocked out in the next 10 seconds, rise again at half health. |
| 10 | **Earthquake** | earthquake, quake, tremor | Zone | Legendary | 30s | Shake the ground. Smashes structures and knocks players around. |
| 10 | **Time Stop** | time stop, timestop, freeze time, pause, stop | Control | Legendary | 35s | Freeze every enemy near you for 1.5 seconds. |
| 10 | **Kraken** | kraken, octopus, squid | Summon | Legendary | 30s | A giant kraken tentacle that slams enemies around it. |
| 10 | **Wizard Hat** | wizard hat, wizard, hat, magic | Buff | Epic | 30s | All your cooldowns are cut in half for 8 seconds. |

## Archetypes and the stats they read

| Archetype | Module | Stats |
|---|---|---|
| Projectile | `Archetypes/Projectile.luau` | `damage, speed, range, radius, knockback, status, statusDuration, chain, comboStatus, comboMultiplier` |
| Control | `Archetypes/Control.luau` | With `speed`: a status projectile. Without: an instant area using `radius`, `status`, `statusDuration`, `damage` (`range = 0` centers it on the caster) |
| Placeable | `Archetypes/Placeable.luau` | `health, lifetime, maxActive`, plus optional `turret` (`damage, range`), `trap` (`status`), `bounce`, `hazardDps` + `radius` |
| Zone | `Archetypes/Zone.luau` | Lingering: `duration, radius, status, damage` (per second), `pull, heal, teamHeal`. Burst: `delay, damage, knockback, destroysStructures` |
| Buff | `Archetypes/Buff.luau` | `heal, shield, duration, reflect, scale, revive, cooldownCut` |
| Movement | `Archetypes/Movement.luau` | `dashSpeed` / `teleport` + `range` / `lift` |
| Summon | `Archetypes/Summon.luau` | `health, lifetime`, plus one of `decoy`, `melee`, or `flier` (shoots), or none for a stationary slam using `radius`. All use `damage, range` |

**Combo:** Lightning deals ×2 damage to a target that is already Water-Locked (`comboStatus = "Root"`). Add the same two fields to any projectile to create new combos.

## Adding a spell

1. Add a row to `SpellDefinitions.luau` with a unique `id`, plain-word `aliases`, a `rarity`, an `unlockLevel` (1–10), an `archetype`, `cooldown`, `stats`, and a primitive `visual`.
2. Run the tests (`require(game.ServerScriptService.Tests.Runner)()`). They fail if an alias collides with another spell's.
3. Regenerate this table.

## Regenerating

Run this in the Studio command bar (Edit mode) and paste the output over the table above:

```lua
local Defs = require(game.ReplicatedStorage.Shared.Spells.SpellDefinitions)
local lines = {"| Lvl | Spell | Say or type | Archetype | Rarity | Cooldown | What it does |", "|---|---|---|---|---|---|---|"}
for _, d in Defs.list do
	table.insert(lines, ("| %d | **%s**%s | %s | %s | %s | %ss | %s |"):format(d.unlockLevel, d.name, d.starter and " ⭐" or "", table.concat(d.aliases, ", "), d.archetype, d.rarity, tostring(d.cooldown), d.description))
end
print(table.concat(lines, "\n"))
```
