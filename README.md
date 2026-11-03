# Spellcraft Arena *(working title)*

A Scribblenauts-inspired PvP game for Roblox: **draw a shape, get the spell, outsmart your opponents.** It's built for all ages and plays on PC, mobile, console, and VR.

- Draw a shape to add a copy of a spell to your hotbar: tap a spell card (or press its key, 1-5) to trace its shape, or press **F** / tap Draw for a blank canvas. The shape is the kind of move: circle = a basic attack, a diagonal slash = a fast attack, a square = a boost, a triangle = a defense or a stun, a lightning bolt = a heavy attack, a V = an area attack, a star = your ultimate; chest spells add a heart, zigzag, hook, X, and spiral. The closer you trace it, the stronger the spell. You draw with a wand: your stroke is written in the air in front of you as a glowing ribbon of light, then pulled into the wand. You hold one copy of each loadout spell (slot N is the Nth spell), each spell has its own cooldown, and you can draw one spell per second.
- Everyone has 100 HP. The hub heals you fast; fights have no passive regeneration (heal with spells and the Health Potion boost). Fall off an arena and the water under it throws you back onto your spawn pad. Walls and almost all scenery break apart, and every spell has its own effects, sounds, and cast animation.
- Placeables show a ghost preview before you put them down, and everything you build can be destroyed.
- 1v1, 2v2, 3v3, and 4v4, best of 3. In the hub, stand on the Blue or Red side of a team box to pick your team before the match. Your loadout (your element's three spells plus two chest spells) is your spellbook, and between rounds you pick a boost. For a drop-in fight with no queue, step into the **Battleground** portal: a big open world where players and raiders are enemies. Knock out NPCs for coins.
- 24 spells: 4 elements (Fire, Water, Earth, Air) with three base spells each, plus 12 chest spells in five rarities. Pick one element free, then win matches to earn coins to buy the others (400) and to open chests (five of them, Common 100 to Legendary 2,000 coins; each drops its rarity or better, and every 10th Common-Rare chest without an Epic is guaranteed one). Between rounds you pick a boost (more damage, health, speed, faster spells, or a Health Potion) instead of earning spells.
- Wins show on the player list, a Most Wins board, and a podium in the hub where the server's top 3 stand as their avatars.
- A round floating-island hub, and 7 duel arenas summoned below it so hub players can watch the fights: Crayon Canyon, Sparring Arena (a colosseum), Frost Hollow, Ember Forge, Moss Ruins, Tidal Temple, and Sky Bridge.

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
| [Economy](docs/ECONOMY.md) | Coins, elements, chest, wins leaderboard, podium |
| [Semantic layer](docs/semantic/features.yaml) | Machine-readable feature map for AI agents (start at [CLAUDE.md](CLAUDE.md)) |
| [Spells](docs/SPELLS.md) | The 4 elements and 24 spells, rarities, drawing quality, boosts, archetypes, the spell registry, how to add a spell |
| [Classes](docs/CLASSES.md) | Planned, not built yet |
| [Architecture](docs/ARCHITECTURE.md) | Code layout, cast pipeline, PvP rules, data and security |
| [Controls](docs/CONTROLS.md) | Per-device bindings, drawing, accessibility |
| [Admin commands](docs/ADMIN.md) | Who is an admin, every `;` command, adding commands |
| [Contributing](docs/CONTRIBUTING.md) | Setup, workflow, conventions, test helpers |
| [Changelog](CHANGELOG.md) | Release notes |

## Structure

- `src/shared` → ReplicatedStorage/Shared: types, config, the spell dictionary, pure logic
- `src/server` → ServerScriptService/Server: authoritative services, archetypes, map builders
- `src/client` → StarterPlayerScripts/Client: HUD, input, drawing, menus, effects, tutorial
- `src/character` → StarterCharacterScripts (replaces Roblox's default health regen), `src/loading` → ReplicatedFirst (join screen)
- `tests` → ServerScriptService/Tests: spec modules and runner
- `tools` → Studio sync without Rojo, Blender model specs, the spell-registry generator, art scripts
