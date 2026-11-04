--!strict
-- Admin commands, typed in chat with Config.ADMIN_PREFIX
-- (";"), e.g. ";cast me fireball" or ";startmatch 2v2", or clicked in the admin
-- panel (client AdminController), which sends the same text through the
-- AdminCommand remote. See docs/ADMIN.md.
--
-- Who is an admin: UserIds in Config.ADMIN_USER_IDS, the place owner (or
-- group members at rank >= ADMIN_GROUP_MIN_RANK), and anyone playtesting
-- in Studio. Admin status is decided ONLY on the server; a non-admin's
-- ";..." message is delivered as normal chat.
--
-- Player targets: "me", "all", "others", or the start of a username or
-- display name ("pho" -> phoozies).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")

local Config = require(ReplicatedStorage.Shared.Config)
local Chests = require(ReplicatedStorage.Shared.Economy.Chests)
local Elements = require(ReplicatedStorage.Shared.Spells.Elements)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local SpellDefinitions = require(ReplicatedStorage.Shared.Spells.SpellDefinitions)
local WordMatcher = require(ReplicatedStorage.Shared.Spells.WordMatcher)
local CastService = require(script.Parent.CastService)
local ChestService = require(script.Parent.ChestService)
local DestructibleService = require(script.Parent.DestructibleService)
local EconomyService = require(script.Parent.EconomyService)
local ElementService = require(script.Parent.ElementService)
local SpellbookService = require(script.Parent.SpellbookService)
local MatchService = require(script.Parent.MatchService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local SpellInputService = require(script.Parent.SpellInputService)
local StatusService = require(script.Parent.StatusService)

type Command = {
	usage: string,
	help: string,
	run: (admin: Player, args: { string }, rest: string) -> string?,
}

local AdminService = {}

local admins: { [Player]: boolean } = {}
local lastPanelCommand: { [Player]: number } = {}
local toastRemote: RemoteEvent
local logRemote: RemoteEvent

-- Panel commands: at most one per this many seconds, and this long at most.
local PANEL_COOLDOWN = 0.1
local PANEL_MAX_LENGTH = 200

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

local function checkAdmin(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	if table.find(Config.ADMIN_USER_IDS, player.UserId) then
		return true
	end
	if game.CreatorType == Enum.CreatorType.User then
		return player.UserId == game.CreatorId
	end
	local ok, rank = pcall(function()
		return player:GetRankInGroup(game.CreatorId)
	end)
	return ok and rank >= Config.ADMIN_GROUP_MIN_RANK
end

function AdminService.isAdmin(player: Player): boolean
	return admins[player] == true
end

local function reply(admin: Player, message: string)
	toastRemote:FireClient(admin, message, "info")
	logRemote:FireClient(admin, message)
end

-- Resolves a target word to players.
local function findPlayers(admin: Player, word: string?): { Player }
	if not word or word == "" or word == "me" then
		return { admin }
	end
	local lower = string.lower(word)
	-- An exact username wins over a prefix ("bob" over "bobby").
	for _, p in Players:GetPlayers() do
		if string.lower(p.Name) == lower then
			return { p }
		end
	end
	if lower == "all" then
		return Players:GetPlayers()
	end
	if lower == "others" then
		local list = {}
		for _, p in Players:GetPlayers() do
			if p ~= admin then
				table.insert(list, p)
			end
		end
		return list
	end
	for _, p in Players:GetPlayers() do
		if
			string.sub(string.lower(p.Name), 1, #lower) == lower
			or string.sub(string.lower(p.DisplayName), 1, #lower) == lower
		then
			return { p }
		end
	end
	return {}
end

local function names(list: { Player }): string
	local out = {}
	for _, p in list do
		table.insert(out, p.Name)
	end
	return table.concat(out, ", ")
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- "fireball", "earth wall", "all" -> spell ids
local function resolveSpells(text: string): { string }
	if string.lower(text) == "all" then
		local ids = {}
		for _, def in SpellDefinitions.list do
			table.insert(ids, def.id)
		end
		return ids
	end
	local id = WordMatcher.matchWord(text) or (SpellDefinitions.get(text) and text)
	return if id then { id } else {}
end

-- Joins args[from..] back into a string (for multi-word spells / messages).
local function joinFrom(args: { string }, from: number): string
	return table.concat(args, " ", from)
end

----------------------------------------------------------------------
-- Commands
----------------------------------------------------------------------

local COMMANDS: { [string]: Command } = {}

COMMANDS.help = {
	usage = "help [command]",
	help = "List commands, or show one command's usage.",
	run = function(_admin, args)
		local name = args[1] and string.lower(args[1])
		local command = name and COMMANDS[name]
		if command then
			return `{Config.ADMIN_PREFIX}{command.usage} — {command.help}`
		end
		local list = {}
		for commandName in COMMANDS do
			table.insert(list, commandName)
		end
		table.sort(list)
		return "Commands: " .. table.concat(list, ", ") .. ` (try {Config.ADMIN_PREFIX}help cast)`
	end,
}

COMMANDS.cast = {
	usage = "cast <player> <spell|all>",
	help = "Make a player cast spells now where they face, skipping the spellbook and recharge rules.",
	run = function(admin, args)
		local targets = findPlayers(admin, args[1])
		local spells = resolveSpells(joinFrom(args, 2))
		if #targets == 0 or #spells == 0 then
			return "Usage: cast <player> <spell|all>"
		end
		local cast = 0
		for _, target in targets do
			for _, id in spells do
				if CastService.castForced(target, id) then
					cast += 1
				end
			end
		end
		return `{names(targets)}: {cast} of {#spells * #targets} cast(s) worked.`
	end,
}

COMMANDS.unlock = {
	usage = "unlock <player> <Fire|Water|Earth|Air|spells|all>",
	help = "Permanently unlock an element (or `spells`: every chest spell) for a player (saved).",
	run = function(admin, args)
		local targets = findPlayers(admin, args[1])
		local word = args[2] or ""
		local wanted: { string } = {}
		local allSpells = string.lower(word) == "spells" or string.lower(word) == "all"
		if string.lower(word) == "all" then
			wanted = Elements.ids()
		elseif allSpells then
			wanted = {}
		else
			local id = string.upper(string.sub(word, 1, 1)) .. string.lower(string.sub(word, 2))
			if Elements.get(id) then
				wanted = { id }
			end
		end
		if #targets == 0 or (#wanted == 0 and not allSpells) then
			return "Usage: unlock <player> <Fire|Water|Earth|Air|spells|all>"
		end
		for _, target in targets do
			for _, id in wanted do
				ElementService.grant(target, id)
			end
			if allSpells then
				for _, def in SpellDefinitions.chestSpells() do
					ElementService.grantSpell(target, def.id)
				end
			end
			EconomyService.sendSummary(target)
		end
		return `Unlocked {if allSpells then "every chest spell and " else ""}{table.concat(
			wanted,
			", "
		)} for {names(targets)}.`
	end,
}

COMMANDS.coins = {
	usage = "coins <player> <amount>",
	help = "Grant coins (spent on chests).",
	run = function(admin, args)
		local targets = findPlayers(admin, args[1])
		local amount = tonumber(args[2])
		if #targets == 0 or not amount or amount <= 0 then
			return "Usage: coins <player> <amount>"
		end
		for _, target in targets do
			EconomyService.addCoins(target, math.min(amount, 1000000), "admin")
		end
		return `Gave {amount} coins to {names(targets)}.`
	end,
}

COMMANDS.wins = {
	usage = "wins <player> <amount>",
	help = "Set a player's win count (leaderboard + podium).",
	run = function(admin, args)
		local targets = findPlayers(admin, args[1])
		local amount = tonumber(args[2])
		if #targets == 0 or not amount or amount < 0 then
			return "Usage: wins <player> <amount>"
		end
		for _, target in targets do
			EconomyService.setWins(target, math.min(amount, 1000000))
		end
		return `Set {names(targets)} to {amount} wins.`
	end,
}

local RESET_SCOPES = {
	"coins",
	"wins",
	"stats",
	"elements",
	"spells",
	"pity",
	"rewards",
	"tutorial",
}

COMMANDS.reset = {
	usage = "reset <player> <coins|wins|stats|elements|spells|pity|rewards|tutorial|all>",
	help = "Reset part of a player's saved profile (`all` = every one of those). Players in a match are skipped.",
	run = function(admin, args)
		local targets = findPlayers(admin, args[1])
		local scope = string.lower(args[2] or "")
		local scopes = if scope == "all" then RESET_SCOPES else { scope }
		if #targets == 0 or (scope ~= "all" and not table.find(RESET_SCOPES, scope)) then
			return `Usage: reset <player> <{table.concat(RESET_SCOPES, "|")}|all>`
		end
		local done: { Player } = {}
		for _, target in targets do
			if not PlayerDataService.get(target) then
				reply(admin, `{target.Name}: profile still loading.`)
			elseif MatchService.isInMatch(target) then
				reply(admin, `{target.Name}: in a match, skipped.`)
			else
				for _, one in scopes do
					if one == "elements" or one == "spells" then
						ElementService.reset(target, one)
					elseif one == "pity" then
						ChestService.resetPity(target)
					else
						EconomyService.reset(target, one)
					end
				end
				table.insert(done, target)
			end
		end
		if #done == 0 then
			return "Nobody was reset."
		end
		return `Reset {scope} for {names(done)}.`
	end,
}

COMMANDS.chest = {
	usage = "chest <player> [common|uncommon|rare|epic|legendary]",
	help = "Open a chest for a player (charges their coins, like the shop). Default: Common.",
	run = function(admin, args)
		local targets = findPlayers(admin, args[1])
		local wanted = string.lower(args[2] or "common")
		local chestId: string? = nil
		for _, chest in Chests.LIST do
			if string.lower(chest.id) == wanted then
				chestId = chest.id
			end
		end
		if #targets == 0 or not chestId then
			return "Usage: chest <player> [common|uncommon|rare|epic|legendary]"
		end
		local opened = 0
		for _, target in targets do
			local result, reason = ChestService.open(target, chestId)
			if result then
				opened += 1
				Remotes.get("ChestOpened"):FireClient(target, result)
			elseif reason then
				reply(admin, `{target.Name}: {reason}`)
			end
		end
		return `Opened {opened} {chestId} chest(s).`
	end,
}

COMMANDS.heal = {
	usage = "heal <player>",
	help = "Restore full health.",
	run = function(admin, args)
		local targets = findPlayers(admin, args[1])
		for _, target in targets do
			local humanoid = target.Character and target.Character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				humanoid.Health = humanoid.MaxHealth
			end
		end
		return `Healed {names(targets)}.`
	end,
}

COMMANDS.kill = {
	usage = "kill <player>",
	help = "Knock a player out.",
	run = function(admin, args)
		local targets = findPlayers(admin, args[1])
		for _, target in targets do
			local humanoid = target.Character and target.Character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.Health = 0
			end
		end
		return `Knocked out {names(targets)}.`
	end,
}

COMMANDS.god = {
	usage = "god <player>",
	help = "Toggle invulnerability (resets on respawn).",
	run = function(admin, args)
		local targets = findPlayers(admin, args[1])
		local states = {}
		for _, target in targets do
			local character = target.Character
			if character then
				local on = character:GetAttribute("God") ~= true
				character:SetAttribute("God", if on then true else nil)
				table.insert(states, `{target.Name}: {if on then "ON" else "off"}`)
			end
		end
		return "God mode — " .. table.concat(states, ", ")
	end,
}

COMMANDS.speed = {
	usage = "speed <player> <walkspeed>",
	help = `Set walk speed until the next status change or respawn (default {Config.WALK_SPEED}).`,
	run = function(admin, args)
		local targets = findPlayers(admin, args[1])
		local speed = tonumber(args[2])
		if #targets == 0 or not speed then
			return "Usage: speed <player> <walkspeed>"
		end
		for _, target in targets do
			local humanoid = target.Character and target.Character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.WalkSpeed = math.clamp(speed, 0, 200)
			end
		end
		return `Set speed {speed} for {names(targets)}.`
	end,
}

COMMANDS.freecast = {
	usage = "freecast <player>",
	help = "Toggle no draw cooldown and no recharges (testing).",
	run = function(admin, args)
		local targets = findPlayers(admin, args[1])
		local states = {}
		for _, target in targets do
			local on = target:GetAttribute("FreeCast") ~= true
			target:SetAttribute("FreeCast", if on then true else nil)
			SpellInputService.setNoDrawCooldown(target, on)
			SpellbookService.setFreeCasting(target, on)
			table.insert(states, `{target.Name}: {if on then "ON" else "off"}`)
		end
		return "Free cast — " .. table.concat(states, ", ")
	end,
}

COMMANDS.tp = {
	usage = "tp <player> <destination player>",
	help = "Teleport players to another player.",
	run = function(admin, args)
		local targets = findPlayers(admin, args[1])
		local destination = findPlayers(admin, args[2])[1]
		local destRoot = destination and rootOf(destination)
		if #targets == 0 or not destRoot then
			return "Usage: tp <player> <destination player>"
		end
		for _, target in targets do
			if target.Character and target ~= destination then
				target.Character:PivotTo(destRoot.CFrame * CFrame.new(math.random(-4, 4), 0, 4))
			end
		end
		return `Teleported {names(targets)} to {destination and destination.Name}.`
	end,
}

COMMANDS.bring = {
	usage = "bring <player>",
	help = "Teleport players to you.",
	run = function(admin, args)
		return COMMANDS.tp.run(admin, { args[1] or "", "me" }, "")
	end,
}

COMMANDS.hub = {
	usage = "hub <player>",
	help = "Send players back to the hub (leaves their match).",
	run = function(admin, args)
		local targets = findPlayers(admin, args[1])
		for _, target in targets do
			MatchService.removeFromMatch(target)
			MatchService.spawnInHub(target)
		end
		return `Sent {names(targets)} to the hub.`
	end,
}

COMMANDS.startmatch = {
	usage = "startmatch <1v1|2v2|3v3|4v4> [players...]",
	help = "Start a match now with the listed players (default: everyone in the hub).",
	run = function(admin, args)
		local mode = args[1] and string.lower(args[1])
		if not mode or not (Config.MODES :: any)[mode] then
			return "Usage: startmatch <1v1|2v2|3v3|4v4> [players...]"
		end
		local chosen: { Player } = {}
		if #args >= 2 then
			for i = 2, #args do
				for _, p in findPlayers(admin, args[i]) do
					if not table.find(chosen, p) then
						table.insert(chosen, p)
					end
				end
			end
		else
			for _, p in Players:GetPlayers() do
				table.insert(chosen, p)
			end
		end
		local free = {}
		for _, p in chosen do
			if not MatchService.isInMatch(p) then
				table.insert(free, p)
			end
		end
		if #free == 0 then
			return "Nobody available (everyone is already in a match)."
		end
		-- Short-handed matches end on the round timer like solo tests.
		local info = (Config.MODES :: any)[mode]
		local needed = info.teams * info.perTeam
		MatchService.startMatch(mode :: any, free, { solo = #free < needed })
		return `Started {mode} with {names(free)}.`
	end,
}

COMMANDS.endmatch = {
	usage = "endmatch <player>",
	help = "End the match a player is in (no winner).",
	run = function(admin, args)
		local target = findPlayers(admin, args[1])[1]
		if not target or not MatchService.isInMatch(target) then
			return "That player isn't in a match."
		end
		MatchService.endMatchOf(target)
		return `Ended {target.Name}'s match.`
	end,
}

COMMANDS.clear = {
	usage = "clear",
	help = "Remove every placed object and summon in the hub.",
	run = function()
		local folder = workspace:FindFirstChild("HubStructures")
		local count = if folder then #folder:GetChildren() else 0
		if folder then
			folder:ClearAllChildren()
		end
		return `Cleared {count} hub object(s).`
	end,
}

COMMANDS.knockback = {
	usage = "knockback <player>",
	help = "Launch a player with a server-authoritative push (testing).",
	run = function(admin, args)
		local targets = findPlayers(admin, args[1])
		for _, target in targets do
			if target.Character then
				DestructibleService.push(target.Character, Vector3.new(0, 80, 60))
			end
		end
		return `Pushed {names(targets)}.`
	end,
}

COMMANDS.status = {
	usage = "status <player> <Root|Slow|Shrink|TimeStop|Slippery> [seconds]",
	help = "Apply a status effect (testing).",
	run = function(admin, args)
		local targets = findPlayers(admin, args[1])
		local kind = args[2]
		local seconds = tonumber(args[3]) or 2
		if #targets == 0 or not kind then
			return "Usage: status <player> <kind> [seconds]"
		end
		for _, target in targets do
			if target.Character then
				StatusService.apply(target.Character, kind, math.clamp(seconds, 0.1, 30))
			end
		end
		return `Applied {kind} to {names(targets)}.`
	end,
}

COMMANDS.announce = {
	usage = "announce <message>",
	help = "Show a message to everyone (filtered).",
	run = function(admin, _args, rest)
		if rest == "" then
			return "Usage: announce <message>"
		end
		-- Broadcast text must go through Roblox's filter.
		local ok, filtered = pcall(function()
			local result = TextService:FilterStringAsync(rest, admin.UserId)
			return result:GetNonChatStringForBroadcastAsync()
		end)
		if not ok then
			return "Couldn't filter that message; try again."
		end
		for _, p in Players:GetPlayers() do
			toastRemote:FireClient(p, `{filtered}`, "round")
		end
		return nil
	end,
}

COMMANDS.kick = {
	usage = "kick <player> [reason]",
	help = "Kick a player from this server.",
	run = function(admin, args)
		local targets = findPlayers(admin, args[1])
		local reason = joinFrom(args, 2)
		local kicked = {}
		for _, target in targets do
			if target ~= admin then
				target:Kick(if reason ~= "" then reason else "Kicked by an admin.")
				table.insert(kicked, target)
			end
		end
		return `Kicked {names(kicked)}.`
	end,
}

COMMANDS.ban = {
	usage = "ban <player> <minutes|perm> [reason]",
	help = "Ban a player from the whole experience (Players:BanAsync).",
	run = function(admin, args)
		local who = string.lower(args[1] or "")
		if who == "all" or who == "others" then
			return "Ban one player at a time."
		end
		local target = findPlayers(admin, args[1])[1]
		if not target or target == admin then
			return "Usage: ban <player> <minutes|perm> [reason]"
		end
		local minutes = tonumber(args[2])
		local duration = if args[2] == "perm"
			then -1
			elseif minutes then math.floor(minutes * 60)
			else nil
		if not duration then
			return "Usage: ban <player> <minutes|perm> [reason]"
		end
		local reason = joinFrom(args, 3)
		local ok, err = pcall(function()
			Players:BanAsync({
				UserIds = { target.UserId },
				ApplyToUniverse = true,
				Duration = duration,
				DisplayReason = if reason ~= "" then reason else "Banned by an admin.",
				PrivateReason = `Banned by {admin.Name} ({admin.UserId})`,
			})
		end)
		return if ok then `Banned {target.Name}.` else `Ban failed: {err}`
	end,
}

COMMANDS.unban = {
	usage = "unban <userId>",
	help = "Lift a ban by UserId.",
	run = function(_admin, args)
		local userId = tonumber(args[1])
		if not userId then
			return "Usage: unban <userId>"
		end
		local ok, err = pcall(function()
			Players:UnbanAsync({ UserIds = { userId }, ApplyToUniverse = true })
		end)
		return if ok then `Unbanned {userId}.` else `Unban failed: {err}`
	end,
}

----------------------------------------------------------------------
-- Dispatch
----------------------------------------------------------------------

-- Returns true when `text` was an admin command from an admin (and is now
-- running). Never yields: the command itself runs in a new thread.
function AdminService.handle(player: Player, text: string): boolean
	if not admins[player] then
		return false
	end
	local body = string.sub(text, #Config.ADMIN_PREFIX + 1)
	local args = string.split(body, " ")
	local name = string.lower(table.remove(args, 1) or "")
	for i = #args, 1, -1 do
		if args[i] == "" then
			table.remove(args, i)
		end
	end
	local command = COMMANDS[name]
	if not command then
		reply(player, `Unknown command "{name}". Try {Config.ADMIN_PREFIX}help`)
		return true
	end
	local rest = string.sub(body, #name + 2)
	task.spawn(function()
		local ok, result = pcall(command.run, player, args, rest)
		if not ok then
			warn(`[Admin] {player.Name} ran {name}: {result}`)
			reply(player, `{name} failed: {result}`)
		elseif result then
			reply(player, result)
		end
		print(`[Admin] {player.Name} ({player.UserId}): {text}`)
	end)
	return true
end

-- Exposed for tests/docs.
AdminService.COMMANDS = COMMANDS

function AdminService.init()
	toastRemote = Remotes.get("Toast")
	logRemote = Remotes.get("AdminLog")
	SpellInputService.setCommandHandler(AdminService.handle)

	-- The admin panel's clicks. Untrusted: only admins, one short string, rate limited.
	Remotes.get("AdminCommand").OnServerEvent:Connect(function(player: Player, text: any)
		if not admins[player] or typeof(text) ~= "string" then
			return
		end
		text = string.gsub(text, "^%s+", "")
		text = string.gsub(text, "%s+$", "")
		if #text == 0 or #text > PANEL_MAX_LENGTH then
			return
		end
		local now = os.clock()
		if now - (lastPanelCommand[player] or 0) < PANEL_COOLDOWN then
			return
		end
		lastPanelCommand[player] = now
		if string.sub(text, 1, #Config.ADMIN_PREFIX) ~= Config.ADMIN_PREFIX then
			text = Config.ADMIN_PREFIX .. text
		end
		AdminService.handle(player, text)
	end)
end

function AdminService.start()
	local function check(player: Player)
		admins[player] = checkAdmin(player)
		if admins[player] then
			-- Tells the client to show the admin panel button. Cosmetic only: every
			-- command is checked against `admins` on the server.
			player:SetAttribute("IsAdmin", true)
			task.delay(4, function()
				if player.Parent then
					reply(
						player,
						"You're an admin. Open the Admin panel with the button or the ` key, or type "
							.. Config.ADMIN_PREFIX
							.. "help."
					)
				end
			end)
		end
	end
	Players.PlayerAdded:Connect(check)
	for _, player in Players:GetPlayers() do
		task.spawn(check, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		admins[player] = nil
		lastPanelCommand[player] = nil
	end)
end

return AdminService
