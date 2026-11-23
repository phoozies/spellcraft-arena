---
name: test-in-studio
description: Sync the repo into Roblox Studio (no Rojo CLI), run the test suite, playtest, read the console, and screenshot via the Studio MCP. Use whenever code must be verified in Studio, or tests must be run.
---

# Testing in Studio (Studio MCP)

There is no Rojo CLI on this machine. Call `mcp__Roblox_Studio__list_roblox_studios` first and pass its `studio_id` to every call (confirm it is the Spellcraft Arena place).

## 1. Sync the code

1. Run `node tools/studio-sync.js` **in the background** (it serves `default.project.json` on `localhost:34873`, and a hash of it on `/version`).
2. With the **Spellcraft Sync** plugin installed (`tools/studio-sync-plugin.lua`; the user installs it once with `node tools/studio-sync.js --install-plugin` and allows its localhost access when Studio asks), Studio syncs by itself within a second of every file change while in **Edit** mode. Check `get_console_output` for `[Spellcraft Sync] synced ...`. The plugin's Sync toolbar button turns it off and on.
3. Without the plugin: `execute_luau` **cannot** reach localhost (the Studio Assistant HTTP allowlist denies it), so push the changed scripts with `multi_edit` (paths in dot notation; Studio's copies may have CRLF line endings, and names with dots like `Wand.spec` need `execute_luau` with `game.ServerScriptService.Tests["Wand.spec"]`), or ask the user to paste `tools/studio-sync.luau` into the command bar with HTTP enabled.
4. Sync again after every edit (automatic with the plugin), and stop playing first: the plugin only syncs in Edit mode. Stop the node server when you are finished.

## 2. Run the tests

1. `start_stop_play` (start). Wait for `[SpellcraftArena] server started` in `get_console_output`.
2. `execute_luau` with datamodel **Server**: `local p, f = require(game.ServerScriptService.Tests.Runner)() return p, f`. The call can take a couple of minutes. If the MCP moves it to the background, read `[Tests] N passed, M failed` from `get_console_output`. Failures are printed as warnings with the test name.
3. Always run from the **Server** context during Play. The command bar and Edit mode have their own module cache and can serve stale modules after a sync.
4. `start_stop_play` (stop) when done.

## 3. Live state and debugging (during Play, Server context)

`game.ServerStorage.SpellcraftDebug:Invoke("state" | "coins", n | "wins", n | "chest", "Common" | "unlockall" | "element", "Water" | "solo", "1v1" | "cast", {spell = "BlackHole", target = Vector3})`. Do not `require` a service from the command bar to inspect it (that gives a fresh, empty copy). Studio playtests with API access can write the real DataStore, so debug commands change the tester's saved profile.

## 4. Looking at a map or the hub

`screen_capture` only captures edit-time views. In **Edit** mode build the thing (for example `require(game.ServerScriptService.Server.Maps.InkwellPlaza)()` and any map builders, parented to a temporary folder), call `screen_capture` with `camera_position` and `look_at_position`, then **destroy the temporary folder**. Do not leave preview objects in the place.

## 5. Lint and format (CI runs these)

`stylua --check src tests`, `selene src tests`, and `rojo build`. If they are not installed, `npm i @johnnymorganz/stylua-bin` in a scratch directory gives a `stylua` binary. Run it only on the files you changed: it reformats whatever it is given and converts CRLF to LF (git normalises that). Avoid reformatting unrelated files.
