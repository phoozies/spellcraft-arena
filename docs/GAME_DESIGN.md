# Game Design — Spellcraft Arena

*Working title.* An all-ages, cross-platform PvP game inspired by Scribblenauts: **draw a shape, get the spell, out-think your opponent.**

## Pillars

1. **Shapes are power.** Tracing a triangle raises a wall of earth (or a shield of wind) in your hands. Drawing is quick to learn, and the glyphs are all over the hub.
2. **Short, social, repeatable.** Rounds are quick, matches are best of 3, and you can be in a queue within 10 seconds of joining.
3. **Fair and kind.** Nothing is pay-to-win, there's no gore (knockouts "poof" into ink), and the visuals are bright and readable for all ages.
4. **Play anywhere.** PC, mobile, console, and VR each get first-class controls. Typing is never required: you can also tap or speak.

## Why these choices (research summary)

- **Retention drives discovery.** In June 2026 Roblox moved "Recommended For You" to a 28-day retention window. It rewards return visits, bringing friends, and spending, not clickbait. That's why the game has daily quests, a login streak, a first-win-of-the-day coin bonus, crates that unlock spells, a wins podium, a collection Spellbook, and party-friendly modes. ([Roblox](https://about.roblox.com/newsroom/2026/06/optimizing-discovery-great-games-reach-millions-players-roblox), [Discovery docs](https://create.roblox.com/docs/discovery.md))
- **What top games share** (Grow a Garden, RIVALS, MM2, Jujutsu Shenanigans): you start playing instantly, rounds are short, goals are visible, play is social, and mobile comes first. ([rowatcher](https://rowatcher.com/news/top-10-roblox-games-by-players-march-2026-data-breakdown))
- **Input:** typing and voice casting were replaced by drawing glyphs (a $1-style stroke recognizer on the server). It needs no keyboard or microphone, so it works for every device and all ages.
- **No LLM word interpretation:** `TextGenerator` comes with content-maturity disclosure requirements that conflict with an all-ages rating. A curated dictionary with synonyms keeps things safe and deterministic. ([TextGenerator](https://create.roblox.com/docs/reference/engine/classes/TextGenerator))

## Core loop

```
Hub ──► queue (pad or Play menu) ──► Match (best of 3)
 ▲                                     │
 │   win: coins + 1 win (podium) ◄────┘
 └── Crate Shop (coins → new elements), daily quests, login streak
```

### In a match

1. **Intro** (4s): a VS screen shows the mode, the map, and both teams with their avatars, then fades to black while everyone is moved into the arena. Your match **spellbook** is your **loadout** (your element's three base spells plus up to two crate spells), locked in for the match. These are the shapes you can draw.
2. **Countdown** (5s, frozen in place, with big 3 · 2 · 1 numbers), then **FIGHT!** and the **Round** (up to 120s). The last team standing wins the round. If time runs out, the team with the most remaining health wins.
3. A round banner announces the result ("BLUE WINS ROUND 1" or "DRAW"). Then comes the **Draft** (15s): you're offered **3 boosts** and pick one (Power +15% damage, Vitality +20 max health, Swiftness +3 speed, Focus -12% cooldowns, Health Potion). Boosts last for the rest of the match, stack up to 3 times, and a pick is made for you if time runs out. There are no new spells to earn in a duel.
4. **First to 2 round wins** takes the match. The **VICTORY!** screen (with confetti), **DEFEAT**, or **DRAW** shows the coins you won counting up (winners get 100, +50 for the first win of the day), then everything fades back to the hub.

Players have **100 HP**. In the hub health regenerates 5 HP/s; in matches and the Battleground it regenerates 1 HP/s, but only after 5 seconds without taking damage (`Config.PASSIVE_REGEN_*`). The Health Potion boost and healing spells are the way to heal mid-fight.

### Casting: draw it, stockpile it, spend it

- **Draw** a spell's glyph (hold **F** or tap ✏ Draw, then trace it) to add **one copy** of that spell to your hotbar. You hold **at most one copy of each spell**. The new copy is readied automatically. **You can only draw in the hub's Training Grove, the rounds of a match, and the Battleground.**
- **Cast** the readied copy: click, R2, tap the world, or pull the VR trigger. **Casting uses the copy up.**
- **Cooldowns:** every spell has its own cast cooldown (basic attacks 3s, fast slashes 2s, the rest up to 9s, ultimates 16-22s; see SPELLS.md). The hotbar shows the cooldown sweep on the slot.
- **Dash:** press **Q** (or the Dash button) to leap forward with three wind streaks behind you; 8 second cooldown.
- **Drawing cooldown:** 1 second between drawings, enforced by the server. The server reads the stroke itself, so the client can't claim a spell it didn't draw. The key that opens the canvas can be changed in **Settings**.
- **Point-and-click spells** (Fire Pillar, Water Nebula, Earth Punch) show their hit circle on the ground where you aim, and a ring for their range limit.
- **Placeables** show a ghost preview that follows your aim. Green means you can place it there, red means you can't. Rotate with R, L1/R1, or the ⟳ button.
- **Which shapes work:** only your loadout's shapes. Others fizzle with a hint. Each round starts empty-handed, so your first move is to draw.
- **Damage numbers** float over whatever you hit, in the hub and in matches. Yellow is damage, blue is shield absorbed, green is healing. Only the attacker and the target's owner see them.
- **Spell VFX and audio:** drawing a glyph pops it over your head; every cast raises the caster's arm and imprints the glyph in a magic circle at their feet. Heal sparkles, Black Hole streams motes inward, and each spell has its own cast and impact sound (`Audio/Cues`). Bolts trail element-themed particles (fire, water, wind), and impacts burst with light and a shockwave ring.
- **Health bars:** your own HP is shown top-left, with a shield overlay and a trailing damage bar. Bars also float over other players: blue for allies and red for enemies in a match, grey in the hub (shown only when hurt).

### Balancing for fast play

Players move fast (walk speed 24), so every bolt flies 1.5× faster and has a bigger hitbox against players and breakables (+2 studs on top of each spell's own generous radius), while still gliding over floors. Since you can stockpile up to 5 copies, the numbers are budgeted per cast cooldown:
- No normal hit takes more than 30 of your 100 HP, and ultimates (slot 5) take 30-40 on cooldowns of 15s or more.
- Burst damage is capped at 20 per second, which works out to about a 6-second kill.
- Hard crowd control can't be chained, thanks to 2.5s of immunity after it ends.
- Timed buffs (Fire Boost, Water Body, Air Boost, Air Shield) are up at most 60% of the time.
- Zones and summons are limited to one live copy per player per spell.
- Ultimates have cooldowns of 15s or more.

`tests/Balance.spec.luau` enforces all of these limits.

### Breakable cover

The Earth Wall is a sculpted earth wall (35 health) whose base, standing stones, and rubble break separately, so you can punch through it piece by piece. Most arenas also have breakable block walls. Blocks darken as they're damaged, chip on each hit, and shatter into tumbling chunks.

### PvP encouragement

- Coins and a win only for winning the match, plus a "SPELL STREAK!" callout at 3 KOs.
- Combos (Water Lock stuns an enemy for a Fire Pillar or Earth Punch), knockback ring-outs on the rim-less maps (Whirlwind, Tornado), and destructible cover.
- A wins leaderboard (player list), a Most Wins board, and a podium where the top 3 players in the server stand as their avatars. There's no PvP in the hub; it all happens in matches.
- Spawn protection lasts 3 seconds and friendly fire is off.

## Modes

| Mode | Players | Teams | Notes |
|---|---|---|---|
| 1v1 | 2 | Blue / Red | The Sparring Arena is weighted ×2 |
| 2v2 | 4 | Blue / Red | The Sparring Arena is weighted ×2 |
| 3v3 | 6 | Blue / Red | Full map |
| 4v4 | 8 | Blue / Red | Full map; never the Sparring Arena (too small) |

### Picking your team: the team boxes

The hub has **boxes for every team mode** (two each for 1v1 and 2v2, one each for 3v3 and 4v4). Every box has a **Blue side and a Red side**, with one spot per teammate. **Stand on a side to pick your team**, so friends can line up together before the match, and the sides show how many spots are filled (for example `BLUE 1/2`). When **both sides are full**, a 5-second countdown starts. It restarts if anyone steps off or swaps sides, and then the match starts with exactly those teams. A full side turns newcomers away with a hint to try the other side.

The **Play menu** also queues for any mode, including 3v3, with the teams balanced automatically.

### The Battleground (open world)

A blue **Battleground portal** in the concourse teleports you to a big open world far from the hub: four biomes (forest, meadow, desert, rocky highlands) ringed by mountains, with Raider camps, ruined stone circles, and the **Warlord's Keep** in the middle. You land at a **random open spot**, away from camps and other fighters. There is no queue and no match.

- **Players are enemies.** Anyone you knock out is out for 3 seconds, then respawns at a new random spot with spawn protection.
- **NPCs fight back.** Sand Raiders (melee) and Ember Mages (ranged) guard the camps, Stone Brutes (heavy hitters with knockback) the ruins, and the Dune Warlord (melee and bolts, very tough) the Keep. They chase when you get close, give up and heal if you run, and respawn after a while.
- **Knocking out an NPC pays coins** (3 / 5 / 12 / 40), up to 120 coins per 5 minutes so camps can't be farmed endlessly.
- You fight with your equipped element's spells and can raise Earth Walls anywhere. There are no wins or boosts; health regenerates slowly after 5 seconds without damage. Four **green gate pads** (or the **Return to Hub** button) take you home. You can't join a match queue while you're inside.

## Maps (7 duel maps plus the hub; the compact ones suit smaller matches)

Every map is built at design size and scaled 2x, and almost everything on them breaks: floors, cliffs, mesas, ramps, rocks, ice spires and cubes, trees, pillars, temple steps, arches, torches and cover break in a few spell hits (`Config.PROPS`, rock 45), while the **baseplate is far tougher** (240 per cell, about 16 Fireballs) so a fight can't dig through the ground quickly; heavier spells carve more. Each round starts on a fresh arena. Only the hub, the rock undersides and the Sparring Arena's imported colosseum and statue stay solid.

| Map | Identity | Signature mechanics |
|---|---|---|
| **Inkwell Plaza** (hub) | A round **floating island** over the ocean: a grass top with a sand beach, a dark rock cone underneath, a wooden rail, and a stepped white-marble amphitheatre, leaning pillars, a ruined arch and bare trees. A sand plaza with a giant inkwell and a stone wizard statue is at the centre | Four element shrines, Spellbook kiosk, Daily Quest chest and gift box on the plaza; the team boxes (1v1–4v4) in an arc to the north with the Arena Gate behind them; the Battleground portal to the south (opposite the duels); two Training Groves (west and east: build, smash dummies, the only hub places to draw and cast); marble roads to each; the Crate Shop (south-east); the wins podium + Most Wins board; four rim overlooks to **spectate the duels fought on arenas below the island** |
| **Crayon Canyon** | Paper canyon, 3 lanes split by mesas (open in every mode, no dividing gates) | Destructible rope bridges, giant crayon cover, ramps to high ground |
| **Sparring Arena** | A marble-pillared colosseum with sandstone seating and a neon rune ring | A roomy ~184-stud floor (the model scaled 4x), with pillars as cover; invisible walls keep everyone on the floor |
| **Frost Hollow** | A round sheet of ice with frozen spires | No rim wall: ring-outs; breakable ice cubes and spires |
| **Ember Forge** | A basalt floor in a lava moat, around a stepped anvil | Obsidian pillars and brick walls as cover; rim wall |
| **Moss Ruins** | An overgrown courtyard with broken marble arches | Lots of cover: toppled columns, mossy blocks, arches, trees (all breakable); rim wall |
| **Tidal Temple** | A sandy island around a three-step temple in shallow sea | Coral pillars and giant clams as cover; torches; rim wall |
| **Sky Bridge** | Two round platforms joined by a plank bridge, with a small island midway | No rim walls: ring-outs; breakable bridge planks |

Maps are built **from code** (`src/server/Maps/*.luau`) so they're versioned and identical on every server.

## Progression: coins, elements, and boosts (no levels)

Everyone starts with **150 coins** and picks **one element for free** the first time they open the Spellbook. Winning a match pays **100 coins** (+50 for the first win of the day); the daily login chest (25 × streak, capped at 7) and daily quests (25-60) pay coins too. Losing pays nothing, so wins are what the economy rewards.

Coins buy **elements** (400 each, in the Spellbook) and **Spell Crate** spins (100 each, at the hub's crate or the 🎁 Crates menu), which win a crate spell by rarity. Equip owned elements and build your two-spell extra loadout in the Spellbook (not during a match). Inside a duel, power comes from the **boosts** you pick between rounds, not from new spells. The full rules and the numbers' homes are in [ECONOMY.md](ECONOMY.md).

**Classes** (a second layer on top of elements) are planned but not built: see [CLASSES.md](CLASSES.md).

**Wins** are the leaderboard stat: shown in the player list, on the Most Wins board, and on the hub's podium, where the top 3 players in the server stand as their avatars.

## All ages and safety

- Matched spell names come from the dictionary. Raw player text is never shown, except through Roblox's own filtered chat.
- Knockouts are cartoon poofs with no blood.
- No paid random items: crates are bought only with coins earned in play. Planned monetization is cosmetic only (spell skins, trails, emotes), and boosts are never sold.
- There is no free text input: spells come from drawn strokes, which the server validates (point count, range, rate) and reduces to a spell id.

## Not yet built (backlog)

- Cosmetics shop and spell skins (cosmetic-only monetization)
- Party queueing (queue with friends as a team), and a friend-invite prompt (`SocialService`)
- Badges for win milestones (needs badge asset IDs)
- A global all-time wins board (OrderedDataStore)
- Localization tables (strings are centralized in UI modules, ready to extract)
- Spectator camera for knocked-out players
- Moving matches to reserved servers (TeleportService) if hub servers get crowded
