# Economy: coins, crates, wins, and the podium

There are **no levels or XP**. Players win matches to earn **coins**, buy **base elements** with them (your first is free), and spin the **Spell Crate** for **crate spells** of five rarities. **Wins** are the leaderboard stat and put the top 3 players in the server on the hub's **podium**.

```
win a match ──► +100 coins (+50 first win of the day) ──► Crate Shop
     │                                                       │ spin
     └──► +1 win ──► leaderstats, Most Wins board, podium    ▼
                                         a new element (you never win one you own)
```

## Coins

| Source | Amount | Where |
|---|---|---|
| Starting balance (new profile) | 150 | `Config.COINS.STARTING` (a Spell Crate spin costs 100) |
| Winning a match | 100 | `Config.COINS.MATCH_WIN`, paid in `MatchService.finishMatch` |
| First win of the day | +50 | `Config.COINS.FIRST_WIN_OF_DAY` |
| Daily login chest | 25 × streak day (max 7) | `Config.COINS.DAILY_LOGIN`, `EconomyService.refreshDaily` |
| Daily quests | 25–60 each | `QUEST_POOL` in `EconomyService` |

Losing, knockouts, and round wins pay nothing. Solo test matches (admin/debug `solo`) never pay. The **Results** screen counts up the coins you earned (`MatchState.coinsGained`).

`EconomyService` is the **only** code that changes `profile.coins` or `profile.stats.wins` (`addCoins`, `spend`, `recordWin`). It fires `EconomyService.Changed(player)` after every change.

## Elements and crates

**Elements (bought directly).** Your first element is a free pick. Each other element costs **400 coins** (`price` in [`Elements.luau`](../src/shared/Spells/Elements.luau)); press Buy in the Spellbook's Elements tab (`BuyElement` remote, `ElementService.buy`). An element comes with its three base spells.

**The Spell Crate (gacha).** Defined in [`src/shared/Economy/Crates.luau`](../src/shared/Economy/Crates.luau) (pure, testable). One crate:

| Crate | Price | What it does |
|---|---|---|
| 🎁 Spell Crate | 100 | Wins one crate spell, picked by rarity |

Rarities are in [`Spells/Rarity.luau`](../src/shared/Spells/Rarity.luau): Common 55%, Uncommon 25%, Rare 12%, Epic 6%, Legendary 2%. There are 12 crate spells (see [SPELLS.md](SPELLS.md)). A spell you already own pays back coins (20 / 35 / 55 / 75 / 90 by rarity, always less than a spin).

**How a spin is decided (server only, `CrateService.open`):**

1. Validate: known crate id, profile loaded, you've picked your first element, **not in a match**, not mid-spin (`Crates.SPIN_TIME` = 4s per player), enough coins, a crate spell left to win.
2. `Crates.roll(owned, rng)`: roll a rarity by weight, then a spell of it.
3. `EconomyService.spend(price)`, then `ElementService.grantSpell`; the new spell is equipped straight into an empty loadout slot when it fits.
4. Fire `CrateOpened(result)` to the opener. After `SPIN_TIME` the server pays any duplicate refund and sends a toast, so the reveal isn't spoiled.

**Client (`CrateController`):** the Spell Crate panel (side menu **🎁 Crates**, or the crate on the hub's stage) shows the price and each rarity's odds and **Spin!**, which only sends `OpenCrate(crateId)`. When `CrateOpened` arrives, a reel of 40 spell cards in rarity colours (the server's result at card 34) eases to a stop, ticking as cards pass, then reveals the prize with a rarity sound and flash.

**Loadout.** Equip crate spells in the Spellbook's Loadout tab (`SetLoadout`): your element's three base spells plus up to two crate spells you own. Two spells with the same shape can't share a loadout.

**Adding a crate spell:** add a row with a `rarity` to `SpellDefinitions`. **Retuning:** edit `Crates.LIST`, `Rarity.LIST`, or an element's `price` (`tests/Economy.spec.luau` covers the rolls).

## Like & Favourite gift

A one-time thank-you of **250 coins** (`Config.SUPPORT.LIKE_FAVORITE_COINS`, less than one element) for players who Like and Favourite the game. It is a **physical gift box on the hub plaza** (tag `LikeGift`): hold its prompt to claim. There is no menu button.

- **Roblox gives no way to check a like or a favourite**, so the claim is on the honor system. The server only opens it after the player has spent `Config.SUPPORT.MIN_SECONDS` (90) in the server, accepts one claim per account (`profile.rewards.likeFav`), and rate-limits the prompt. `EconomyService.claimLikeReward` pays it through `addCoins`. The client (`SupportController`) turns the prompt off once claimed and counts down "ready in Ns" on it.
- Before launching, check Roblox's current rules on rewarding likes or favourites, and switch the feature off (remove the gift box and `SupportController`) if they don't allow it.
- Studio QA: `SpellcraftDebug:Invoke("likefav", false)` makes it claimable again, `("takecoins", 250)` removes the coins.

## Wins leaderboard and podium (`LeaderboardService`)

- **leaderstats:** every player gets `leaderstats.Wins` and `leaderstats.Coins`, so the Roblox player list shows wins. Synced on profile load and on every `EconomyService.Changed`.
- **Most Wins board** (hub part tagged `WinsBoard`): the top `Config.LEADERBOARD_ROWS` (10) players **in this server** by wins.
- **Podium** (hub parts tagged `PodiumSpot`, attribute `Rank` 1–3): the top 3 players in the server with at least one win stand on the gold (1), silver (2) and bronze (3) pedestals as their real avatars (`Players:CreateHumanoidModelFromUserId`, anchored, cached per user, facing the island's centre). Each pedestal's front shows `#rank name / N wins` (its SurfaceGui label named `Text`). Empty pedestals read "Win a match to stand here!".
- Refreshes at most every `Config.LEADERBOARD_REFRESH` (10s), only when something changed.

The ranking is per server (players currently here), built from their saved `stats.wins`, so a player's wins follow them between servers. A global all-time board would need an `OrderedDataStore`; see "Ideas" below.

## Hub layout

| Thing | Where (studs; bearing 0 = north = -Z, 90 = east) | Built by |
|---|---|---|
| Spellbook kiosk (imported **Grimoire** model on a lectern, prompt "Spellbook") | plaza, bearing 150, radius 36 | `Maps/InkwellPlaza.luau` |
| Element shrines (4, list each element's 3 base spells, shapes, and price; prompt "Spellbook") | plaza, radius 30, bearings 35 / 105 / 255 / 325 | same |
| Daily Quests chest | plaza, bearing 210, radius 36 | same |
| Like & Favourite gift box | plaza, bearing 180, radius 40 | same |
| Crate Shop stage (the Spell Crate, prompt "Crates", with five rarity orbs) | (100, 0, 45), east | same; the crate uses the imported **Crate** model tinted gold, else a colored block |
| Podium (3 pedestals) | bearing 335, radius 64, facing the centre | same |
| Most Wins board | bearing 25, radius 64, facing the centre | same |

## Admin and debug

- `;coins <player> <amount>`, `;wins <player> <amount>`, `;crate <player>`, `;unlock <player> <element|spells|all>` (see [ADMIN.md](ADMIN.md)).
- Studio playtests: `game.ServerStorage.SpellcraftDebug:Invoke("crate", "Spell")` (also `coins`, `wins`, `state`, `unlockall`, `element`). The MCP and command bar don't share module caches or `_G` with the running game, which is why this is a BindableFunction.

## Data

`Types.Profile` schema **5**: `elements` (owned elements), `element` (the equipped one, `""` until the first pick), `spells` (crate spells owned), `loadout` (up to 2 equipped crate spells), and `tutorial.done`. Schema 4 to 5 adds the new fields and marks players who already picked an element as done with the tutorial. Schema 3 replaced `ownedSpells` with `elements`/`element`. Migration from schema 2 (`PlayerDataService.reconcile`): drop `ownedSpells`; the player picks their first element again. Schema 1 to 2 dropped `xp`/`level` and re-rolled the quests.

## Ideas (not built)

- Global all-time wins board via `OrderedDataStore` (`SetAsync` on win, `GetSortedAsync` every few minutes).
- Robux coin packs (would need a receipt-safe `ProcessReceipt` and the game's no-paid-random-items rule revisited: crates are paid with earned coins only).
- Selling or dropping classes (see [CLASSES.md](CLASSES.md)).

## Battleground NPC coins

Knocking out a hostile NPC in the Battleground pays `reward` coins (Raider 3, Mage 5, Brute 12, Warlord 40; `src/shared/Battleground/Npcs.luau`) through `EconomyService.addCoins`. Each player can earn at most `Config.BATTLEGROUND.NPC.COIN_CAP` (120) coins from NPCs per `COIN_WINDOW` (300 s); past the cap, kills still count for quests but pay nothing. NPCs come back `RESPAWN` seconds (45; the Warlord 180) after they fall.
