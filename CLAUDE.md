# Spellcraft Arena: guide for AI agents

All-ages Roblox PvP: draw a spell's shape, get a copy of the spell, cast it. Rojo project in `--!strict` Luau, fully server-authoritative.

## Read first

| You want to… | Read |
|---|---|
| Know what every feature does, which files own it, its remotes, data, rules | [`docs/semantic/features.yaml`](docs/semantic/features.yaml) (machine-readable semantic layer) |
| Understand coins, elements, the Chest Shop, wins, leaderboard, podium | [`docs/ECONOMY.md`](docs/ECONOMY.md) |
| Plan classes (not built yet) | [`docs/CLASSES.md`](docs/CLASSES.md) |
| Add or tune a spell | [`docs/SPELLS.md`](docs/SPELLS.md), source of truth `src/shared/Spells/SpellDefinitions.luau` |
| See (or add) a spell's model, particles, animation, and sounds | `src/shared/Spells/SpellRegistry.luau` (the registry), mirrored in [`docs/semantic/spell_registry.yaml`](docs/semantic/spell_registry.yaml); regenerate with `python tools/gen-spell-registry.py` |
| Change how spells are drawn, or add a glyph | `src/shared/Spells/Glyphs.luau` + `GlyphRecognizer.luau`, `tests/Glyphs.spec.luau` |
| Change how spells look in the UI (HUD cards, Spellbook) | `src/client/UI/Sigil.luau` (a spell's sigil), `src/client/UI/SpellCard.luau`, `GlyphView.glow` in `src/shared/UI/GlyphView.luau` |
| Change the drawing canvas or the wand | `src/client/Controllers/DrawController.luau` (2D canvas), `WandController.luau` + `src/client/Fx/WandVfx.luau` (3D, magic circle, live stroke relay), `src/server/Services/WandService.luau`, `src/shared/Util/WandAir.luau`, `tests/Wand.spec.luau` |
| Change the first-join tutorial or its arrows | `src/client/Controllers/TutorialController.luau`, `src/client/Fx/GuideArrow.luau` |
| Change a sound | `src/shared/Audio/Cues.luau` (every cue id in one table) |
| Understand services, cast pipeline, PvP rules, data | [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) |
| Add a 3D model | [`assets/models/README.md`](assets/models/README.md); block models come from `tools/blender/block_models.py` |
| Change how the UI looks | `src/client/UI/Theme.luau` (minimal: flat surfaces, one accent, one typeface) |
| Admin / debug commands | [`docs/ADMIN.md`](docs/ADMIN.md) |
| Follow a repeatable process (new feature, map, spell, testing in Studio, shipping) | the project skills in [`.claude/skills/`](.claude/skills): `repo-map`, `new-feature`, `add-map`, `add-spell`, `test-in-studio`, `ship-change` |

## The game in one screen

- **Elements and spells (24):** four base elements (Fire, Water, Earth, Air) with three base spells each: Fire = Fireball, Fire Slash, Fire Boost; Water = Water Slice, Water Body, Water Lock; Earth = Rock Throw, Earth Wall, Earth Punch; Air = Gust, Whirlwind, Air Boost. The first element is a free pick, the others are bought with coins. The other 12 spells are **chest spells** with a rarity (Common to Legendary) won from the Chest Shop gacha, including Heal, Air Shield, Black Hole, Turret, and Lightning. The **loadout** is your element's 3 base spells plus 2 equipped chest spells (no two may share a shape). Classes are planned but not built ([`docs/CLASSES.md`](docs/CLASSES.md)).
- **No levels or XP.** Winning a match pays **coins** (`Config.COINS`) and +1 **win**. Coins buy base elements and **chests**: five of them, Common to Legendary (`Economy/Chests`), each winning one chest spell of its rarity or better, decided by the server (duplicates pay coins back, Epic and Legendary chests never give one while a new spell is left; the 10th Common-Rare chest in a row without an Epic or better is guaranteed one, `Chests.PITY`).
- **Leaderboard:** `leaderstats.Wins`/`Coins`, a Most Wins board, and a top-3 podium with avatars in the hub (`LeaderboardService`).
- **Battleground:** a hub portal or the Play window's button drops you at a random spot in a big open world (`BattlegroundService`, `Maps/Battleground`); players are enemies (respawn after 3s), and hostile NPCs (`NpcService`, `shared/Battleground/Npcs`) fight back and pay coins (capped). Green gates or the HUD button return you to the hub.
- **First person and the sight:** the camera is locked in first person (mouse look at the player's Camera speed setting, `Config.CAMERA`) and players aim with one dot in the middle of the screen; nothing marks a target. Every spell follows it (`CastService.resolveAim`, table in `docs/SPELLS.md`): strikes, lines and placed spells land where it stops, never through a wall. Only bolts get a quiet assist (`Util/AutoAim`, `Config.AUTO_AIM`): the opponent closest to the sight is aimed at, led and tracked slightly, so a hard sidestep still dodges.
- **The hub is a round floating island** (`Maps/InkwellPlaza`); duels are fought on one of **7 flat maps** (each a theme on `Maps/FlatArena`: one level tiled board painted with team halves, point-symmetric cover, spawn pads) (`ArenaService.MAP_NAMES`) summoned in rings *below* the island (`Config.ARENA`), so hub players can look over the rim and watch.
- **Matches:** hub team boxes or queues → best of 3 rounds → your loadout; between rounds you pick 1 of 3 **boosts** (Power, Vitality, Swiftness, Focus, Health Potion) instead of earning spells. No passive regen in fights (the hub heals fast). Arena floors and scenery break; falling into the water under an arena, or getting stuck in a carved pit, throws you back onto your spawn pad (`Services/Rescue`).
- **Analytics:** `TelemetryService` sends the onboarding and match funnels, coin flows, and custom events to Roblox `AnalyticsService` (step names in `shared/Analytics/Funnels`).
- **Look and feel:** everything is blocky, classic Roblox: block-model spells and scenery (Blender spec in `tools/blender/block_models.py`), a minimal GUI (flat near-black surfaces, one warm accent, one typeface, buttons that pick their own readable text colour, `UI/Theme`), cast animations per move, background music (hub and fight playlists) with an on/off setting, a one-time Like & Favourite coin gift (honor system) claimed at a gift box in the hub, a first-person camera everywhere (`CameraController`) with a one-dot sight (`CrosshairController`); open windows free the mouse (`UI/MouseLock`), Shift turns the cursor on and off like shift lock (`CursorController`), touch just taps, M opens the menu, and a first-join tutorial with guiding arrows.
- **Casting:** there is no cast button and nothing is stored: **finishing a shape casts the spell at once**, where you look. Tap a spell card or press its key (**1-5**, key N = the Nth loadout spell) to see its shape and trace it (the closer you follow it, the higher the drawing **quality**: more power, size, and duration, see `Spells/Quality`), or press **F** (or tap Draw) for a blank canvas. Aim first: the canvas frees the mouse, so the camera holds still while you draw, and the stroke is sent with the point under the crosshair (`DrawSpell`). The shape is the KIND of move, the same in every element: circle = a basic attack, a diagonal slash = a fast attack, a square = a boost, a triangle = a defense or a stun, a lightning bolt = a heavy attack, a V = an area attack, a star = your ultimate; chest spells use a heart (heal), zigzag (lightning), hook (turret), X (ward), or spiral (black hole). The server recognizes the stroke and casts the spell; there is no typing or voice input. Everyone draws with a **wand** (`WandService` welds it to the hand, tinted by element; `WandController` / `Fx/WandVfx` raise it while the canvas is open, open a magic circle in the air, and write the stroke on it as a glowing ribbon that is pulled into the wand; the stroke is relayed live (`AirStroke`) so nearby players watch it being drawn; cosmetic only, `Config.WAND`). Every spell is shown in the UI as its sigil (`UI/Sigil`).

## Rules that must stay true

1. **The server decides everything.** Clients send intent only (a drawn stroke, the point under the crosshair, a chest id, a draft pick). Every remote handler validates type, range, ownership, and rate.
2. **One owner per state.** `EconomyService` is the only writer of `profile.coins` and `profile.stats.wins`; `ElementService` owns `profile.elements`/`profile.element`/`profile.spells`/`profile.loadout` (elements are bought through it; `ChestService` is the only code that wins chest spells); `ChestService` owns `profile.pity`; `PlayerDataService` owns load/save/migration (profile schema **7**).
3. **Data, not code, for spells.** A new spell is a row in `SpellDefinitions.luau`; behavior comes from its archetype (`src/server/Services/Archetypes`). New behavior = a new optional stat read by an archetype.
4. **Models always have fallbacks.** Imported models live in the place (`ReplicatedStorage.Models`), not the repo; `ModelKit.clone` can return nil and every caller must draw plain shapes instead.
5. **Balance budgets** in `tests/Balance.spec.luau` (no one-shots, ultimates ≥ 15s and 30+ damage, timed buffs ≤ 60% uptime, …), unique aliases in `tests/WordMatcher.spec.luau`, and one distinct glyph per spell in `tests/Glyphs.spec.luau`.
6. **Tunables live in `Config.luau`**, spell numbers in `SpellDefinitions.luau`, chest price and pity in `Economy/Chests.luau`, rarity odds in `Spells/Rarity.luau`, element prices in `Spells/Elements.luau`, boosts in `Match/Boosts.luau`. Nothing hard-coded in systems.
7. **Every spell has a registry entry** (model, particle style, cast pose, sounds) and **every model has a fallback**: block models are generated data (`Models/BlockModels.luau`, never hand-edited), imported meshes may be missing.
8. Every file starts with `--!strict` and a header comment saying what it owns. Services/controllers use `init()` then `start()`.

## Working in Studio (Studio MCP)

- No Rojo CLI here: run `node tools/studio-sync.js` (background), then in **Edit** mode enable `HttpService.HttpEnabled`, run the body of `tools/studio-sync.luau`, and disable HTTP again.
- Tests: during Play, from the **Server** context: `require(game.ServerScriptService.Tests.Runner)()`.
- Live state: the command bar/MCP has its **own module cache and `_G`**, so requiring a service gives a fresh copy. Use `game.ServerStorage.SpellcraftDebug:Invoke("state" | "coins", n | "wins", n | "chest", "unlockall" | "element", "Water")` instead (Studio only).
- Studio playtests may save to the real DataStore when API access is on: debug commands change the tester's saved profile.

## Blender models

The Blender scene for game models is set up for Roblox: **metric, unit scale 0.01, length in centimeters** (1 Blender unit = 1 cm), so FBX exports import into Studio at a sane size. Part names in the FBX are the contract with `tools/prepare-models.luau` and `tests/Models.spec.luau`. Details in `assets/models/README.md`.

## Git workflow (every new feature or change)

The user has authorised this for the whole project, so follow it without asking each time:

1. **Start on a branch.** Before editing, create a branch from an up-to-date `main` (`feature/<short-name>`; `fix/<short-name>` for fixes). Never work directly on `main`. If the working tree already holds unrelated changes, say so instead of mixing them in.
2. **Build and sync as you go.** Sync to Roblox Studio after code changes (see the `test-in-studio` skill) so the user can try it in their open place.
3. **Finish when tests pass or the user says so.** Once the suite is green in Studio (or the user says to ship it), do all of these in order:
   1. update docs and `CHANGELOG.md` (`ship-change` skill), then commit with a clear message;
   2. push the branch and merge it into `main` (a PR merged on GitHub, or `gh pr merge`; never force-push `main`);
   3. delete the branch locally and on the remote;
   4. switch to `main`, pull, and **sync to Roblox** so the place matches `main`.
4. **Never merge on red.** If tests fail, or something could not be run, stop and report it plainly instead of merging. If the user asks only for a PR, open it and leave the merge to them.

## Before you finish a change

- Follow the git workflow above (branch, test, commit, push, merge to `main`, delete the branch, sync to Roblox).
- Run the tests in Studio; update `docs/semantic/features.yaml` and the human doc for the feature you touched; add a `CHANGELOG.md` entry.
- CI runs `stylua --check`, `selene`, and `rojo build` (see `.github/workflows/ci.yml`).
