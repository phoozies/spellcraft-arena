# Changelog

All notable changes to this project are documented here ([Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format).

## [Unreleased]

### Added (clicking buttons in first person)
- **Press Shift to get the cursor** (new `CursorController`, keys in `Config.CURSOR`), like Roblox's shift lock: it stays out until you press Shift again, or until a window or the canvas opens and closes. This replaces holding Left Alt, and Roblox's own shift lock is turned off.
- **Shift lock icon in the bottom left** (PC only, Roblox's built-in textures): blue while the mouse is locked, white while the cursor is out. Click it to go back to aiming.
- **The cursor hint now shows in fights too** (Return to Hub has no key) and changes while the cursor is out.
- **The spectate bar frees the mouse**, and the tutorial now tells PC players how to reach the glowing button.

### Added (Battleground button)
- **The Play window has a Battleground button** (`EnterBattleground` remote). It follows the same rules as walking into the portal, and is hidden while you are already there.

### Changed (bigger buttons on touch)
- **Bigger touch targets on phones and tablets:** spell cards, Return to Hub, Party, window Close buttons, and the tutorial's Skip. Party moves beside the side menu on touch so they can't overlap. The hidden button that frees the mouse is no longer shown on devices without a mouse.

### Changed (slower bolts, slower camera)
- **Bolts fly a third slower** (`Config.PROJECTILE_SPEED_SCALE` 1.5 to 1; a Fireball now moves 95 studs a second instead of 142). This covers every projectile, including NPC and turret shots.
- **Bolts track more often and curve more visibly:** the assist's cone is 15° (was 10°). The turn rate stays 60°/s, which now bends a slower bolt further. A steady walker gets hit; reversing direction up close still dodges (`tests/AutoAim.spec`).
- **Mouse look is slower again:** 25% by default (`Config.CAMERA`), down to 5% in Settings, in 5% steps. Schema 7 moves profiles still on the old 50% default to the new one; a value you chose yourself stays.

### Changed (the sight)
- **The target indicator is gone: you just have a sight**, one small dot (`CrosshairController`, replaces `LockOnController`). No brackets, ring, spell name or cooldown text around it.
- **Every spell now follows the sight** (`CastService.resolveAim`). Strikes and lines land exactly where it stops, walls and turrets stand on the first solid thing along it, bolts fly along it, and self-cast spells ignore it. Hit circles no longer snap onto an opponent, so they show where the spell really lands.
- **Only bolts keep an aim assist, now invisible and narrower** (cone back to 10°, 25° up close), because the camera can't turn while drawing. It now picks the opponent **closest to the sight** rather than the nearest one, so a spell doesn't curve toward someone you weren't looking at. `Config.AUTO_AIM.ASSIST = false` turns it off.
- **Nothing lands through a wall:** the server stops aim at the first solid surface, whatever the client sends.
- **Mouse look is slower** (50% by default), with a new **Camera speed** setting (`Config.CAMERA`, `profile.settings.camera`).

### Changed (UI)
- **New minimal look** (`UI/Theme`): flat near-black surfaces, off-white text, one warm accent, hairlines instead of outlines, one typeface (Builder Sans). Bevels, studs, shadows, rims and bouncy animations are gone.
- **The HUD is down to the essentials:** a row of small spell discs with their keys, a thin health bar, F and Q chips, and small pills for coins and the match. Draw and Dash are big buttons on touch only. The health bar and chips hide in the hub when they have nothing to say.
- **Plainer screens:** one-line match bar, plain-text kill feed, a quiet Settings list, a simple loading screen, plain sigils (no rune stones or spinning).

### Changed (first-person view while drawing)
- Your own raised arm, 3D magic circle and air ribbon no longer cover the view while you draw. Other players still see them. Trace lines and ink are thinner, and the title no longer overlaps the match bar.

### Added
- **M opens the menu** (Settings during a match), so you no longer need to hold Left Alt to reach it.
- **Refusals now say why:** a short line under the sight ("Can't cast that there."), as well as the buzz.

### Fixed
- Spell cards and the Draw button couldn't be clicked while the canvas was open, because the canvas sat on top of them and swallowed the click. Switching spells by click, and tapping Draw to cancel on touch, now work.
- Stale text: the match bar's "Draft a spell!" (it's a boost pick) and loading tips about holding copies and spinning.

### Changed (draw to cast)
- **Finishing a shape casts the spell at once.** There is no click, tap, R2 or trigger to cast any more, and spells can't be stored: the hotbar, held copies and readied slot are gone (`HandService` became the much smaller `SpellbookService`; remotes `CastSpell`, `SelectSlot` and `HandUpdated` are removed, `SpellbookUpdated` is new). `DrawSpell` now carries the point under the crosshair and the placement rotation.
- **Keys 1-5 and the spell cards open a spell's shape to trace** (the D-pad cycles them); the cards moved down to the bottom of the screen and show their key. A spell on cooldown can still be previewed, but finishing its shape fizzles.
- **Aiming reworked for no click:** the crosshair and lock-on brackets stay up over the canvas, and brackets now show wherever you can draw, so you know who you will hit before you start. A traced ground strike or wall still previews where it lands. The gamepad stick that draws no longer turns the camera. The auto-aim cone widened from 10° to 15°, since you can't turn while drawing.
- **Walls and turrets:** they now stand side-on to you by default (R still turns them), land at most 20 studs away instead of 40 (looking straight ahead used to put a wall at the far limit), and the aim ray ignores characters, so aiming through an opponent no longer blocks the placement.
- **The tutorial's "draw" and "cast" steps are one step.**
- **Admin: `;give` is now `;cast <player> <spell|all>`**, which casts where the player faces and reports how many worked; the panel's Spells tab uses it.
- **Hardening:** the 1s draw cooldown now runs before the draw gate, so spamming strokes outside a fight can't flood every client with `glyphFail`; `rotationY` must be finite; a player leaving mid-match no longer recreates their spellbook state.

### Changed (first person and auto-aim)
- **The game is first person, everywhere** (new `CameraController`: `LockFirstPerson`, FOV 80). Your right arm and wand stay visible, so you see the wand raise and the magic circle open when you draw.
- **You never aim with the mouse.** Every device casts at the crosshair in the middle of the screen. The server then **auto-aims** (new pure `shared/Util/AutoAim`, `Config.AUTO_AIM`, `CastService.resolveAim`): for bolts, ground strikes and lines it locks onto the **nearest opponent in plain sight near the crosshair** (players, hostile NPCs, training dummies). The cone is 10°, widening to 30° up close and never narrower than the target itself; candidates rank by distance inflated by how far off-centre they are, and line of sight is only raycast in rank order. Bolts are **led** toward a moving target and **home slightly** (60°/s) until dodged by more than 75°; clients steer their copy the same way (new Fx `projectileTurn` corrections). Walls, boosts, dashes and turrets go exactly where you look.
- **New crosshair and lock-on marker** (new `LockOnController`, replaces `CursorController`): a centre crosshair in the readied spell's colour (red with the cooldown), and corner brackets that snap onto the opponent your spell will hit. Ground-strike circles snap under that opponent.
- **Getting the mouse back** (new `UI/MouseLock`): menus, the Chest Shop, the boost pick, the map vote, the party panel, the admin window and the drawing canvas free the mouse while open; hold **Left Alt** anywhere else (a hint shows outside fights). A free mouse never casts.

### Changed (crates are now chests, in five rarities)
- **The Spell Crate is gone; the Chest Shop sells five chests**: Common (100), Uncommon (250), Rare (500), Epic (1,000), Legendary (2,000) (`shared/Economy/Chests`, replaces `Economy/Crates`). Each wins a chest spell of **its rarity or better**, by the rarity weights renormalised (a Rare Chest is Rare 60%, Epic 30%, Legendary 10%). **Epic and Legendary chests never give a duplicate** while a spell they can drop is unowned. Duplicates pay back 30% of the chest's price. The pity (10th Common-Rare chest without an Epic) is kept. The shop won't sell a chest whose every spell you own.
- Renamed everywhere: `ChestService`, `ChestController`, remotes `OpenChest` / `ChestOpened`, types `ChestDef` / `ChestResult`, `SpellDefinitions.chestSpells`, funnel step `FirstChestOpen`, sound cues `chest*`, admin `;chest <player> [rarity]`, debug `("chest", "Common")`.
- **The hub's Chest Shop stage shows all five chests** (new `ShopChest` / `ShopChestOpen` block models: a domed treasure chest whose bands and gem take the rarity colour), each glowing brighter the rarer it is, with its price; its prompt opens the shop on that chest, and the chest throws its lid open while your reel spins.
- **New Chest Shop panel**: a shelf of the five chests as 3D previews, the picked chest's odds as animated bars, how many of its spells you own, the pity count, and Open; the reel is rolled from that chest's odds.

### Changed (flat maps)
- **Every duel map is now flat**, rebuilt on a shared `Maps/FlatArena` builder: one level board of breakable tiles painted with a soft checkerboard, a **Blue half and a Red half**, and a centre line and mark; **point-symmetric cover** (brick walls, low walls, pillars, blocks, trees) so both teams get the same map; glowing spawn pads and team-coloured edge lights; a glowing small-mode ring for 1v1 and 2v2. Sparring Arena, Frost Hollow and Sky Bridge (now one long lane) are open for ring-outs; Crayon Canyon (three lanes), Ember Forge, Moss Ruins and Tidal Temple are walled. No more ramps, mesas, bridges or the imported colosseum.
- **The Battleground is a flat board too**: 30-stud ground tiles painted by biome with stone roads from the gates to the Warlord's Keep, low square rocks, low blocky cliffs instead of tall mountains, and a lower keep.

### Changed (UI)
- **New look, "spellbook at night"** (`UI/Theme`): deep indigo panels with a top-lit gradient, gold headings, white text, rounder corners, a glowing rim and drop shadow on windows that pop in when opened, and gem-coloured buttons that **pick readable text automatically** and lift on hover / squash on press. New `Theme.pill`, `Theme.shadow`, `Theme.inkFor`, `Theme.juice`.

### Improved (drawing recognition)
- The recognizer finds the best rotation from its exact **least-squares angle** (as in Protractor) and only polishes it, instead of searching the whole ±45° range: faster, and it can't settle in the wrong dip.
- **Closing a shape past its start** (a circle that loops on) no longer costs accuracy: the overshoot is trimmed.
- A flat V is no longer thrown away as a "line" when slashes aren't allowed; only a clearly straight stroke is.

### Fixed
- Round floors built with `MapKit.terrainDisc` were missing their centre cell (a hole in the middle of the floor).

### Added (watch others draw, magic circles)
- **Everyone near you watches you draw.** Your stroke is streamed while you draw (new `AirStroke` remote, small batches every `Config.WAND.STROKE_SEND_RATE`); the server checks it (canvas open, batch size, point range, a rate bucket, a cap per stroke; `WandAir.cleanPoints`) and relays it to players within `RELAY_RANGE`, whose screens write the same glowing ribbon in the air in front of you, in your ink colour.
- **A magic circle opens in the air** in front of anyone drawing: a faint glass disc, two rings of light, rune stones, and a six-pointed star turning against them; it spins up fast as it opens, then settles. It stands upright facing where the drawer looks (`DrawingState` now sends the facing, kept as the `DrawLook` attribute; `WandAir.facing`), and the stroke is drawn on it. It stays open until the drawing's verdict: readied flashes it (and the ribbon) in the quality colour and pulls the ribbon into the wand; a fizzle crumbles the ribbon (new Fx `glyphFail` from `SpellInputService`). Your own circle opens at once, without waiting for the server.

### Changed (spell UI)
- **Every spell now shows as a sigil** (`UI/Sigil`): its shape in glowing ink (new `GlyphView.glow`: halo, glow, core and shine, all opaque so nothing beads) inside a small night-blue magic circle ringed in the spell's colour with rune stones, the drawing canvas's look.
- **Spell cards** (Spellbook, loadout, collection, Spell Crate reel) get a band of the spell's colour, the sigil, the name, and a rarity or school pill; unwon spells are grey with a "?" sigil.
- **Hotbar slots show the spell's sigil once a copy is ready in them** (they showed only the name); the readied slot's rune ring turns. An empty slot shows only the dimmed name of the spell that fills it, no sigil.
- **The cards above the hotbar** match: a colour band and sigil; hovering lifts a card, and the card you are tracing lifts further with its accent outline and a spinning sigil.
- The Spellbook's spell picture, the canvas banner, and the hub's element shrines use the glowing sigil ink too.

### Added (the wand, 3D drawing)
- **Every player holds a wand.** A new `Wand` block model (wood grip and shaft, gold bands and prongs, a crystal tip; `tools/blender/block_models.py`, `assets/models/blocks/Wand.fbx`) is welded to the right hand on every spawn by the new `WandService`. Its crystal, halo and runes take your element's colour and change when you switch element. It can't collide or be hit. Without the model a plain stick is used.
- **Drawing happens in the world.** Opening the canvas raises your wand for everyone (`CastPoses.WandDraw`, held until the canvas closes): the tip glows and sparks, and a rune circle turns at your feet. Your stroke is written in the air in front of you as a glowing ribbon of light, fed by a curved beam from the wand tip. When the server recognizes it, the ribbon flashes in its quality colour and is pulled into the wand with a burst and a flick (`WandFlick`); a failed drawing turns red and crumbles in a puff of smoke. Other players see your wand trace the clean glyph in the air, then absorb it (Fx `glyph` now carries the quality). This replaces the glyph that popped over your head.
- New remote `DrawingState(on)` (the canvas opened or closed; type-checked, opening rate limited, sets the character's `Drawing` attribute), `Config.WAND`, `Util/WandAir` (pure wand geometry), `Fx/WandVfx`, `WandController`, `CastAnimations.stop`, cues `wandCharge` and `wandAbsorb`, `tests/Wand.spec.luau`.

### Changed (drawing canvas)
- **A brand-new canvas.** The flat dark overlay is now a vignette that darkens only the screen's edges, so you can watch your wand's drawing. A rune circle in the spell's colour turns behind the guide, and the banner is a studded pastel card with the spell's glyph. The guide is a clean see-through shape with a soft glow (drawn in CanvasGroups, so no darker beads where pieces overlap) and a comet that shows how to trace it.
- **Glowing ink.** Your line has a soft glow, a solid core and a bright shine in the spell's colour (or your element's on a blank canvas), with a pulsing pen orb and sparks flying off the tip. A recognized drawing flashes its quality colour and collapses into the middle; a failed one shakes, turns red and fades.
- **Fixed:** strokes now start from `UserInputService` instead of the canvas frame (the ink and spark layers above the canvas would swallow the press); presses on buttons still don't start a stroke.

### Changed (documentation refresh)
- **Every doc re-checked against the code** (README, CLAUDE.md, GAME_DESIGN, ECONOMY, SPELLS, CONTROLS, ADMIN, CONTRIBUTING, ARCHITECTURE, `docs/semantic/features.yaml`, `assets/models/README.md`, the `add-map` skill). Fixed stale claims: up to 5 duplicate copies (now one per spell, slot N = the Nth loadout spell, keys 1-5), passive health regen in fights and the Battleground (removed), profile schema 4/5 (now 6 with `pity`), crates winning elements, drawing quality's top power (x1.5, not x1.2), Earth Wall's imported mesh (now the `EarthWall` block model), the Arcane models marked unused (they are used), emoji button labels, the 8-spell / 8-shape layout notes, the Water Body / Earth Pillar / Earthquake numbers, and the Studio debug command list.
- **New in the docs:** the Spell Crate pity, the water and pit rescues, drawing quality tiers, the spell wind-up swell, the dash somersault, every service, controller and shared module in the ARCHITECTURE layout, a migration table, the Battleground rows of the PvP table, and a Studio debug command table in ADMIN.md.
- **`docs/semantic/features.yaml` is valid YAML again:** values containing `: ` are quoted, and the `testing` block no longer swallows the telemetry, juice and rescue features. Bootstrap orders, Fx kinds, remotes, and the spec list now match the code.
- `;speed`'s help text names the real default walk speed (`Config.WALK_SPEED`, 24; it said 18), and a stale "duplicates allowed" comment in `Config` is fixed.

### Added (spell wind-up)
- **Every spell now swells as it is summoned.** Projectiles (Fireball, Fire Slash, Water Slice, Water Lock, Water Wave, Rock Throw, Gust, Whirlwind, Tornado, Fire Bomb) grow from a small spark to full size over 0.25s as they leave the caster (`BOLT_GROW` in `FxController`; turret bullets are born full size). Spells that had no growing effect get a wind-up ball or bubble in their color (`CastPoses.SWELLS`, `SpellVfx` `swell`): Fire Boost, Water Body, Water Lock, Water Wave, Water Nebula, Gust, Whirlwind, Tornado, Air Boost, Air Shield, Heal, Turret. Fireball, Rock Throw, Fire Pillar, Fire Bomb, Lightning and Black Hole already grew in the hand and are unchanged; the Earth stomps and Earthquake keep their ground effects. Cosmetic only: server timing and balance are untouched.

### Changed (dash somersault)
- **The dash is now a forward somersault** (arms flung wide, a full 360 degree flip in four quarter turns over `Config.DASH.DURATION`) instead of a held lean. New `flip` field on `CastPoses` keys, applied to the hips by `CastAnimations`. Landing now gets a smaller dust puff and a `dashLand` thud, and the wind streaks fade faster (0.45s to 0.3s).

### Fixed (admin panel outlines)
- **Button outlines are no longer clipped** at the edges of the Admin panel's scrolling lists (targets, tabs content, log): they are inset with padding. The Economy tab's Reset group now also has stats, gift claim and tutorial buttons.

### Added (crate pity, admin reset)
- **Spell Crate pity.** Every spin that is not Epic or better adds one to `profile.pity`; the 10th spin in a row is guaranteed Epic or Legendary (`Crates.PITY`), preferring a spell you do not own yet. A hit resets the counter. The crate panel shows how many spins are left. Profile schema 5 to 6 (`pity`, default 0).
- **`;reset <player> <coins|wins|stats|elements|spells|pity|rewards|tutorial|all>`** (also a "Reset (saved data)" group in the Admin panel's Economy tab). Players in a match are skipped. New `EconomyService.setWins/reset`, `ElementService.reset`, `CrateService.resetPity`.

### Changed (no emojis in the GUI)
- Every emoji is gone from labels, buttons, hub signs, toasts and the tutorial text. Prices now say "coins", the wallet says "Coins"/"Wins", and match boosts use short text tags (PWR, HP, SPD, FOC, POT). The element `icon` field was removed. Plain text glyphs (the quality stars, the guide arrow) stay.

### Changed (crate spell tuning)
- **Black Hole** cooldown 10s to 20s. **Heal** restores 20 (was 25). **Turret** is now Epic (was Rare) with a 20s cooldown (was 12s). **Tornado** flies 2x as fast (55 to 110) and its hitbox and model are 1.5x bigger (radius 8.5 to 12.75).
- **Crate spells show their numbers.** The Spell Crate reveal and the Spellbook detail panel list a crate spell's damage (or heal / health), cooldown, duration, and range (new `Spells/SpellStats`).

### Changed (rubble Earth Wall)
- **Earth Wall is a rectangular wall of rubble.** New `EarthWall` block model (`tools/blender/block_models.py`, `assets/models/blocks/EarthWall.fbx`): five staggered rows of uneven stones with a broken top edge and loose rubble along both faces. It fills the same 23 x 12.4 x 9.7 box as the old `RockWall` mesh, so placement, health (35) and the chunk-by-chunk breaking are unchanged; the spell now uses it with no imported mesh needed.

### Changed (bigger Training Grove)
- **Each Training Grove is about three times the area** (58 x 64 to 100 x 112 studs) with a single row of 7 training dummies instead of two staggered rows; more archery targets and hay bales fill the extra room. The hub island grew to match (`Config.HUB.RADIUS` 180 to 240), and the meadow trees keep clear of the larger groves.

### Changed (hotbar slots follow the loadout)
- **A drawn spell goes in its own hotbar slot.** Slot N holds the Nth spell of your loadout (the same order as the spell cards and the 1-5 keys), so with two spells drawn you can still press 5 and have the fifth spell land in slot 5. Slots stay put after a cast (the slot just empties) instead of sliding together, and an empty slot shows the name of the spell that fills it. The number labels moved back from the spell cards to the hotbar slots.
- `HandService` keeps a fixed `MAX_HAND`-long hand with `""` for empty slots; changing element or loadout re-seats held copies in their new slots.

### Changed (spell hotkeys, nerfs, no spell popups)
- **Keys 1-5 are tied to your loadout.** Key N is the Nth spell card above the hotbar (the number now shows on the card). If you hold a copy it readies it; if not, the drawing canvas opens with that spell's shape to trace. The hotbar slots no longer show numbers (tap them or use the gamepad D-pad).
- **No spell popups.** "Draw a spell first!", "+1 Spell!", cooldown, fizzle, and can't-draw/cast messages are gone; failures play the new `uiError` buzz instead (Toast kind `error` is a sound only).
- **Water Body** lasts 3s (was 7s). **Heal** recharges in 60s (was 30s).
- **No passive health regeneration** in matches or the Battleground (`PASSIVE_REGEN_*` removed); the hub still heals fast.
- **Earthquake** radius 25 to 50. **Earth Pillar** hitbox 6.5 to 13 and reach doubled (spacing 9 to 18, same 6 pillars).

### Changed (Arena Gate portal, wider health bar, equipped-slot bubble)
- **The Arena Gate is a red portal** (new `ArenaPortal` block model, the Battleground portal's palette swapped to red). Walking into it also sends you to the Battleground; duels still start from the team boxes. Both portals' triggers carry the `BattlegroundPortal` tag.
- **The health bar is as wide as the hotbar** (`HudController.hotbarWidth()`).
- **The equipped spell pops out of the hotbar.** The readied slot swells to 122% with a springy overshoot and a soft bubble of the spell's colour behind its icon; it shrinks back when you pick another. The spell-card row and health bar moved up slightly to clear the swelling slot.

### Changed (Battleground portal, health bar position)
- **The Battleground is a real portal.** A new `BattlegroundPortal` block model (made in `tools/blender/block_models.py`, exported to `assets/models/blocks/BattlegroundPortal.fbx`): a ~30-stud octagonal stone gateway with glowing runes, two pylons with floating crystals, and layered blue swirl discs. It stands at the end of the south road; walk into the opening to enter. A plain arch and disc remain as the fallback if the model is missing.
- **The Battleground is out of sight.** `Config.BATTLEGROUND.CENTER` moved from x = 900 to x = 15000, so it can no longer be seen from the hub.
- **Your health bar sits above the hotbar,** and lifts above the spell-guide cards when they are showing (fights, the Battleground, the Training Groves).

### Changed (HUD layout pass)
- **No more overlapping buttons.** The health bar moved to the top-right corner (the kill feed sits under it). Coins and wins are centered at the top, with the match bar, Battleground banner, and boost icons stacked under them (they slide up when a phone hides the wallet in a fight). On the left, Admin sits on top, then Party, and the Party panel opens beside the side menu instead of on top of it (it used to cover the Party button, the health bar, and the menu). The spectate bar sits under the wallet.

### Changed (symmetric hub, mobile HUD)
- **The hub is symmetric, with roads to every destination.** Four marble roads leave the plaza due north (to the Arena Gate, through a gap in the middle of the team boxes), south (to the Battleground portal), west and east (to the Training Groves), crossing the grey ring road. The duels (north) and the Battleground (south) are opposite each other, and there are now **two mirrored Training Groves** (west and east, 58 x 64 studs, clear of the ring road, dummies face the plaza from both). The amphitheatre stands moved off the Battleground path to two mirrored half-arcs on the south diagonals, the Crate Shop moved to the south-east (a matching pavilion sits south-west), and the team boxes were reordered so both halves of the arc are about the same width. All tags, names, and box ids are unchanged.
- **Less clutter on phones.** The "Great! +50% power" popup after drawing a shape is gone (the ink line still changes colour and the screen still reacts). The health bar sits below the Admin button instead of under it, the "Health regenerates slowly" note under it is removed, and the round-won banner rides high (level with the Settings button) on phone-sized screens.

### Added (analytics funnel, game feel, water rescue, pit rescue)
- **Analytics funnel (`TelemetryService`, `Shared/Analytics/Funnels`).** Sends an onboarding funnel (Joined, TutorialDone, ElementPicked, FirstSpellDrawn, FirstCast, FirstMatchStarted, FirstMatchFinished, FirstWin, FirstCrateSpin, FirstElementBought), a per-match funnel (Started, Round1Done, Finished), a coin economy flow (every source and sink, with the reason or item), and custom events (SessionEnd, DailyReturn, MatchAbandoned, BattlegroundJoined, QuestClaimed, WaterRescue, PitRescue) to Roblox's AnalyticsService, so the Creator Hub shows where players drop off. Every call is pcall-wrapped and never touches a profile. `EconomyService.spend` takes an optional `item` for the economy flow.
- **Cast and hit game feel (`JuiceController`).** A hit marker (X) appears at your aim point when your spell lands (gold and bigger on a heavy hit), you get a red edge flash and shake when you are hit (scaled by the damage), a small kick when you cast (ultimates kick harder), a golden flash on a Great or Perfect drawing, a big marker, zoom and sting when you knock someone out, and the screen edges pulse red when you are nearly out. Damage numbers pop in. The server now tells the client whether a number is a hit you dealt or took (`Fx number`'s fifth argument); hits on terrain and wall chunks stay quiet. New cues `hitMarker`, `heavyHit`, `hurt`, `knockoutSting`, `waterSplash`.
- **Screen shake setting** (Settings panel, `profile.settings.shake`, default on; old profiles get the default, no schema bump). It turns off camera shake and field-of-view kicks; flashes and sounds stay. The Settings panel is taller to fit it.
- **Water under every arena.** Falling off an arena no longer knocks you out: the water under it (`Config.RESCUE.WATER_SURFACE`) splashes you for 30 damage, stuns you for 1.2s, and throws you in an arc back onto your spawn pad (the last enemy who hit you still gets the knockout if the splash finishes you). If something blocks the arc or it would be too fast, you are put on the pad instead. The old void depth is only a fallback for a player with no pad.
- **No more getting stuck in a hole.** A player who stands for 1.5s in a hole whose every side is terrain cells too tall to jump out of (spells can carve the ground) is thrown out over the nearest rim, or put on the pad if the rim is very high. Open air, gaps or non-terrain scenery on any side means no rescue.
- The `Impulse` remote takes a second argument, `hold`: the client follows the launch as an exact arc for that many seconds (used by the rescues); dashes and pads are unchanged.
- Tests: `tests/Rescue.spec.luau` (arc landing, rescue settings against jump height and health, pit detection with made-up walls) and `tests/Telemetry.spec.luau` (funnel data, once-per-player steps, juice settings and cues).

### Changed (bubbly spell glyphs, rarity borders, UI contrast)
- **Spell shapes are fatter and outlined.** `GlyphView.create` draws a line 12% of the icon size (was 7%) over a near-black outline, so a pale colour (Common grey, Legendary gold) reads on any card. The drawing guide is thicker too, and the player's pen line is a little thicker.
- **Crate spells are drawn and ringed in their rarity colour everywhere**: spell cards, the HUD glyph cards, the hotbar and the drawing guide (the HUD and guide used the element colour before). New `Theme.rim` adds a dark outer edge around the ring so it has high contrast on any background.
- **Borders are no longer cut off.** The Loadout collection scroll area has padding for the rings (cards are 84 px wide so six still fit), and the HUD glyph row has more spacing.
- **Contrast fixes:** SLOT / SAME SHAPE tags sit on dark chips, the crate odds are dark text with a rarity-coloured dot, a selected card turns sunny yellow instead of losing its rarity ring, and the hotbar element icon has a dark text outline.
- **Crate panel layout:** the "Spells you have" line no longer overlaps the Spin button.

### Changed (sound effects switch, no hub crowd)
- **The hub's cheering crowd ambience is gone** (`hubCrowd` cue and its loop in `AudioController`).
- **New Sound effects switch in Settings** next to Background music. It saves to the profile as `settings.sfx` (default on; old profiles pick it up through the settings defaults, no schema bump) and mutes the whole sound-effects group.

### Fixed (wind moves push NPCs)
- **Gust, Whirlwind and Tornado now blow Battleground NPCs back.** Knockback only ever reached players (`DestructibleService.push` skipped anything without an owner, and projectiles only pushed player characters). `push` now also shoves server-owned NPCs: they go limp for 0.7s so their walking can't undo it, and get the push velocity. Live test: Whirlwind sent a Sand Raider about 63 studs and Tornado about 68.
- Training dummies are anchored posts and still do not move. Knockback from Earth Punch and Earth Pillar (zones and lines) still only reaches players.
- The Studio `cast` debug command now clears your hand first, so a leftover copy can't block it.

### Added (Black Hole and Turret: effects, sounds, animations, dummy and NPC targeting)
- **Black Hole now hurts and pulls training dummies and Battleground NPCs**, not just players (`DestructibleService.isTrainingTarget`). NPCs go limp so their walking can't fight the pull, are dragged to the core, rooted there, and stand back up when the hole closes; dummies are posts, so they take the damage but stay put.
- **Black Hole vortex** (`SpellVfx.blackHole`, Fx `vortex`): a dark core with a glow and two spinning accretion discs hangs over the target, 30 glowing motes with trails spiral in on three arms, rings ripple inward over the ground, and particles stream into the core. When it ends it implodes and blows out in a flash, a shockwave and sparks.
- **Suction on every victim** (Fx `suck`): whoever is caught glows purple, drags a streak, and motes peel off them and whip into the core.
- **Black Hole sounds:** a looping low hum at the hole while it is open (`AudioController.loop`, cue `blackHoleHum`), a pull whoosh when someone is caught (`voidPull`), and a layered collapse boom that finally plays (`blackHoleCollapse`).
- **Black Hole cast:** feet planted wide, arms flung out then dragged together while dark sparks stream into both hands (the `gather` beat now supports two hands).
- **Turret now shoots training dummies and Battleground NPCs** as well as players and decoys.
- **Turret effects:** it kneels to bolt the turret down (new `Deploy` pose, `build` beat with hand sparks and dust); when it finishes rising a scan ring, a sweeping radar arm, rising sparks and a chime play (Fx `deploy`); every shot gets a muzzle flash, sparks, smoke, a flipped brass casing and a layered crack (Fx `muzzle`); bullets that land throw sparks and play a hit sound (`bulletHit`).
- Studio QA: debug command `cast` (`SpellcraftDebug:Invoke("cast", {spell = "...", target = Vector3})`) gives you a spell and casts it through the normal pipeline.
- `tests/Vortex.spec.luau`.

### Added (a cast pose and a hit effect for every spell)
- **Each spell has its own cast animation** (20 new or reworked poses in `CastPoses`): Fireball held overhead then thrown with a lunge, a diagonal Fire Slash chop, a flat Water Slice sweep, Water Body's rippling arms, the Water Wave heave, Rock Throw's scoop-and-heave, stomps for Earth Wall, Earth Pillar and Earthquake, an Earth Punch lunge, a Gust fan, Whirlwind and Tornado body twists, Air Boost's lean, and more. The animator gained **leg poses** (hips, knees) and **waist twist**; a pose with no legs still leaves the walk cycle alone.
- **Cast beats** (`CastPoses.BEATS`, `SpellVfx.castBeat`): a glowing fireball or boulder grows in the raised hand and is released into the throw, slashes leave a hand trail, stomps kick up dust and a ring (with a thud), big spells and Lightning draw sparks into the hand and flash, spins whirl rings of wind, water moves spray droplets, Gust shoves a ring of air.
- **A distinct hit effect per spell** (`VfxStyles` `hit` kinds): explosion (Fireball, bigger for Fire Bomb), crossed cut marks (Fire Slash), splash (Water Slice, bigger Water Wave), popping bubble (Water Lock), rubble (Rock Throw), wind rings (Gust, bigger Whirlwind), storm with debris (Tornado), white flash and lightning forks (Lightning), sparks (Turret bullets).
- **New sounds:** per-spell impact cues (`slashHit`, `sliceHit`, `lockPop`, `waveCrash`, `rockSmash`), stomp / charge / push / spin cues for the poses, and layered cues (`with`) such as a splash plus a thump. They reuse the existing recordings at different pitch and length, so swap ids in `Audio/Cues` if you find better ones.
- **Fixed:** Lightning's strike never played its impact sound and used the plain burst; it now uses its bolt effect and `zapStrike`.
- Tests: no two spells of an element share a pose, beats land inside their pose, every impact kind and layered cue exists, every projectile spell has its own impact sound.

### Changed (tough baseplate, easy scenery)
- **The baseplate is way harder to break:** floor and island-top cells now have 240 health (`Config.TERRAIN.HEALTH.Ground`, about 16 Fireball hits each; was 30), so a fight can't dig through the ground quickly.
- **Scenery stays easy:** rock terrain (cliffs, mesas, steps, outcrops) takes 45, and trees, pillars, spires, cubes, columns, bridges and torches use `Config.PROPS` (Brick 15, Light 25, Medium 45, Heavy 70), the same effective health as before.
- The global `TERRAIN.PROP_HEALTH` multiplier is gone (it halved the baseplate too); every health value is explicit in `Config`.

### Changed (all scenery is breakable)
- **The items on the maps break, not just the ground.** Crayon Canyon's cliffs and end walls, the Ember Forge dais, the Tidal Temple steps and torches, Frost Hollow's snow bank, and Moss Ruins' dais are now breakable terrain or props. Scenery health comes from named tiers in `Config.PROPS` (Light 50, Medium 90, Heavy 140, then halved by `PROP_HEALTH`): ice cubes, clams, mossy blocks and torches fall to a couple of hits, trees, columns, bridges and arches to three or four, and spires and pillars to five (a Fireball does 15). Torch flames go down with their post. A cliff or end wall that breaks opens onto the void, so it can ring players out.
- Only the hub, the rock undersides and the Sparring Arena's imported colosseum and statue (single meshes) stay solid. `tests/Terrain.spec.luau` now fails if a map gains solid scenery that can't be broken.

### Changed (git workflow)
- **Documented project workflow** (`CLAUDE.md`, `docs/CONTRIBUTING.md`, `ship-change` and `new-feature` skills): every change starts on a `feature/<name>` branch; when tests pass or the user says so, commit, push, merge into `main`, delete the branch, and sync to Roblox. Never merge on red tests.

### Changed (seven maps, easier to destroy)
- **Sky Islands is removed** (7 duel maps now); its jump-pad re-aiming code went with it.
- **Crayon Canyon's glass lane gates are gone**: the canyon is open in 1v1 and 2v2 too.
- **Everything on the maps breaks more easily.** Every map prop (floor and mesa cells, rocks, pillars, arches, columns, cover walls) now has half its design health (`Config.TERRAIN.PROP_HEALTH` 0.5, applied in `ArenaService.makeProp`), and terrain splash is 75% (was 50%) so craters are wider. **Moss Ruins' trees and arches are now breakable** (`MapKit.tree` takes `makeProp`). Cliffs, end walls and the hub stay solid.

### Added (breakable terrain, bigger arenas)
- **Terrain breaks.** The floors of Frost Hollow, Ember Forge, Moss Ruins, Tidal Temple and Sky Bridge (platforms, middle island), Crayon Canyon's floor, mesas and ramps, and six new rock outcrops in the Sparring Arena are made of cells (`MapKit.terrain`) that take spell damage like any prop. The hit cell takes the full damage and the cells touching it take half (`Config.TERRAIN.SPLASH`), so a heavy spell breaks through faster and opens a wider hole; blast the floor out and players fall (ring-outs). Cliffs, end walls, and the Sparring Arena's imported floor mesh stay solid. Every round starts on a fresh arena, so the terrain respawns. Terrain gives no quest credit, and a bolt skimming over the floor does not break it (`GroundTile`).
- **Arenas are twice as big** (`Config.ARENA_SCALE`, applied by `MapKit.scale` in `ArenaService.init`, all maps). The summon ring below the hub is wider to fit them (`Config.ARENA.RADIUS` 380 -> 560, `RING_STEP` 420 -> 600).
- `tests/Terrain.spec.luau`.

### Changed (dash cooldown)
- **Dash cooldown is 8s** (was 2s on this branch), and the Dash button now shows only the countdown while recharging (it used to keep the word "Dash" underneath).

### Changed (floating-island hub, duels below, 8 maps, new dash)
- **The hub is a round floating island** (`Maps/InkwellPlaza`, `Config.HUB`): a grass disc with a sand beach, a dark rock cone with stalactites and crystals underneath, open ocean far below, and a wooden rail around the rim. It follows the look of the reference video: stepped white-marble amphitheatre arcs, leaning marble pillars, a ruined arch, bare dark trees, crates. Everything sits in rings around the inkwell: plaza (shrines, kiosks, gift box, spawn), amphitheatre and Battleground portal to the south, the team boxes in an arc to the north with the Arena Gate behind them, the Training Grove to the west, the Crate Shop to the east, podium and Most Wins board facing the centre. All tags and names the services use are unchanged.
- **Duels are summoned below the island.** Arenas are no longer at `y = 400`: `ArenaService.slotOrigin` places them in rings 300 studs under the hub (`Config.ARENA`), outside its footprint, so players on the rim (four 👁 SPECTATE overlooks) can look down and watch fights live. Arena models stream in persistently, carry a floating "⚔ mode · map" sign, effects draw out to 900 studs, and the hub's haze is thinner so the arenas are clear.
- **Eight duel maps** (was three): the new **Frost Hollow** (ice sheet, ring-outs), **Ember Forge** (basalt over a lava moat), **Moss Ruins** (overgrown arches and cover), **Tidal Temple** (sand island, stepped temple), and **Sky Bridge** (two platforms and a breakable plank bridge, ring-outs). The map vote shows all eight in a 4 x 2 grid. New `MapKit` helpers: `disc`, `pillar`, `barrierRing`, `underside`, `tree`.
- **The dash is now a leap, as in the reference video:** the character hops in a low arc (`Config.DASH.HOP`) with arms flung wide and three thin pale wind streaks trailing behind (`SpellVfx.windStreaks`). The cooldown is 2s (was 4s), 70 studs/s for 0.4s (about 28 studs).
- Project skills for agents in `.claude/skills/` (new feature, add a map, add a spell, testing, Studio sync, docs and changelog).
- Tests: `tests/Maps.spec.luau` (map contract, arena placement, hub tags, dash).

### Changed (store art)
- **New icons and thumbnails in the classic blocky Roblox style** (`assets/marketing/`: two 512px icons, three 1920x1080 thumbnails: key art, action, spell crates). They are drawn by `tools/make-marketing-art.py` (needs Pillow), so edit a scene there and re-run. They replace the old "Wordcraft Arena" art.

### Added (Admin panel)
- **A clickable Admin panel** in the classic Roblox admin style: a draggable window with an **X** to close it, a **Target** list (Me, All, Others, every player), tabs (Player, Spells, Economy, Match, Server) of buttons, a command box, and a log of replies. Open it with the purple **🛡 Admin** button or the **`** key. Danger buttons (kill, kick, ban, end match) need a second click. Chat `;` commands still work. Buttons live in `Shared/Admin/Catalog`; the client sends only a command string (`AdminCommand` remote), and the server re-checks admin status, length (200), and rate on every call. New `AdminLog` remote carries replies to the panel.
- Admin commands now prefer an exact username over a prefix match, and `ban` refuses `all` / `others`.

### Changed (heal cooldown, GUI colours)
- **Heal's cooldown is 30s** (was 10s).
- **GUI uses a pastel palette with dark ink text** (from the supplied swatches): Blue Grey `#DBE1F1` panels, Blue `#96ADFC` buttons and cards, Orange `#EDDD6E` for primary / selected, Green `#A8F29A` for go, Red `#E0A6AA` for stop, Purple `#B987DC`, plus Peach, Turquoise, Yellow, and Grey. Text is near-black ink (7.5:1 or better on every swatch), borders are thick near-black, studs are faint, and titles are deep purple. Text over the world or dark overlays stays white with a dark outline (`Theme.COLORS.onDark`). The loading screen matches.

### Added (five new shapes)
- **Heart, spiral, zigzag (M), hook (J), and X** join the seven shapes (12 in all). Heal is a **heart**, Lightning a **zigzag**, Turret a **hook**, Air Shield an **X** (drawn in one unbroken stroke: down, up the side, down), and Black Hole a **spiral**. Their roles are `support`, `storm`, `summon`, `ward`, and `vortex`. All five are unused by any base spell, so every crate spell now fits next to every element's base trio; only Water Wave (bolt), Fire Pillar and Earth Pillar (V) can still clash.
- **Black Hole is now Legendary.** It drags every enemy it catches to the exact center and holds them there for 3 seconds. Held enemies can still cast spells (it roots, it does not stun). 10 damage in total.

### Changed (elements, loadout, Spell Crate gacha)
- **Base elements with three spells.** Fire = Fireball, Fire Slash, Fire Boost; Water = Water Slice, Water Body, Water Lock; Earth = Rock Throw, Earth Wall, Earth Punch; Air = Gust, Whirlwind, Air Boost. The first element is still a free pick; the others are now **bought with coins** (400 each, `BuyElement`, `ElementService.buy`) instead of coming from crates.
- **Spell Crate gacha.** The Element Crate is now a **Spell Crate** (100 coins) that wins one of the 12 other spells by rarity: **Common 55%, Uncommon 25%, Rare 12%, Epic 6%, Legendary 2%** (`Spells/Rarity`, `Economy/Crates`). A spell you already own pays coins back. The reel shows spell cards in rarity colours, ticks as cards pass, and reveals with a rarity sound and flash. `CrateResult` now carries `spell`, `rarity`, `duplicate`, `refund`, `equipped`.
- **Loadout.** You draw your element's 3 base spells plus up to **2 crate spells** you equipped in the Spellbook's new **Loadout** tab (`SetLoadout`, `Spells/Loadout`). A loadout can't hold two spells with the same shape; the UI says which spell it clashes with. The match spellbook, the drawing recognizer, and the HUD cards all use the loadout. Spell cards are outlined by rarity.
- **Earth Wall lets your own spells through.** Your own (and your allies') spells fly through your wall; enemy spells hit it. (It used to block everyone.)
- **Profile schema 5:** `spells`, `loadout`, `tutorial.done`. Players who had already picked an element skip the tutorial.

### Added (spells, tutorial, cursor, gift box)
- **Four crate spells back from the old spell list, with models:** **Lightning** (the Zap bolt, Rare), **Heal** (Common), **Black Hole** (Epic), **Turret** (Rare), in a new neutral **Arcane** school. They have their imported models (with plain-shape fallbacks), particle styles, cast poses (Call, Offer, Conjure, Deploy), and sounds. **Air Shield** (the shield) is a Common crate spell; Fire Pillar, Earth Pillar, Water Wave, Fire Bomb, Water Nebula, Earthquake, and Tornado are crate spells too. New role `support` (a V) for Heal.
- **First-join tutorial** (`TutorialController`, `Fx/GuideArrow`): a welcome screen, then guided steps with bobbing arrows, an outline on the target, a flowing chevron trail on the ground, and an edge-of-screen pointer: choose an element, spin for a spell, draw it in the Training Grove, cast at a dummy, and earn coins in a duel or the Battleground. Skippable, saved once (`TutorialDone`).
- **Spell cursor** (`CursorController`): while a spell is readied the mouse is a pulsing crosshair in the spell's colour with its name and "Click to cast" (red with the seconds left while it recharges). The normal arrow returns over buttons and menus.
- **Like & Favourite is a physical gift box** on the hub plaza (hold its prompt to claim). The "Like!" menu button and panel and the `ClaimLikeReward` remote are gone.
- Admin/debug: `;unlock <player> spells`, `;crate` spins the Spell Crate, `SpellcraftDebug:Invoke("tutorial", false)`.

### Changed (training-ground hub)
- **The Training Grove lets you draw and cast again.** It is now a big 100 x 110 stud yard (was 64 x 76) with a fence, corner torches, 11 dummies in two rows, archery targets, and hay bales. Standing inside it (tag `PracticeZone`, `shared/Util/PracticeZone`) is the one place in the hub where drawing works; the server (`MatchService.canDraw`) and client (`ClientState.canDraw`) both check it.
- **No stone walls in the hub.** The concourse walls, arched bays, windows, banners, buttresses, overhead ribs, entrance pylons, end wall, and the stone ring around the hub are gone, as are the glass walls around the duel pads. The 1v1/2v2/3v3/4v4 pads are now open training mats with hay bales; wooden fences, archery targets, hay bales, and torches line the carpet; invisible barriers still keep players on the grass. The hub reads as a training-ground map ("Spellcraft Arena, Training Grounds").

### Changed (pacing, one copy per spell, fights only)
- **Cooldowns:** basic spells (Fireball, Rock Throw, Gust) now wait **3 seconds** between casts; slash moves (Fire Slash, Water Slice) wait **2 seconds** (they were 0.9-1.1s and 0.55s). `tests/Balance.spec.luau` keeps it that way.
- **Earthquake's wind-up is shorter and harder to punish:** 1.2 seconds (was 2s), still rooted while it charges.
- **One copy of each spell.** Drawing a spell you already hold is refused ("You already hold Fireball. Cast it first!"); the hotbar holds at most one of each of your element's five spells.
- **Drawing only works in fights:** the rounds of a match (every duel and team map, including the Sparring Arena) and the Battleground. Not in the hub, and not during a match's intro, countdown, draft, or results. The server enforces it (`MatchService.canDraw`, installed into `SpellInputService`); the Draw button and spell cards hide where drawing isn't allowed. The hub's Spell Practice sign became "Training Grove".
- **Phones and tablets get a clean screen in fights:** the menu buttons, wallet, party button and panel, kill feed, and boost icons are hidden in matches and the Battleground (the hotbar, spell cards, Draw and Dash buttons, health, the match bar, and Return to Hub stay).
- **The ice map is gone:** Frostbite Fortress was removed from the map list, the map vote, and the docs.
- **More team boxes:** the hub now has **two 1v1 boxes and two 2v2 boxes** (plus one 3v3 and one 4v4). Boxes now have ids (`Box` attribute), so a mode can have several, each with its own countdown.
- **The hub's centerpiece is the wizard statue**, standing on the inkwell where the golden quill was (the quill returns only if the model is missing).

### Added (dash, spectate)
- **Dash:** press **Q** (gamepad **B**) or the new **Dash** button to burst about 24 studs the way you're moving, with a dash pose, a dust puff, and a whoosh for everyone; 4 second cooldown shown on the button (`Config.DASH`, `DashService`, `DashController`, remotes `Dash` / `DashStarted`, Fx `dash`). Q can no longer be the draw key.
- **Spectate:** a **Watch** side button lists the other players and where they are; pick one to follow them with the camera, with Previous / Next / Stop controls at the top (`SpectateController`). It ends when the target leaves or you join a fight.
### Added (studded GUI, music, like gift, block models, spell registry)
- **Studded Roblox GUI.** `UI/Theme` now draws every panel and button in the classic studded style: bright blue with a stud grid (`assets/ui/studs.png`, made by `tools/make-stud-texture.py`), a bevel, small corners, navy outlines, and outlined white text, with orange for primary, green for go, and red for close. Studs hide on small, see-through, or dark frames (health bars, overlays). The loading screen matches. `Theme.button` shows its text in a child label above the studs, so existing code is unchanged.
- **Block models** (`tools/blender/block_models.py`, one spec): 24 chunky classic-Roblox models, exported as FBX (`assets/models/blocks`) and a Blender scene, and generated as plain data (`src/shared/Models/BlockModels.luau`) that `ModelKit` builds into Parts, so they work in every place with no import. New spell models for Fire Slash, Fire Boost, Fire Pillar, Water Slice, Water Body, Water Wave, Water Nebula, Rock Throw, Earth Punch, Earth Pillar, Earthquake, Air Boost, Air Shield, and Tornado (every spell now has a model), plus **trees** (oak, pine, birch, cactus; used in the Battleground and the hub), the **training dummy**, the **Element Crate** (closed and open), the **Daily Quests chest** (closed and open), and the **wizard statue** at the center of the Sparring Arena.
- **Spell registry.** `Spells/SpellRegistry` lists, for every spell, its model, particle style, cast pose, Fx events, and sounds; `docs/semantic/spell_registry.yaml` and a table in `docs/SPELLS.md` mirror it (`python tools/gen-spell-registry.py`), and `tests/Registry.spec.luau` fails if a spell is missing or names something that doesn't exist.
- **Cast animations.** Each kind of move has its own arm and body pose (Throw, Slash, Flex, Guard, Point, Smash, Sweep, Ascend, Stomp) in `Spells/CastPoses`, played on the caster for everyone by `Fx/CastAnimations` as runtime KeyframeSequences (Motor6D `C0` is read-only at runtime, so the old arm-raise never moved). Earthquake holds its pose for the whole channel.
- **Spell VFX and SFX gaps filled.** Buffs (Fire Boost, Water Body, Air Boost, Air Shield) now have an aura on the caster (embers, shimmer, wind streaks, orbiting blades, an outline); every spell has a particle style (`Spells/VfxStyles`); Gust, Whirlwind, Tornado, and Earth Wall got impact sounds (Tornado no longer uses the water sound).
- **Background music** with a mute: a hub playlist and a fight playlist (`Audio/Music`) loop and fade between each other; the new **Background music** switch in Settings saves to the profile (`settings.music`, schema 4). Volume and fades are in `Config.MUSIC`.
- **Like & Favourite gift.** A "👍 Like!" menu button opens a panel with the steps and a Claim button for a one-time **250 coins** (`Config.SUPPORT`). Roblox can't verify likes or favourites, so it is honor-based: the server opens it after 90 seconds in the server and pays once per account (`EconomyService.claimLikeReward`, remote `ClaimLikeReward`, `profile.rewards.likeFav`). Check Roblox's policy on rewarding likes before launch.
- The hub crate throws its lid open (and the chest opens on a quest claim) while the reward plays (`Fx/PropSwap`).
- Debug commands `likefav <bool>` and `takecoins <n>` for QA.

### Fixed (effects that never showed)
- **Fire Pillar, Water Nebula, Earth Punch, Earth Pillar, Earthquake, and the drawn-glyph pop-up had no visuals:** `FxController` received their `pillar`, `rise`, `quake`, and `glyph` events but never handled them. They are wired up, and now draw their block models.
- `tests/Quality.spec.luau` allowed 10% power at average quality; an average drawing is now about +17% (perfect is +50%), so it allows 20%.
- Zone spells with a `visual.model` and a column, boulder, or channel no longer also drop that model from the sky as a strike.

### Changed (arena size, open Battleground)
- **The Return to Hub button now shows** whenever you are in the Battleground (it was built but never made visible). The green gates still work too.
- **Bigger Sparring Arena** (the 1v1/2v2 map): the floor is 4x larger than the original model (about 184 studs), with spawns and the invisible wall ring scaled to match.
- **One open Battleground.** The mountain ring is now distant scenery you can't collide with; thicker invisible walls at the edge keep everyone on the map, and a once-a-second safety net puts anyone who still ends up below the world or outside the walls back at a random spot.

### Changed (precision, passive regen)
- **Perfect drawings hit harder:** the top of the quality range is now +50% power (was +20%); the pop-up and docs say so. (`Config.QUALITY.POWER = { 0.85, 1.5 }`)
- **Passive health regen** in matches and the Battleground: 1 HP/s, starting 5 seconds after you last took damage (`Config.PASSIVE_REGEN_PER_SECOND` / `PASSIVE_REGEN_DELAY`). The hub still heals 5 HP/s.

### Fixed (crowd control on NPCs)
- **Water Lock (and every status spell) now works on Battleground NPCs.** The stun was only applied to player characters, so NPCs took the damage and kept fighting. Single-target shots and area control spells (Vine Snare, Time Stop, ...) now apply their status to hostile NPCs too, with the bubble. A stunned, rooted, or time-stopped NPC stops moving, swinging and shooting, and a wind-up already in progress is cancelled. NPCs keep their own speed and size after the effect ends (`BaseWalkSpeed` / `BaseScale` attributes read by `StatusService`). Players were already stunned correctly.

### Added (duel map vote, name change)
- **Vote for the map in duels.** After a 1v1 is found, both players see a vote screen with every map and a countdown (`Config.MAP_VOTE`); the most votes wins, ties and no votes are random. New `MapVoteService`, `MapVoteController`, and remotes `MapVote` / `MapVoteState`.
- **Renamed to Spellcraft Arena** everywhere (docs, project name, debug bindable `ServerStorage.SpellcraftDebug`, GUI names).

### Fixed (Battleground walls)
- **The walls that split the Battleground are gone.** Each edge wall and mountain row was laid along the wrong axis, so they cut across the middle of the map and left the real edges open. They now run along the four edges: invisible walls at the border keep players on the map, and the mountains are distant scenery.

### Added (NPC aggro, parties)
- **NPCs stay on whoever hit them.** Hitting an NPC locks it onto you at any distance until you are knocked out or leave the Battleground, so you can't snipe from out of range. NPCs that only noticed you can still be outrun. A **red "!"** shows over any NPC that is hunting someone.
- **Parties** (`PartyService`, `PartyController`): a Party button under the wallet opens a panel to invite players, accept or decline invites, kick (leader), and leave. Up to 4 per party (`Config.PARTY`). In the Battleground party mates can't hurt each other, their heals and buffs reach each other, their health bars are blue, and you drop in beside a party mate who is already inside. New remotes `PartyAction` and `PartyState`.

### Added (trace-to-cast quality, mobile layout)
- **Tap a spell card to see its shape.** The cards above the hotbar are now buttons: tapping one opens the drawing canvas with that spell's shape as a faint guide and a dot tracing how to draw it. The F key / Draw button still open a blank canvas.
- **Drawing quality.** The closer your stroke follows the shape, the stronger the spell: a Rough to Perfect tier (1 to 4 stars on the hotbar copy, and a "Perfect! +20% power" pop-up) scales damage/healing/shields/health, hit radius, and durations (`Spells/Quality`, `Config.QUALITY`). A straighter slash scores higher. With a card selected the server only accepts that spell's shape (`DrawSpell` now carries the spell id; `GlyphResult` and `HandUpdated` carry quality).
- **Mobile on every screen size.** One scaling rule for the HUD and the Draw button (`UI/Responsive`): phones use a smaller design size so text stays readable, and the scale is capped so menu panels always fit, in portrait too. The drawing canvas banner now fits narrow screens.

### Added (Battleground open world and NPCs)
- **The Battleground is now an open world, not an arena.** A 600 x 600 stud land of four biomes ringed by mountains, with Raider camps, ruined circles, and the Warlord's Keep. You drop in at a **random open spot** (away from camps and other fighters) and leave through one of four gates or the new **Return to Hub** button (`LeaveBattleground` remote).
- **Hostile NPCs** (`NpcService`): Sand Raiders, Ember Mages (ranged), Stone Brutes, and the Dune Warlord. They chase, swing, and shoot back with telegraphed windups, give up and heal when you run, and respawn. Every spell hurts them.
- **NPC knockouts pay coins** (3 / 5 / 12 / 40), capped at 120 per player per 5 minutes (`Config.BATTLEGROUND.NPC`).

### Changed (Battleground, no more swirls)
- **The FFA arena is now the Battleground.** The pink FFA queue pad is a blue portal that teleports you to a big open sand arena (`BattlegroundService`, `Maps/Battleground`): drop in any time, everyone inside is an enemy, you respawn 3 seconds after being knocked out, and green exit pads take you back to the hub. FFA as a queued match mode is removed (the Play menu, `Config.MODES`, the match code, and the FFA spawns).
- **No more swirly shapes.** Fire Boost, Water Body, and Air Boost are drawn as a **square**; Earth Wall and Air Shield as a **triangle**. The swirl, squiggle, and infinity shapes are gone from the library, and so is the movement role. A circle and a square are told apart by how much of its bounding box the stroke fills.

### Changed (arena hub, swirl for boosts)
- **Boost and defense spells are drawn as a swirl** (the spiral): Fire Boost, Water Body, Earth Wall, and Air Shield. The V (chevron) moves to the area attacks (Fire Pillar, Earth Pillar). A swirl is accepted with 1 to 3 turns, drawn in or out, so it is forgiving to draw.
- **The hub is an arena, not a dark Halloween scene.** Sunny warm light, a sand plaza with gold-and-stone rings, a three-tier grandstand with blue and red pennants, sandstone and marble walls with sky-glass windows, team flag poles, and green trees. The pumpkins, purple trees, glowing orange windows, and night lighting are gone, and the hub's ambience is a quiet arena crowd instead of crickets. The hall is now the Champions' Concourse.

### Changed (shapes by kind of move, bigger hitboxes)
- **Every spell's shape now says what kind of move it is, and no element repeats a shape:** a circle is a basic attack (Fireball, Rock Throw, Gust), a diagonal slash a fast attack (Fire Slash, Water Slice), a squiggly line movement (Air Boost), a triangle a stun (Water Lock), a V a boost or defense, a lightning bolt a heavy attack, a spiral an area attack, and a star an ultimate. New `slash` shape (any straight stroke, recognized by straightness), `Glyphs.ROLE`, and a `role` on every spell. Only the equipped element's five shapes are recognized.
- **Bigger hitboxes on every move** (about 40% wider, with the visuals scaled to match): Fireball 3.5 to 5, Fire Slash and Water Slice 3 to 4.5, Fire Bomb 7 to 10, Water Wave 8 to 11, Rock Throw 4.2 to 6, Gust 3.2 to 4.6, Whirlwind 7 to 10, Tornado 6 to 8.5, Water Lock 2.5 to 4, Fire Pillar 9 to 12, Water Nebula 10 to 13, Earth Punch 5 to 7, Earth Pillar 4.5 to 6.5 (pillars 9 studs apart), Earthquake 22 to 25. The bonus against players (`HITBOX_BONUS`) goes from 1.5 to 2.

### Changed (elements replace the 8 spells)
- **Four elements, 20 spells.** Fire, Water, Earth, and Air have five spells each: a basic attack, a second move, a utility or boost, a heavy move, and an ultimate. Each slot uses the same shape in every element (circle, wave, triangle, lightning bolt, star), and recognition only considers those five shapes.
  - **Fire:** Fireball (15), Fire Slash (10, fast), Fire Boost (+25% damage, 8s), Fire Pillar (30, large area, point and click), Fire Bomb (ultimate, 35).
  - **Water:** Water Slice (10, fast), Water Body (invincible 7s), Water Lock (5 + stun), Water Wave (25, piercing), Water Nebula (ultimate, 35 pillar).
  - **Earth:** Rock Throw (15, large rock), Earth Wall (35 HP), Earth Punch (20, boulder under the aim point), Earth Pillar (30, a line of pillars), Earthquake (ultimate, 40, 2s cast).
  - **Air:** Gust (15, fast), Whirlwind (15, wide, blows enemies away), Air Boost (faster, higher jump), Air Shield (blocks the next hit, 4s), Tornado (ultimate, 30, piercing).
- **Elements are chosen and unlocked.** Pick your first element free in the Spellbook; the others unlock from **Element Crates** (`ElementService`, one crate for 250 coins that always lands on an element you don't own). Equip any owned element in the hub; it is locked in during a match. Hub **shrines** list each element's spells and shapes.
- **Duels give boosts, not spells.** After each round you pick 1 of 3 match boosts (Power, Vitality, Swiftness, Focus, Health Potion), which stack up to 3 times (`Match/Boosts`, `BoostService`). Your spellbook is always your element's five spells.
- New mechanics: `Stun` (no moving or casting), `Invincible`, `Barrier`, `Haste`, `Channel` statuses; the `Line` archetype; piercing projectiles; `channel`, `rise`, and `pillar` zone bursts; a damage multiplier in `DestructibleService.damage`.
- New effects and sounds: element pillars, rising boulders and stone pillars, an earthquake wind-up, new bolt styles, and 18 more audio cues (`Audio/Cues`).
- **Classes are planned, not built.** `docs/CLASSES.md` records what's decided and the open questions.
- Profile schema **3** (`elements`, `element`; `ownedSpells` removed): existing players pick their first element again.
- Tests: `tests/Economy.spec` (elements, crate, boosts), updated `Balance`, `Glyphs`, `WordMatcher`, and `Audio` specs (204 pass).

### Removed (elements)
- The old 8 spells' unique ones: Zap, Heal, Black Hole, and Turret (their models stay in the repo but nothing uses them), Rarity tiers (Common to Legendary), the spell draft, and the five-crate shop with duplicate refunds.

### Added (drawing, a new hub, audio and VFX)
- **Draw spells.** Press **F** (or tap ✏ Draw, or **X** on a gamepad) and trace a shape: circle = Fireball, wave = Water Lock, triangle = Rock Wall, chevron = Gust, lightning = Zap, infinity = Heal, spiral = Black Hole, star = Turret. The server recognizes the stroke (`Glyphs`, `GlyphRecognizer`, a $1 unistroke recognizer that ignores size, rotation, direction, and start point) and readies the spell. The line turns gold or red with the verdict, and everyone sees the glyph pop over the caster's head. New `DrawController`, `GlyphView`, `DrawSpell` and `GlyphResult` remotes, `tests/Glyphs.spec`.
- **Glyph cards** above the hotbar show what to draw (with cooldowns); the Spellbook shows each spell's glyph.
- **New hub: the Great Hall of Glyphs.** A moonlit round plaza (inkwell fountain, eight glyph stones) opens into a long stone hall with pointed arches, glowing rune windows, glyph banners, a red carpet, the team boxes, the FFA portal, and a red Arena Gate at the far end. The Spell Practice pavilion is west, the Crate Shop east, the podium and Most Wins board at the hall entrance. Pumpkins and torches throughout.
- **Night mood** (`LightingController`): the hub fades to a purple night with bloom; matches keep the bright arena lighting.
- **Audio** (`Audio/Cues`, `AudioController`): a cast and an impact sound per spell, hit sounds, shattering rock, drawing success and failure chimes, the crate reveal, and a quiet night ambience in the hub. Spells name their cues with `sfx = { cast, impact }`. `tests/Audio.spec`.
- **Spell VFX:** the glyph you drew is imprinted in the magic circle under the caster, Heal sparkles and a ring, Black Hole streams motes inward with a pulsing glow.

### Removed (drawing)
- Typing, chat casting, the spell box, and voice casting (`VoiceService`, `VoiceListen`, `VoiceHeard`, `SubmitWord`). Chat still carries admin `;` commands, and spell names still work in them.
- The "type a spell" key setting is now the **draw key** setting (default F).

### Added (coins, crates, wins podium)
- **Coins.** Winning a match pays 100 coins (+50 for the first win of the day); the daily login chest and daily quests pay coins too. New players start with 150. The HUD's top-left wallet shows coins and wins, and the Victory screen counts up the coins you won.
- **Crates** (`Economy/Crates`, `CrateService`, `CrateController`): a Common, Uncommon, Rare, Epic, and Legendary crate (100 / 250 / 500 / 1000 / 2000 coins). Each spin is decided on the server and unlocks a spell of the crate's rarity (with a 15–20% chance of one tier up); a spell you already own refunds half the price. Open them from the new 🎁 Crates menu or the Crate Shop stage in the hub; a reel of spell cards spins and lands on your prize.
- **Five new spells**, one per crate: **Gust** (Common: low damage, huge hitbox, big shove), **Zap** (Uncommon: point-and-click thunder strike with a hover hitbox and a 60-stud range limit), **Heal** (Rare: +10 HP), **Black Hole** (Epic: sucks enemies in, traps them for 3 seconds, 10 damage over time), **Turret** (Legendary: a 30-HP turret that shoots the nearest enemy player).
- **Wins leaderboard** (`LeaderboardService`): Wins and Coins in the player list, a Most Wins board, and a gold/silver/bronze podium in the hub where the server's top 3 players stand as their avatars.
- **Spellbook kiosk uses the Grimoire model**, open on a lectern (plain-shape fallback without it).
- **Semantic layer for AI agents:** `CLAUDE.md`, `docs/semantic/features.yaml` (every feature's files, remotes, data, invariants), and `docs/ECONOMY.md`.
- Admin `;coins`, `;wins`, `;crate`; Studio debug through `ServerStorage.WordcraftDebug:Invoke(...)` (`coins`, `wins`, `crate`, `state`).
- New rarity tier **Uncommon** (▲, green). The Legendary glyph is now 👑 (✦ didn't render in Roblox's font); the coin icon is 💰.

### Removed (coins, crates, wins podium)
- **Levels and XP** (`LevelCurve`, `ProgressionService`): no level bar, level-up banner, or XP rewards. Profiles migrate to schema 2 (XP and level dropped, quests re-rolled).
- **35 spells.** Only Fireball, Water Lock, and Rock Wall remain from the old dictionary; the Movement and Summon archetypes stay in code for future spells.
- The session knockouts board (replaced by the wins board).

### Changed (coins, crates, wins podium)
- `ProgressionService` is now `EconomyService`, the only writer of coins and wins.
- Draft rarity weights are 50 / 25 / 15 / 8 / 2, and a draft card falls back to a higher tier when every spell of its tier is already in your spellbook.
- Bolts, placeables, zones, and buffs can name an imported model in `visual.model` (Turret's body, Black Hole's swirl, Zap's strike, Heal's pop-up, Gust's bolt).

### Added (team boxes, 3v3, Sparring Arena map)
- **Team boxes in the hub** for 1v1, 2v2, 3v3 and 4v4. Each has a Blue side and a Red side with one spot per teammate. Standing on a side picks your team, and the labels show how full it is (`BLUE 1/2`). When both sides are full, a 5-second countdown runs (it restarts if anyone steps off or swaps), then the match starts with exactly those teams (`MatchService.startMatch(..., { teams })`).
- **3v3 mode**, with the Play menu and the admin `;startmatch` updated.
- **Sparring Arena is now a match map** (`Maps/SparringArena.luau`), weighted ×2 for 1v1 and 2v2 and never picked for 4v4. Invisible walls keep players on its floor.

### Changed (team boxes, 3v3, Sparring Arena map)
- **Rock Wall is 1.6× bigger:** 23 × 12.4 × 9.7 studs (it was 14.4 × 7.7 × 6.1).
- **The old queue pads for 1v1, 2v2 and 4v4 are replaced by the team boxes.** FFA keeps its pad, and the Play menu still queues for every mode.
- **The Sparring Ring/Arena is gone from the hub**, and so is hub PvP, since the ring was its only place.

### Removed
- The brick wall in the hub's Practice Grove.
- The starter Baseplate and SpawnLocation from the place (the hub and arenas are built at runtime, so press Play to see them).

### Changed (wall + Fireball)
- **Every spell hits the Rock Wall, your own included** (`HitByAll`), where before your own spells passed through your own structures.
- **The Rock Wall takes 50 damage in total** (it was 150), shared across its pieces: the base breaks first, then the rubble, then the stones, and the whole wall is gone at 50.
- **Bigger Fireball hitbox:** radius 2 → 3.5 (it now hits from up to 5 studs off-center), with the visual enlarged from 2 to 3.2 studs to match.

### Added (3D models)
- **Imported models** (`assets/models`, prepared by `tools/prepare-models.luau`, stored in `ReplicatedStorage.Models`) for the Fireball, Water Lock, Rock Wall, and the sparring arena. All fall back to plain shapes if the models aren't in the place.
- **Fireball** and **Water Lock** bolts are drawn with the models (the fireball trails its tail behind it).
- **Water Lock** now wraps its victim in a glassy bubble (before, only area-style crowd control showed one).
- **Rock Wall** is a sculpted earth wall (standing stones, base, rubble). Its three pieces break separately. The placement ghost shows the real model.
- **Sparring arena:** a marble-pillared, sandstone-seated colosseum with a neon rune ring replaces the red mat. It has four entrances, and its floor lines up with the 50×50 PvP zone.
- `tests/Models.spec.luau` checks the models when they're present.

### Fixed (3D models)
- Placement checks now use real collision shapes (`GetPartsInPart`), so large hollow meshes no longer block everything inside their bounding box.

### Added (round 3)
- **Stackable hotbar:** hold up to 5 spell copies in any mix, including 5 of the same spell. Copies of the same spell share one cast cooldown, and casting readies the next copy automatically.
- **Breakable blocks:** Rock Wall (3×2) and Castle (5×3) are grids of separately breakable blocks. There are brick, ice, and cloud block walls in every arena, plus a self-rebuilding practice wall in the hub. Blocks darken as they're damaged, chip on hits, and shatter into chunks.
- **Spell VFX:** each spell's bolt gets themed trails and particles (fire, sparks, ice, water, wind), plus impact bursts with a light flash and shockwave. Every cast plays an arm-raise animation and a magic circle. Zones and slams send out shockwave rings, and placed objects kick up a dust ring as they rise.
- **Health:** a HUD health bar with shield overlay and damage trail, overhead health bars (team-colored in matches), and Roblox's default health display hidden.
- **No regen in arenas:** the default regen script is replaced, and the hub regenerates 5 HP/s.
- **Settings panel (⚙):** rebind the "type a spell" key, saved to the profile. Reserved keys are refused.
- **Match presentation:**
  - VS intro with avatars, then a fade into the arena
  - 3-2-1-FIGHT countdown
  - round banners
  - VICTORY (confetti) / DEFEAT / DRAW screen with an XP count-up
  - KO pop-ups and a level-up banner
- **Custom join loading screen** with tips.

### Changed (round 3)
- **Every player has 100 HP** and moves faster (walk speed 24, jump power 55).
- **Faster projectiles:** speed ×1.5 (`PROJECTILE_SPEED_SCALE`).
- **Bigger hitboxes:** +1.5 studs against players and breakables (`HITBOX_BONUS`), and area spells reach 1.5 studs further against players.
- **Cooldowns are cast cooldowns:** each spell's `cooldown` now applies to casting, not typing. Fireball is 0.9s, Spark and Crate 0.5s.
- **No one-shots:** a new balance rule caps any single hit at 34 damage.

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
