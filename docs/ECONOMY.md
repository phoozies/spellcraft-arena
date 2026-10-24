# Economy: coins, crates, wins, and the podium

There are **no levels or XP**. Players win matches to earn **coins**, spend coins on **Element Crates**, and each crate spin unlocks a new **element** (five new spells). **Wins** are the leaderboard stat and put the top 3 players in the server on the hub's **podium**.

```
win a match ──► +100 coins (+50 first win of the day) ──► Crate Shop
     │                                                       │ spin
     └──► +1 win ──► leaderstats, Most Wins board, podium    ▼
                                         a new element (you never win one you own)
```

## Coins

| Source | Amount | Where |
|---|---|---|
| Starting balance (new profile) | 150 | `Config.COINS.STARTING` (an Element Crate costs 250: one win away) |
| Winning a match | 100 | `Config.COINS.MATCH_WIN`, paid in `MatchService.finishMatch` |
| First win of the day | +50 | `Config.COINS.FIRST_WIN_OF_DAY` |
| Daily login chest | 25 × streak day (max 7) | `Config.COINS.DAILY_LOGIN`, `EconomyService.refreshDaily` |
| Daily quests | 25–60 each | `QUEST_POOL` in `EconomyService` |

Losing, knockouts, and round wins pay nothing. Solo test matches (admin/debug `solo`) never pay. The **Results** screen counts up the coins you earned (`MatchState.coinsGained`).

`EconomyService` is the **only** code that changes `profile.coins` or `profile.stats.wins` (`addCoins`, `spend`, `recordWin`). It fires `EconomyService.Changed(player)` after every change.

## Crates

Defined in [`src/shared/Economy/Crates.luau`](../src/shared/Economy/Crates.luau) (pure, testable). There is one crate:

| Crate | Price | What it does |
|---|---|---|
| 🎁 Element Crate | 250 | Unlocks a random element you don't own yet |

You start with one element (a free first pick in the Spellbook) and there are four, so three crates unlock everything. Once you own all four the crate can't be opened.

**How a spin is decided (server only, `CrateService.open`):**

1. Validate: known crate id, profile loaded, you've picked your first element, **not in a match**, not mid-spin (`Crates.SPIN_TIME` = 4s per player), enough coins, an element left to win.
2. `Crates.roll(owned, rng)`: pick uniformly among the elements you don't own.
3. `EconomyService.spend(price)`, then `ElementService.grant`.
4. Fire `CrateOpened(result)` to the opener. After `SPIN_TIME` the server sends the profile summary and a toast, so the balance and Spellbook don't spoil the spin.

**Client (`CrateController`):** the Crate Shop panel (side menu **🎁 Crates**, or the crate on the hub's Crate Shop stage) shows the price, the elements you own, and **Open**, which only sends `OpenCrate(crateId)`. When `CrateOpened` arrives, a reel of 40 element cards (the server's result at card 34) eases to a stop under the center marker, then reveals **NEW ELEMENT**. Equip it in the Spellbook.

**Adding an element:** add it to `Elements.LIST` with its five spells; the crate, reel, Spellbook, and hub shrines pick it up. **Retuning the crate:** edit `Crates.LIST` (`tests/Economy.spec.luau` covers the rolls).

## Wins leaderboard and podium (`LeaderboardService`)

- **leaderstats:** every player gets `leaderstats.Wins` and `leaderstats.Coins`, so the Roblox player list shows wins. Synced on profile load and on every `EconomyService.Changed`.
- **Most Wins board** (hub part tagged `WinsBoard`): the top `Config.LEADERBOARD_ROWS` (10) players **in this server** by wins.
- **Podium** (hub parts tagged `PodiumSpot`, attribute `Rank` 1–3): the top 3 players in the server with at least one win stand on the gold (1), silver (2) and bronze (3) pedestals as their real avatars (`Players:CreateHumanoidModelFromUserId`, anchored, cached per user, facing the plaza). Each pedestal's front shows `#rank name / N wins` (its SurfaceGui label named `Text`). Empty pedestals read "Win a match to stand here!".
- Refreshes at most every `Config.LEADERBOARD_REFRESH` (10s), only when something changed.

The ranking is per server (players currently here), built from their saved `stats.wins`, so a player's wins follow them between servers. A global all-time board would need an `OrderedDataStore`; see "Ideas" below.

## Hub layout

| Thing | Where (studs) | Built by |
|---|---|---|
| Spellbook kiosk (imported **Grimoire** model on a lectern, prompt "Spellbook") | (-22, 0, 70) | `Maps/InkwellPlaza.luau` |
| Element shrines (4, list each element's spells and shapes; prompt "Spellbook") | around the fountain | same |
| Daily Quests chest | (22, 0, 70) | same |
| Crate Shop stage (the Element Crate, prompt "Crates", with four element orbs) | (76, 0, 36) | same; the crate uses the imported **Crate** model tinted gold, else a colored block |
| Podium (3 pedestals) | (-23, 0, -20), the hall entrance | same |
| Most Wins board | right side of the hall entrance, angled to the plaza | same |

## Admin and debug

- `;coins <player> <amount>`, `;wins <player> <amount>`, `;crate <player>`, `;unlock <player> <element>` (see [ADMIN.md](ADMIN.md)).
- Studio playtests: `game.ServerStorage.WordcraftDebug:Invoke("crate", "Element")` (also `coins`, `wins`, `state`, `unlockall`, `element`). The MCP and command bar don't share module caches or `_G` with the running game, which is why this is a BindableFunction.

## Data

`Types.Profile` schema **3**: `elements` (the unlocked elements) and `element` (the equipped one, `""` until the first pick) replace `ownedSpells`. Migration from schema 2 (`PlayerDataService.reconcile`): drop `ownedSpells`; the player picks their first element again. Schema 1 to 2 dropped `xp`/`level` and re-rolled the quests.

## Ideas (not built)

- Global all-time wins board via `OrderedDataStore` (`SetAsync` on win, `GetSortedAsync` every few minutes).
- Robux coin packs (would need a receipt-safe `ProcessReceipt` and the game's no-paid-random-items rule revisited: crates are paid with earned coins only).
- Selling or dropping classes (see [CLASSES.md](CLASSES.md)).
