---
name: ship-change
description: Final checklist before finishing any change in Spellcraft Arena - tests, formatting, docs, semantic feature index, changelog, and commit conventions. Use when a change is code-complete.
---

# Shipping a change

Do these before telling the user a change is done.

1. **Tests green** in Studio (`test-in-studio`). Say so plainly if something could not be run (for example, no Studio connection).
2. **Format and lint**: `stylua` on changed files, `selene`, `rojo build` (CI: `.github/workflows/ci.yml`). Every file starts with `--!strict` and a header comment saying what it owns.
3. **Docs for the feature you touched**:
   - `docs/semantic/features.yaml` (the machine-readable entry: files, remotes, config, invariants)
   - the human doc: `docs/ARCHITECTURE.md` (services, arenas), `docs/ECONOMY.md` (coins, crates, hub layout), `docs/SPELLS.md`, `docs/CONTROLS.md`, `docs/GAME_DESIGN.md`, `docs/ADMIN.md`
   - `README.md` if the one-screen summary changed; `CLAUDE.md` only for rules or "the game in one screen"
4. **`CHANGELOG.md`**: add to `## [Unreleased]` in Keep a Changelog style (`### Added`, `### Changed`, `### Fixed`), player-visible behaviour first, then the files or config keys that matter.
5. **Rules check** (`CLAUDE.md`): the server decides; one owner per state; data not code for spells; models have fallbacks; tunables in `Config`; balance budgets and unique glyphs and aliases still pass.
6. **Review** remote, DataStore or performance changes with the `roblox-dev:roblox-reviewer` agent.
7. **Git** (the project workflow in `CLAUDE.md`, authorised by the user): work on a `feature/<name>` branch cut from `main`. When tests are green, or the user says so: commit, push, merge into `main`, delete the branch (local and remote), pull `main`, and sync to Roblox (`test-in-studio`). Do not merge on red tests; if the user asked only for a PR, stop after opening it. Keep PRs focused. Never force-push `main`. Do not commit `*.rbxl` or `sourcemap.json`.
