# Wordcraft Arena *(working title)*

A Scribblenauts-inspired PvP game for Roblox: **type or say a word, get the spell, outsmart your opponents.** It's built for all ages and plays on PC, mobile, console, and VR.

- Type "fireball", "rock wall", or "tornado" in chat, the spell box, or out loud 🎤 to get one copy of the spell. Casting uses it up, so type it again. You can submit one word per second, and pasting is blocked.
- Placeables show a ghost preview before you put them down, and everything you build can be destroyed.
- 1v1, 2v2, 4v4, and FFA, best of 3. You start each match with 3 random spells you own, then draft a new card each round (cards have random rarities) until your hand holds 5.
- 40 spells to unlock across levels 1–10. Players start with Fireball, Water Lock, and Rock Wall.
- A central hub plus 3 arenas: Crayon Canyon, Frostbite Fortress, and Sky Islands.

## Quick start

```bash
rokit install
```

```bash
rojo serve
```

Then connect with the Rojo plugin in Studio and press **Play**. No Rojo CLI? See [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) for the `tools/studio-sync` fallback.

Run the tests from the Studio command bar:

```lua
require(game.ServerScriptService.Tests.Runner)()
```

## Docs

| Doc | What's in it |
|---|---|
| [Game design](docs/GAME_DESIGN.md) | Pillars, research, core loop, modes, maps, progression, safety |
| [Spells](docs/SPELLS.md) | The full dictionary, rarity, archetypes, how to add a spell |
| [Architecture](docs/ARCHITECTURE.md) | Code layout, cast pipeline, PvP rules, data and security |
| [Controls](docs/CONTROLS.md) | Per-device bindings, voice, accessibility |
| [Admin commands](docs/ADMIN.md) | Who is an admin, every `;` command, adding commands |
| [Contributing](docs/CONTRIBUTING.md) | Setup, workflow, conventions, test helpers |
| [Changelog](CHANGELOG.md) | Release notes |

## Structure

- `src/shared` → ReplicatedStorage/Shared: types, config, the spell dictionary, pure logic
- `src/server` → ServerScriptService/Server: authoritative services, archetypes, map builders
- `src/client` → StarterPlayerScripts/Client: HUD, input, placement preview, menus
- `tests` → ServerScriptService/Tests: spec modules and runner
