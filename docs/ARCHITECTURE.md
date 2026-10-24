# Architecture

A Rojo project in `--!strict` Luau. The server is authoritative for everything. Clients send intent only (a word, an aim point, a placement rotation, a draft pick), and the server re-validates all of it.

## Layout

```
src/shared  → ReplicatedStorage.Shared      pure data + logic used by both sides
  Config.luau                 all tunables (timers, XP, limits, modes)
  Types.luau                  shared types (SpellDef, Profile, MatchState…)
  Net/Remotes.luau            the one registry of every RemoteEvent
  Spells/SpellDefinitions     the 40-spell dictionary (data only)
  Spells/WordMatcher          text/voice → spell id
  Spells/Rarity               weights, colors, glyphs, roll()
  Spells/Placement            placement rules shared by ghost preview + server
  Match/DraftRoller           draft card rolling (injectable RNG)
  Progression/LevelCurve      XP thresholds and unlocks
  Util/Signal                 tiny module-to-module event

src/server  → ServerScriptService.Server    (init.server.luau bootstraps)
  Services/
    PlayerDataService   session-locked DataStore profiles, autosave, BindToClose
    ProgressionService  XP, levels, unlocks, daily login/quests, first win
    StatusService       timed effects (Root, Slow, Shrink, TimeStop, Slippery, buffs)
    DestructibleService single damage path, health bars, knockouts, push
    HandService         held spell copies (1 per spell), match spellbook, readied spell, recharges
    CastService         validates casts, builds CastContext, dispatches archetype
    Archetypes/*        Projectile, Control, Placeable, Zone, Buff, Movement, Summon
    SpellInputService   chat hook + spell box remote → 1s typing cooldown → WordMatcher → HandService.grant
    AdminService        ";" admin commands (chat or spell box), server-side admin check
    VoiceService        push-to-talk AudioSpeechToText → SpellInputService
    ArenaService        builds map templates, instanced arenas, jump pads
    MatchService        queues, round state machine, drafts, teams, PvP rules
    HubService          builds the hub, spawning, pads, dummies, sparring, board
    DebugService        Studio-only test commands
  Maps/                 MapKit + one builder per map (code-built, versioned)

src/client  → StarterPlayerScripts.Client   (init.client.luau bootstraps)
  Controllers/
    ClientState         mirror of server state + change signals
    HudController       hotbar, spell box, mic, XP bar, match bar, toasts, feed
    MenuController      Play / Spellbook / Quests panels
    DraftController     draft cards
    PlacementController ghost preview
    InputController     per-device bindings + aiming (mouse, pad, touch, VR)
    EffectsController   self boosts, slippery friction, team outlines, camera reset
    FxController        renders projectiles, poofs, beams, SpinFx from Fx events
  UI/Theme              shared look and builders

tests/      → ServerScriptService.Tests     Runner + *.spec modules
tools/      studio-sync.js / .luau          fallback sync without the Rojo CLI
```

## Bootstrapping

Both entry points use the same two phases, in a fixed order:

1. `init()`: create state and look up remotes. No yielding cross-service calls.
2. `start()`: connect events and start loops (each runs in `task.spawn`).

`Players.CharacterAutoLoads = false`. Spawning is explicit: `MatchService.spawnInHub`, or `spawnRound` for arenas. Dead players therefore stay out until the next round instead of popping back into the hub.

Some dependencies would form a cycle, so they're injected instead of required:

- `DestructibleService.setRelationResolver(fn)`: MatchService decides who may damage whom.
- `CastService.setWorldHooks(hooks)`: MatchService supplies the team, the structures folder, and the build regions.

## Cast pipeline (copy model)

```
client: word ──SubmitWord──► SpellInputService
                               ├ ";" prefix + admin → AdminService (never shown in chat)
                               ├ 1s typing cooldown (per player, all sources)
                               └ WordMatcher → HandService.grant
                                    ├ already holding it? → just ready it
                                    ├ match: in spellbook? hub: owned?
                                    ├ word recharging? → refuse
                                    └ add ONE copy (max 5 held) and ready it
client: aim  ──CastSpell───► CastService
                               ├ alive? not frozen/time-stopped?
                               ├ holding a copy of the readied spell; global lockout 0.35s
                               ├ clamp target to range (placeables: 40 studs)
                               ├ build CastContext {team, structures, buildRegions, enemiesNear…}
                               ├ Archetypes[def.archetype].cast(ctx)  → false = rejected, copy kept
                               └ HandService.consume (copy used up) + startRecharge(def.cooldown)
```

- **Paste blocking** is client-side (`HudController.guardAgainstPaste` undoes any text change of more than one character). The server's typing cooldown is the real limit, and it also covers chat and voice.
- **Damage numbers:** `DestructibleService.damage` and `heal` send `Fx("number", position, amount, kind)` to the attacker and the target's owner only. `FxController` draws them.
- **Crowd-control immunity:** `StatusService.apply` refuses to refresh an active Root, Time Stop, or Shrink, and adds a 2.5s immunity after it ends (`Config.CC_IMMUNITY`).

- **Damage** always goes through `DestructibleService.damage(target, amount, attacker, spellName)`. It resolves players, placed objects, summons, and map props the same way, and applies spawn protection, Shield, Shrink/Giant modifiers, and the Phoenix revive.
- **Knockback is server-authoritative.** `DestructibleService.push` briefly takes network ownership of the victim's root (`SetNetworkOwner(nil)`), sets the velocity on the server, and returns ownership after 0.45s. Overlapping pushes extend the hold. A client that ignores remotes still gets knocked back, pulled, tripped, and rung out.
- **Self-beneficial movement** (Dash, Balloon, bounce pads, jump pads) uses `DestructibleService.boost`, which the owner's client applies through the `Impulse` remote for responsiveness. Skipping a boost only hurts the cheater.
- **Projectiles** are server-simulated sphere-casts in **one shared Heartbeat loop** (`Archetypes/Projectile.luau`), capped at 300 in flight. Each step is `pcall`-guarded, so an error ends that projectile instead of leaking it. The server creates **no Parts** for them. It fires one `Fx("projectile", …)` event at launch and one `Fx("projectileEnd", …)` at impact, and clients (`FxController`) draw the bolt along the same line. Projectiles pass through your own and allied structures and bounce off Mirror.
- **Cosmetic effects** (debris poofs, chain-lightning beams, the Tornado and Black Hole spin) are all rendered client-side from `Fx` events or the `SpinFx` tag. Clients skip effects more than 600 studs away, so concurrent arenas don't draw each other's effects.

## PvP rules (`MatchService.relation`)

| Situation | May damage? |
|---|---|
| Both in the same match, round active, different teams | ✅ |
| Same team / different matches / draft or countdown | ❌ |
| Hub: both players inside the Sparring Ring | ✅ |
| Training dummies | ✅ always |
| Map props | ✅ only by players in that arena's match |

## Matches and arenas

- **One place, instanced arenas.** Templates are built once into `ServerStorage.MapTemplates`. Each match clones one to `x = slot × 2000, y = 400`, so several matches run at once. Each round, `ArenaService.rebuild` swaps in a fresh copy, which restores broken props.
- **The arena contract** is documented in `Maps/MapKit.luau` (`Bounds`, `Spawns/Team1_*`, `Team2_*`, `FFA_*`, `SmallModeWalls`).
- **To move matches to reserved servers later:** keep MatchService's state machine and replace `ArenaService.create` / `spawnAt` with `TeleportService:ReserveServer` and a match place that reads its mode from `TeleportData`.

## Data

The profile (`Types.Profile`, schema 1) is stored under `PlayerProfiles_v1/u_<userId>` as `{ data, lockJobId, lockTime }`.

- **Load:** `UpdateAsync` takes the lock if it's free, ours, or stale (> 30 min). Otherwise it retries with backoff, and finally kicks the player instead of risking a dupe.
- **Save:** autosave every 90s, release on leave, and flush in `BindToClose`. A save never overwrites a lock owned by another server.
- **Studio without API access:** the player gets a temporary profile that is never saved, with one retry.
- **Migrations:** `reconcile()` fills in new fields. Bump `SCHEMA` and transform there for breaking changes.

## Security checklist

- Every remote handler type-checks its arguments (`typeof`, NaN and range checks, string length limits).
- Words are limited to one per second across chat, box, and voice.
- Debug commands only run when `RunService:IsStudio()`.
- Admin status is decided server-side on join (UserId list, place or group owner, or Studio). A non-admin's `;` message is delivered as plain chat. Commands run in their own thread and are logged.
- `;announce` text goes through `TextService:FilterStringAsync` before broadcast.
- The client never reports damage, hits, cooldowns, or ownership. It only sends intent.
