---
name: test-in-studio
description: Sync the repo into Roblox Studio (no Rojo CLI), run the test suite, playtest, read the console, and screenshot via the Studio MCP. Use whenever code must be verified in Studio, or tests must be run.
---

# Testing in Studio (Studio MCP)

There is no Rojo CLI on this machine. Call `mcp__Roblox_Studio__list_roblox_studios` first and pass its `studio_id` to every call (confirm it is the Spellcraft Arena place).

## 1. Sync the code

1. Run `node tools/studio-sync.js` **in the background** (it serves `default.project.json` on `localhost:34873`).
2. With Studio in **Edit** mode, call `execute_luau` (datamodel `Edit`): set `HttpService.HttpEnabled = true`, run the body of `tools/studio-sync.luau` (inline it; the tool cannot read repo files), then set `HttpEnabled = false` again. Wrap the body in `pcall` so HTTP is always switched back off.
3. Re-sync after every edit. Stop the node server when you are finished.

## 2. Run the tests

1. `start_stop_play` (start). Wait for `[SpellcraftArena] server started` in `get_console_output`.
2. `execute_luau` with datamodel **Server**: `local p, f = require(game.ServerScriptService.Tests.Runner)() return p, f`. The call can take a couple of minutes. If the MCP moves it to the background, read `[Tests] N passed, M failed` from `get_console_output`. Failures are printed as warnings with the test name.
3. Always run from the **Server** context during Play. The command bar and Edit mode have their own module cache and can serve stale modules after a sync.
4. `start_stop_play` (stop) when done.

## 3. Live state and debugging (during Play, Server context)

`game.ServerStorage.SpellcraftDebug:Invoke("state" | "coins", n | "wins", n | "crate", "Spell" | "unlockall" | "element", "Water" | "solo", "1v1")`. Do not `require` a service from the command bar to inspect it (that gives a fresh, empty copy). Studio playtests with API access can write the real DataStore, so debug commands change the tester's saved profile.

## 4. Looking at a map or the hub

`screen_capture` only captures edit-time views. In **Edit** mode build the thing (for example `require(game.ServerScriptService.Server.Maps.InkwellPlaza)()` and any map builders, parented to a temporary folder), call `screen_capture` with `camera_position` and `look_at_position`, then **destroy the temporary folder**. Do not leave preview objects in the place.

## 5. Lint and format (CI runs these)

`stylua --check src tests`, `selene src tests`, and `rojo build`. If they are not installed, `npm i @johnnymorganz/stylua-bin` in a scratch directory gives a `stylua` binary. Run it only on the files you changed: it reformats whatever it is given and converts CRLF to LF (git normalises that). Avoid reformatting unrelated files.
