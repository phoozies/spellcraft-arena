# Game Design — Wordcraft Arena

*Working title.* An all-ages, cross-platform PvP game inspired by Scribblenauts: **say a word, get the spell, out-think your opponent.**

## Pillars

1. **Words are power.** Typing or saying "rock wall" puts a wall in your hands. Creativity matters more than reflexes.
2. **Short, social, repeatable.** Rounds are quick, matches are best of 3, and you can be in a queue within 10 seconds of joining.
3. **Fair and kind.** Nothing is pay-to-win, there's no gore (knockouts "poof" into ink), and the visuals are bright and readable for all ages.
4. **Play anywhere.** PC, mobile, console, and VR each get first-class controls. Typing is never required: you can also tap or speak.

## Why these choices (research summary)

- **Retention drives discovery.** In June 2026 Roblox moved "Recommended For You" to a 28-day retention window. It rewards return visits, bringing friends, and spending, not clickbait. That's why the game has daily quests, a login streak, first-win-of-the-day XP, a collection Spellbook, and party-friendly modes. ([Roblox](https://about.roblox.com/newsroom/2026/06/optimizing-discovery-great-games-reach-millions-players-roblox), [Discovery docs](https://create.roblox.com/docs/discovery.md))
- **What top games share** (Grow a Garden, RIVALS, MM2, Jujutsu Shenanigans): you start playing instantly, rounds are short, goals are visible, play is social, and mobile comes first. ([rowatcher](https://rowatcher.com/news/top-10-roblox-games-by-players-march-2026-data-breakdown))
- **Voice:** `AudioSpeechToText` was fully released in May 2026, so speaking spells is possible with push-to-talk. ([DevForum](https://devforum.roblox.com/t/full-release-speech-to-text-api/4357786))
- **No LLM word interpretation:** `TextGenerator` comes with content-maturity disclosure requirements that conflict with an all-ages rating. A curated dictionary with synonyms keeps things safe and deterministic. ([TextGenerator](https://create.roblox.com/docs/reference/engine/classes/TextGenerator))

## Core loop

```
Hub ──► queue (pad or Play menu) ──► Match (best of 3)
 ▲                                     │
 │      XP, level-ups, new spells ◄────┘
 └── daily quests, login streak, Spellbook collection
```

### In a match

1. **Intro** (4s): a VS screen shows the mode, the map, and both teams with their avatars, then fades to black while everyone is moved into the arena. Your match **spellbook** is **3 random spells from the ones you own**. New players own exactly Fireball, Water Lock, and Rock Wall. These are the words you can type this match.
2. **Countdown** (5s, frozen in place, with big 3 · 2 · 1 numbers), then **FIGHT!** and the **Round** (up to 120s). The last team standing wins the round. If time runs out, the team with the most remaining health wins.
3. A round banner announces the result ("BLUE WINS ROUND 1" or "DRAW"). Then comes the **Draft** (15s), while your spellbook has fewer than 5 spells: you're offered **3 cards, each with its own randomly rolled rarity**, and you pick one. If time runs out, one is picked for you. Your spellbook grows 3 → 4 → 5.
4. **First to 2 round wins** takes the match. The **VICTORY!** screen (with confetti), **DEFEAT**, or **DRAW** shows your XP counting up, then everything fades back to the hub.

Players have **100 HP** and **don't regenerate in the arena**; only healing spells restore health. The hub regenerates 5 HP/s.

### Casting: type it, stockpile it, spend it

- **Type** a spell word in chat or the spell box, or **say** it with 🎤, to add **one copy** of that spell to your hotbar. You can hold **up to 5 copies in any mix**, including 5 of the same spell. The new copy is readied automatically.
- **Cast** the readied copy: click, R2, tap the world, or pull the VR trigger. **Casting uses the copy up.** If you hold more copies of that spell, the next one is readied for you.
- **Shared cooldown:** all copies of the same spell share one cast cooldown (0.5–2s for commons, 4–25s for big spells; see SPELLS.md). The hotbar shows the cooldown sweep on every slot holding that spell.
- **Typing cooldown:** 1 second between words across chat, the spell box, and voice. Pasting into the spell box is blocked, so speed comes from actually typing. The key that opens the spell box can be changed in **Settings**.
- **Placeables** show a ghost preview that follows your aim. Green means you can place it there, red means you can't. Rotate with R, L1/R1, or the ⟳ button.
- **Which words work:** in a match, words outside your spellbook fizzle with a hint ("Draft it next round!"). In the hub, any spell you own works. Each round starts empty-handed, so your first move is to type.
- **Damage numbers** float over whatever you hit, in the hub and in matches. Yellow is damage, blue is shield absorbed, green is healing. Only the attacker and the target's owner see them.
- **Spell VFX:** every cast raises the caster's arm and flashes a magic circle at their feet. Bolts trail element-themed particles (fire, sparks, ice, water, wind), and impacts burst with light and a shockwave ring.
- **Health bars:** your own HP is shown top-left, with a shield overlay and a trailing damage bar. Bars also float over other players: blue for allies and red for enemies in a match, grey in the hub (shown only when hurt).

### Balancing for fast play

Players move fast (walk speed 24), so every bolt flies 1.5× faster and has a bigger hitbox against players and breakables (+1.5 studs), while still gliding over floors. Since you can stockpile up to 5 copies, the numbers are budgeted per cast cooldown:
- No single hit takes more than 34 of your 100 HP.
- Burst damage is capped at 20 per second, which works out to about a 6-second kill.
- Hard crowd control can't be chained, thanks to 2.5s of immunity after it ends.
- Shields don't stack.
- Zones and summons are limited to one live copy per player per spell.
- Legendaries have cooldowns of 10s or more.

`tests/Balance.spec.luau` enforces all of these limits.

### Breakable cover

Rock Wall and Castle are built from separately breakable blocks, so you can punch holes through them. Every arena has breakable brick walls, and the hub's Practice Grove has one that rebuilds itself. Blocks darken as they're damaged, chip on each hit, and shatter into tumbling chunks.

### PvP encouragement

- XP for knockouts, round wins, and match wins, plus a "SPELL STREAK!" callout at 3 KOs.
- Combos (Water Lock → Lightning deals ×2), knockback ring-outs on Sky Islands, and destructible cover.
- A session leaderboard in the hub, and the hub Sparring Ring for opt-in PvP between matches.
- Spawn protection lasts 3 seconds and friendly fire is off.

## Modes

| Mode | Players | Teams | Notes |
|---|---|---|---|
| 1v1 | 2 | Blue / Red | Small-mode walls shrink the map |
| 2v2 | 4 | Blue / Red | Small-mode walls shrink the map |
| 4v4 | 8 | Blue / Red | Full map; Frostbite Fortress is weighted ×2 |
| FFA | 2–8 | everyone alone | Starts at 8 players, or 15s after reaching 2; Sky Islands is weighted ×2 |

## Maps (all designed for 8 players)

| Map | Identity | Signature mechanics |
|---|---|---|
| **Inkwell Plaza** (hub) | Cobblestone plaza around a giant inkwell | Queue pads, Practice Grove (build anything, smash dummies), Sparring Ring, Spellbook kiosk, Daily Quest chest, leaderboard |
| **Crayon Canyon** | Paper canyon, 3 lanes split by mesas | Destructible rope bridges, giant crayon cover, ramps to high ground |
| **Frostbite Fortress** | Snowy castle courtyard | Corner towers, central keep, slippery ice patches, breakable ice gates |
| **Sky Islands** | Floating islands over the void | Jump pads, ring-outs, breakable cloud blocks |

Maps are built **from code** (`src/server/Maps/*.luau`) so they're versioned and identical on every server.

## Progression (levels 1–10)

| Level | Total XP | Unlocks |
|---|---|---|
| 1 | 0 | Fireball, Water Lock, Rock Wall |
| 2 | 100 | Wind Gust, Wooden Crate, Heal Leaf, Spark |
| 3 | 250 | Ice Shard, Bounce Pad, Mud Puddle, Shield |
| 4 | 450 | Lightning, Ladder, Dash, Cannon |
| 5 | 700 | Tornado, Snowman, Bridge, Banana Peel |
| 6 | 1000 | Meteor, Teleport, Vine Snare, Tower |
| 7 | 1400 | Dragon, Black Ice, Magnet, Balloon |
| 8 | 1900 | Volcano, Mirror, Robot, Giant |
| 9 | 2500 | Black Hole, Castle, Shrink, Rainbow |
| 10 | 3200 | Phoenix, Earthquake, Time Stop, Kraken, Wizard Hat |

**XP sources:** 40 per match, +20 per round won, +40 per match won, +10 per knockout, +100 for the first win of the day, a daily login chest (25 × streak, capped at 7 days), and daily quests (50–100 each). A match pays roughly 40–140 XP, so reaching level 10 takes about 30–50 matches. All values live in `Config.luau` and `LevelCurve.luau`.

## All ages and safety

- Matched spell names come from the dictionary. Raw player text is never shown, except through Roblox's own filtered chat.
- Knockouts are cartoon poofs with no blood.
- No paid random items. Planned monetization is cosmetic only (spell skins, trails, emotes), and the draft is never sold.
- Voice transcripts go only to the speaking player, as "Heard: …" feedback.

## Not yet built (backlog)

- Cosmetics shop and spell skins (cosmetic-only monetization)
- Party queueing (queue with friends as a team), and a friend-invite prompt (`SocialService`)
- Badges per level (needs badge asset IDs)
- Localization tables (strings are centralized in UI modules, ready to extract)
- Spectator camera for knocked-out players
- Moving matches to reserved servers (TeleportService) if hub servers get crowded
