# Architecture

A Rojo project in `--!strict` Luau. The server is authoritative for everything. Clients send intent only (a drawn stroke, the point under the first-person crosshair, a placement rotation, a boost pick, a chest id, an element id), and the server re-validates all of it.

For a machine-readable map of every feature (files, remotes, data, invariants), see [`docs/semantic/features.yaml`](semantic/features.yaml). Coins, chests, wins, and the podium are in [ECONOMY.md](ECONOMY.md).

## Layout

```
src/shared  → ReplicatedStorage.Shared      pure data + logic used by both sides
  Config.luau                 all tunables (timers, coins, limits, modes)
  Types.luau                  shared types (SpellDef, Profile, MatchState…)
  Net/Remotes.luau            the one registry of every RemoteEvent (with a payload note each)
  Spells/SpellDefinitions     the 24-spell dictionary (data only)
  Spells/Glyphs               the 12 drawable shapes (single strokes) and Glyphs.ROLE, the shape for each kind of move
  Spells/GlyphRecognizer      stroke → glyph id + score ($1 unistroke recognizer)
  Spells/Quality              recognizer score → drawing quality → stat multipliers and star tiers
  Spells/WordMatcher          admin spell names → spell id
  Spells/Elements             the 4 elements: 3 base spells and a price each (+ the Arcane school)
  Spells/Rarity               Common..Legendary: chest odds and duplicate refunds
  Spells/Loadout              base spells + 2 chest spells; one shape per spell
  Spells/Placement            placement rules shared by ghost preview + server
  Spells/SpellStats           the numbers shown for a chest spell (damage/heal, cooldown, duration, range)
  Spells/SpellRegistry        per spell: model, particle style, cast pose, Fx events, sounds (the presentation registry)
  Spells/VfxStyles            particle styles, hit kinds, and buff auras per spell
  Spells/CastPoses            the cast animations as data (POSES, BEATS, SWELLS, the dash flip)
  Audio/Cues                  every sound by name (asset ids, volume, pitch, layered `with`)
  Audio/Music                 the background music tracks (hub and fight playlists)
  ModelKit                    reads a model by name: the place's imported meshes, else a block model
  Models/BlockModels          GENERATED: every blocky model as plain data (tools/blender/block_models.py)
  UI/GlyphView                draws a glyph as a line (HUD, signs, VFX)
  Match/Boosts                the match boosts + roll/totals (injectable RNG)
  Economy/Chests              the Chest Shop gacha: price, pity, roll() of a rarity then a spell (injectable RNG)
  Battleground/Npcs           the Battleground NPC types (health, speed, attacks, reward, look)
  Admin/Catalog               the Admin panel's tabs and buttons (each one a command string)
  Analytics/Funnels           onboarding and match funnel step names (pure data)
  Util/Signal                 tiny module-to-module event
  Util/Ballistic              launch velocity for an arc that lands on a point (rescues)
  Util/Pit                    is a point walled in by terrain on every side (pit rescue)
  Util/PracticeZone           is a position inside a Training Grove (the hub's draw zone)
  Util/WandAir                wand geometry: the grip in the hand, the air canvas (upright, facing the drawer), screen/glyph points -> studs, checks for relayed stroke data

src/server  → ServerScriptService.Server    (init.server.luau bootstraps)
  Services/
    PlayerDataService   session-locked DataStore profiles, autosave, BindToClose
    TelemetryService    analytics funnels, coin flows and custom events to AnalyticsService (never touches a profile)
    EconomyService      coins, wins, daily login/quests, first win, settings, tutorial flag, Like & Favourite gift (only writer of coins/wins)
    StatusService       timed effects (Root, Slow, Shrink, TimeStop, Slippery, buffs)
    DestructibleService single damage path, health bars, knockouts, push
    SpellbookService    which spells a player can draw (match spellbook, else loadout), per-spell cast cooldowns and the global lockout
    DashService         the dash: validates the cooldown and state, tells the client which way to go, fires the dash Fx
    WandService         welds every player's wand to the right hand, tints it with their element, keeps the Drawing / DrawLook attributes (DrawingState remote), relays live strokes to nearby players (AirStroke; cosmetic)
    CastService         casts a drawn spell at once: validates, resolves auto-aim, builds CastContext, dispatches archetype
    Archetypes/*        Projectile, Control, Placeable, Zone, Line, Buff, Movement, Summon
    SpellInputService   DrawSpell remote → draw gate (fights and the Training Grove) → validate → 1s draw cooldown → GlyphRecognizer → CastService.cast (+ the chat hook for admin commands)
    AdminService        ";" admin commands (chat), server-side admin check
    ArenaService        builds map templates, summons instanced arenas below the hub island (with water under each), jump pads
    MatchService        queues, round state machine, boost drafts, teams, PvP rules, draw gate (canDraw), water/pit checks
    Rescue              water splash and pit rescue (called from MatchService's round loop)
    TrapBubble          Water Lock's bubble around a stunned victim
    HubService          builds the hub, spawning, team boxes, dummies, hub regen (no regen anywhere else)
    BattlegroundService the drop-in Battleground: portal/gate pads, random-spot teleports, respawns, no queue while inside
    NpcService          Battleground NPCs: bodies, AI, aggro that sticks to whoever hit them, coin rewards, respawn at NpcSpot parts
    MapVoteService      the pre-duel map vote (MatchService.startMatch waits on it)
    PartyService        parties (invites, leader, PartyId attribute); party mates are allies in the Battleground
    ElementService      owns profile.elements/element/spells/loadout: free first pick, buy, equip, chest spells, loadout
    BoostService        per-match boost picks: max health, speed, damage, cooldowns, Health Potion
    ChestService        OpenChest: validate, spend coins, roll a chest spell by rarity (with pity), grant it; only writer of profile.pity
    LeaderboardService  leaderstats (Wins, Coins), Most Wins board, top-3 podium avatars
    DebugService        Studio-only test commands (ServerStorage.SpellcraftDebug BindableFunction)
  Maps/                 MapKit, FlatArena (the flat duel board) + one theme per map (code-built, versioned)

src/client  → StarterPlayerScripts.Client   (init.client.luau bootstraps)
  Controllers/
    ClientState         mirror of server state + change signals (canDraw, inPractice)
    LightingController  warm hub light vs neutral arena daylight, hub haze
    HudController       spell cards (card N = Nth loadout spell), coins/wins wallet, match bar, toasts, feed
    PartyController     Party button and panel (invites, members)
    MapVoteController   the pre-duel map vote cards
    MenuController      Play / Spellbook (Elements, Loadout) / Chests / Quests panels
    ChestController     Chest Shop panel: five chests (3D previews), odds bars, pity, reel (animates the server's result)
    DraftController     boost draft cards
    PlacementController ghost preview while a placeable's shape is on the canvas; turns placeables side-on to you (+ R)
    ReticleController   hit circle + range ring while tracing point-and-click spells (Fire Pillar, Water Nebula, Earth Punch, Lightning, Black Hole)
    CameraController    first person everywhere; mouse look speed (settings.camera); frees the mouse while drawing; keeps your arm and wand visible except while drawing
    CursorController    the cursor key: tap Left Alt for one click, or hold it (rules in Util/CursorMode)
    CrosshairController the sight: one dot, shown over the canvas too; the cursor hint on keyboards
    WandController      raises every drawing player's wand (pose, tip glow, rune circle), writes your stroke in the air, traces other players' glyphs
    DrawController      the drawing canvas (blank or traced over a spell's guide): vignette, rune circle, banner, glowing ink, pen sparks, quality feedback
    InputController     per-device bindings; every device aims from the screen centre (VR: right hand), keys 1-5 open a spell's guide; no cast button
    EffectsController   self boosts, slippery friction, team outlines, camera reset
    FxController        dispatches Fx events (bolts, impacts, cast anim, glyphs, shatter, chips, dust, numbers, element pillars, rising rocks, earthquake)
    HealthController    own HP bar (shield + damage trail), overhead bars, hides Roblox health
    SettingsController  Settings panel: rebind the draw key, switch the background music, sound effects and screen shake on or off (saved to profile)
    AdminController     the Admin panel (admins only): targets, tabs of buttons from Admin/Catalog, command box, log
    JuiceController     game feel: camera shake, field-of-view kicks, hit markers, damage vignette, low-health pulse (called by the Fx, Presentation, Draw and Health controllers)
    DashController      the dash: Q / B / Dash button, cooldown display, moves your own character when the server allows it
    SpectateController  watch another player: player list panel, a Previous/Next/Stop bar, camera follows the target
    MobileController    on touch-only devices in a fight, hides the menu, wallet, party, feed, and boost GUIs
    SupportController   the hub gift box's prompt: the one-time Like & Favourite gift (honor system, server-checked)
    AudioController     sound cues (muted by the Sound effects setting), loops, and the background music playlists (muted by the Music setting)
    PresentationController  VS intro, fades, 3-2-1-FIGHT, round banners, Victory/Defeat (+coins), KO
    TutorialController  the first-join walkthrough (welcome, five guided steps, Skip)
  Fx/SpellVfx           bolt trails, impact bursts, swells, cast beats, buff auras, model columns/boulders/cracks, black hole vortex, magic circle
  Fx/CastAnimations     plays a spell's cast pose as a runtime KeyframeSequence through the Animator (stop() ends a held pose)
  Fx/WandVfx            the wand's 3D effects: tip glow + rune circle, the air ribbon and its beam, the absorb burst, the fizzle
  Fx/GuideArrow         the tutorial's world and GUI arrows, outlines, ground trail, edge pointer
  Fx/PropSwap           swaps a hub prop for its open block model for a moment (a shop chest, tinted to its rarity, while the reel spins; the quest chest on a claim)
  UI/Theme              minimal: flat near-black surfaces, one accent, hairlines, one typeface, buttons with auto-contrast text, pills
  UI/MouseLock          frees the first-person mouse (an invisible Modal button) while any window is shown, the canvas is open or the cursor key is used
  UI/Responsive         keeps every UIScale matched to the screen size
  UI/SpellCard          the spell card used by the Spellbook, chest reel, and loadout
  UI/Sigil              a spell's sigil: its shape in its colour on a small dark disc (HUD spell row, Spellbook, chest)

src/character → StarterPlayer.StarterCharacterScripts
  Health.server.luau    empty: replaces Roblox's default regen (HubService does the hub regen)

src/loading   → ReplicatedFirst.LoadingScreen
  LoadingScreen.client  custom join screen (title, tips, progress) until the HUD exists

tests/      → ServerScriptService.Tests     Runner + *.spec modules
tools/      studio-sync.js / .luau (sync without the Rojo CLI), blender/ (model specs),
            gen-spell-registry.py, prepare-models.luau, make-stud-texture.py, make-marketing-art.py
```

## Block models (the classic blocky look)

Everything that isn't an imported mesh is a **block model**: a handful of plain, chunky Parts in the classic Roblox style (spell effects, the Earth Wall, trees, cactus, training dummy, Element Chest, quest chest, wizard statue, the two hub portals, the wand; 28 in all). They are authored once, in `tools/blender/block_models.py` (a Python spec of blocks with positions, sizes, colours, and materials), and that spec produces two things:

- `src/shared/Models/BlockModels.luau` (generated, plain data). `ModelKit` builds a model from it the first time it's asked for, so block models exist in **every** place, including one built by CI, with no import step.
- `assets/models/blocks/<Name>.fbx` and `assets/models/source/BlockModels.blend`, the Blender versions (1 stud = 28 cm, forward = Blender +Y) for artists and for uploading meshes later.

`ModelKit.get(name)` checks the place's `ReplicatedStorage.Models` first (imported meshes), then the block models. Callers still fall back to plain shapes when it returns nil. To change a block model, edit the spec, run `python tools/blender/block_models.py --luau .` (Luau data) and `blender --background --python tools/blender/block_models.py -- .` (FBX + blend), and run the tests (`tests/Models.spec.luau` checks every model builds).

| Model | Where it's used |
|---|---|
| `FireSlash`, `WaterSlice`, `RockThrow`, `WaterWave`, `Tornado` | The bolt of that spell (`FxController` `onProjectile`) |
| `FireBoost`, `WaterBody`, `AirBoost`, `AirShield` | The emblem that pops over the caster's head (`Buff` → Fx `modelPop`) |
| `FirePillar`, `WaterNebula` | The column that erupts (`SpellVfx.pillar`) |
| `EarthPunch`, `EarthPillar` | The boulder or spike that rises (`SpellVfx.rise`) |
| `Earthquake` | Ground cracks spreading during the wind-up (`SpellVfx.quake`) |
| `Wand` | Every player's wand, welded to the right hand (`WandService`; the tip, halo and runes take the element colour) |
| `EarthWall` | The Earth Wall spell (`stats.model`): 33 rubble stones, each its own breakable chunk (`Placeable.buildModelWall`) |
| `TreeOak`, `TreePine`, `TreeBirch`, `Cactus` | Battleground and hub scenery |
| `TrainingDummy` | The Training Grove dummies (`HubService.spawnDummy`; parts `Body` and `Head` are the hit parts) |
| `ElementCrate`, `ElementCrateOpen` | The Chest Shop chest (closed); the open one is for reveals |
| `QuestChest`, `QuestChestOpen` | The Daily Quests chest on the plaza (closed); open for rewards |
| `WizardStatue` | The center of the Sparring Arena (`Maps/SparringArena.luau`) |
| `ArenaPortal` | The hub's red Arena Gate (the same portal, also into the Battleground) |
| `BattlegroundPortal` | The hub's stone portal into the Battleground (`Maps/InkwellPlaza.luau`) |

## Imported 3D models

Hand-made models (`assets/models/*.fbx`) are imported in Studio, scaled and coloured by `tools/prepare-models.luau`, and stored **in the place** under `ReplicatedStorage.Models`. `src/shared/ModelKit.luau` is the only reader. Because the place file isn't part of the Rojo project, every use falls back to plain shapes when a model is missing. See `assets/models/README.md`.

| Model | Where it's used |
|---|---|
| Fireball | `FxController` bolt (Fireball); particles and trail attach to its invisible `Root` part |
| WaterBubble | `FxController` bolt (Water Lock) and `TrapBubble`, welded around a trapped player and scaled to 1.5× their height |
| EarthWall (block model; the old imported `RockWall` mesh still works as an override placed in the place) | `Placeable.buildModelWall`: each mesh part is its own chunk, all sharing one 35-damage budget (`WallHealth` on the wall; chunks break at `BreakAt` thresholds, low pieces first; `DestructibleService.damageWall`). Chunks carry `HitByAll`, which makes `canHarm`/`damage` skip the owner and team rules, so every spell hits the wall. The placement ghost shows the model |
| Grimoire | The hub's Spellbook kiosk (`Maps/InkwellPlaza.luau`), open on a lectern |
| Gust | `FxController` bolt (Gust, Whirlwind) |
| Zap | Lightning's thunderbolt that slams down on the target (Zone Fx `strike`) |
| Heal | The emblem over the caster's head (Buff Fx `modelPop`) |
| BlackHole | The Black Hole swirl (`Archetypes/Zone.luau`; clients add the vortex Fx) |
| Turret | The Turret body (`Placeable` `skin()`; the primitive stays the hitbox) |
| Chest | The hub's Chest Shop (the Chest Shop, trim and gem tinted gold) |
| Arena | `Maps/SparringArena.luau`, a match map (not in the hub). The floor top is the model's pivot, so the map's floor is at y = 0. An invisible wall ring (radius 24.2 x the 4 `SCALE` the arena is built at, `CanQuery` off so spells pass) keeps players on the floor, because the seating has no ground and its gaps drop into the void |

Placement overlap tests use `GetPartsInPart` with a parentless probe part. `GetPartBoundsInBox` only tests bounding boxes, so the arena's hollow ring meshes would have blocked every placement inside them.

## Bootstrapping

Both entry points use the same two phases, in a fixed order:

1. `init()`: create state and look up remotes. No yielding cross-service calls.
2. `start()`: connect events and start loops (each runs in `task.spawn`).

`Players.CharacterAutoLoads = false`. Spawning is explicit: `MatchService.spawnInHub`, `spawnRound` for arenas, or `MatchService.teleport`/`respawnAt` for the Battleground. Dead players therefore stay out until the next round instead of popping back into the hub.

Some dependencies would form a cycle, so they're injected instead of required:

- `DestructibleService.setRelationResolver(fn)`: MatchService decides who may damage whom.
- `CastService.setWorldHooks(hooks)`: MatchService supplies the team, the structures folder, and the build regions.

## Cast pipeline (draw = cast)

Nothing is stored and nothing is clicked: a recognized drawing is cast in the same server step.

```
client: stroke + crosshair point + rotation ──DrawSpell──► SpellInputService
                               ├ validate (≤200 Vector2, finite, in range)
                               ├ draw gate; 1s draw cooldown (per player)
                               └ GlyphRecognizer (only SpellbookService.drawable's shapes) → glyph → spell → CastService.cast
                               ├ alive? not frozen/time-stopped/stunned?
                               ├ global lockout 0.35s; that spell's cooldown is over
                               ├ clamp target to range (placeables: Config.PLACE_RANGE, 20 studs)
                               ├ resolveAim: look dir (the sent point, or the facing if it's off by > MAX_YAW_ERROR);
                               │  self: ignored; placed/strikes/lines: sightPoint (first solid surface along it);
                               │  bolts: AutoAim.pick (closest to the sight, in plain sight), led (AutoAim.lead) → ctx.target, ctx.lock
                               ├ build CastContext {team, structures, buildRegions, enemiesNear…}
                               ├ Archetypes[def.archetype].cast(ctx)  → false = rejected, the drawing fizzles
                               ├ SpellbookService.startCooldown(def.cooldown)
                               ├ Fx("cast") → every client plays the cast pose, beat, swell + magic circle
                               └ GlyphResult to the drawer, Fx("glyph") to everyone (or glyphFail on any refusal)
```

- **The sight and the bolts' assist** (`shared/Util/AutoAim`, `Config.AUTO_AIM`): only bolts get an assist, and nothing on screen shows it. Candidates are enemy players, hostile NPCs and training dummies within the spell's range and inside the aim cone (`CONE` 15°, widening linearly to `CLOSE_CONE` 25° at point blank, and never narrower than the target's own angular size). They rank by how far off the sight they are (`angle / cone`), with `DISTANCE_WEIGHT` settling near-ties; line of sight is raycast only in rank order until one is visible. Bolts aim at the intercept with the target's motion (`LEAD` 0.8 of it, vertical speed damped by `LEAD_VERTICAL`, capped at `MAX_LEAD_SECONDS`) and home on the lock at `HOMING` °/s until it is more than `HOMING_GIVE_UP` off their heading. `ASSIST = false` turns it all off.

- **Aiming with no click:** the point under the crosshair is read when the stroke ends and travels with it. The canvas frees the mouse, so the camera holds still while you draw; on a gamepad the drawing stick is sunk (`DrawController`) so it can't swing the aim. The sight stays up over the canvas, and a traced spell also shows its hit circle or placement ghost. The server's `sightPoint` looks through characters and stops at the first solid surface, so nothing lands through a wall and a wall aimed past an opponent still lands. Your own arm, 3D circle and ribbon are hidden on your screen while you draw. Placeables default to side-on to you (`PlacementController.getRotation`, R turns them further).

- **Quality:** `SpellInputService` turns the recognizer's score into a quality (`Spells/Quality`) and passes it to `CastService`, which scales the spell's stats by it (`Quality.apply`).

- **Projectile hit tests:** each bolt sweeps a thin sphere (0.75) against the world, so it glides over floors. A second, fatter sweep (radius + `Config.HITBOX_BONUS`) sees only characters and breakables the caster can hurt. The nearest hit wins. Breakables are fetched once per frame and pre-filtered by distance.
- **Breakable blocks:** `segments` in a placeable's stats builds a grid of separately breakable blocks under an untagged parent Model, which deletes itself when empty. `DestructibleService` darkens damaged parts (`BaseColor` attribute), sends `Fx("chip")` on hits, and sends `Fx("shatter")` per part on break. Arenas use `MapKit.blockWall`.
- **Match presentation:** `MatchState` carries `roster`, `roundWinner`, `winner`, `won`, and `coinsGained`. A new `Intro` phase (`Config.INTRO_TIME`) plays the VS screen while players are still in the hub. Clients fade to black just before each teleport.

- **Drawing** is recorded by `DrawController` (mouse, touch, or the right stick) in screen-height units and sent once, when the stroke ends, with the crosshair's aim point. The server never trusts the client's verdict: `GlyphResult` is feedback only. Admin chat commands (`;`) still travel through chat, handled by `SpellInputService`'s `ShouldDeliverCallback`.
- **Audio and mood:** `AudioController` plays cues by name (`Audio/Cues`, spells point at theirs with `sfx`), places them in the world with falloff. `LightingController` fades between the hub's warm afternoon light and the arenas' neutral daylight on the client only.
- **Damage numbers:** `DestructibleService.damage` and `heal` send `Fx("number", position, amount, kind)` to the attacker and the target's owner only. `FxController` draws them.
- **Crowd-control immunity:** `StatusService.apply` refuses to refresh an active Root, Time Stop, or Shrink, and adds a 2.5s immunity after it ends (`Config.CC_IMMUNITY`).

- **Damage** always goes through `DestructibleService.damage(target, amount, attacker, spellName)`. It resolves players, placed objects, summons, and map props the same way, and applies spawn protection, the attacker's damage multiplier (Fire Boost, the Power boost), and the defender's protections: Water Body (Invincible) takes no damage or effects, an Air Shield (Barrier) blocks one hit, and the generic Shield, Shrink/Giant, and Revive modifiers.
- **Knockback is server-authoritative.** `DestructibleService.push` briefly takes network ownership of the victim's root (`SetNetworkOwner(nil)`), sets the velocity on the server, and returns ownership after 0.45s. Overlapping pushes extend the hold. A client that ignores remotes still gets knocked back, pulled, tripped, and rung out.
- **Self-beneficial movement** (the Movement archetype, bounce pads, jump pads, rescue arcs) uses `DestructibleService.boost`, which the owner's client applies through the `Impulse` remote for responsiveness. Skipping a boost only hurts the cheater.
- **Projectiles** are server-simulated sphere-casts in **one shared Heartbeat loop** (`Archetypes/Projectile.luau`), capped at 300 in flight. Each step is `pcall`-guarded, so an error ends that projectile instead of leaking it. The server creates **no Parts** for them. It fires one `Fx("projectile", …)` event at launch and one `Fx("projectileEnd", …)` at impact, and clients (`FxController`) draw the bolt along the same line. Projectiles pass through your own and allied structures (a `reflect` buff would send them back; no current spell has one).
- **Cosmetic effects** (debris poofs, beams, element pillars, rising boulders, the earthquake wind-up, glyph emblems) are all rendered client-side from `Fx` events or the `SpinFx` tag. Clients skip effects more than 900 studs away (`FxController.DRAW_DISTANCE`), so far-apart arenas don't draw each other's effects, yet the hub's rim still sees the duels below it.

## PvP rules (`MatchService.relation`)

| Situation | May damage? |
|---|---|
| Both in the same match, round active, different teams | ✅ |
| Same team / different matches / draft or countdown | ❌ |
| Hub (no PvP there) | ❌ |
| Both in the Battleground, not in the same party | ✅ |
| A Battleground player against an NPC (`Hostile`) | ✅ |
| Training dummies | ✅ always |
| Map props | ✅ only by players in that arena's match |

## Matches and arenas

- **One place, instanced arenas, summoned below the hub.** Templates are built once into `ServerStorage.MapTemplates`. Each match clones one to `ArenaService.slotOrigin(slot)`: `Config.ARENA.Y` (-300) studs, on a ring of `Config.ARENA.PER_RING` (8) slots `Config.ARENA.RADIUS` (560) studs from the hub's axis (further rings step out by `RING_STEP`). The hub is a floating island over open ocean, so players on its rim look down and watch the fights; each arena model is `ModelStreamingMode.Persistent` and carries a `SpectatorSign` billboard ("1v1 · Frost Hollow"). Each round, `ArenaService.rebuild` swaps in a fresh copy, which restores broken props.
- **Arena size and terrain:** every map is built at design size, then `MapKit.scale` enlarges it by `Config.ARENA_SCALE` (2) in `ArenaService.init`. Floors (every map's tiled board), the curbs and the pillars are `MapKit.terrain` cells (`Destructible` + `Terrain`), damaged by `DestructibleService.damageTerrain`: the hit cell takes the full damage, cells touching it take `Config.TERRAIN.SPLASH` of it, so stronger spells break more. Health is explicit, not multiplied: the baseplate (floor cells, `Config.TERRAIN.HEALTH.Ground`, 240) is very tough, while rock cells (45) and scenery (`Config.PROPS`) break in a few hits. Brick walls, cover blocks, trees, crayons and the other scenery are breakable too, with health from the `Config.PROPS` tiers (Light 25, Medium 45, Heavy 70, Brick 15). Only the hub and the rock undersides (`Underside`) stay solid; `tests/Terrain.spec.luau` fails if a map gains solid scenery that can't be broken. The next round clones a fresh arena (`ArenaService.rebuild`), which restores every cell.
- **Water and pits (`Services/Rescue`).** Every arena has a Water part under it (`Config.RESCUE.WATER_SURFACE`). `MatchService`'s round loop checks every 0.25s: a player below the surface is splashed (damage and a short stun) and thrown in an arc onto their spawn pad (`match.pads`); a player standing in a hole walled in by terrain cells on every side for 1.5s is thrown out over the rim. The arc is planned by `Ballistic`, checked for obstacles, and followed exactly by the client (`Impulse` remote with a hold). See the `rescue` entry in `docs/semantic/features.yaml`.
- **The arena contract** is documented in `Maps/MapKit.luau` (`Bounds`, `Spawns/Team1_*`, `Team2_*`, `SmallModeWalls`). There are **7 duel maps**: Crayon Canyon, Sparring Arena, Frost Hollow, Ember Forge, Moss Ruins, Tidal Temple, Sky Bridge. Maps are registered in `ArenaService.MAP_NAMES` (and `DISPLAY_NAMES`, which feeds the vote screen), with per-mode weights in `pickMap`. Every duel map is **flat**: a `FlatArena.Theme` (colours, materials, a round or rect board, walled or open, spawn distance, a cover layout for the Blue half that is point-mirrored for Red, optional decor) built by `Maps/FlatArena.build` (tile-painted floor with team halves and a centre mark, curb and underside, glowing spawn pads and edge lights, a small-mode ring). `MapKit` has the lower-level builders (`disc`, `pillar`, `barrierRing`, `underside`, `tree`, `blockWall`, `terrain` with a per-cell `paint`).
- **Team boxes** (`HubService.updateBoxes`, every 0.25s): the hub builder tags each side of a box `TeamPad` (`Box`, `Mode`, `Team`, `Slots` attributes; `Box` is the box's id, so a mode can have several boxes: there are two for 1v1 and for 2v2). The service collects who stands on each pad (sticky arrival order, capped at `Slots`), updates the labels, and, once both sides are full, runs a `Config.TEAM_BOX_COUNTDOWN` that restarts if anyone steps off or swaps. It then calls `MatchService.startMatch(mode, players, { teams = {...} })`, where `teams` maps each player to "Blue" or "Red". `Slots` is re-read every tick, so a pad can be resized live.
- **To move matches to reserved servers later:** keep MatchService's state machine and replace `ArenaService.create` / `spawnAt` with `TeleportService:ReserveServer` and a match place that reads its mode from `TeleportData`.

## Analytics (`TelemetryService`)

`TelemetryService` sends the funnel to Roblox's `AnalyticsService`: onboarding steps, a per-match funnel, a coin economy flow (sources and sinks) and a few custom events. Step names live in `Shared/Analytics/Funnels`. Other services call it (`EconomyService`, `ElementService`, `ChestService`, `SpellInputService`, `CastService`, `MatchService`, `BattlegroundService`, `Rescue`); it never touches a profile and every call is pcall-wrapped. View the results in the Creator Hub under Analytics. Never renumber an onboarding step that has shipped.

## Data

The profile (`Types.Profile`, schema 7: `coins`, `elements`, `element`, `spells`, `loadout`, `tutorial` (`done`), `cosmetics`, `stats`, `daily`, `settings` (`drawKey`, `music`, `sfx`, `shake`), `rewards` (`likeFav`), `pity`; no XP or level) is stored under `PlayerProfiles_v1/u_<userId>` as `{ data, lockJobId, lockTime }`.

- **Load:** `UpdateAsync` takes the lock if it's free, ours, or stale (> 30 min). Otherwise it retries with backoff, and finally kicks the player instead of risking a dupe.
- **Save:** autosave every 90s, release on leave, and flush in `BindToClose`. A save never overwrites a lock owned by another server.
- **Studio without API access:** the player gets a temporary profile that is never saved, with one retry.
- **Migrations:** `reconcile()` fills in new fields. Bump `SCHEMA` and transform there for breaking changes. 1 to 2 dropped `xp`/`level`, re-rolled quests (they paid XP), dropped spell ids that no longer exist, and guarantees the starters. 2 to 3 dropped `ownedSpells` for `elements`/`element` (players pick their first element again). 3 to 4 added `settings.music` and `rewards.likeFav`. 4 to 5 added `spells`, `loadout`, and `tutorial.done` (true for players who had already picked an element). 5 to 6 added `pity`. 6 to 7 moved `settings.camera` from the old 0.5 default to the new one. New settings keys (`sfx`, `shake`) come from the defaults without a bump.

## Security checklist

- Every remote handler type-checks its arguments (`typeof`, NaN and range checks, string length limits).
- Drawings are limited to one per second, at most 200 points each, every coordinate finite and within `Config.DRAW_MAX_COORD`.
- Debug commands only run when `RunService:IsStudio()`.
- Admin status is decided server-side on join (UserId list, place or group owner, or Studio). A non-admin's `;` message is delivered as plain chat. The Admin panel's `AdminCommand` remote is re-checked for admin status, length (200), and rate on every call. Commands run in their own thread and are logged.
- `;announce` text goes through `TextService:FilterStringAsync` before broadcast.
- The client never reports damage, hits, cooldowns, ownership, or coins. It only sends intent.
- `OpenChest` is refused mid-match, before your first element is picked, and while a chest is opening (4s), and for a chest whose every spell you own; the server rolls, spends, and saves before the client's reel starts. `ChooseElement` is refused mid-match.
