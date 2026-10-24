--!strict
-- Studio-only test helpers (roblox-testing skill: gated cheat remotes).
-- Every command is rejected outside Studio, so this is safe to ship.
--
--   xp <n>         grant XP
--   solo <mode>    start a match alone (rounds end on the timer)
--   unlockall      own every spell
--   knockback      server-push your own character (tests authoritative knockback)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local SpellDefinitions = require(ReplicatedStorage.Shared.Spells.SpellDefinitions)
local DestructibleService = require(script.Parent.DestructibleService)
local MatchService = require(script.Parent.MatchService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local ProgressionService = require(script.Parent.ProgressionService)

local DebugService = {}

local function enabled(): boolean
	return RunService:IsStudio() and Config.DEBUG_COMMANDS_IN_STUDIO
end

function DebugService.run(player: Player, command: string, arg: any)
	if not enabled() then
		return
	end
	if command == "xp" and typeof(arg) == "number" then
		ProgressionService.addXp(player, arg, "debug")
	elseif command == "solo" and typeof(arg) == "string" and (Config.MODES :: any)[arg] then
		MatchService.startMatch(arg :: any, { player }, { solo = true })
	elseif command == "knockback" and player.Character then
		DestructibleService.push(player.Character, Vector3.new(0, 80, 60))
	elseif command == "unlockall" then
		local profile = PlayerDataService.get(player)
		if profile then
			profile.ownedSpells = {}
			for _, def in SpellDefinitions.list do
				table.insert(profile.ownedSpells, def.id)
			end
			ProgressionService.sendSummary(player)
		end
	end
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
	--   _G.WordcraftDebug("solo", "1v1")
	-- selene: allow(global_usage)
	local globals: any = _G
	globals.WordcraftDebug = function(command: string, arg: any)
		for _, player in Players:GetPlayers() do
			DebugService.run(player, command, arg)
		end
	end
end

return DebugService
