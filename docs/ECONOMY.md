# Economy: coins, chests, wins, and the podium

There are **no levels or XP**. Players win matches to earn **coins**, buy **base elements** with them (your first is free), and open **chests** (Common, Uncommon, Rare, Epic, Legendary) for **chest spells** of five rarities. **Wins** are the leaderboard stat and put the top 3 players in the server on the hub's **podium**.

```
win a match ──► +100 coins (+50 first win of the day) ──┬──► Spellbook: buy an element (400)
     │                                                   └──► Chest Shop: a chest (100 .. 2000)
     └──► +1 win ──► leaderstats, Most Wins board, podium        │
                         a chest spell of the chest's rarity or better ◄──┘
                         (a duplicate pays coins back; pity every 10th Common-Rare chest)
```

## Coins

| Source | Amount | Where |
|---|---|---|
| Starting balance (new profile) | 150 | `Config.COINS.STARTING` (a Common Chest costs 100) |
| Winning a match | 100 | `Config.COINS.MATCH_WIN`, paid in `MatchService.finishMatch` |
| First win of the day | +50 | `Config.COINS.FIRST_WIN_OF_DAY` |
| Daily login chest | 25 × streak day (max 7) | `Config.COINS.DAILY_LOGIN`, `EconomyService.refreshDaily` |
| Daily quests | 25–60 each | `QUEST_POOL` in `EconomyService` |
| Battleground NPC knockouts | 3 / 5 / 12 / 40, capped at 120 per 5 minutes | see "Battleground NPC coins" below |
| Like & Favourite gift (once) | 250 | `Config.SUPPORT`, see below |
| Duplicate chest spell | 30% of the chest price | `Chests.refund` |

Losing, player knockouts, and round wins pay nothing. Solo test matches (admin/debug `solo`) never pay. The **Results** screen counts up the coins you earned (`MatchState.coinsGained`).

`EconomyService` is the **only** code that changes `profile.coins` or `profile.stats.wins` (`addCoins`, `spend(player, amount, item?)`, `recordWin`, and the admin-only `setWins` / `reset`). It fires `EconomyService.Changed(player)` after every change, and reports every source and sink to `TelemetryService` as a coin economy flow.

## Elements and chests

**Elements (bought directly).** Your first element is a free pick. Each other element costs **400 coins** (`price` in [`Elements.luau`](../src/shared/Spells/Elements.luau)); press Buy in the Spellbook's Elements tab (`BuyElement` remote, `ElementService.buy`). An element comes with its three base spells.

**The chests (gacha).** Defined in [`src/shared/Economy/Chests.luau`](../src/shared/Economy/Chests.luau) (pure, testable). Five chests, one per rarity; each drops a chest spell of **its rarity or better**:

| Chest | Price | Odds (rolled by the rarity weights, renormalised) | Duplicates |
|---|---|---|---|
| Common Chest | 100 | Common 55%, Uncommon 25%, Rare 12%, Epic 6%, Legendary 2% | possible |
| Uncommon Chest | 250 | Uncommon 56%, Rare 27%, Epic 13%, Legendary 4% | possible |
| Rare Chest | 500 | Rare 60%, Epic 30%, Legendary 10% | possible |
| Epic Chest | 1000 | Epic 75%, Legendary 25% | never while one is unowned |
| Legendary Chest | 2000 | Legendary 100% | never while one is unowned |

Rarity weights are in [`Spells/Rarity.luau`](../src/shared/Spells/Rarity.luau). There are 12 chest spells (see [SPELLS.md](SPELLS.md)). A duplicate pays back `Chests.refund`: 30% of the chest's price (`Chests.REFUND_SHARE`), at least the rarity's own `refund`, never the whole price. The shop won't sell a chest whose every spell you already own.

**Pity.** Every chest that lands below Epic adds one to `profile.pity`; when it reaches `Chests.PITY.SPINS - 1` (9), the next Common, Uncommon or Rare chest is guaranteed Epic or Legendary (`Chests.PITY`, the Epic:Legendary weights kept at 3:1) and a spell you don't own yet if one is left. Any Epic or Legendary result resets the counter. The shop shows how many chests are left. `ChestService` is the only writer of `profile.pity`.

**How a chest is decided (server only, `ChestService.open`):**

1. Validate: known chest id, profile loaded, you've picked your first element, **not in a match**, not mid-spin (`Chests.SPIN_TIME` = 4s per player), enough coins, a spell left to win from that chest.
2. `Chests.roll(chestId, owned, rng, pity)`: roll a rarity by weight among the ones the chest can drop (Epic+ when the pity is due; only rarities with an unowned spell for Epic/Legendary chests and the pity), then a spell of it.
3. `EconomyService.spend(price, "chest<Id>")`, then `ElementService.grantSpell`; the new spell is equipped straight into an empty loadout slot when it fits. The pity counter moves (`Chests.nextPity`).
4. Fire `ChestOpened(result)` to the opener (`chest`, `spell`, `rarity`, `duplicate`, `refund`, `equipped`, `pity`, `coins`). After `SPIN_TIME` the server pays any duplicate refund and sends a toast, so the reveal isn't spoiled.

**Client (`ChestController`):** the Chest Shop panel (side menu **Chests**, or any of the five chests on the hub's stage, which opens the panel on that chest) shows a shelf of the five chests as 3D previews tinted to their rarity with their prices, and for the picked chest its odds as animated bars, how many of its spells you own, the pity count, and **Open**, which only sends `OpenChest(chestId)`. When `ChestOpened` arrives the hub chest throws its lid open and a reel of 40 spell cards rolled from that chest's odds (the server's result at card 34) eases to a stop, ticking as cards pass, then reveals the prize with a rarity sound and flash and lists its numbers (`Spells/SpellStats`).

**Loadout.** Equip chest spells in the Spellbook's Loadout tab (`SetLoadout`): your element's three base spells plus up to two chest spells you own. Two spells with the same shape can't share a loadout.

**Adding a chest spell:** add a row with a `rarity` to `SpellDefinitions`. **Retuning:** edit `Chests.LIST`, `Chests.PITY`, `Chests.REFUND_SHARE`, `Rarity.LIST`, or an element's `price` (`tests/Economy.spec.luau` covers the rolls and the pity).

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
| Chest Shop stage (the five chests Common to Legendary, each prompt "Chests" with a `ChestId`) | bearing 135 (south-east), radius 122, facing the plaza | same; each chest is the **ShopChest** block model tinted to its rarity, else a coloured block |
| Podium (3 pedestals) | bearing 335, radius 64, facing the centre | same |
| Most Wins board | bearing 25, radius 64, facing the centre | same |
| Team boxes (two 1v1, two 2v2, one 3v3, one 4v4) and the red Arena Gate behind them | arc to the north, radius 112 (gate near bearing 0, radius 150) | same |
| Battleground portal | bearing 180, radius 130 (end of the south road) | same |
| Training Groves (west and east, 100 x 112) | x 102 to 202 studs either side of the axis | same |

## Admin and debug

- `;coins <player> <amount>`, `;wins <player> <amount>`, `;chest <player> [rarity]`, `;unlock <player> <element|spells|all>`, `;reset <player> <coins|wins|stats|elements|spells|pity|rewards|tutorial|all>` (see [ADMIN.md](ADMIN.md)).
- Studio playtests: `game.ServerStorage.SpellcraftDebug:Invoke("chest", "Common")` (also `coins`, `takecoins`, `wins`, `state`, `unlockall`, `element`, `likefav`). The MCP and command bar don't share module caches or `_G` with the running game, which is why this is a BindableFunction.

## Data

`Types.Profile` schema **7**. The economy fields: `coins`, `stats.wins`, `elements` (owned elements), `element` (the equipped one, `""` until the first pick), `spells` (chest spells owned), `loadout` (up to 2 equipped chest spells), `pity` (chests opened since the last Epic or better), `rewards.likeFav`, and `daily` (login streak, first win, quests). Migrations (`PlayerDataService.reconcile`):

| Step | Change |
|---|---|
| 1 → 2 | dropped `xp`/`level` and re-rolled the quests |
| 2 → 3 | `ownedSpells` replaced by `elements`/`element`; the player picks their first element again |
| 3 → 4 | added `settings.music` and `rewards.likeFav` |
| 4 → 5 | added `spells`, `loadout`, `tutorial.done` (done for players who already picked an element) |
| 5 → 6 | added `pity` (0) |

Settings added later (`settings.sfx`, `settings.shake`) come from the defaults with no schema bump.

## Ideas (not built)

- Global all-time wins board via `OrderedDataStore` (`SetAsync` on win, `GetSortedAsync` every few minutes).
- Robux coin packs (would need a receipt-safe `ProcessReceipt` and the game's no-paid-random-items rule revisited: chests are paid with earned coins only).
- Selling or dropping classes (see [CLASSES.md](CLASSES.md)).

## Battleground NPC coins

Knocking out a hostile NPC in the Battleground pays `reward` coins (Raider 3, Mage 5, Brute 12, Warlord 40; `src/shared/Battleground/Npcs.luau`) through `EconomyService.addCoins`. Each player can earn at most `Config.BATTLEGROUND.NPC.COIN_CAP` (120) coins from NPCs per `COIN_WINDOW` (300 s); past the cap, kills still count for quests but pay nothing. NPCs come back `RESPAWN` seconds (45; the Warlord 180) after they fall.
