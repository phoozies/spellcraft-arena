# Admin Commands

There are two ways to run a command, and both go through the same server code:

- **The Admin panel (click).** Admins see a purple **Admin** button under the wallet. Click it, or press the **`** (backquote) key, to open a classic Roblox-style admin window. Drag its title bar to move it, and close it with **X** (or the button or key again).
- **Chat (type).** Use the `;` prefix, for example `;give me fireball`. Admin commands are never shown in chat. If a non-admin types `;something`, it's sent as a normal chat message.

Every command you run sends you a short confirmation toast and is printed to the server log (`[Admin] name (userId): command`).

## The Admin panel

- **Target (left):** `Me`, `All`, `Others`, or any other player in the server. Every button that acts on a player uses the picked target.
- **Tabs (right):**
  - **Player:** heal, god mode, free cast, knockback, kill, bring / go to / send to hub, walk speed, status effects, kick, ban.
  - **Spells:** give any spell (grouped by element, crate spells under Arcane) or all of them.
  - **Economy:** coins (+100 / +1,000 / +10,000 or a custom amount), set wins, a Reset group (coins, wins, stats, elements, crate spells, crate pity, gift claim, tutorial, everything), spin a Spell Crate, unlock elements.
  - **Match:** start 1v1 to 4v4 now, end a match, send everyone to the hub, clear hub objects.
  - **Server:** announce a message, unban a UserId, list commands.
- **Danger buttons** (kill, kick, ban, end match, everyone to hub) change to **Sure?** and need a second click within 2 seconds.
- **Command box (bottom):** type any command from the table below (no `;` needed) and press Enter. The log above it shows what you ran and what the server answered.

The panel only draws buttons from `src/shared/Admin/Catalog.luau`. Each button is just a command string, so it can't do anything chat can't. The server re-checks that you are an admin on every click (the `AdminCommand` remote: admins only, 200 characters at most, 10 per second at most).

## Who is an admin

Admin status is checked only on the server, when a player joins (`AdminService`). You're an admin if any of these is true:

1. Your UserId is in `Config.ADMIN_USER_IDS` (currently `118721190`). Add more IDs there.
2. You own the place, or for a group game, you're at or above `Config.ADMIN_GROUP_MIN_RANK` (255 = owner).
3. You're playtesting in **Studio**, where everyone is an admin.

## Targets

Commands that take a `<player>` accept:

- `me`
- `all`
- `others`
- The start of a username or display name: `pho` matches `phoozies`.

Leaving the target out means `me` where that makes sense.

## Commands

| Command | What it does |
|---|---|
| `;help [command]` | Lists the commands, or shows one command's usage |
| `;give <player> <spell\|all>` | Gives spell copies, skipping the spellbook and recharge rules. The hotbar holds 5. |
| `;unlock <player> <Fire\|Water\|Earth\|Air\|all>` | Permanently unlocks an element (saved) |
| `;coins <player> <amount>` | Grants coins (spent on crates) |
| `;wins <player> <amount>` | Sets the win count (leaderboard, board, podium) |
| `;reset <player> <coins\|wins\|stats\|elements\|spells\|pity\|rewards\|tutorial\|all>` | Resets saved data: coins back to the starting amount, wins/stats to 0, owned elements or crate spells forgotten (free first pick again), crate pity to 0, the Like & Favourite gift claimable again, the tutorial shown again. Players in a match are skipped. |
| `;crate <player>` | Spins a Spell Crate for the player, charging their coins like the shop |
| `;heal <player>` | Restores full health |
| `;kill <player>` | Knocks the player out |
| `;god <player>` | Toggles invulnerability. Resets on respawn. |
| `;speed <player> <n>` | Sets walk speed (default 18). Resets on the next status change or respawn. |
| `;freecast <player>` | Toggles no typing cooldown and no recharges, for testing |
| `;tp <player> <destination>` | Teleports players to another player |
| `;bring <player>` | Teleports players to you |
| `;hub <player>` | Pulls players out of their match and back to the hub |
| `;startmatch <1v1\|2v2\|3v3\|4v4> [players...]` | Starts a match right away, with everyone in the hub if no players are listed. Short-handed matches end on the round timer. |
| `;endmatch <player>` | Ends that player's match with no winner |
| `;clear` | Removes every placed object and summon in the hub |
| `;knockback <player>` | Launches the player with a server-side push, for testing |
| `;status <player> <Root\|Slow\|Shrink\|TimeStop\|Slippery> [sec]` | Applies a status effect, for testing |
| `;announce <message>` | Shows a toast to everyone. The text goes through Roblox's text filter. |
| `;kick <player> [reason]` | Kicks the player from this server |
| `;ban <player> <minutes\|perm> [reason]` | Bans the player across the whole experience (`Players:BanAsync`) |
| `;unban <userId>` | Lifts a ban |

Spell names can be any alias and can be more than one word, for example `;give me fire bomb`. `;give` readies a copy of the spell on your hotbar even if it isn't in your element.

`ban` takes one player at a time (not `all` or `others`). A player named exactly like the target word always wins over a longer name that starts the same way.

## Adding a command

Add an entry to `COMMANDS` in [`src/server/Services/AdminService.luau`](../src/server/Services/AdminService.luau):

```lua
COMMANDS.example = {
	usage = "example <player>",
	help = "One line shown by ;help example.",
	run = function(admin, args, rest)
		-- args: words after the command name; rest: the raw text after it
		return "Message toasted back to the admin"
	end,
}
```

Commands run in their own thread, so yielding inside them (DataStores, filtering, bans) is fine.

To give it a button, add an entry in `src/shared/Admin/Catalog.luau`: `button("Label", "example {t}")`, or `input(...)` for a command that needs typed text (`{t}` is the picked target, `{v}` the typed value).
