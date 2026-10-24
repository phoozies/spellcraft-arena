# Wordcraft Arena: guide for AI agents

All-ages Roblox PvP: draw a spell's shape, get a copy of the spell, cast it. Rojo project in `--!strict` Luau, fully server-authoritative.

## Read first

| You want to… | Read |
|---|---|
| Know what every feature does, which files own it, its remotes, data, rules | [`docs/semantic/features.yaml`](docs/semantic/features.yaml) (machine-readable semantic layer) |
| Understand coins, crates, wins, leaderboard, podium | [`docs/ECONOMY.md`](docs/ECONOMY.md) |
| Add or tune a spell | [`docs/SPELLS.md`](docs/SPELLS.md), source of truth `src/shared/Spells/SpellDefinitions.luau` |
| Change how spells are drawn, or add a glyph | `src/shared/Spells/Glyphs.luau` + `GlyphRecognizer.luau`, `tests/Glyphs.spec.luau` |
| Change a sound | `src/shared/Audio/Cues.luau` (every cue id in one table) |
| Understand services, cast pipeline, PvP rules, data | [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) |
| Add a 3D model | [`assets/models/README.md`](assets/models/README.md) |
| Admin / debug commands | [`docs/ADMIN.md`](docs/ADMIN.md) |

## The game in one screen

- **Spells (8):** starters Fireball, Water Lock, Rock Wall (everyone owns them), plus one crate spell per rarity: Gust (Common), Zap (Uncommon), Heal (Rare), Black Hole (Epic), Turret (Legendary).
- **No levels or XP.** Winning a match pays **coins** (`Config.COINS`) and +1 **win**. Coins buy **crates** (one per rarity); a server-decided spin unlocks a spell (duplicates refund half).
- **Leaderboard:** `leaderstats.Wins`/`Coins`, a Most Wins board, and a top-3 podium with avatars in the hub (`LeaderboardService`).
- **Matches:** hub team boxes or queues → best of 3 rounds → 3 random owned spells + a draft card per round.
- **Casting:** press **F** (or tap ✏ Draw) and trace a shape: circle = Fireball, wave = Water Lock, triangle = Rock Wall, chevron = Gust, lightning = Zap, infinity = Heal, spiral = Black Hole, star = Turret. The server recognizes the stroke and readies the spell; there is no typing or voice input.

## Rules that must stay true

1. **The server decides everything.** Clients send intent only (a drawn stroke, an aim point, a crate id, a draft pick). Every remote handler validates type, range, ownership, and rate.
2. **One owner per state.** `EconomyService` is the only writer of `profile.coins` and `profile.stats.wins`; `CrateService` is the only code that unlocks spells from crates; `PlayerDataService` owns load/save/migration (profile schema **2**).
3. **Data, not code, for spells.** A new spell is a row in `SpellDefinitions.luau`; behavior comes from its archetype (`src/server/Services/Archetypes`). New behavior = a new optional stat read by an archetype.
4. **Models always have fallbacks.** Imported models live in the place (`ReplicatedStorage.Models`), not the repo; `ModelKit.clone` can return nil and every caller must draw plain shapes instead.
5. **Balance budgets** in `tests/Balance.spec.luau` (no one-shots, heal ≤ 5/s, legendary cooldown ≥ 10s, …), unique aliases in `tests/WordMatcher.spec.luau`, and one distinct glyph per spell in `tests/Glyphs.spec.luau`.
6. **Tunables live in `Config.luau`**, spell numbers in `SpellDefinitions.luau`, crate prices/odds in `Economy/Crates.luau`. Nothing hard-coded in systems.
7. Every file starts with `--!strict` and a header comment saying what it owns. Services/controllers use `init()` then `start()`.

## Working in Studio (Studio MCP)

- No Rojo CLI here: run `node tools/studio-sync.js` (background), then in **Edit** mode enable `HttpService.HttpEnabled`, run the body of `tools/studio-sync.luau`, and disable HTTP again.
- Tests: during Play, from the **Server** context: `require(game.ServerScriptService.Tests.Runner)()`.
- Live state: the command bar/MCP has its **own module cache and `_G`**, so requiring a service gives a fresh copy. Use `game.ServerStorage.WordcraftDebug:Invoke("state" | "coins", n | "wins", n | "crate", "Epic" | "unlockall")` instead (Studio only).
- Studio playtests may save to the real DataStore when API access is on: debug commands change the tester's saved profile.

## Blender models

The Blender scene for game models is set up for Roblox: **metric, unit scale 0.01, length in centimeters** (1 Blender unit = 1 cm), so FBX exports import into Studio at a sane size. Part names in the FBX are the contract with `tools/prepare-models.luau` and `tests/Models.spec.luau`. Details in `assets/models/README.md`.

## Before you finish a change

- Run the tests in Studio; update `docs/semantic/features.yaml` and the human doc for the feature you touched; add a `CHANGELOG.md` entry.
- CI runs `stylua --check`, `selene`, and `rojo build` (see `.github/workflows/ci.yml`).
