# Architecture

A Rojo project in `--!strict` Luau. The server is authoritative for everything. Clients send intent only (a drawn stroke, an aim point, a placement rotation, a boost pick, a crate id, an element id), and the server re-validates all of it.

For a machine-readable map of every feature (files, remotes, data, invariants), see [`docs/semantic/features.yaml`](semantic/features.yaml). Coins, crates, wins, and the podium are in [ECONOMY.md](ECONOMY.md).

## Layout

```
src/shared  → ReplicatedStorage.Shared      pure data + logic used by both sides
  Config.luau                 all tunables (timers, coins, limits, modes)
  Types.luau                  shared types (SpellDef, Profile, MatchState…)
  Net/Remotes.luau            the one registry of every RemoteEvent
  Spells/SpellDefinitions     the 8-spell dictionary (data only)
  Spells/Glyphs               the 8 drawable shapes (single strokes)
  Spells/GlyphRecognizer      stroke → glyph id ($1 unistroke recognizer)
  Spells/WordMatcher          admin spell names → spell id
  Audio/Cues                  every sound by name (asset ids, volume, pitch)
  Audio/Music                 the background music tracks (hub and fight playlists)
  ModelKit                    reads a model by name: the place's imported meshes, else a block model
  Models/BlockModels          GENERATED: every blocky model as plain data (tools/blender/block_models.py)
  Spells/SpellRegistry        per spell: model, particle style, cast pose, Fx events, sounds (the presentation registry)
  Spells/VfxStyles            particle styles per spell + buff auras
  Spells/CastPoses            the cast animations as data (arm and body poses)
  UI/GlyphView                draws a glyph as a line (HUD, signs, VFX)
  Spells/Elements             the 4 elements: 3 base spells and a price each
  Spells/Rarity               Common..Legendary: crate odds and duplicate refunds
  Spells/Loadout              base spells + 2 crate spells; one shape per spell
  (Spells/Glyphs              the shapes and Glyphs.ROLE, the shape for each kind of move)
  Spells/Placement            placement rules shared by ghost preview + server
  Match/Boosts                the match boosts + roll/totals (injectable RNG)
  Economy/Crates              the Spell Crate gacha: price, roll() of a rarity then a spell (injectable RNG)
  Util/Signal                 tiny module-to-module event

src/server  → ServerScriptService.Server    (init.server.luau bootstraps)
  Services/
    PlayerDataService   session-locked DataStore profiles, autosave, BindToClose
    EconomyService      coins, wins, daily login/quests, first win, settings (only writer of coins/wins)
    StatusService       timed effects (Root, Slow, Shrink, TimeStop, Slippery, buffs)
    DestructibleService single damage path, health bars, knockouts, push
    HandService         held spell copies (one per spell, up to 5), match spellbook, readied slot, per-spell cast cooldowns
    DashService         the dash: validates the cooldown and state, tells the client which way to go, fires the dash Fx
    CastService         validates casts, builds CastContext, dispatches archetype
    Archetypes/*        Projectile, Control, Placeable, Zone, Line, Buff, Movement, Summon
    SpellInputService   DrawSpell remote → draw gate (fights and the Training Grove) → validate → 1s draw cooldown → GlyphRecognizer → HandService.grant (+ the chat hook for admin commands)
    AdminService        ";" admin commands (chat), server-side admin check
    ArenaService        builds map templates, summons instanced arenas below the hub island, jump pads
    MatchService        queues, round state machine, boost drafts, teams, PvP rules
    HubService          builds the hub, spawning, team boxes, dummies, hub regen and passive regen
    BattlegroundService the drop-in Battleground: portal/gate pads, random-spot teleports, respawns, no queue while inside
    NpcService          Battleground NPCs: bodies, AI, aggro that sticks to whoever hit them, coin rewards, respawn at NpcSpot parts
    MapVoteService      the pre-duel map vote (MatchService.startMatch waits on it)
    PartyService        parties (invites, leader, PartyId attribute); party mates are allies in the Battleground
    ElementService      owns profile.elements/element/spells/loadout: free first pick, buy, equip, crate spells, loadout
    BoostService        per-match boost picks: max health, speed, damage, cooldowns, Health Potion
    CrateService        OpenCrate: validate, spend coins, roll an unowned element, grant it
    LeaderboardService  leaderstats (Wins, Coins), Most Wins board, top-3 podium avatars
    DebugService        Studio-only test commands (ServerStorage.SpellcraftDebug BindableFunction)
  Maps/                 MapKit + one builder per map (code-built, versioned)

src/client  → StarterPlayerScripts.Client   (init.client.luau bootstraps)
  Controllers/
    ClientState         mirror of server state + change signals
    HudController       hotbar, glyph cards, coins/wins wallet, match bar, toasts, feed
    MenuController      Play / Spellbook / Crates / Quests panels
    CrateController     Crate Shop panel + spin reel (animates the server's result)
    DraftController     boost draft cards
    PlacementController ghost preview
    ReticleController   hit circle + range ring for point-and-click spells (Fire Pillar, Water Nebula, Earth Punch)
    InputController     per-device bindings + aiming (mouse, pad, touch, VR)
    EffectsController   self boosts, slippery friction, team outlines, camera reset
    FxController        dispatches Fx events (bolts, impacts, cast anim, glyphs, shatter, chips, dust, numbers, element pillars, rising rocks, earthquake)
    HealthController    own HP bar (shield + damage trail), overhead bars, hides Roblox health
    SettingsController  Settings panel: rebind the draw key, switch the background music on or off (saved to profile)
    DashController      the dash: Q / B / Dash button, cooldown display, moves your own character when the server allows it
    SpectateController  watch another player: player list panel, a Previous/Next/Stop bar, camera follows the target
    MobileController    on touch-only devices in a fight, hides the menu, wallet, party, feed, and boost GUIs
    SupportController   Like & Favourite panel: the one-time thank-you gift (honor system, server-checked)
    AudioController     sound cues, hub ambience, and the background music playlists (muted by the Music setting)
    PresentationController  VS intro, fades, 3-2-1-FIGHT, round banners, Victory/Defeat (+coins), KO
  Fx/SpellVfx           bolt trails, impact bursts, buff auras, model columns/boulders/cracks, magic circle
  Fx/CastAnimations     plays a spell's cast pose as a runtime KeyframeSequence through the Animator
  UI/Theme              the studded-Roblox look: studded pastel panels and buttons, bevels, dark ink text

## Block models (the classic blocky look)

Everything that isn't an imported mesh is a **block model**: a handful of plain, chunky Parts in the classic Roblox style (spell effects, trees, cactus, training dummy, Element Crate, quest chest, wizard statue). They are authored once, in `tools/blender/block_models.py` (a Python spec of blocks with positions, sizes, colours, and materials), and that spec produces two things:

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
| `TreeOak`, `TreePine`, `TreeBirch`, `Cactus` | Battleground and hub scenery |
| `TrainingDummy` | The Training Grove dummies (`HubService.spawnDummy`; parts `Body` and `Head` are the hit parts) |
| `ElementCrate`, `ElementCrateOpen` | The Crate Shop crate (closed); the open one is for reveals |
| `QuestChest`, `QuestChestOpen` | The Daily Quests chest on the plaza (closed); open for rewards |
| `WizardStatue` | The center of the Sparring Arena (`Maps/SparringArena.luau`) |

## Imported 3D models

Hand-made models (`assets/models/*.fbx`) are imported in Studio, scaled and coloured by `tools/prepare-models.luau`, and stored **in the place** under `ReplicatedStorage.Models`. `src/shared/ModelKit.luau` is the only reader. Because the place file isn't part of the Rojo project, every use falls back to plain shapes when a model is missing. See `assets/models/README.md`.

| Model | Where it's used |
|---|---|
| Fireball | `FxController` bolt (Fireball); particles and trail attach to its invisible `Root` part |
| WaterBubble | `FxController` bolt (Water Lock) and `TrapBubble`, welded around a trapped player and scaled to 1.5× their height |
| RockWall | `Placeable.buildModelWall`: each mesh part is its own chunk, all sharing one 35-damage budget (`WallHealth` on the wall; chunks break at `BreakAt` thresholds, low pieces first; `DestructibleService.damageWall`). Chunks carry `HitByAll`, which makes `canHarm`/`damage` skip the owner and team rules, so every spell hits the wall. The placement ghost shows the model |
| Grimoire | The hub's Spellbook kiosk (`Maps/InkwellPlaza.luau`), open on a lectern |
| Gust | `FxController` bolt (Gust, Whirlwind) |
| Crate | The hub's Crate Shop (the Element Crate, trim and gem tinted gold) |
| Arena | `Maps/SparringArena.luau`, a match map (not in the hub). The floor top is the model's pivot, so the map's floor is at y = 0. An invisible wall ring (radius 24.2 x the 4 `SCALE` the arena is built at, `CanQuery` off so spells pass) keeps players on the floor, because the seating has no ground and its gaps drop into the void |

Placement overlap tests use `GetPartsInPart` with a parentless probe part. `GetPartBoundsInBox` only tests bounding boxes, so the arena's hollow ring meshes would have blocked every placement inside them.

src/character → StarterPlayer.StarterCharacterScripts
  Health.server.luau    empty: replaces Roblox's default regen (HubService does the regen)

src/loading   → ReplicatedFirst.LoadingScreen
  LoadingScreen.client  custom join screen (title, tips, progress) until the HUD exists
tests/      → ServerScriptService.Tests     Runner + *.spec modules
tools/      studio-sync.js / .luau          fallback sync without the Rojo CLI
```

## Bootstrapping

Both entry points use the same two phases, in a fixed order:

1. `init()`: create state and look up remotes. No yielding cross-service calls.
2. `start()`: connect events and start loops (each runs in `task.spawn`).

`Players.CharacterAutoLoads = false`. Spawning is explicit: `MatchService.spawnInHub`, `spawnRound` for arenas, or `MatchService.teleport`/`respawnAt` for the Battleground. Dead players therefore stay out until the next round instead of popping back into the hub.

Some dependencies would form a cycle, so they're injected instead of required:

- `DestructibleService.setRelationResolver(fn)`: MatchService decides who may damage whom.
- `CastService.setWorldHooks(hooks)`: MatchService supplies the team, the structures folder, and the build regions.

## Cast pipeline (copy model)

```
client: stroke ──DrawSpell──► SpellInputService
                               ├ validate (≤200 Vector2, finite, in range)
                               ├ 1s draw cooldown (per player)
                               └ GlyphRecognizer → glyph → spell → HandService.grant
                                    ├ match: in spellbook? hub: owned?
                                    ├ hotbar full (5)? → refuse
                                    └ add ONE copy (refused if you already hold that spell) and ready it
client: aim  ──CastSpell───► CastService
                               ├ alive? not frozen/time-stopped?
                               ├ readied slot holds a copy; global lockout 0.35s;
                               │  that spell's SHARED cooldown is over
                               ├ clamp target to range (placeables: 40 studs)
                               ├ build CastContext {team, structures, buildRegions, enemiesNear…}
                               ├ Archetypes[def.archetype].cast(ctx)  → false = rejected, copy kept
                               ├ HandService.consume (that copy used up; next copy of the same spell readied)
                               ├ HandService.startCooldown(def.cooldown) — shared by every copy
                               └ Fx("cast") → every client plays the arm raise + magic circle
```

- **Projectile hit tests:** each bolt sweeps a thin sphere (0.75) against the world, so it glides over floors. A second, fatter sweep (radius + `Config.HITBOX_BONUS`) sees only characters and breakables the caster can hurt. The nearest hit wins. Breakables are fetched once per frame and pre-filtered by distance.
- **Breakable blocks:** `segments` in a placeable's stats builds a grid of separately breakable blocks under an untagged parent Model, which deletes itself when empty. `DestructibleService` darkens damaged parts (`BaseColor` attribute), sends `Fx("chip")` on hits, and sends `Fx("shatter")` per part on break. Arenas use `MapKit.blockWall`.
- **Match presentation:** `MatchState` carries `roster`, `roundWinner`, `winner`, `won`, and `coinsGained`. A new `Intro` phase (`Config.INTRO_TIME`) plays the VS screen while players are still in the hub. Clients fade to black just before each teleport.

- **Drawing** is recorded by `DrawController` (mouse, touch, or the right stick) in screen-height units and sent once, when the stroke ends. The server never trusts the client's verdict: `GlyphResult` is feedback only. Admin chat commands (`;`) still travel through chat, handled by `SpellInputService`'s `ShouldDeliverCallback`.
- **Audio and mood:** `AudioController` plays cues by name (`Audio/Cues`, spells point at theirs with `sfx`), places them in the world with falloff, and runs the hub ambience. `LightingController` fades between the hub's warm afternoon light and the arenas' neutral daylight on the client only.
- **Damage numbers:** `DestructibleService.damage` and `heal` send `Fx("number", position, amount, kind)` to the attacker and the target's owner only. `FxController` draws them.
- **Crowd-control immunity:** `StatusService.apply` refuses to refresh an active Root, Time Stop, or Shrink, and adds a 2.5s immunity after it ends (`Config.CC_IMMUNITY`).

- **Damage** always goes through `DestructibleService.damage(target, amount, attacker, spellName)`. It resolves players, placed objects, summons, and map props the same way, and applies spawn protection, the attacker's damage multiplier (Fire Boost, the Power boost), and the defender's protections: Water Body (Invincible) takes no damage or effects, an Air Shield (Barrier) blocks one hit, and the generic Shield, Shrink/Giant, and Revive modifiers.
- **Knockback is server-authoritative.** `DestructibleService.push` briefly takes network ownership of the victim's root (`SetNetworkOwner(nil)`), sets the velocity on the server, and returns ownership after 0.45s. Overlapping pushes extend the hold. A client that ignores remotes still gets knocked back, pulled, tripped, and rung out.
- **Self-beneficial movement** (Dash, Balloon, bounce pads, jump pads) uses `DestructibleService.boost`, which the owner's client applies through the `Impulse` remote for responsiveness. Skipping a boost only hurts the cheater.
- **Projectiles** are server-simulated sphere-casts in **one shared Heartbeat loop** (`Archetypes/Projectile.luau`), capped at 300 in flight. Each step is `pcall`-guarded, so an error ends that projectile instead of leaking it. The server creates **no Parts** for them. It fires one `Fx("projectile", …)` event at launch and one `Fx("projectileEnd", …)` at impact, and clients (`FxController`) draw the bolt along the same line. Projectiles pass through your own and allied structures and bounce off Mirror.
- **Cosmetic effects** (debris poofs, beams, element pillars, rising boulders, the earthquake wind-up, glyph emblems) are all rendered client-side from `Fx` events or the `SpinFx` tag. Clients skip effects more than 900 studs away (`FxController.DRAW_DISTANCE`), so far-apart arenas don't draw each other's effects, yet the hub's rim still sees the duels below it.

## PvP rules (`MatchService.relation`)

| Situation | May damage? |
|---|---|
| Both in the same match, round active, different teams | ✅ |
| Same team / different matches / draft or countdown | ❌ |
| Hub (no PvP there) | ❌ |
| Training dummies | ✅ always |
| Map props | ✅ only by players in that arena's match |

## Matches and arenas

- **One place, instanced arenas, summoned below the hub.** Templates are built once into `ServerStorage.MapTemplates`. Each match clones one to `ArenaService.slotOrigin(slot)`: `Config.ARENA.Y` (-300) studs, on a ring of `Config.ARENA.PER_RING` (8) slots `Config.ARENA.RADIUS` (380) studs from the hub's axis (further rings step out by `RING_STEP`). The hub is a floating island over open ocean, so players on its rim look down and watch the fights; each arena model is `ModelStreamingMode.Persistent` and carries a `SpectatorSign` billboard ("⚔ 1v1 · Frost Hollow"). Each round, `ArenaService.rebuild` swaps in a fresh copy, which restores broken props.
- **The arena contract** is documented in `Maps/MapKit.luau` (`Bounds`, `Spawns/Team1_*`, `Team2_*`, `SmallModeWalls`). There are **8 duel maps**: Crayon Canyon, Sky Islands, Sparring Arena, Frost Hollow, Ember Forge, Moss Ruins, Tidal Temple, Sky Bridge. Maps are registered in `ArenaService.MAP_NAMES` (and `DISPLAY_NAMES`, which feeds the vote screen), with per-mode weights in `pickMap`. `MapKit` has the shared builders (`disc`, `pillar`, `barrierRing`, `underside`, `tree`, `blockWall`).
- **Team boxes** (`HubService.updateBoxes`, every 0.25s): the hub builder tags each side of a box `TeamPad` (`Box`, `Mode`, `Team`, `Slots` attributes; `Box` is the box's id, so a mode can have several boxes: there are two for 1v1 and for 2v2). The service collects who stands on each pad (sticky arrival order, capped at `Slots`), updates the labels, and, once both sides are full, runs a `Config.TEAM_BOX_COUNTDOWN` that restarts if anyone steps off or swaps. It then calls `MatchService.startMatch(mode, players, { teams = {...} })`, where `teams` maps each player to "Blue" or "Red". `Slots` is re-read every tick, so a pad can be resized live.
- **To move matches to reserved servers later:** keep MatchService's state machine and replace `ArenaService.create` / `spawnAt` with `TeleportService:ReserveServer` and a match place that reads its mode from `TeleportData`.

## Data

The profile (`Types.Profile`, schema 4: `coins`, `elements`, `element`, `stats`, `daily`, `settings` (`drawKey`, `music`), `rewards` (`likeFav`); no XP or level) is stored under `PlayerProfiles_v1/u_<userId>` as `{ data, lockJobId, lockTime }`.

- **Load:** `UpdateAsync` takes the lock if it's free, ours, or stale (> 30 min). Otherwise it retries with backoff, and finally kicks the player instead of risking a dupe.
- **Save:** autosave every 90s, release on leave, and flush in `BindToClose`. A save never overwrites a lock owned by another server.
- **Studio without API access:** the player gets a temporary profile that is never saved, with one retry.
- **Migrations:** `reconcile()` fills in new fields. Bump `SCHEMA` and transform there for breaking changes. 1 to 2 dropped `xp`/`level`, re-rolled quests (they paid XP), dropped spell ids that no longer exist, and guarantees the starters. 2 to 3 dropped `ownedSpells` for `elements`/`element` (players pick their first element again).

## Security checklist

- Every remote handler type-checks its arguments (`typeof`, NaN and range checks, string length limits).
- Drawings are limited to one per second, at most 200 points each, every coordinate finite and within `Config.DRAW_MAX_COORD`.
- Debug commands only run when `RunService:IsStudio()`.
- Admin status is decided server-side on join (UserId list, place or group owner, or Studio). A non-admin's `;` message is delivered as plain chat. Commands run in their own thread and are logged.
- `;announce` text goes through `TextService:FilterStringAsync` before broadcast.
- The client never reports damage, hits, cooldowns, ownership, or coins. It only sends intent.
- `OpenCrate` is refused mid-match, before your first element is picked, and while a spin is running (4s); the server rolls, spends, and saves before the client's reel starts. `ChooseElement` is refused mid-match.
