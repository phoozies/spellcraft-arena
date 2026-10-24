# Changelog

All notable changes to this project are documented here ([Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format).

## [Unreleased]

### Added
- **Copy model:** typing (or saying) a spell word grants one copy of that spell, never more than one per spell. Casting uses the copy up, so you re-type to recast. Each round starts empty-handed.
- **1-second typing cooldown** across chat, the spell box, and voice, with a draining bar under the spell box.
- **Paste blocking** in the spell box.
- **Floating damage numbers** everywhere: yellow damage, blue shield absorbed, green heals. Only the attacker and the target's owner see them.
- **Spellbook and recharge chips** above the spell box. The hotbar shows held copies, with a "type!" hint in the first empty slot.
- **Admin commands** with the `;` prefix (`AdminService`, `docs/ADMIN.md`): give, unlock, xp, level, heal, kill, god, speed, freecast, tp, bring, hub, startmatch, endmatch, clear, knockback, status, announce (filtered), kick, ban, unban.
- `tests/Balance.spec.luau`: per-spell budgets for damage, healing, shields, and crowd control under ~1s recasts.

### Changed
- **Rebalanced every spell for ~1s recasts.**
  - `cooldown` is now each word's recharge after casting: 0–2s for commons, 10s or more for legendaries.
  - Per-cast numbers are lower. For example, Fireball does 16 damage, Rock Wall has 140 HP, and Meteor does 30.
- **Hard crowd control can't be chained.** Root, Time Stop, and Shrink can't be refreshed and leave 2.5s of immunity.
- **Shields don't stack.**
- **Live caps:** lingering zones and summons are limited to one per player per spell.

### Changed (earlier)
- **Knockback, pulls, traps, and ring-outs are now server-authoritative.** The server briefly takes network ownership of the victim and applies the velocity itself. Self-beneficial movement (dash, balloon, pads) still runs on the client for responsiveness.
- **Projectiles run in one batched, error-guarded server loop** with no server Parts. Clients render bolts, debris poofs, chain beams, and zone spins from a new `Fx` remote.

### Fixed
- Profile locks are released when a player leaves mid-load, and stale locks expire after 5 minutes instead of 30.
- Players are released only once at shutdown.
- FFA teams now use UserIds, so duplicate display names no longer merge teams.
- Overlapping Shield casts no longer expire early.
- A quick voice re-press no longer ends the new session.
- The queue and slot remotes are rate-limited.
- Summons must be placed inside build areas.
- Debounce tables use weak keys.

## [0.1.0] — 2026-10-24

### Added
- Word-to-spell casting through chat, an on-screen spell box, push-to-talk voice (AudioSpeechToText), and hotbar taps.
- A 40-spell dictionary across 10 levels and 7 archetypes (Projectile, Control, Placeable, Zone, Buff, Movement, Summon), with aliases and typo tolerance.
- A placement ghost preview with valid/invalid tinting, plus destructible objects with health bars.
- Best-of-3 matches in 1v1, 2v2, 4v4, and FFA. Players start with 3 random owned spells and draft +1 per round (max 5) from cards with independently rolled rarities.
- The Inkwell Plaza hub (queue pads, Practice Grove, Sparring Ring, Spellbook, Daily Quests, leaderboard) and 3 arenas: Crayon Canyon, Frostbite Fortress, Sky Islands.
- Progression to level 10, a daily login streak, daily quests, and a first-win bonus.
- Session-locked DataStore profiles with autosave and BindToClose.
- Cross-platform input: keyboard/mouse, gamepad, touch, and VR.
- A dependency-free test runner with WordMatcher, LevelCurve, Rarity, and DraftRoller specs.
- Documentation: game design, architecture, spells, controls, and contributing.
