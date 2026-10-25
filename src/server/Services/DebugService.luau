--!strict
-- Studio-only test helpers (roblox-testing skill: gated cheat remotes).
-- Every command is rejected outside Studio, so this is safe to ship.
--
--   coins <n>      grant coins
--   takecoins <n>  remove coins (spends them)
--   likefav <bool> mark the Like & Favourite gift claimed (true) or claimable again (false)
--   wins <n>       add n match wins (leaderboard + podium)
--   crate <id>     open a crate (charges coins), returns the result
--   state          returns {coins, wins, elements, element} per player
--   solo <mode>    start a match alone (rounds end on the timer)
--   unlockall      own every element
--   element <id>   equip an element (grants it first)
--   cast {spell, target}  give yourself the spell and cast it at a Vector3
--   knockback      server-push your own character (tests authoritative knockback)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local Elements = require(ReplicatedStorage.Shared.Spells.Elements)
local SpellDefinitions = require(ReplicatedStorage.Shared.Spells.SpellDefinitions)
local CastService = require(script.Parent.CastService)
local CrateService = require(script.Parent.CrateService)
local ElementService = require(script.Parent.ElementService)
local DestructibleService = require(script.Parent.DestructibleService)
local MatchService = require(script.Parent.MatchService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local EconomyService = require(script.Parent.EconomyService)

local DebugService = {}

local function enabled(): boolean
	return RunService:IsStudio() and Config.DEBUG_COMMANDS_IN_STUDIO
end

function DebugService.run(player: Player, command: string, arg: any): any
	if not enabled() then
		return nil
	end
	if command == "coins" and typeof(arg) == "number" then
		EconomyService.addCoins(player, arg, "debug")
	elseif command == "takecoins" and typeof(arg) == "number" then
		return EconomyService.spend(player, math.max(0, math.floor(arg)))
	elseif command == "likefav" and typeof(arg) == "boolean" then
		EconomyService.setLikeRewardClaimed(player, arg)
	elseif command == "wins" and typeof(arg) == "number" then
		for _ = 1, math.clamp(math.floor(arg), 0, 1000) do
			EconomyService.recordWin(player)
		end
	elseif command == "crate" and typeof(arg) == "string" then
		local result, reason = CrateService.open(player, arg)
		if result then
			Remotes.get("CrateOpened"):FireClient(player, result)
		end
		return result or reason
	elseif command == "state" then
		local profile = PlayerDataService.get(player)
		return profile
			and {
				coins = profile.coins,
				wins = profile.stats.wins,
				elements = profile.elements,
				element = profile.element,
				spells = profile.spells,
				loadout = profile.loadout,
				tutorialDone = profile.tutorial.done,
			}
	elseif command == "solo" and typeof(arg) == "string" and (Config.MODES :: any)[arg] then
		MatchService.startMatch(arg :: any, { player }, { solo = true })
	elseif command == "cast" and typeof(arg) == "table" then
		local spell, target = (arg :: any).spell, (arg :: any).target
		if typeof(spell) == "string" and typeof(target) == "Vector3" then
			return CastService.castFor(player, spell, target)
		end
	elseif command == "knockback" and player.Character then
		DestructibleService.push(player.Character, Vector3.new(0, 80, 60))
	elseif command == "unlockall" then
		local profile = PlayerDataService.get(player)
		if profile then
			for _, id in Elements.ids() do
				ElementService.grant(player, id)
			end
			for _, def in SpellDefinitions.crateSpells() do
				ElementService.grantSpell(player, def.id)
			end
			EconomyService.sendSummary(player)
		end
	elseif command == "tutorial" and typeof(arg) == "boolean" then
		-- Studio QA: true marks the tutorial done, false makes it show again.
		local profile = PlayerDataService.get(player)
		if profile then
			profile.tutorial.done = arg
			EconomyService.sendSummary(player)
		end
	elseif command == "element" and typeof(arg) == "string" and Elements.get(arg) then
		ElementService.grant(player, arg)
		ElementService.equip(player, arg)
		EconomyService.sendSummary(player)
	end
	return nil
end

function DebugService.start()
	if not enabled() then
		return
	end
	Remotes.get("DebugCommand").OnServerEvent:Connect(function(player, command, arg)
		if typeof(command) == "string" then
			DebugService.run(player, command, arg)
		end
	end)

	-- Handy from the Studio command bar / MCP execute_luau:
	--   _G.SpellcraftDebug("solo", "1v1")
	-- selene: allow(global_usage)
	local globals: any = _G
	local function runAll(command: string, arg: any)
		local results = {}
		for _, player in Players:GetPlayers() do
			results[player.Name] = DebugService.run(player, command, arg)
		end
		return results
	end
	globals.SpellcraftDebug = runAll

	-- The command bar and the MCP don't share _G or module caches with the
	-- running game, but they do share instances: invoke this instead, e.g.
	--   game.ServerStorage.SpellcraftDebug:Invoke("crate", "Common")
	local bindable = Instance.new("BindableFunction")
	bindable.Name = "SpellcraftDebug"
	bindable.OnInvoke = runAll
	bindable.Parent = game:GetService("ServerStorage")
end

return DebugService
