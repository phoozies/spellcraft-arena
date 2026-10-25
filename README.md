# Spellcraft Arena *(working title)*

A Scribblenauts-inspired PvP game for Roblox: **draw a shape, get the spell, outsmart your opponents.** It's built for all ages and plays on PC, mobile, console, and VR.

- Draw a shape to add a copy of a spell to your hotbar: press **F** or tap ✏ Draw, then trace it. The shape is the kind of move: circle = a basic attack, a diagonal slash = a fast attack, a square = a boost, a triangle = a defense or a stun, a lightning bolt = a heavy attack, a V = an area attack, a star = your ultimate. You can hold up to 5 copies, duplicates included, and copies of the same spell share a cooldown. You can draw one spell per second.
- Everyone has 100 HP with no regeneration in the arena. Walls break apart block by block, and every spell has its own effects and a cast animation.
- Placeables show a ghost preview before you put them down, and everything you build can be destroyed.
- 1v1, 2v2, 3v3, and 4v4, best of 3. In the hub, stand on the Blue or Red side of a team box to pick your team before the match. Your equipped element's five spells are your spellbook, and between rounds you pick a boost. For a drop-in fight with no queue, step into the **Battleground** portal: a big open world where players and raiders are enemies. Knock out NPCs for coins.
- 20 spells in 4 elements (Fire, Water, Earth, Air), five each. Pick one element free, then win matches to earn coins and open Element Crates to unlock the others. Between rounds you pick a boost (more damage, health, speed, or faster spells) instead of earning spells.
- Wins show on the player list, a Most Wins board, and a podium in the hub where the server's top 3 stand as their avatars.
- A central hub plus 4 arenas: Crayon Canyon, Frostbite Fortress, Sky Islands, and the Sparring Arena (a colosseum).

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
| [Economy](docs/ECONOMY.md) | Coins, crates, wins leaderboard, podium |
| [Semantic layer](docs/semantic/features.yaml) | Machine-readable feature map for AI agents (start at [CLAUDE.md](CLAUDE.md)) |
| [Spells](docs/SPELLS.md) | The 4 elements and 20 spells, boosts, archetypes, how to add a spell |
| [Classes](docs/CLASSES.md) | Planned, not built yet |
| [Architecture](docs/ARCHITECTURE.md) | Code layout, cast pipeline, PvP rules, data and security |
| [Controls](docs/CONTROLS.md) | Per-device bindings, drawing, accessibility |
| [Admin commands](docs/ADMIN.md) | Who is an admin, every `;` command, adding commands |
| [Contributing](docs/CONTRIBUTING.md) | Setup, workflow, conventions, test helpers |
| [Changelog](CHANGELOG.md) | Release notes |

## Structure

- `src/shared` → ReplicatedStorage/Shared: types, config, the spell dictionary, pure logic
- `src/server` → ServerScriptService/Server: authoritative services, archetypes, map builders
- `src/client` → StarterPlayerScripts/Client: HUD, input, placement preview, menus
- `tests` → ServerScriptService/Tests: spec modules and runner
