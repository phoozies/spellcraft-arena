---
name: new-feature
description: Step-by-step process for adding a gameplay feature to Spellcraft Arena (server service plus client controller, remotes, config, tests, docs). Use when asked to build a new system or mechanic that is not just a spell or a map.
---

# Adding a feature

Follow in order. Read `repo-map` first if you do not know where things live. **Start by creating a `feature/<name>` branch from `main`** (the git workflow in `CLAUDE.md`); `ship-change` covers committing, merging, deleting the branch, and syncing to Roblox at the end.

1. **Find the owner.** Check `docs/semantic/features.yaml` for an existing feature to extend. Decide which service owns each piece of state (rule 2 in `CLAUDE.md`). Never write `profile.coins`, `stats.wins`, `elements`, `spells` or `loadout` outside their owner.
2. **Tunables first.** Add numbers to `src/shared/Config.luau` (or the right data module: `SpellDefinitions`, `Chests`, `Rarity`, `Elements`, `Boosts`). Nothing hard-coded in a system.
3. **Remotes.** Add each new remote to `src/shared/Net/Remotes.luau` with a one-line payload description. The client only sends intent.
4. **Server service** in `src/server/Services/<Name>Service.luau`: `--!strict`, a header comment saying what it owns, `init()` then `start()`. Register it in `src/server/init.server.luau` at the right place in the order. Every remote handler validates **type, range, ownership and rate** (see the `roblox-dev:roblox-security` skill). Clean up per-player state on `PlayerRemoving` (weak-keyed tables are fine).
5. **Client controller** in `src/client/Controllers/<Name>Controller.luau` with the same `init()`/`start()` shape, registered in `src/client/init.client.luau`. UI uses `UI/Theme` builders and `UI/Responsive`, touch targets of at least 52 px, and `Selectable` buttons for gamepad. The client displays state; it never decides it.
6. **Fallbacks.** Models may be missing (`ModelKit.clone` can return nil); draw plain shapes instead.
7. **Tests.** Put pure logic in a module that tests can require, and add or extend `tests/<Name>.spec.luau` (it returns `function(t) t.describe(...) end`; the runner picks it up). Balance-affecting changes must keep `tests/Balance.spec.luau` green.
8. **Run it for real** with `test-in-studio`: sync, run the tests, playtest the feature, read the console.
9. **Docs and changelog** with `ship-change`.

## Typical file set

```
src/shared/Config.luau                      (tunables)
src/shared/Net/Remotes.luau                 (remotes)
src/server/Services/FooService.luau         (+ register in src/server/init.server.luau)
src/client/Controllers/FooController.luau   (+ register in src/client/init.client.luau)
tests/Foo.spec.luau
docs/semantic/features.yaml                 (new `- id: foo` entry)
docs/<the human doc for the area>.md
CHANGELOG.md
```

## Review

For remote, DataStore or performance changes run the `roblox-dev:roblox-reviewer` agent before finishing.
