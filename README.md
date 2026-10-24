# Wordcraft Arena *(working title)*

A Scribblenauts-inspired PvP game for Roblox: **type or say a word, get the spell, outsmart your opponents.** It's built for all ages and plays on PC, mobile, console, and VR.

- Type "fireball", "rock wall", or "zap" in chat, the spell box, or out loud 🎤 to add a copy of the spell to your hotbar. You can hold up to 5, duplicates included, and copies of the same spell share a cooldown. You can submit one word per second, and pasting is blocked.
- Everyone has 100 HP with no regeneration in the arena. Walls break apart block by block, and every spell has its own effects and a cast animation.
- Placeables show a ghost preview before you put them down, and everything you build can be destroyed.
- 1v1, 2v2, 3v3, 4v4, and FFA, best of 3. In the hub, stand on the Blue or Red side of a team box to pick your team before the match. You start each match with 3 random spells you own, then draft a new card each round (cards have random rarities) until your hand holds 5.
- 8 spells. Everyone starts with Fireball, Water Lock, and Rock Wall. Win matches to earn coins, then spin crates (Common to Legendary) to unlock Gust, Zap, Heal, Black Hole, and Turret.
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
| [Spells](docs/SPELLS.md) | The dictionary, rarity, archetypes, how to add a spell |
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
