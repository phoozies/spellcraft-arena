# Changelog

All notable changes to this project are documented here ([Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format).

## [Unreleased]

### Changed (arena size, open Battleground)
- **The Return to Hub button now shows** whenever you are in the Battleground (it was built but never made visible). The green gates still work too.
- **Bigger Sparring Arena** (the 1v1/2v2 map): the floor is 4x larger than the original model (about 184 studs), with spawns and the invisible wall ring scaled to match.
- **One open Battleground.** The mountain ring is now distant scenery you can't collide with; thicker invisible walls at the edge keep everyone on the map, and a once-a-second safety net puts anyone who still ends up below the world or outside the walls back at a random spot.

### Added (NPC aggro, parties)
- **NPCs stay on whoever hit them.** Hitting an NPC locks it onto you at any distance until you are knocked out or leave the Battleground, so you can't snipe from out of range. NPCs that only noticed you can still be outrun. A **red "!"** shows over any NPC that is hunting someone.
- **Parties** (`PartyService`, `PartyController`): a Party button under the wallet opens a panel to invite players, accept or decline invites, kick (leader), and leave. Up to 4 per party (`Config.PARTY`). In the Battleground party mates can't hurt each other, their heals and buffs reach each other, their health bars are blue, and you drop in beside a party mate who is already inside. New remotes `PartyAction` and `PartyState`.

### Added (trace-to-cast quality, mobile layout)
- **Tap a spell card to see its shape.** The cards above the hotbar are now buttons: tapping one opens the drawing canvas with that spell's shape as a faint guide and a dot tracing how to draw it. The F key / Draw button still open a blank canvas.
- **Drawing quality.** The closer your stroke follows the shape, the stronger the spell: a Rough to Perfect tier (1 to 4 stars on the hotbar copy, and a "Perfect! +20% power" pop-up) scales damage/healing/shields/health, hit radius, and durations (`Spells/Quality`, `Config.QUALITY`). A straighter slash scores higher. With a card selected the server only accepts that spell's shape (`DrawSpell` now carries the spell id; `GlyphResult` and `HandUpdated` carry quality).
- **Mobile on every screen size.** One scaling rule for the HUD and the Draw button (`UI/Responsive`): phones use a smaller design size so text stays readable, and the scale is capped so menu panels always fit, in portrait too. The drawing canvas banner now fits narrow screens.

### Added (Battleground open world and NPCs)
- **The Battleground is now an open world, not an arena.** A 600 x 600 stud land of four biomes ringed by mountains, with Raider camps, ruined circles, and the Warlord's Keep. You drop in at a **random open spot** (away from camps and other fighters) and leave through one of four gates or the new **Return to Hub** button (`LeaveBattleground` remote).
- **Hostile NPCs** (`NpcService`): Sand Raiders, Ember Mages (ranged), Stone Brutes, and the Dune Warlord. They chase, swing, and shoot back with telegraphed windups, give up and heal when you run, and respawn. Every spell hurts them.
- **NPC knockouts pay coins** (3 / 5 / 12 / 40), capped at 120 per player per 5 minutes (`Config.BATTLEGROUND.NPC`).

### Changed (Battleground, no more swirls)
- **The FFA arena is now the Battleground.** The pink FFA queue pad is a blue portal that teleports you to a big open sand arena (`BattlegroundService`, `Maps/Battleground`): drop in any time, everyone inside is an enemy, you respawn 3 seconds after being knocked out, and green exit pads take you back to the hub. FFA as a queued match mode is removed (the Play menu, `Config.MODES`, the match code, and the FFA spawns).
- **No more swirly shapes.** Fire Boost, Water Body, and Air Boost are drawn as a **square**; Earth Wall and Air Shield as a **triangle**. The swirl, squiggle, and infinity shapes are gone from the library, and so is the movement role. A circle and a square are told apart by how much of its bounding box the stroke fills.

### Changed (arena hub, swirl for boosts)
- **Boost and defense spells are drawn as a swirl** (the spiral): Fire Boost, Water Body, Earth Wall, and Air Shield. The V (chevron) moves to the area attacks (Fire Pillar, Earth Pillar). A swirl is accepted with 1 to 3 turns, drawn in or out, so it is forgiving to draw.
- **The hub is an arena, not a dark Halloween scene.** Sunny warm light, a sand plaza with gold-and-stone rings, a three-tier grandstand with blue and red pennants, sandstone and marble walls with sky-glass windows, team flag poles, and green trees. The pumpkins, purple trees, glowing orange windows, and night lighting are gone, and the hub's ambience is a quiet arena crowd instead of crickets. The hall is now the Champions' Concourse.

### Changed (shapes by kind of move, bigger hitboxes)
- **Every spell's shape now says what kind of move it is, and no element repeats a shape:** a circle is a basic attack (Fireball, Rock Throw, Gust), a diagonal slash a fast attack (Fire Slash, Water Slice), a squiggly line movement (Air Boost), a triangle a stun (Water Lock), a V a boost or defense, a lightning bolt a heavy attack, a spiral an area attack, and a star an ultimate. New `slash` shape (any straight stroke, recognized by straightness), `Glyphs.ROLE`, and a `role` on every spell. Only the equipped element's five shapes are recognized.
- **Bigger hitboxes on every move** (about 40% wider, with the visuals scaled to match): Fireball 3.5 to 5, Fire Slash and Water Slice 3 to 4.5, Fire Bomb 7 to 10, Water Wave 8 to 11, Rock Throw 4.2 to 6, Gust 3.2 to 4.6, Whirlwind 7 to 10, Tornado 6 to 8.5, Water Lock 2.5 to 4, Fire Pillar 9 to 12, Water Nebula 10 to 13, Earth Punch 5 to 7, Earth Pillar 4.5 to 6.5 (pillars 9 studs apart), Earthquake 22 to 25. The bonus against players (`HITBOX_BONUS`) goes from 1.5 to 2.

### Changed (elements replace the 8 spells)
- **Four elements, 20 spells.** Fire, Water, Earth, and Air have five spells each: a basic attack, a second move, a utility or boost, a heavy move, and an ultimate. Each slot uses the same shape in every element (circle, wave, triangle, lightning bolt, star), and recognition only considers those five shapes.
  - **Fire:** Fireball (15), Fire Slash (10, fast), Fire Boost (+25% damage, 8s), Fire Pillar (30, large area, point and click), Fire Bomb (ultimate, 35).
  - **Water:** Water Slice (10, fast), Water Body (invincible 7s), Water Lock (5 + stun), Water Wave (25, piercing), Water Nebula (ultimate, 35 pillar).
  - **Earth:** Rock Throw (15, large rock), Earth Wall (35 HP), Earth Punch (20, boulder under the aim point), Earth Pillar (30, a line of pillars), Earthquake (ultimate, 40, 2s cast).
  - **Air:** Gust (15, fast), Whirlwind (15, wide, blows enemies away), Air Boost (faster, higher jump), Air Shield (blocks the next hit, 4s), Tornado (ultimate, 30, piercing).
- **Elements are chosen and unlocked.** Pick your first element free in the Spellbook; the others unlock from **Element Crates** (`ElementService`, one crate for 250 coins that always lands on an element you don't own). Equip any owned element in the hub; it is locked in during a match. Hub **shrines** list each element's spells and shapes.
- **Duels give boosts, not spells.** After each round you pick 1 of 3 match boosts (Power, Vitality, Swiftness, Focus, Health Potion), which stack up to 3 times (`Match/Boosts`, `BoostService`). Your spellbook is always your element's five spells.
- New mechanics: `Stun` (no moving or casting), `Invincible`, `Barrier`, `Haste`, `Channel` statuses; the `Line` archetype; piercing projectiles; `channel`, `rise`, and `pillar` zone bursts; a damage multiplier in `DestructibleService.damage`.
- New effects and sounds: element pillars, rising boulders and stone pillars, an earthquake wind-up, new bolt styles, and 18 more audio cues (`Audio/Cues`).
- **Classes are planned, not built.** `docs/CLASSES.md` records what's decided and the open questions.
- Profile schema **3** (`elements`, `element`; `ownedSpells` removed): existing players pick their first element again.
- Tests: `tests/Economy.spec` (elements, crate, boosts), updated `Balance`, `Glyphs`, `WordMatcher`, and `Audio` specs (204 pass).

### Removed (elements)
- The old 8 spells' unique ones: Zap, Heal, Black Hole, and Turret (their models stay in the repo but nothing uses them), Rarity tiers (Common to Legendary), the spell draft, and the five-crate shop with duplicate refunds.

### Added (drawing, a new hub, audio and VFX)
- **Draw spells.** Press **F** (or tap ✏ Draw, or **X** on a gamepad) and trace a shape: circle = Fireball, wave = Water Lock, triangle = Rock Wall, chevron = Gust, lightning = Zap, infinity = Heal, spiral = Black Hole, star = Turret. The server recognizes the stroke (`Glyphs`, `GlyphRecognizer`, a $1 unistroke recognizer that ignores size, rotation, direction, and start point) and readies the spell. The line turns gold or red with the verdict, and everyone sees the glyph pop over the caster's head. New `DrawController`, `GlyphView`, `DrawSpell` and `GlyphResult` remotes, `tests/Glyphs.spec`.
- **Glyph cards** above the hotbar show what to draw (with cooldowns); the Spellbook shows each spell's glyph.
- **New hub: the Great Hall of Glyphs.** A moonlit round plaza (inkwell fountain, eight glyph stones) opens into a long stone hall with pointed arches, glowing rune windows, glyph banners, a red carpet, the team boxes, the FFA portal, and a red Arena Gate at the far end. The Spell Practice pavilion is west, the Crate Shop east, the podium and Most Wins board at the hall entrance. Pumpkins and torches throughout.
- **Night mood** (`LightingController`): the hub fades to a purple night with bloom; matches keep the bright arena lighting.
- **Audio** (`Audio/Cues`, `AudioController`): a cast and an impact sound per spell, hit sounds, shattering rock, drawing success and failure chimes, the crate reveal, and a quiet night ambience in the hub. Spells name their cues with `sfx = { cast, impact }`. `tests/Audio.spec`.
- **Spell VFX:** the glyph you drew is imprinted in the magic circle under the caster, Heal sparkles and a ring, Black Hole streams motes inward with a pulsing glow.

### Removed (drawing)
- Typing, chat casting, the spell box, and voice casting (`VoiceService`, `VoiceListen`, `VoiceHeard`, `SubmitWord`). Chat still carries admin `;` commands, and spell names still work in them.
- The "type a spell" key setting is now the **draw key** setting (default F).

### Added (coins, crates, wins podium)
- **Coins.** Winning a match pays 100 coins (+50 for the first win of the day); the daily login chest and daily quests pay coins too. New players start with 150. The HUD's top-left wallet shows coins and wins, and the Victory screen counts up the coins you won.
- **Crates** (`Economy/Crates`, `CrateService`, `CrateController`): a Common, Uncommon, Rare, Epic, and Legendary crate (100 / 250 / 500 / 1000 / 2000 coins). Each spin is decided on the server and unlocks a spell of the crate's rarity (with a 15–20% chance of one tier up); a spell you already own refunds half the price. Open them from the new 🎁 Crates menu or the Crate Shop stage in the hub; a reel of spell cards spins and lands on your prize.
- **Five new spells**, one per crate: **Gust** (Common: low damage, huge hitbox, big shove), **Zap** (Uncommon: point-and-click thunder strike with a hover hitbox and a 60-stud range limit), **Heal** (Rare: +10 HP), **Black Hole** (Epic: sucks enemies in, traps them for 3 seconds, 10 damage over time), **Turret** (Legendary: a 30-HP turret that shoots the nearest enemy player).
- **Wins leaderboard** (`LeaderboardService`): Wins and Coins in the player list, a Most Wins board, and a gold/silver/bronze podium in the hub where the server's top 3 players stand as their avatars.
- **Spellbook kiosk uses the Grimoire model**, open on a lectern (plain-shape fallback without it).
- **Semantic layer for AI agents:** `CLAUDE.md`, `docs/semantic/features.yaml` (every feature's files, remotes, data, invariants), and `docs/ECONOMY.md`.
- Admin `;coins`, `;wins`, `;crate`; Studio debug through `ServerStorage.WordcraftDebug:Invoke(...)` (`coins`, `wins`, `crate`, `state`).
- New rarity tier **Uncommon** (▲, green). The Legendary glyph is now 👑 (✦ didn't render in Roblox's font); the coin icon is 💰.

### Removed (coins, crates, wins podium)
- **Levels and XP** (`LevelCurve`, `ProgressionService`): no level bar, level-up banner, or XP rewards. Profiles migrate to schema 2 (XP and level dropped, quests re-rolled).
- **35 spells.** Only Fireball, Water Lock, and Rock Wall remain from the old dictionary; the Movement and Summon archetypes stay in code for future spells.
- The session knockouts board (replaced by the wins board).

### Changed (coins, crates, wins podium)
- `ProgressionService` is now `EconomyService`, the only writer of coins and wins.
- Draft rarity weights are 50 / 25 / 15 / 8 / 2, and a draft card falls back to a higher tier when every spell of its tier is already in your spellbook.
- Bolts, placeables, zones, and buffs can name an imported model in `visual.model` (Turret's body, Black Hole's swirl, Zap's strike, Heal's pop-up, Gust's bolt).

### Added (team boxes, 3v3, Sparring Arena map)
- **Team boxes in the hub** for 1v1, 2v2, 3v3 and 4v4. Each has a Blue side and a Red side with one spot per teammate. Standing on a side picks your team, and the labels show how full it is (`BLUE 1/2`). When both sides are full, a 5-second countdown runs (it restarts if anyone steps off or swaps), then the match starts with exactly those teams (`MatchService.startMatch(..., { teams })`).
- **3v3 mode**, with the Play menu and the admin `;startmatch` updated.
- **Sparring Arena is now a match map** (`Maps/SparringArena.luau`), weighted ×2 for 1v1 and 2v2 and never picked for 4v4. Invisible walls keep players on its floor.

### Changed (team boxes, 3v3, Sparring Arena map)
- **Rock Wall is 1.6× bigger:** 23 × 12.4 × 9.7 studs (it was 14.4 × 7.7 × 6.1).
- **The old queue pads for 1v1, 2v2 and 4v4 are replaced by the team boxes.** FFA keeps its pad, and the Play menu still queues for every mode.
- **The Sparring Ring/Arena is gone from the hub**, and so is hub PvP, since the ring was its only place.

### Removed
- The brick wall in the hub's Practice Grove.
- The starter Baseplate and SpawnLocation from the place (the hub and arenas are built at runtime, so press Play to see them).

### Changed (wall + Fireball)
- **Every spell hits the Rock Wall, your own included** (`HitByAll`), where before your own spells passed through your own structures.
- **The Rock Wall takes 50 damage in total** (it was 150), shared across its pieces: the base breaks first, then the rubble, then the stones, and the whole wall is gone at 50.
- **Bigger Fireball hitbox:** radius 2 → 3.5 (it now hits from up to 5 studs off-center), with the visual enlarged from 2 to 3.2 studs to match.

### Added (3D models)
- **Imported models** (`assets/models`, prepared by `tools/prepare-models.luau`, stored in `ReplicatedStorage.Models`) for the Fireball, Water Lock, Rock Wall, and the sparring arena. All fall back to plain shapes if the models aren't in the place.
- **Fireball** and **Water Lock** bolts are drawn with the models (the fireball trails its tail behind it).
- **Water Lock** now wraps its victim in a glassy bubble (before, only area-style crowd control showed one).
- **Rock Wall** is a sculpted earth wall (standing stones, base, rubble). Its three pieces break separately. The placement ghost shows the real model.
- **Sparring arena:** a marble-pillared, sandstone-seated colosseum with a neon rune ring replaces the red mat. It has four entrances, and its floor lines up with the 50×50 PvP zone.
- `tests/Models.spec.luau` checks the models when they're present.

### Fixed (3D models)
- Placement checks now use real collision shapes (`GetPartsInPart`), so large hollow meshes no longer block everything inside their bounding box.

### Added (round 3)
- **Stackable hotbar:** hold up to 5 spell copies in any mix, including 5 of the same spell. Copies of the same spell share one cast cooldown, and casting readies the next copy automatically.
- **Breakable blocks:** Rock Wall (3×2) and Castle (5×3) are grids of separately breakable blocks. There are brick, ice, and cloud block walls in every arena, plus a self-rebuilding practice wall in the hub. Blocks darken as they're damaged, chip on hits, and shatter into chunks.
- **Spell VFX:** each spell's bolt gets themed trails and particles (fire, sparks, ice, water, wind), plus impact bursts with a light flash and shockwave. Every cast plays an arm-raise animation and a magic circle. Zones and slams send out shockwave rings, and placed objects kick up a dust ring as they rise.
- **Health:** a HUD health bar with shield overlay and damage trail, overhead health bars (team-colored in matches), and Roblox's default health display hidden.
- **No regen in arenas:** the default regen script is replaced, and the hub regenerates 5 HP/s.
- **Settings panel (⚙):** rebind the "type a spell" key, saved to the profile. Reserved keys are refused.
- **Match presentation:**
  - VS intro with avatars, then a fade into the arena
  - 3-2-1-FIGHT countdown
  - round banners
  - VICTORY (confetti) / DEFEAT / DRAW screen with an XP count-up
  - KO pop-ups and a level-up banner
- **Custom join loading screen** with tips.

### Changed (round 3)
- **Every player has 100 HP** and moves faster (walk speed 24, jump power 55).
- **Faster projectiles:** speed ×1.5 (`PROJECTILE_SPEED_SCALE`).
- **Bigger hitboxes:** +1.5 studs against players and breakables (`HITBOX_BONUS`), and area spells reach 1.5 studs further against players.
- **Cooldowns are cast cooldowns:** each spell's `cooldown` now applies to casting, not typing. Fireball is 0.9s, Spark and Crate 0.5s.
- **No one-shots:** a new balance rule caps any single hit at 34 damage.

### Added
- **Copy model:** typing (or saying) a spell word grants one copy of that spell, never more than one per spell. Casting uses the copy up, so you re-type to recast. Each round starts empty-handed.
- **1-second typing cooldown** across chat, the spell box, and voice, with a draining bar under the spell box.
- **Paste blocking** in the spell box.
- **Floating damage numbers** everywhere: yellow damage, blue shield absorbed, green heals. Only the attacker and the target's owner see them.
- **Spellbook and recharge chips** above the spell box. The hotbar shows held copies, with a "type!" hint in the first empty slot.
- **Admin commands** with the `;` prefix (`AdminService`, `docs/ADMIN.md`): give, unlock, xp, level, heal, kill, god, speed, freecast, tp, bring, hub, startmatch, endmatch, clear, knockback, status, announce (filtered), kick, ban, unban.
- `tests/Balance.spec.luau`: per-spell budgets for damage, healing, shields, and crowd control under ~1s recasts.

### Changed
- **Rebalanced every spell for ~1s recasts.**
  - `cooldown` is now each word's recharge after casting: 0–2s for commons, 10s or more for legendaries.
  - Per-cast numbers are lower. For example, Fireball does 16 damage, Rock Wall has 140 HP, and Meteor does 30.
- **Hard crowd control can't be chained.** Root, Time Stop, and Shrink can't be refreshed and leave 2.5s of immunity.
- **Shields don't stack.**
- **Live caps:** lingering zones and summons are limited to one per player per spell.

### Changed (earlier)
- **Knockback, pulls, traps, and ring-outs are now server-authoritative.** The server briefly takes network ownership of the victim and applies the velocity itself. Self-beneficial movement (dash, balloon, pads) still runs on the client for responsiveness.
- **Projectiles run in one batched, error-guarded server loop** with no server Parts. Clients render bolts, debris poofs, chain beams, and zone spins from a new `Fx` remote.

### Fixed
- Profile locks are released when a player leaves mid-load, and stale locks expire after 5 minutes instead of 30.
- Players are released only once at shutdown.
- FFA teams now use UserIds, so duplicate display names no longer merge teams.
- Overlapping Shield casts no longer expire early.
- A quick voice re-press no longer ends the new session.
- The queue and slot remotes are rate-limited.
- Summons must be placed inside build areas.
- Debounce tables use weak keys.

## [0.1.0] — 2026-10-24

### Added
- Word-to-spell casting through chat, an on-screen spell box, push-to-talk voice (AudioSpeechToText), and hotbar taps.
- A 40-spell dictionary across 10 levels and 7 archetypes (Projectile, Control, Placeable, Zone, Buff, Movement, Summon), with aliases and typo tolerance.
- A placement ghost preview with valid/invalid tinting, plus destructible objects with health bars.
- Best-of-3 matches in 1v1, 2v2, 4v4, and FFA. Players start with 3 random owned spells and draft +1 per round (max 5) from cards with independently rolled rarities.
- The Inkwell Plaza hub (queue pads, Practice Grove, Sparring Ring, Spellbook, Daily Quests, leaderboard) and 3 arenas: Crayon Canyon, Frostbite Fortress, Sky Islands.
- Progression to level 10, a daily login streak, daily quests, and a first-win bonus.
- Session-locked DataStore profiles with autosave and BindToClose.
- Cross-platform input: keyboard/mouse, gamepad, touch, and VR.
- A dependency-free test runner with WordMatcher, LevelCurve, Rarity, and DraftRoller specs.
- Documentation: game design, architecture, spells, controls, and contributing.
