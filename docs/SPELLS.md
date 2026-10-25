# Spells

Spellcraft Arena has **20 spells in 4 elements**: Fire, Water, Earth, and Air, five each. You equip **one element at a time** and can draw its five spells. Your first element is a free pick; the other three are unlocked from **Element Crates** (see [ECONOMY.md](ECONOMY.md)). In a match your equipped element is locked in and its five spells are your spellbook.

> **Source of truth:** [`src/shared/Spells/SpellDefinitions.luau`](../src/shared/Spells/SpellDefinitions.luau) and [`Elements.luau`](../src/shared/Spells/Elements.luau).
> The tables below are generated from them (see "Regenerating"). Don't hand-edit numbers here.

## The shapes: one per kind of move

Every spell has a **role**, and the role decides the shape you draw. A shape means the same thing in every element, and an element never repeats a shape, so each spell has its own:

| Role | Shape | Spells |
|---|---|---|
| Basic attack | Circle | Fireball, Rock Throw, Gust |
| Fast attack | Diagonal slash (a straight line) | Fire Slash, Water Slice |
| Boost | Square | Fire Boost, Water Body, Air Boost |
| Defense | Triangle | Earth Wall, Air Shield |
| Stun | Triangle | Water Lock |
| Heavy attack | Lightning bolt | Water Wave, Earth Punch, Whirlwind |
| Area attack | V (chevron) | Fire Pillar, Earth Pillar |
| Ultimate | Star | Fire Bomb, Water Nebula, Earthquake, Tornado |

No spell uses a swirl or a squiggle.

The shapes live in `Glyphs.ROLE` and each spell's `role` in `SpellDefinitions`; `tests/Glyphs.spec.luau` checks that the two agree.

## Getting spells: the copy model

- **Drawing a spell's shape adds one copy of that spell to your hotbar.** You hold **at most one copy of each spell**, so at most one of each of your element's five. Drawing a spell you already hold is refused ("You already hold Fireball"); cast it first.
- **Casting uses up the copy.** Draw the shape again to get another.
- **Each spell has its own cast cooldown** (the **Cooldown** column below). Basic attacks wait **3 seconds**, fast slashes **2 seconds**.
- **You can draw one spell per second.** This **drawing cooldown** (`Config.DRAW_COOLDOWN = 1`) is enforced by the server.
- **Where you can draw:** the rounds of a match (duels, the Sparring Arena, every map), the Battleground, and the hub's **Training Grove** (a 100 x 110 stud yard in the west with dummies and targets). **Not anywhere else in the hub, and not while a match is in its intro, countdown, draft, or results.** The server enforces it (`MatchService.canDraw`, installed as `SpellInputService`'s draw gate) and the Draw button and spell cards hide when drawing isn't allowed.
- **Which shapes work:** only the five spells of your equipped element (the others are never even considered). A shape from a spell you don't have fizzles (in the hub the toast tells you which element it belongs to).

### Balance rules (enforced by `tests/Balance.spec.luau`)

- No non-ultimate hit above 30 damage; no hit above 34% of a player's HP, or 40% for ultimates.
- Burst damage is capped at 20 per second of cooldown.
- Ultimates (slot 5) have cooldowns of at least 15s and deal 30+ damage.
- Hard crowd control (Stun, Root, ...) is limited to 60% uptime and needs a cooldown of at least 2s.
- Timed buffs are up at most 60% of the time; walls and placeables have a lifetime and at most 3 alive.

## How drawings are matched

The client records your stroke and sends it (`DrawSpell`); the server runs `GlyphRecognizer` on it:

1. A **straight stroke** (no point strays far from the line between its ends) is a slash, in any direction. Anything else is resampled to 64 points, rotated and scaled to a square, then compared with your element's other four shapes (the **$1 unistroke recognizer**). A circle and a square look alike to it, so when they are the finalists it checks how much of its tightest bounding box the stroke fills (a square fills nearly all of it, a circle about 78%).
2. Size, position, rotation, and drawing direction don't matter, and closed shapes can start anywhere. Only the shape does.
3. The best shape wins if its score is at least `MIN_SCORE` (0.8) **and** clearly ahead of the runner-up (`MIN_MARGIN`). Otherwise the drawing fizzles. Straight lines, dots, and scribbles are rejected.
4. The spell your element draws with that shape is readied by `HandService.grant`.

`tests/Glyphs.spec.luau` draws every shape with wobble, rotation, reversal, and random start points, and checks that an element never repeats a shape and that each spell uses its role's shape. Admin commands still take spell names through `WordMatcher` (`;give fireball`).

## Drawing quality

How well a stroke follows its shape sets a **quality** from 0 to 1 (`Spells/Quality`, tunables in `Config.QUALITY`): the recognizer's score maps from 0.85 (quality 0) to 0.975 (quality 1). The copy remembers it, and when it is cast the spell's stats scale between these multipliers:

| What | Stats | Worst to best |
|---|---|---|
| Power | `damage`, `heal`, `shield`, `health`, `hazardDps`, and the bonus part of `damageMult` | x0.85 to x1.2 |
| Size | `radius` (the hit area) | x0.9 to x1.25 |
| Time | `duration`, `statusDuration`, `lifetime` | x0.85 to x1.3 |

Cooldowns, range, and speed never change, and an average drawing (quality 0.5) is close to the numbers in the spell tables below. `tests/Quality.spec.luau` checks that even a perfect drawing stays inside the balance budgets times its bonus, so a new spell must leave that headroom.

## Hitboxes

Hitbox sizes are the spell's `radius` in studs; players add `Config.HITBOX_BONUS` (2), so a spell reaches that much farther than its radius. Hitboxes are generous on purpose: **medium** 4.5-5, **large** 6-7, **wide** 8.5-11, **huge** 12+ (area attacks and ultimates, up to 25 for Earthquake). The visuals are sized to match.

## The 20 spells

### 🔥 Fire

| Slot | Spell | Draw | Archetype | Cooldown | What it does |
|---|---|---|---|---|---|
| 1 | **Fireball** | circle | Projectile | 3s | Hurl a ball of fire with a medium hitbox. 15 damage. |
| 2 | **Fire Slash** | slash | Projectile | 2s | A fast crescent of fire with a medium hitbox. 10 damage, 2 second cooldown. |
| 3 | **Fire Boost** | square | Buff | 14s | Your fire burns hotter: +25% damage for 8 seconds. |
| 4 | **Fire Pillar** | V | Zone | 7s | Point and click: a huge pillar of fire erupts where you aim after a short warning. 30 damage in a large area. Range 70. |
| 5 | **Fire Bomb** ★ | star | Projectile | 16s | ULTIMATE: a huge fireball with a very large hitbox. 35 damage. |

### 💧 Water

| Slot | Spell | Draw | Archetype | Cooldown | What it does |
|---|---|---|---|---|---|
| 1 | **Water Slice** | slash | Projectile | 2s | A fast slice of water with a medium hitbox. 10 damage. |
| 2 | **Water Body** | square | Buff | 22s | Turn to flowing water: you can't be hurt or affected by spells for 7 seconds. |
| 3 | **Water Lock** | triangle | Control | 4s | Trap an enemy in a bubble: 5 damage and a 1.5 second stun (no moving or casting). |
| 4 | **Water Wave** | lightning bolt | Projectile | 8s | Send a large wave rolling forward through everything in its path. 25 damage. |
| 5 | **Water Nebula** ★ | star | Zone | 18s | ULTIMATE: point and click: a towering water pillar crashes down in a large area. 35 damage. Range 70. |

### ⛰ Earth

| Slot | Spell | Draw | Archetype | Cooldown | What it does |
|---|---|---|---|---|---|
| 1 | **Rock Throw** | circle | Projectile | 3s | Hurl a large boulder. 15 damage and a solid shove. |
| 2 | **Earth Wall** | triangle | Placeable | 4s | Raise a rocky wall with 35 health that blocks spells. It breaks apart piece by piece. |
| 3 | **Earth Punch** | lightning bolt | Zone | 5s | Point and click: a boulder bursts out of the ground beneath your target. 20 damage. Range 60. |
| 4 | **Earth Pillar** | V | Line | 9s | A wave of stone pillars erupts in a line in front of you. 30 damage to anyone it catches. |
| 5 | **Earthquake** ★ | star | Zone | 22s | ULTIMATE: the ground shakes around you, then bursts. A quick 1.2 second cast leaves you rooted, but it deals 40 damage in a huge area. |

### 🌪 Air

| Slot | Spell | Draw | Archetype | Cooldown | What it does |
|---|---|---|---|---|---|
| 1 | **Gust** | circle | Projectile | 3s | A fast gust of air. 15 damage. |
| 2 | **Whirlwind** | lightning bolt | Projectile | 5s | A wide gust that blows everyone it hits far away. 15 damage. |
| 3 | **Air Boost** | square | Buff | 16s | Ride the wind: much faster and a higher jump for 6 seconds. |
| 4 | **Air Shield** | triangle | Buff | 14s | A swirling shield for 4 seconds that blocks the next spell or damage that hits you. |
| 5 | **Tornado** ★ | star | Projectile | 18s | ULTIMATE: a tornado tears forward, blowing away everything it hits. 30 damage. |

### Notes on the spells

- **Earth Wall:** the imported earth-wall model, and **every spell hits it, your own included**. The whole wall has a shared **35-damage** budget. As the budget drains, the pieces break one by one (the low base first, then the rubble, then the tall stones). Without the model it falls back to a 3×2 grid of blocks.
- **Point-and-click spells** (Fire Pillar, Water Nebula, Earth Punch) show their hit circle on the ground while readied, and a ring for their range limit. Aiming past the range pulls the circle in to the limit.
- **Water Body** makes you immune to damage *and* effects (stun, knockback) for its duration. **Air Shield** blocks one hit of any kind, including a spell's effect, then pops.
- **Fire Boost** multiplies all your damage by 1.25 for 8s (it stacks multiplicatively with the Power match boost).
- **Piercing spells** (Water Wave, Tornado) keep flying after they hit a player and hit each player only once. They still stop on walls.
- **Earthquake** roots you for its whole 1.2s cast (shortened from 2s, so it is much harder to dodge-and-punish) (`stats.channel`) and cancels if you are knocked out first.

`cooldown` on every spell is its **cast cooldown**, shared by every copy of that spell you hold.

## Match boosts (instead of earning spells)

In a duel the spellbook is always your element's five spells. After each round you pick **one of three boosts** that last for the rest of the match and stack up to 3 times (`shared/Match/Boosts.luau`, applied by `BoostService`):

| Boost | Effect |
|---|---|
| 💥 Power | +15% damage |
| ❤ Vitality | +20 max health |
| 👟 Swiftness | +3 move speed |
| ⏱ Focus | Spells recharge 12% faster (never below half) |
| 🧪 Health Potion | Once a round, heal 35 when you fall below 35% health |

## Stats the spells read

| Archetype | Module | Stats |
|---|---|---|
| Projectile | `Archetypes/Projectile.luau` | `damage, speed, range, radius, knockback, pierce, status, statusDuration, chain, comboStatus, comboMultiplier` |
| Control | `Archetypes/Control.luau` | With `speed`: a status projectile. Without: an instant area using `radius`, `status`, `statusDuration`, `damage` (`range = 0` centers it on the caster) |
| Placeable | `Archetypes/Placeable.luau` | `health, lifetime, maxActive`, plus optional `turret` (`damage, range, fireInterval`), `trap` (`status`), `bounce`, `hazardDps` + `radius` |
| Zone | `Archetypes/Zone.luau` | Lingering: `duration, radius, status, damage` (per second), `pull, hold, heal, teamHeal, maxActive`. Burst: `delay, damage, knockback, destroysStructures, radius, range`; `reticle` shows the client hit circle; `pillar` draws the element column; `rise` pops a boulder; `channel` roots the caster for `delay` |
| Line | `Archetypes/Line.luau` | `damage, radius, count, spacing, step, delay, knockback`: a row of bursts along the caster's aim |
| Buff | `Archetypes/Buff.luau` | `heal, shield, duration, reflect, scale, revive, cooldownCut, damageMult, invincible, barrier, haste` |
| Movement | `Archetypes/Movement.luau` | `dashSpeed` / `teleport` + `range` / `lift` |
| Summon | `Archetypes/Summon.luau` | `health, lifetime`, plus one of `decoy`, `melee`, or `flier` (shoots), or none for a stationary slam using `radius`. All use `damage, range` |

**`visual.model`:** every spell names a 3D model that replaces its primitive look: the bolt for projectiles, the column or boulder for zones and lines, the head emblem for buffs, the body for placeables (the primitive stays as the invisible hitbox). A model is either a **block model** (the classic blocky Parts in `Models/BlockModels`, built by `ModelKit` in any place) or an imported mesh stored in the place (`ReplicatedStorage.Models`: Fireball, Water Lock's bubble, Earth Wall, Gust). Without the model, the primitive `visual` is drawn. See [`assets/models/README.md`](../assets/models/README.md).

## Look and feel: the spell registry

Every spell has a **model**, a **particle style**, a **cast animation**, and **sounds**. The numbers live in `SpellDefinitions`; the presentation lives in one table, [`SpellRegistry`](../src/shared/Spells/SpellRegistry.luau), mirrored for reading in [`docs/semantic/spell_registry.yaml`](semantic/spell_registry.yaml) and in the table below. `tests/Registry.spec.luau` fails if a spell is missing from it, or names a model, style, pose, or cue that doesn't exist.

- **Model** (`visual.model` / `stats.model`): 14 spells use block models made in Blender (`tools/blender/block_models.py`); Fireball, Fire Bomb, Water Lock, Earth Wall, Gust, and Whirlwind use imported meshes.
- **Particles** (`Spells/VfxStyles`): a bolt trail and impact burst per spell; buffs also get an **aura** on the caster (rising embers, a water shimmer, wind streaks, or orbiting blades) for as long as they last (`SpellVfx.buffAura`). Zones draw their element's column (`SpellVfx.pillar`), Earth Punch and Earth Pillar rise as boulders and spikes (`SpellVfx.rise`), and Earthquake spreads ground cracks and pulsing rings while it winds up (`SpellVfx.quake`).
- **Cast animation** (`Spells/CastPoses`): nine arm and body poses (Throw, Slash, Flex, Guard, Point, Smash, Sweep, Ascend, Stomp) played on the caster by `Fx/CastAnimations`, for every player to see. They are built as KeyframeSequences at runtime, so no animation uploads are needed. Earthquake holds its Stomp for the whole channel.
- **Sound** (`sfx = { cast, impact }` naming cues in `Audio/Cues`): every spell has a cast sound; every attack has an impact sound. Buffs and Earth Wall have no impact by design (`noImpact` in the registry).

<!-- REGISTRY:start -->
| Spell | Element | Model | Particles (`VfxStyles`) | Cast pose (`CastPoses`) | Cast sound | Impact sound |
|---|---|---|---|---|---|---|
| **Fireball** | Fire | `Fireball` | `Fireball` | Throw | `fireballCast` | `fireballHit` |
| **Fire Slash** | Fire | `FireSlash` | `FireSlash` | Slash | `slashCast` | `fireballHit` |
| **Fire Boost** | Fire | `FireBoost` | `FireBoost` | Flex | `boostCast` | n/a |
| **Fire Pillar** | Fire | `FirePillar` | `FirePillar` | Sweep | `pillarCast` | `pillarBoom` |
| **Fire Bomb** | Fire | `Fireball` | `FireBomb` | Ascend | `bombCast` | `bombBoom` |
| **Water Slice** | Water | `WaterSlice` | `WaterSlice` | Slash | `sliceCast` | `waterTrap` |
| **Water Body** | Water | `WaterBody` | `WaterBody` | Flex | `bodyCast` | n/a |
| **Water Lock** | Water | `WaterBubble` | `WaterLock` | Point | `waterCast` | `waterTrap` |
| **Water Wave** | Water | `WaterWave` | `WaterWave` | Smash | `waveCast` | `waterTrap` |
| **Water Nebula** | Water | `WaterNebula` | `WaterNebula` | Ascend | `nebulaCast` | `nebulaBoom` |
| **Rock Throw** | Earth | `RockThrow` | `RockThrow` | Throw | `throwCast` | `rockBreak` |
| **Earth Wall** | Earth | `RockWall` | `EarthWall` | Guard | `rockRaise` | `wallHit` |
| **Earth Punch** | Earth | `EarthPunch` | `EarthPunch` | Smash | `punchCast` | `rockBreak` |
| **Earth Pillar** | Earth | `EarthPillar` | `EarthPillar` | Sweep | `rockRaise` | `rockBreak` |
| **Earthquake** | Earth | `Earthquake` | `Earthquake` | Stomp | `quakeRumble` | `quakeBoom` |
| **Gust** | Air | `Gust` | `Gust` | Throw | `gustCast` | `gustHit` |
| **Whirlwind** | Air | `Gust` | `Whirlwind` | Smash | `whirlCast` | `whirlHit` |
| **Air Boost** | Air | `AirBoost` | `AirBoost` | Flex | `airBoostCast` | n/a |
| **Air Shield** | Air | `AirShield` | `AirShield` | Guard | `shieldCast` | n/a |
| **Tornado** | Air | `Tornado` | `Tornado` | Ascend | `tornadoCast` | `tornadoHit` |
<!-- REGISTRY:end -->

Regenerate the YAML and this table after changing the registry: `python tools/gen-spell-registry.py`.

## Adding a spell

1. Add a row to `SpellDefinitions.luau` with a unique `id`, an `element`, a `slot`, a `role` and its `glyph` (`Glyphs.ROLE[role]`; an element can't repeat a shape, so add a new role and shape if none is free), plain-word `aliases` (admin names), `sfx` cue names, an `archetype`, `cooldown`, `stats`, and a primitive `visual`. Add its id to the element's list in `Elements.luau`.
2. Run the tests. They fail if an alias collides, an element repeats a shape, a cue name is wrong, the spell breaks a balance budget, or it is missing from the registry.
3. Give it a look: add its model to `tools/blender/block_models.py` (then `python tools/blender/block_models.py --luau .`, and run the script under Blender for the FBX) and name it in `visual.model`; add a particle style to `Spells/VfxStyles` (and an aura if it is a buff); pick a cast pose from `Spells/CastPoses`; and add its entry to `Spells/SpellRegistry`.
4. Run `python tools/gen-spell-registry.py`, regenerate the tables above, and update `docs/semantic/features.yaml` (the `spells.catalog`).

## Regenerating

Run this during a playtest (the server's module cache is fresh) and paste the output over the tables above:

```lua
local Defs = require(game.ReplicatedStorage.Shared.Spells.SpellDefinitions)
local Elements = require(game.ReplicatedStorage.Shared.Spells.Elements)
for _, element in Elements.LIST do
	print(`### {element.icon} {element.name}\n`)
	print("| Slot | Spell | Draw | Archetype | Cooldown | What it does |\n|---|---|---|---|---|---|")
	for slot, def in Defs.ofElement(element.id) do
		print(("| %d | **%s**%s | %s | %s | %ss | %s |"):format(slot, def.name, def.ultimate and " ★" or "", def.glyph, def.archetype, tostring(def.cooldown), def.description))
	end
end
```
