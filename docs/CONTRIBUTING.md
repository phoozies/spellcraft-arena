# Contributing

## Setup

1. Install the toolchain with [Rokit](https://github.com/rojo-rbx/rokit): `rokit install` (pins live in `rokit.toml`).
2. Run `rojo serve`, then connect from the Rojo plugin in Studio.
3. **No Rojo CLI?** Run `node tools/studio-sync.js` and paste `tools/studio-sync.luau` into the Studio command bar. It temporarily needs *Allow HTTP Requests*, so turn that back off afterwards.

## 3D models

The imported models live in the place file, not the project. To add or change one, follow `assets/models/README.md` (import the FBX, run `tools/prepare-models.luau`, save the place). Always keep a plain-shape fallback in code, because a place built by CI won't have the models.

## Workflow

- **Branch from `main`** and keep PRs focused, one system at a time.
- **Format and lint before pushing.** Run `stylua src tests` and `selene src tests`. CI runs both and also does a `rojo build`.
- **Run the tests** in Studio. During a playtest, run this from the Server command bar, where module caches are fresh. In Edit mode Studio can serve stale cached modules after a sync.
  ```lua
  require(game.ServerScriptService.Tests.Runner)()
  ```
  To add tests, create `tests/<Name>.spec.luau` that returns `function(t) t.describe(...) end`. The runner picks it up automatically.
- **Playtest helpers:** in Studio everyone is an admin, so the `;` commands in [ADMIN.md](ADMIN.md) work (`;freecast me`, `;unlock me all`, `;coins me 5000`, `;crate me Epic`, `;startmatch 1v1`). From the command bar or the Studio MCP during Play (Server context), use the BindableFunction. The command bar has its own module cache and `_G`, so requiring a service there gives you a fresh, empty copy.
  ```lua
  local debug = game.ServerStorage.SpellcraftDebug
  debug:Invoke("solo", "1v1")       -- match against nobody; rounds end on the timer
  debug:Invoke("coins", 500)
  debug:Invoke("crate", "Element")     -- returns the CrateResult (or the refusal reason)
  debug:Invoke("wins", 3)
  debug:Invoke("state")             -- {coins, wins, elements, element} per player
  debug:Invoke("unlockall")
  ```
  Studio playtests with API access save to the real DataStore, so these change your saved profile.
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
- [ ] Tests pass and docs are updated (SPELLS.md table regenerated, `docs/semantic/features.yaml` updated)
- [ ] Tried on PC, plus the device emulator for phone and console
- [ ] `roblox-dev:roblox-reviewer` audit for remote, DataStore, or performance changes
