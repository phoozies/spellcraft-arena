# Spell Dictionary

Wordcraft Arena has 8 spells. Every player starts with the three ⭐ starters. The other five are unlocked from **crates**, one per rarity, bought with coins earned by winning matches (see [ECONOMY.md](ECONOMY.md)). In a match, any spell can also show up as a draft card, even one you haven't unlocked yet.

> **Source of truth:** [`src/shared/Spells/SpellDefinitions.luau`](../src/shared/Spells/SpellDefinitions.luau).
> This table is generated from it (see "Regenerating" below). Don't hand-edit numbers here.

## Getting spells: the copy model

- **Drawing a spell's glyph adds one copy of that spell to your hotbar.** You can hold **up to 5 copies in any mix**, including 5 of the same spell. When all 5 slots are full, cast one before drawing another.
- **Casting uses up a copy.** Draw the glyph again to get more.
- **Copies of the same spell share one cast cooldown** (the **Cooldown** column below). After you cast a Fireball, your other Fireballs wait out its 0.9s before they can fire.
- **You can draw one spell per second.** This **drawing cooldown** (`Config.DRAW_COOLDOWN = 1`) is enforced by the server.
- **Which glyphs work:** in the hub, any spell you own. In a match, only the spells in your match spellbook (3 random owned spells, plus one per draft, up to 5).

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

**Movement and hitboxes:**
- Players walk at 24 (Roblox's default is 16). Every projectile flies at 1.5× its listed `speed` (`Config.PROJECTILE_SPEED_SCALE`) to keep up.
- Bolts sweep a thin sphere against plain map geometry, so they glide over floors. Against players and breakable objects they use their radius **+1.5 studs** (`Config.HITBOX_BONUS`). The Fireball's radius is 3.5, so it hits from up to 5 studs off the center of its path. Area spells also reach 1.5 studs past their edge against players.

**Health:** there's no regeneration in arenas, only healing spells. The hub regenerates 5 HP/s.

**Rock Wall:** it's the imported earth-wall model, and **every spell hits it, your own included**. The whole wall has a shared **50-damage** budget. As the budget drains, the pieces break one by one (the low base first, then the rubble, then the tall stones), and the wall is gone at 50. Four Fireballs bring it down. Without the model it falls back to a 3×2 grid of blocks. Every arena also has breakable block walls, and the hub's Practice Grove has one that rebuilds itself. Blocks darken as they take damage, chip on each hit, and shatter when they break.

## How drawings are matched

Every spell owns one **glyph**, a single-stroke shape (`glyph` in `SpellDefinitions`, shapes in `shared/Spells/Glyphs.luau`). The client records your stroke and sends it (`DrawSpell`); the server runs `GlyphRecognizer` on it:

1. The stroke is resampled to 64 points, rotated and scaled to a square, then compared with every glyph template (the **$1 unistroke recognizer**).
2. Size, position, rotation, and drawing direction don't matter, and closed shapes can start anywhere. Only the shape does.
3. The best glyph wins if its score is at least `MIN_SCORE` (0.8) **and** clearly ahead of the runner-up (`MIN_MARGIN`). Otherwise the drawing fizzles. Straight lines, dots, and scribbles are rejected.
4. The spell that owns the glyph is granted through `HandService.grant`, which still checks ownership (hub) or the match spellbook.

| Glyph | Spell |
|---|---|
| Circle | Fireball |
| Wave | Water Lock |
| Triangle | Rock Wall |
| Chevron (V) | Gust |
| Lightning bolt | Zap |
| Infinity (figure eight) | Heal |
| Spiral | Black Hole |
| Star | Turret |

`tests/Glyphs.spec.luau` draws every glyph with wobble, rotation, reversal, and random start points, and fails if a spell lacks a unique glyph. Admin commands still take spell names through `WordMatcher` (`;give fire`).

## Rarity

| Rarity | Glyph | Draft weight | Color | Crate |
|---|---|---|---|---|
| Common | ● | 50% | grey | 100 coins |
| Uncommon | ▲ | 25% | green | 250 coins |
| Rare | ◆ | 15% | blue | 500 coins |
| Epic | ★ | 8% | purple | 1000 coins |
| Legendary | 👑 | 2% | gold | 2000 coins |

Each glyph is a different shape, so rarity is readable without relying on color (colorblind-friendly).

## Spells

| Spell | Draw | Archetype | Rarity | Cooldown | How you get it | What it does |
|---|---|---|---|---|---|---|
| **Fireball** ⭐ | circle | Projectile | Common | 0.9s | Starter | Hurl a ball of fire that burns players and structures. |
| **Water Lock** ⭐ | wave | Control | Common | 3s | Starter | Trap an enemy in a bubble so they can't move for 1.5 seconds. |
| **Rock Wall** ⭐ | triangle | Placeable | Common | 1s | Starter | Raise a rocky earth wall that blocks spells. It breaks apart piece by piece. |
| **Gust** | chevron | Projectile | Common | 1.5s | Common crate | A wide blast of wind that shoves enemies far away. Low damage, huge hitbox. |
| **Zap** | lightning bolt | Zone | Uncommon | 2.5s | Uncommon crate | Point and click: a thunderbolt strikes the ground where you aim after a short flash. Range 60. |
| **Heal** | infinity | Buff | Rare | 4s | Rare crate | Restore 10 health. |
| **Black Hole** | spiral | Zone | Epic | 10s | Epic crate | A black hole sucks enemies in, traps them for 3 seconds, and deals 10 damage over time. |
| **Turret** | star | Placeable | Legendary | 12s | Legendary crate | Summon a 30-health turret that shoots bullets at the nearest enemy player. |

### The crate spells in detail

- **Gust** (Projectile): 5 damage, radius 6 (7.5 against players with `HITBOX_BONUS`), knockback 95, range 90. Drawn with the imported `Gust` model.
- **Zap** (Zone burst + `reticle`): while Zap is readied, a circle on the ground shows exactly where it will hit (its 5-stud radius + 1.5 bonus) and a faint ring shows its **60-stud range**; aiming past the range pulls the circle in to the limit (it turns orange). On cast, a red warning circle flashes for 0.45s, then the `Zap` bolt model slams down: 18 damage and a small knockback.
- **Heal** (Buff): +10 HP (4s cooldown, 2.5 HP/s, inside the 5 HP/s budget). The `Heal` model pops up over your head.
- **Black Hole** (Zone + `hold`): a 16-radius zone for 3s that pulls enemies toward the center (pull 60) and deals 10 damage in total over its life. Anyone pulled into the core (4 studs) is **Rooted until it closes**: sucked in, then trapped. The `BlackHole` model spins over the zone.
- **Turret** (Placeable + `turret`): a 30-HP turret (the `Turret` model) that shoots a 6-damage bullet at the nearest enemy player within 80 studs every second, for 20s. One alive at a time.

## Archetypes and the stats they read

| Archetype | Module | Stats |
|---|---|---|
| Projectile | `Archetypes/Projectile.luau` | `damage, speed, range, radius, knockback, status, statusDuration, chain, comboStatus, comboMultiplier` |
| Control | `Archetypes/Control.luau` | With `speed`: a status projectile. Without: an instant area using `radius`, `status`, `statusDuration`, `damage` (`range = 0` centers it on the caster) |
| Placeable | `Archetypes/Placeable.luau` | `health, lifetime, maxActive`, plus optional `turret` (`damage, range, fireInterval`), `trap` (`status`), `bounce`, `hazardDps` + `radius` |
| Zone | `Archetypes/Zone.luau` | Lingering: `duration, radius, status, damage` (per second), `pull, hold, heal, teamHeal, maxActive`. Burst: `delay, damage, knockback, destroysStructures`; `reticle` shows the client hit circle |
| Buff | `Archetypes/Buff.luau` | `heal, shield, duration, reflect, scale, revive, cooldownCut` |
| Movement | `Archetypes/Movement.luau` | `dashSpeed` / `teleport` + `range` / `lift` |
| Summon | `Archetypes/Summon.luau` | `health, lifetime`, plus one of `decoy`, `melee`, or `flier` (shoots), or none for a stationary slam using `radius`. All use `damage, range` |

Movement and Summon have no spells right now; they're kept as ready-made behaviors for future spells.

`cooldown` on every spell is its **cast cooldown**, shared by every copy of that spell you hold.

**`visual.model`:** any spell can name an imported model (`ReplicatedStorage.Models`) that replaces its primitive look: the bolt for projectiles, the body for placeables (the primitive stays as the invisible hitbox), the swirl for lingering zones, the strike for burst zones (Fx `strike`), and a pop-up over the caster for buffs (Fx `modelPop`). Without the model, the primitive `visual` is drawn.

## Adding a spell

1. Add a row to `SpellDefinitions.luau` with a unique `id`, a **unique `glyph`** (add the shape to `Glyphs.luau` if none is free), plain-word `aliases` (admin names), `sfx` cue names, a `rarity`, an `archetype`, `cooldown` (cast cooldown), `stats`, and a primitive `visual` (optionally `visual.model`). Leave out `starter` and it joins its rarity's **crate** automatically.
2. Run the tests. They fail if an alias or glyph collides with another spell's, a cue name is wrong, or the spell breaks a balance budget.
3. Regenerate this table and update `docs/semantic/features.yaml` (the `spells.catalog`).

## Regenerating

Run this during a playtest (the server's module cache is fresh) and paste the output over the table above:

```lua
local Defs = require(game.ReplicatedStorage.Shared.Spells.SpellDefinitions)
local lines = {"| Spell | Draw | Archetype | Rarity | Cooldown | How you get it | What it does |", "|---|---|---|---|---|---|---|"}
for _, d in Defs.list do
	table.insert(lines, ("| **%s**%s | %s | %s | %s | %ss | %s | %s |"):format(d.name, d.starter and " ⭐" or "", d.glyph, d.archetype, d.rarity, tostring(d.cooldown), d.starter and "Starter" or (d.rarity .. " crate"), d.description))
end
print(table.concat(lines, "\n"))
```
