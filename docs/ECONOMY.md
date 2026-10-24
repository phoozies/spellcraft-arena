# Economy: coins, crates, wins, and the podium

There are **no levels or XP**. Players win matches to earn **coins**, spend coins on **crates**, and each crate spin unlocks a **spell**. **Wins** are the leaderboard stat and put the top 3 players in the server on the hub's **podium**.

```
win a match ──► +100 coins (+50 first win of the day) ──► Crate Shop
     │                                                       │ spin
     └──► +1 win ──► leaderstats, Most Wins board, podium    ▼
                                              new spell (or a duplicate: half the price back)
```

## Coins

| Source | Amount | Where |
|---|---|---|
| Starting balance (new profile) | 150 | `Config.COINS.STARTING` (enough for one Common crate) |
| Winning a match | 100 | `Config.COINS.MATCH_WIN`, paid in `MatchService.finishMatch` |
| First win of the day | +50 | `Config.COINS.FIRST_WIN_OF_DAY` |
| Daily login chest | 25 × streak day (max 7) | `Config.COINS.DAILY_LOGIN`, `EconomyService.refreshDaily` |
| Daily quests | 25–60 each | `QUEST_POOL` in `EconomyService` |
| Crate duplicate | half the crate's price | `Crates.DUPLICATE_REFUND` |

Losing, knockouts, and round wins pay nothing. Solo test matches (admin/debug `solo`) never pay. The **Results** screen counts up the coins you earned (`MatchState.coinsGained`).

`EconomyService` is the **only** code that changes `profile.coins` or `profile.stats.wins` (`addCoins`, `spend`, `recordWin`). It fires `EconomyService.Changed(player)` after every change.

## Crates

Defined in [`src/shared/Economy/Crates.luau`](../src/shared/Economy/Crates.luau) (pure, testable). One crate per rarity:

| Crate | Price | Odds |
|---|---|---|
| ● Common | 100 | Common 80%, Uncommon 20% |
| ▲ Uncommon | 250 | Uncommon 80%, Rare 20% |
| ◆ Rare | 500 | Rare 80%, Epic 20% |
| ★ Epic | 1000 | Epic 85%, Legendary 15% |
| 👑 Legendary | 2000 | Legendary 100% |

**How a spin is decided (server only, `CrateService.open`):**

1. Validate: known crate id, profile loaded, **not in a match**, not mid-spin (`Crates.SPIN_TIME` = 4s per player), enough coins.
2. `Crates.roll(crate, rng)`: roll the crate's rarity odds, then pick a random spell of that rarity from `SpellDefinitions.crateDrops(rarity)` (starters never drop). If a tier has no spells, fall back to lower tiers.
3. `EconomyService.spend(price)`.
4. If the player already owns the spell, it's a **duplicate**: refund `floor(price × 0.5)` (credited right away, shown after the spin). Otherwise add it to `profile.ownedSpells`.
5. Fire `CrateOpened(result)` to the opener. After `SPIN_TIME` the server sends the profile summary and a toast, so the balance and Spellbook don't spoil the spin.

**Client (`CrateController`):** the Crate Shop panel (side menu **🎁 Crates**, or any crate's prompt at the hub's Crate Shop stage) shows each crate's price and odds. **Open** only sends `OpenCrate(crateId)`. When `CrateOpened` arrives, a reel of 40 spell cards (random possible drops, the server's result at card 34) eases to a stop under the center marker, then reveals **NEW SPELL** or **duplicate +N coins**.

**Adding a spell to crates:** give it a `rarity` and no `starter` flag in `SpellDefinitions.luau`. It's automatically in that rarity's crate pool, the reel, the Spellbook's lock text, and the draft.

**Adding or retuning a crate:** edit `Crates.LIST`. Keep `odds` summing to 100 and mostly the crate's own tier (`tests/Economy.spec.luau` checks both).

## Wins leaderboard and podium (`LeaderboardService`)

- **leaderstats:** every player gets `leaderstats.Wins` and `leaderstats.Coins`, so the Roblox player list shows wins. Synced on profile load and on every `EconomyService.Changed`.
- **Most Wins board** (hub part tagged `WinsBoard`): the top `Config.LEADERBOARD_ROWS` (10) players **in this server** by wins.
- **Podium** (hub parts tagged `PodiumSpot`, attribute `Rank` 1–3): the top 3 players in the server with at least one win stand on the gold (1), silver (2) and bronze (3) pedestals as their real avatars (`Players:CreateHumanoidModelFromUserId`, anchored, cached per user, facing the plaza). Each pedestal's front shows `#rank name / N wins` (its SurfaceGui label named `Text`). Empty pedestals read "Win a match to stand here!".
- Refreshes at most every `Config.LEADERBOARD_REFRESH` (10s), only when something changed.

The ranking is per server (players currently here), built from their saved `stats.wins`, so a player's wins follow them between servers. A global all-time board would need an `OrderedDataStore`; see "Ideas" below.

## Hub layout

| Thing | Where (studs) | Built by |
|---|---|---|
| Spellbook kiosk (imported **Grimoire** model on a lectern, prompt "Spellbook") | (-16, 0, 50) | `Maps/InkwellPlaza.luau` |
| Daily Quests chest | (16, 0, 50) | same |
| Crate Shop stage (5 crates, prompt "Crates") | (50, 0, 38) | same; crates use the imported **Crate** model tinted by rarity, else colored blocks |
| Podium (3 pedestals) | (62, 0, -12) | same |
| Most Wins board | right of the podium, angled to the plaza | same |

## Admin and debug

- `;coins <player> <amount>`, `;wins <player> <amount>`, `;crate <player> <rarity>` (see [ADMIN.md](ADMIN.md)).
- Studio playtests: `game.ServerStorage.WordcraftDebug:Invoke("crate", "Epic")` (also `coins`, `wins`, `state`, `unlockall`). The MCP and command bar don't share module caches or `_G` with the running game, which is why this is a BindableFunction.

## Data

`Types.Profile` schema **2**: `coins` replaces `xp`/`level`. Migration from schema 1 (`PlayerDataService.reconcile`): drop `xp`/`level`, re-roll daily quests (they rewarded XP), drop owned spell ids that no longer exist, and always own the starters. Existing players keep spells that still exist (for example a schema-1 player who had unlocked Black Hole keeps it).

## Ideas (not built)

- Global all-time wins board via `OrderedDataStore` (`SetAsync` on win, `GetSortedAsync` every few minutes).
- Robux coin packs (would need a receipt-safe `ProcessReceipt` and the game's no-paid-random-items rule revisited: crates are paid with earned coins only).
