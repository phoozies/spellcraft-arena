---
name: add-map
description: How to add or change a duel map or the hub island in Spellcraft Arena (arena contract, MapKit helpers, registration, vote, spectating below the hub, tests). Use for any change under src/server/Maps or ArenaService.
---

# Adding a duel map

Maps are **code**, built once at startup into `ServerStorage.MapTemplates` and cloned per match by `ArenaService.create`.

## The arena contract (what `ArenaService` and `MatchService` rely on)

A map module is `return function(makeProp: (Instance, number) -> ()): Model`. It builds, with the **floor top at y = 0** around the origin:

- `Bounds`: an invisible Part (`MapKit.bounds`), the build and teleport region.
- A `Spawns` folder with `Team1_1..4` and `Team2_1..4` (`MapKit.teamSpawns(spawns, center, distance, y)`).
- A `SmallModeWalls` folder (may be empty; its walls show only for 1v1 and 2v2).
- Breakable cover: pass the part to `makeProp(part, health)`; `MapKit.blockWall` builds breakable brick walls.
- Optional jump pads: tag `JumpPad` with a `LaunchVelocity` attribute (see `SkyIslands`).
- No rim wall means ring-outs (the void is `Config.ARENA_VOID_DEPTH` below the origin); otherwise `MapKit.barrierRing(model, radius, height)`.

Use `MapKit.disc`, `pillar`, `underside` (the rock cone that makes a floor look like it floats; arenas hang in the air below the hub), `tree`, `blockWall` and `part`. Put a seeded `MapKit.rng(seed)` behind any scatter so every server builds the same map. Every model needs a plain-shape fallback.

## Steps

1. Create `src/server/Maps/<MapName>.luau` (`--!strict`, a header comment describing the map and its rules, same style as `FrostHollow.luau`).
2. Register it in `src/server/Services/ArenaService.luau`: `MAP_NAMES`, `DISPLAY_NAMES`, and a weight in `pickMap` (0 excludes a mode, as `SparringArena` does for 4v4). `MapVoteService` and the vote screen pick it up automatically. The screen is a 4 x 2 grid, so a ninth map needs a layout change in `MapVoteController`.
3. Add it to `EXPECTED_MAPS` in `tests/Maps.spec.luau` (and bump the count it asserts).
4. Docs: the map table in `docs/GAME_DESIGN.md`, "Matches and arenas" in `docs/ARCHITECTURE.md`, `docs/semantic/features.yaml` (`duel_maps`), `README.md`, `CHANGELOG.md`.

## Where arenas go (spectating from the hub)

Do not position arenas inside the map. `ArenaService.slotOrigin(slot)` summons them in rings below the floating hub (`Config.ARENA`: `Y`, `RADIUS`, `RING_STEP`, `PER_RING`) so players on the hub rim can look down and watch. Maps are built at design size and then scaled by `Config.ARENA_SCALE` (2): keep a map within roughly 95 design studs of its origin so the scaled arena never overlaps its neighbours (400+ studs apart). Make floors and cover breakable with `MapKit.terrainDisc` / `MapKit.terrain` (`MapKit.groundTerrain(makeProp)`); jump pads should set a `LaunchTo` attribute so scaling can re-aim them. Each arena automatically gets a `SpectatorSign` billboard and persistent streaming.

## The hub island

`src/server/Maps/InkwellPlaza.luau` builds the hub as a round floating island. Bearings are degrees clockwise from north (-Z); `polar(bearing, radius)` places things. Services find parts by **tag and name**, so keep these: tags `HubSpawn`, `TeamPad` (with `Box`, `Mode`, `Team`, `Slots`), `TeamBoxHeader`, `BuildZone`, `PracticeZone`, `DummySpot`, `BattlegroundPortal`, `WinsBoard`, `PodiumSpot` (with `Rank`), `LikeGift`; names `SpellbookKiosk`, `Crate_Spell`, `CrateModel_Spell`, `Leaderboard`. `tests/Maps.spec.luau` checks them, and that nothing sticks out past `Config.HUB.RADIUS`. Pedestals and the wins board face the centre (their front face), and `LeaderboardService` turns the avatars to match.

## Verify

Run `test-in-studio`. To look at a map, build it in **Edit** mode under a temporary folder, `screen_capture` it, then delete the folder (do not leave preview objects in the place).
