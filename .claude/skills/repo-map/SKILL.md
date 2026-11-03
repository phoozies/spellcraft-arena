---
name: repo-map
description: Orient yourself in the Spellcraft Arena repo. Use at the start of any task to find which files own a feature, where data lives, and which doc to read.
---

# Repo map

Read `CLAUDE.md` first, then use this to jump straight to the right place.

## Layout (Rojo project, `default.project.json`)

| Path | Runs in | What lives there |
|---|---|---|
| `src/shared/` | `ReplicatedStorage.Shared` | `Config.luau` (all tunables), `Types.luau`, `Net/Remotes.luau` (every remote), `Spells/*` (definitions, registry, glyphs, elements, rarity), `Economy/Chests`, `Match/Boosts`, `Audio/Cues`, `Models/BlockModels` (generated, never hand-edit), `ModelKit` |
| `src/server/Services/` | server | One service per owner of state (`init()` then `start()`); order in `src/server/init.server.luau` |
| `src/server/Services/Archetypes/` | server | Spell behaviours (Projectile, Zone, Buff, ...) |
| `src/server/Maps/` | server | Maps and the hub built from code (`MapKit` helpers, `InkwellPlaza` = the floating-island hub) |
| `src/client/Controllers/` | client | One controller per feature (`init()` then `start()`), order in `src/client/init.client.luau` |
| `src/client/Fx/`, `src/client/UI/` | client | Visual effects, `Theme` (night-indigo GUI), `MouseLock` (first-person mouse release), `Responsive` |
| `tests/` | `ServerScriptService.Tests` | `Runner.luau` runs every `*.spec.luau` |
| `docs/` | | Human docs; `docs/semantic/features.yaml` is the machine-readable feature index |
| `tools/` | | Studio sync, Blender model scripts, registry generator, art scripts |
| `.claude/skills/` | | These skills |

## Where to look for X

- A feature's files, remotes, data, rules: `docs/semantic/features.yaml`
- Coins, chests, wins, podium, hub layout table: `docs/ECONOMY.md`
- Services, cast pipeline, PvP rules, arenas: `docs/ARCHITECTURE.md`
- Spells and balance budgets: `docs/SPELLS.md`, `src/shared/Spells/SpellDefinitions.luau`, `tests/Balance.spec.luau`
- Controls: `docs/CONTROLS.md`; admin commands: `docs/ADMIN.md`
- A tunable number: `src/shared/Config.luau` (never hard-code it in a system)
- A remote: `src/shared/Net/Remotes.luau`
- Maps, arenas, the hub: `src/server/Maps/`, `src/server/Services/ArenaService.luau`, `HubService.luau`

## Hard rules (from CLAUDE.md)

The server decides everything. One owner per piece of state (`EconomyService` writes coins and wins, `ElementService` writes elements and loadout, `PlayerDataService` owns saves). Spells are data, not code. Every model has a plain-shape fallback. Every file has `--!strict` and a header comment. Tunables live in `Config`.

## Related skills

`new-feature`, `add-map`, `add-spell`, `test-in-studio`, `ship-change`.
