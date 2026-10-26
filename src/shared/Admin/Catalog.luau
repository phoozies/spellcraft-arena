--!strict
-- What the admin panel offers: tabs of groups of buttons. Every entry is just
-- one admin command (docs/ADMIN.md) with two placeholders, so the server stays
-- the only place commands are understood and checked:
--   {t}  the target picked in the panel ("me", "all", "others", or a username)
--   {v}  the text typed into an input entry
-- The panel (client AdminController) draws this; the server never trusts it.

local SpellDefinitions = require(script.Parent.Parent.Spells.SpellDefinitions)
local Elements = require(script.Parent.Parent.Spells.Elements)

export type Entry = {
	kind: "button" | "input",
	label: string,
	cmd: string,
	-- A Theme.COLORS key for the button ("good", "bad", "accent", ...).
	color: string?,
	-- Danger buttons need a second click within a couple of seconds.
	confirm: boolean?,
	-- Inputs only: the box's hint, its starting text, and the button's text.
	placeholder: string?,
	default: string?,
	button: string?,
}

export type Group = { title: string, entries: { Entry } }
export type Tab = { id: string, label: string, groups: { Group } }

local Catalog = {}

local function button(label: string, cmd: string, color: string?, confirm: boolean?): Entry
	return { kind = "button", label = label, cmd = cmd, color = color, confirm = confirm }
end

local function input(
	label: string,
	cmd: string,
	placeholder: string,
	default: string?,
	buttonText: string?
): Entry
	return {
		kind = "input",
		label = label,
		cmd = cmd,
		placeholder = placeholder,
		default = default,
		button = buttonText or "Run",
	}
end

-- The Give tab lists every spell, grouped by element (crate spells under Arcane).
local function spellGroups(): { Group }
	local order: { string } = {}
	local byElement: { [string]: { Entry } } = {}
	for _, def in SpellDefinitions.list do
		if not byElement[def.element] then
			byElement[def.element] = {}
			table.insert(order, def.element)
		end
		table.insert(byElement[def.element], button(def.name, "give {t} " .. def.id))
	end
	local groups: { Group } = {
		{
			title = "Everything",
			entries = { button("Give ALL spells", "give {t} all", "accent") },
		},
	}
	for _, element in order do
		local school = Elements.school(element)
		table.insert(groups, {
			title = if school then school.name else element,
			entries = byElement[element],
		})
	end
	return groups
end

local function unlockGroup(): Group
	local entries: { Entry } = {}
	for _, id in Elements.ids() do
		table.insert(entries, button(`Unlock {id}`, "unlock {t} " .. id, "good"))
	end
	table.insert(entries, button("Unlock all elements", "unlock {t} all", "good"))
	table.insert(entries, button("Unlock crate spells", "unlock {t} spells", "good"))
	return { title = "Unlock (saved)", entries = entries }
end

function Catalog.tabs(): { Tab }
	local statuses: { Entry } = {}
	for _, kind in { "Root", "Slow", "Shrink", "TimeStop", "Slippery" } do
		table.insert(statuses, button(kind, "status {t} " .. kind .. " 5", "purple"))
	end
	local modes: { Entry } = {}
	for _, mode in { "1v1", "2v2", "3v3", "4v4" } do
		table.insert(modes, button(`Start {mode}`, `startmatch {mode}`, "good"))
	end

	return {
		{
			id = "Player",
			label = "Player",
			groups = {
				{
					title = "Quick actions",
					entries = {
						button("Heal", "heal {t}", "good"),
						button("God mode", "god {t}", "accent"),
						button("Free cast", "freecast {t}", "accent"),
						button("Knockback", "knockback {t}", "peach"),
						button("Kill", "kill {t}", "bad", true),
					},
				},
				{
					title = "Move",
					entries = {
						button("Bring to me", "bring {t}", "turquoise"),
						button("Go to them", "tp me {t}", "turquoise"),
						button("Send to hub", "hub {t}", "turquoise"),
					},
				},
				{
					title = "Values",
					entries = {
						input("Walk speed", "speed {t} {v}", "default 18", "32", "Set"),
					},
				},
				{ title = "Status effect (5s)", entries = statuses },
				{
					title = "Moderation",
					entries = {
						button("Kick", "kick {t}", "bad", true),
						button("Ban 1 hour", "ban {t} 60 Banned by an admin", "bad", true),
						button("Ban forever", "ban {t} perm Banned by an admin", "bad", true),
					},
				},
			},
		},
		{ id = "Give", label = "Spells", groups = spellGroups() },
		{
			id = "Economy",
			label = "Economy",
			groups = {
				{
					title = "Coins",
					entries = {
						button("+100", "coins {t} 100", "accent"),
						button("+1,000", "coins {t} 1000", "accent"),
						button("+10,000", "coins {t} 10000", "accent"),
						input("Custom coins", "coins {t} {v}", "amount", "500", "Give"),
					},
				},
				{
					title = "Wins",
					entries = {
						input("Set wins to", "wins {t} {v}", "number", "10", "Set"),
					},
				},
				{
					title = "Spell Crate",
					entries = { button("Spin a crate (costs coins)", "crate {t}", "purple") },
				},
				unlockGroup(),
				{
					title = "Reset (saved data)",
					entries = {
						button("Reset coins", "reset {t} coins", "bad", true),
						button("Reset wins", "reset {t} wins", "bad", true),
						button("Reset elements", "reset {t} elements", "bad", true),
						button("Reset crate spells", "reset {t} spells", "bad", true),
						button("Reset crate pity", "reset {t} pity", "bad", true),
						button("Reset stats", "reset {t} stats", "bad", true),
						button("Reset gift claim", "reset {t} rewards", "bad", true),
						button("Reset tutorial", "reset {t} tutorial", "bad", true),
						button("Reset EVERYTHING", "reset {t} all", "bad", true),
					},
				},
			},
		},
		{
			id = "Match",
			label = "Match",
			groups = {
				{ title = "Start now (everyone in the hub)", entries = modes },
				{
					title = "Control",
					entries = {
						button("End their match", "endmatch {t}", "bad", true),
						button("Everyone to hub", "hub all", "turquoise", true),
						button("Clear hub objects", "clear", "peach"),
					},
				},
			},
		},
		{
			id = "Server",
			label = "Server",
			groups = {
				{
					title = "Announce to everyone",
					entries = { input("Message", "announce {v}", "type a message", nil, "Send") },
				},
				{
					title = "Bans",
					entries = { input("Unban UserId", "unban {v}", "UserId", nil, "Unban") },
				},
				{ title = "Help", entries = { button("List commands", "help", "blue") } },
			},
		},
	}
end

return Catalog
