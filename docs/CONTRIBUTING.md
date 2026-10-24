# Contributing

## Setup

1. Install the toolchain with [Rokit](https://github.com/rojo-rbx/rokit): `rokit install` (pins live in `rokit.toml`).
2. Run `rojo serve`, then connect from the Rojo plugin in Studio.
3. **No Rojo CLI?** Run `node tools/studio-sync.js` and paste `tools/studio-sync.luau` into the Studio command bar. It temporarily needs *Allow HTTP Requests*, so turn that back off afterwards.

## Workflow

- **Branch from `main`** and keep PRs focused, one system at a time.
- **Format and lint before pushing.** Run `stylua src tests` and `selene src tests`. CI runs both and also does a `rojo build`.
- **Run the tests** in Studio (Edit or Server mode):
  ```lua
  require(game.ServerScriptService.Tests.Runner)()
  ```
  To add tests, create `tests/<Name>.spec.luau` that returns `function(t) t.describe(...) end`. The runner picks it up automatically.
- **Playtest helpers** (Studio only), from the command bar during Play:
  ```lua
  _G.WordcraftDebug("solo", "1v1")   -- match against nobody; rounds end on the timer
  _G.WordcraftDebug("xp", 500)
  _G.WordcraftDebug("unlockall")
  ```
  Use **Test → Clients and Servers** (2–8 players) to check PvP, teams, and drafts.

## Code conventions

- Every file starts with `--!strict` and a header comment saying what it owns.
- Services and controllers follow the `init()` / `start()` pattern. Cross-service cycles are broken with injected hooks (see ARCHITECTURE.md).
- **Server-authoritative:** remote handlers validate type, range, ownership, and rate. Never trust a client number.
- **Tunables** go in `Config.luau`. Spell numbers go in `SpellDefinitions.luau`. Nothing is hard-coded inside systems.
- New remotes go in `Net/Remotes.luau` with a one-line payload description.
- UI uses `UI/Theme` builders, scale-friendly layouts, and touch targets of at least 52 px. Make every button `Selectable` for gamepad.

## Checklist for a new spell / map / system

- [ ] Data row or builder added (see SPELLS.md or MapKit's arena contract)
- [ ] Tests pass and docs are updated (SPELLS.md table regenerated)
- [ ] Tried on PC, plus the device emulator for phone and console
- [ ] `roblox-dev:roblox-reviewer` audit for remote, DataStore, or performance changes
