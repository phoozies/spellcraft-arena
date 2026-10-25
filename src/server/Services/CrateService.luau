--!strict
-- Crate opening: the only way to unlock elements after the free first pick.
--
--   client OpenCrate(crateId) ──► validate (known crate, not mid-spin, in the
--   hub, enough coins, an element left to win) ──► EconomyService.spend ──►
--   Crates.roll ──► ElementService.grant ──► CrateOpened(result) to the opener
--
-- The server decides the result before the client's reel starts spinning;
-- the client only animates toward it (CrateController). Opening is refused
-- during a match so nobody changes elements mid-fight.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Crates = require(ReplicatedStorage.Shared.Economy.Crates)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local EconomyService = require(script.Parent.EconomyService)
local ElementService = require(script.Parent.ElementService)
local MatchService = require(script.Parent.MatchService)
local PlayerDataService = require(script.Parent.PlayerDataService)

local CrateService = {}

local rng = Random.new()
local busyUntil: { [Player]: number } = {}
local toastRemote: RemoteEvent
local openedRemote: RemoteEvent

-- Opens a crate for a player. Returns the result, or (nil, reason).
-- Exposed for admin/debug and tests; the remote handler calls it too.
function CrateService.open(player: Player, crateId: string): (Types.CrateResult?, string?)
	local crate = Crates.get(crateId)
	if not crate then
		return nil, "That crate doesn't exist."
	end
	local profile = PlayerDataService.get(player)
	if not profile then
		return nil, "Your spellbook is still loading."
	end
	if #profile.elements == 0 then
		return nil, "Pick your first element in the Spellbook before opening crates!"
	end
	if MatchService.isInMatch(player) then
		return nil, "Open crates in the hub, after your match."
	end
	local now = os.clock()
	if (busyUntil[player] or 0) > now then
		return nil, "Your crate is still spinning!"
	end
	if profile.coins < crate.price then
		return nil, `You need {crate.price - profile.coins} more coins. Win matches to earn coins!`
	end
	local element = Crates.roll(profile.elements, rng)
	if not element then
		return nil, "You already own every element!"
	end
	if not EconomyService.spend(player, crate.price) then
		return nil, "Not enough coins."
	end
	busyUntil[player] = now + Crates.SPIN_TIME
	ElementService.grant(player, element)
	local result: Types.CrateResult = {
		crate = crate.id,
		element = element :: Types.ElementId,
		coins = profile.coins,
	}
	-- Reveal (toast + new element in the spellbook) only once the reel has
	-- stopped, so the summary doesn't spoil the spin.
	task.delay(Crates.SPIN_TIME, function()
		if not player.Parent then
			return
		end
		EconomyService.sendSummary(player)
		toastRemote:FireClient(
			player,
			`Unlocked {element}! Equip it in the Spellbook to use its spells.`,
			"reward"
		)
	end)
	return result, nil
end

function CrateService.init()
	toastRemote = Remotes.get("Toast")
	openedRemote = Remotes.get("CrateOpened")
end

function CrateService.start()
	Remotes.get("OpenCrate").OnServerEvent:Connect(function(player, crateId)
		if typeof(crateId) ~= "string" or #crateId > 20 then
			return
		end
		local result, reason = CrateService.open(player, crateId)
		if result then
			openedRemote:FireClient(player, result)
		elseif reason then
			toastRemote:FireClient(player, reason, "fizzle")
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		busyUntil[player] = nil
	end)
end

return CrateService
