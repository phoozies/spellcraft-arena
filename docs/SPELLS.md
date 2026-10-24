# Spell Dictionary

Wordcraft Arena v1 has 40 spells across 10 levels. Players start with the three ⭐ spells and unlock the rest by leveling up. In a match, any spell can also show up as a draft card, even one you haven't unlocked yet.

> **Source of truth:** [`src/shared/Spells/SpellDefinitions.luau`](../src/shared/Spells/SpellDefinitions.luau).
> This table is generated from it (see "Regenerating" below). Don't hand-edit numbers here.

## Getting spells: the copy model

- **Typing a spell word adds one copy of that spell to your hotbar.** You can hold **up to 5 copies in any mix**, including 5 of the same spell. When all 5 slots are full, cast one before typing another.
- **Casting uses up a copy.** Type the word again to get more.
- **Copies of the same spell share one cast cooldown** (the **Cooldown** column below). After you cast a Fireball, your other Fireballs wait out its 0.9s before they can fire.
- **You can submit one word per second.** This **typing cooldown** (`Config.TYPE_COOLDOWN = 1`) is shared across chat, the spell box, and voice. Pasting into the spell box is blocked.
- **Which words work:** in the hub, any spell you own. In a match, only the words in your match spellbook (3 random owned spells, plus one per draft, up to 5).

### Balance rules (enforced by `tests/Balance.spec.luau`)

Every player has **100 HP**. Since you can stockpile copies, the fastest a spell can be re-cast is its cooldown (or the 0.35s global cast lockout), so every spell's value is measured per `max(0.35s, cooldown)`:

| Budget | Limit |
|---|---|
| Any single hit (including combos) | ≤ 34 damage (no one-shots; best spam is about a 6s kill) |
| Burst damage (including combos) | ≤ 20 per second |
| Lingering zone damage | ≤ 24 total per second |
| Healing / shields | ≤ 5 per second |
| Hard crowd control (Root, Time Stop, Shrink) | ≤ 60% uptime, cooldown ≥ 2s, and **2.5s immunity** after it wears off (no chaining or refreshing) |
| Placeables | 1–3 alive per player per spell, all expire |
| Lingering zones | 1 alive per player per spell (a recast replaces the old one) |
| Summons | 1 alive per player per spell, cooldown ≥ 5s |
| Legendary spells | cooldown ≥ 10s |

Shields don't stack: a recast refills the shield to its full value instead of adding to it.

**Movement and hitboxes:**
- Players walk at 24 (Roblox's default is 16). Every projectile flies at 1.5× its listed `speed` (`Config.PROJECTILE_SPEED_SCALE`) to keep up.
- Bolts sweep a thin sphere against plain map geometry, so they glide over floors. Against players and breakable objects they use their radius **+1.5 studs** (`Config.HITBOX_BONUS`). Area spells also reach 1.5 studs past their edge against players.

**Health:** there's no regeneration in arenas, only healing spells. The hub regenerates 5 HP/s.

**Breakable blocks:** Rock Wall (3×2) and Castle (5×3) are built from separately breakable blocks, each holding an equal share of the spell's `health`. Every arena also has breakable block walls, and the hub's Practice Grove has one that rebuilds itself. Blocks darken as they take damage, chip on each hit, and shatter when they break.

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
| 1 | **Fireball** ⭐ | fireball, fire, flame, blaze | Projectile | Common | 0.9s | Hurl a ball of fire that burns players and structures. |
| 1 | **Water Lock** ⭐ | water lock, waterlock, water, bubble, trap | Control | Common | 3s | Trap an enemy in a bubble so they can't move for 1.5 seconds. |
| 1 | **Rock Wall** ⭐ | rock wall, rockwall, wall, rock, stone | Placeable | Common | 1s | Raise a stone wall that blocks spells. It breaks apart block by block. |
| 2 | **Wind Gust** | wind gust, wind, gust, push | Projectile | Common | 1.5s | A blast of wind that shoves enemies away. |
| 2 | **Wooden Crate** | wooden crate, crate, box | Placeable | Common | 0.5s | Drop a crate to hide behind or climb on. |
| 2 | **Heal Leaf** | heal leaf, heal, leaf, medicine | Buff | Common | 4s | Restore 15 health. |
| 2 | **Spark** | spark, zap | Projectile | Common | 0.5s | A quick little zap. Low damage, super fast. |
| 3 | **Ice Shard** | ice shard, ice, shard, freeze | Projectile | Common | 1s | An icy spike that slows whoever it hits. |
| 3 | **Bounce Pad** | bounce pad, trampoline, spring, bounce | Placeable | Common | 1s | A springy pad that launches anyone who steps on it. |
| 3 | **Mud Puddle** | mud puddle, mud, swamp | Zone | Common | 3s | A sticky puddle that slows enemies inside it. |
| 3 | **Shield** | shield, barrier, protect | Buff | Rare | 6s | A bubble that absorbs the next 25 damage (doesn't stack). |
| 4 | **Lightning** | lightning, thunder, bolt | Projectile | Rare | 2s | A bolt that chains to a nearby enemy. Double damage on bubbled foes! |
| 4 | **Ladder** | ladder, stairs, steps | Placeable | Common | 1s | Climbable steps to reach high ground. |
| 4 | **Dash** | dash, sprint, zoom, run | Movement | Common | 1.5s | Zoom forward in a burst of speed. |
| 4 | **Cannon** | cannon, turret | Placeable | Rare | 6s | A cannon that fires at the closest enemy. |
| 5 | **Tornado** | tornado, twister, cyclone | Zone | Rare | 5s | A swirling twister that pulls enemies in. |
| 5 | **Snowman** | snowman, decoy | Summon | Rare | 5s | A snowman decoy that cannons and summons target first. |
| 5 | **Bridge** | bridge, plank | Placeable | Common | 1s | A long plank to cross gaps. |
| 5 | **Banana Peel** | banana peel, banana, slip | Placeable | Common | 2s | A sneaky peel. Enemies who step on it slip and slide. |
| 6 | **Meteor** | meteor, comet, asteroid | Zone | Epic | 4s | Call down a meteor. Big boom after a short warning. |
| 6 | **Teleport** | teleport, blink, warp | Movement | Rare | 4s | Blink to where you're aiming. |
| 6 | **Vine Snare** | vine snare, vine, vines, roots | Control | Rare | 5s | Roots grab every enemy in a small area. |
| 6 | **Tower** | tower, fort, watchtower | Placeable | Rare | 4s | A tall tower for high ground. |
| 7 | **Dragon** | dragon, wyvern | Summon | Epic | 8s | A baby dragon that flies at enemies and breathes fire. |
| 7 | **Black Ice** | black ice, frost, glacier, icy | Zone | Rare | 4s | Super slippery ice. Enemies slide around helplessly. |
| 7 | **Magnet** | magnet, pull, attract | Control | Rare | 3s | Yank the enemy you hit toward you. |
| 7 | **Balloon** | balloon, float, fly | Movement | Common | 2s | Float upward to escape or get the high ground. |
| 8 | **Volcano** | volcano, lava, magma | Placeable | Epic | 8s | A mini volcano that burns enemies nearby. |
| 8 | **Mirror** | mirror, reflect | Buff | Epic | 8s | For 2 seconds, projectiles that hit you bounce back. |
| 8 | **Robot** | robot, golem, bot | Summon | Epic | 8s | A clunky robot buddy that punches enemies. |
| 8 | **Giant** | giant, grow, big, huge | Buff | Rare | 10s | Grow huge: bigger, tougher, and harder to knock back. |
| 9 | **Black Hole** | black hole, blackhole, vortex, void | Zone | Legendary | 12s | A tiny black hole that drags everything in and crushes it. |
| 9 | **Castle** | castle, fortress | Placeable | Epic | 10s | A big castle wall. Very hard to break, but it crumbles block by block. |
| 9 | **Shrink** | shrink, tiny, small, mini | Control | Epic | 6s | Shrink an enemy so they're tiny and weak for 3 seconds. |
| 9 | **Rainbow** | rainbow | Zone | Rare | 8s | A rainbow that heals you and your teammates inside it. |
| 10 | **Phoenix** | phoenix, rebirth, revive | Buff | Legendary | 25s | If you're knocked out in the next 8 seconds, rise again at half health. |
| 10 | **Earthquake** | earthquake, quake, tremor | Zone | Legendary | 12s | Shake the ground. Smashes structures and knocks players around. |
| 10 | **Time Stop** | time stop, timestop, freeze time, pause, stop | Control | Legendary | 15s | Freeze every enemy near you for 1.5 seconds. |
| 10 | **Kraken** | kraken, octopus, squid | Summon | Legendary | 12s | A giant kraken tentacle that slams enemies around it. |
| 10 | **Wizard Hat** | wizard hat, wizard, hat, magic | Buff | Epic | 15s | All your spell cooldowns are cut in half for 6 seconds. |

## Archetypes and the stats they read

| Archetype | Module | Stats |
|---|---|---|
| Projectile | `Archetypes/Projectile.luau` | `damage, speed, range, radius, knockback, status, statusDuration, chain, comboStatus, comboMultiplier` |
| Control | `Archetypes/Control.luau` | With `speed`: a status projectile. Without: an instant area using `radius`, `status`, `statusDuration`, `damage` (`range = 0` centers it on the caster) |
| Placeable | `Archetypes/Placeable.luau` | `health, lifetime, maxActive`, plus optional `turret` (`damage, range`), `trap` (`status`), `bounce`, `hazardDps` + `radius` |
| Zone | `Archetypes/Zone.luau` | Lingering: `duration, radius, status, damage` (per second), `pull, heal, teamHeal, maxActive`. Burst: `delay, damage, knockback, destroysStructures` |
| Buff | `Archetypes/Buff.luau` | `heal, shield, duration, reflect, scale, revive, cooldownCut` |
| Movement | `Archetypes/Movement.luau` | `dashSpeed` / `teleport` + `range` / `lift` |
| Summon | `Archetypes/Summon.luau` | `health, lifetime`, plus one of `decoy`, `melee`, or `flier` (shoots), or none for a stationary slam using `radius`. All use `damage, range` |

`cooldown` on every spell is its **cast cooldown**, shared by every copy of that spell you hold.

**Combo:** Lightning deals ×2 damage to a target that is already Water-Locked (`comboStatus = "Root"`). Add the same two fields to any projectile to create new combos.

## Adding a spell

1. Add a row to `SpellDefinitions.luau` with a unique `id`, plain-word `aliases`, a `rarity`, an `unlockLevel` (1–10), an `archetype`, `cooldown` (cast cooldown), `stats`, and a primitive `visual`.
2. Run the tests. They fail if an alias collides with another spell's or if the spell breaks a balance budget.
3. Regenerate this table.

## Regenerating

Run this during a playtest (the server's module cache is fresh) and paste the output over the table above:

```lua
local Defs = require(game.ReplicatedStorage.Shared.Spells.SpellDefinitions)
local lines = {"| Lvl | Spell | Say or type | Archetype | Rarity | Cooldown | What it does |", "|---|---|---|---|---|---|---|"}
for _, d in Defs.list do
	table.insert(lines, ("| %d | **%s**%s | %s | %s | %s | %ss | %s |"):format(d.unlockLevel, d.name, d.starter and " ⭐" or "", table.concat(d.aliases, ", "), d.archetype, d.rarity, tostring(d.cooldown), d.description))
end
print(table.concat(lines, "\n"))
```
