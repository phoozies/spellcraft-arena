# Spellcraft Arena: guide for AI agents

All-ages Roblox PvP: draw a spell's shape, get a copy of the spell, cast it. Rojo project in `--!strict` Luau, fully server-authoritative.

## Read first

| You want to… | Read |
|---|---|
| Know what every feature does, which files own it, its remotes, data, rules | [`docs/semantic/features.yaml`](docs/semantic/features.yaml) (machine-readable semantic layer) |
| Understand coins, elements, the Spell Crate, wins, leaderboard, podium | [`docs/ECONOMY.md`](docs/ECONOMY.md) |
| Plan classes (not built yet) | [`docs/CLASSES.md`](docs/CLASSES.md) |
| Add or tune a spell | [`docs/SPELLS.md`](docs/SPELLS.md), source of truth `src/shared/Spells/SpellDefinitions.luau` |
| See (or add) a spell's model, particles, animation, and sounds | `src/shared/Spells/SpellRegistry.luau` (the registry), mirrored in [`docs/semantic/spell_registry.yaml`](docs/semantic/spell_registry.yaml); regenerate with `python tools/gen-spell-registry.py` |
| Change how spells are drawn, or add a glyph | `src/shared/Spells/Glyphs.luau` + `GlyphRecognizer.luau`, `tests/Glyphs.spec.luau` |
| Change the first-join tutorial or its arrows | `src/client/Controllers/TutorialController.luau`, `src/client/Fx/GuideArrow.luau` |
| Change a sound | `src/shared/Audio/Cues.luau` (every cue id in one table) |
| Understand services, cast pipeline, PvP rules, data | [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) |
| Add a 3D model | [`assets/models/README.md`](assets/models/README.md); block models come from `tools/blender/block_models.py` |
| Change how the UI looks | `src/client/UI/Theme.luau` (studded Roblox style), stud texture `assets/ui/studs.png` |
| Admin / debug commands | [`docs/ADMIN.md`](docs/ADMIN.md) |
| Follow a repeatable process (new feature, map, spell, testing in Studio, shipping) | the project skills in [`.claude/skills/`](.claude/skills): `repo-map`, `new-feature`, `add-map`, `add-spell`, `test-in-studio`, `ship-change` |

## The game in one screen

- **Elements and spells (24):** four base elements (Fire, Water, Earth, Air) with three base spells each: Fire = Fireball, Fire Slash, Fire Boost; Water = Water Slice, Water Body, Water Lock; Earth = Rock Throw, Earth Wall, Earth Punch; Air = Gust, Whirlwind, Air Boost. The first element is a free pick, the others are bought with coins. The other 12 spells are **crate spells** with a rarity (Common to Legendary) won from the Spell Crate gacha, including Heal, Air Shield, Black Hole, Turret, and Lightning. The **loadout** is your element's 3 base spells plus 2 equipped crate spells (no two may share a shape). Classes are planned but not built ([`docs/CLASSES.md`](docs/CLASSES.md)).
- **No levels or XP.** Winning a match pays **coins** (`Config.COINS`) and +1 **win**. Coins buy base elements and **Spell Crate** spins; a server-decided spin wins one crate spell by rarity (duplicates pay coins back).
- **Leaderboard:** `leaderstats.Wins`/`Coins`, a Most Wins board, and a top-3 podium with avatars in the hub (`LeaderboardService`).
- **Battleground:** a hub portal drops you at a random spot in a big open world (`BattlegroundService`, `Maps/Battleground`); players are enemies (respawn after 3s), and hostile NPCs (`NpcService`, `shared/Battleground/Npcs`) fight back and pay coins (capped). Green gates or the HUD button return you to the hub.
- **The hub is a round floating island** (`Maps/InkwellPlaza`); duels are fought on one of **8 maps** (`ArenaService.MAP_NAMES`) summoned in rings *below* the island (`Config.ARENA`), so hub players can look over the rim and watch.
- **Matches:** hub team boxes or queues → best of 3 rounds → your loadout; between rounds you pick 1 of 3 **boosts** (Power, Vitality, Swiftness, Focus, Health Potion) instead of earning spells.
- **Look and feel:** everything is blocky, classic Roblox: block-model spells and scenery (Blender spec in `tools/blender/block_models.py`), a studded pastel GUI with dark ink text, cast animations per move, background music (hub and fight playlists) with an on/off setting, a one-time Like & Favourite coin gift (honor system) claimed at a gift box in the hub, a mouse cursor that turns into a crosshair while a spell is readied, and a first-join tutorial with guiding arrows.
- **Casting:** tap a spell card to see its shape and trace it (the closer you follow it, the higher the drawing **quality**: more power, size, and duration, see `Spells/Quality`), or press **F** (or tap ✏ Draw) for a blank canvas. The shape is the KIND of move, the same in every element: circle = a basic attack, a diagonal slash = a fast attack, a square = a boost, a triangle = a defense or a stun, a lightning bolt = a heavy attack, a V = an area attack, a star = your ultimate; crate spells use a heart (heal), zigzag (lightning), hook (turret), X (ward), or spiral (black hole). The server recognizes the stroke and readies the spell; there is no typing or voice input.

## Rules that must stay true

1. **The server decides everything.** Clients send intent only (a drawn stroke, an aim point, a crate id, a draft pick). Every remote handler validates type, range, ownership, and rate.
2. **One owner per state.** `EconomyService` is the only writer of `profile.coins` and `profile.stats.wins`; `ElementService` owns `profile.elements`/`profile.element`/`profile.spells`/`profile.loadout` (elements are bought through it; `CrateService` is the only code that wins crate spells); `PlayerDataService` owns load/save/migration (profile schema **5**).
3. **Data, not code, for spells.** A new spell is a row in `SpellDefinitions.luau`; behavior comes from its archetype (`src/server/Services/Archetypes`). New behavior = a new optional stat read by an archetype.
4. **Models always have fallbacks.** Imported models live in the place (`ReplicatedStorage.Models`), not the repo; `ModelKit.clone` can return nil and every caller must draw plain shapes instead.
5. **Balance budgets** in `tests/Balance.spec.luau` (no one-shots, ultimates ≥ 15s and 30+ damage, timed buffs ≤ 60% uptime, …), unique aliases in `tests/WordMatcher.spec.luau`, and one distinct glyph per spell in `tests/Glyphs.spec.luau`.
6. **Tunables live in `Config.luau`**, spell numbers in `SpellDefinitions.luau`, crate price in `Economy/Crates.luau`, rarity odds in `Spells/Rarity.luau`, element prices in `Spells/Elements.luau`, boosts in `Match/Boosts.luau`. Nothing hard-coded in systems.
7. **Every spell has a registry entry** (model, particle style, cast pose, sounds) and **every model has a fallback**: block models are generated data (`Models/BlockModels.luau`, never hand-edited), imported meshes may be missing.
8. Every file starts with `--!strict` and a header comment saying what it owns. Services/controllers use `init()` then `start()`.

## Working in Studio (Studio MCP)

- No Rojo CLI here: run `node tools/studio-sync.js` (background), then in **Edit** mode enable `HttpService.HttpEnabled`, run the body of `tools/studio-sync.luau`, and disable HTTP again.
- Tests: during Play, from the **Server** context: `require(game.ServerScriptService.Tests.Runner)()`.
- Live state: the command bar/MCP has its **own module cache and `_G`**, so requiring a service gives a fresh copy. Use `game.ServerStorage.SpellcraftDebug:Invoke("state" | "coins", n | "wins", n | "crate", "unlockall" | "element", "Water")` instead (Studio only).
- Studio playtests may save to the real DataStore when API access is on: debug commands change the tester's saved profile.

## Blender models

The Blender scene for game models is set up for Roblox: **metric, unit scale 0.01, length in centimeters** (1 Blender unit = 1 cm), so FBX exports import into Studio at a sane size. Part names in the FBX are the contract with `tools/prepare-models.luau` and `tests/Models.spec.luau`. Details in `assets/models/README.md`.

## Before you finish a change

- Run the tests in Studio; update `docs/semantic/features.yaml` and the human doc for the feature you touched; add a `CHANGELOG.md` entry.
- CI runs `stylua --check`, `selene`, and `rojo build` (see `.github/workflows/ci.yml`).
