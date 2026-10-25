--!strict
-- Crate opening: the gacha that wins crate spells.
--
--   client OpenCrate(crateId) ──► validate (known crate, not mid-spin, in the
--   hub, an element picked, enough coins, a spell left to win) ──►
--   EconomyService.spend ──► Crates.roll (rarity, then spell) ──►
--   ElementService.grantSpell ──► CrateOpened(result) to the opener
--
-- The server decides the result before the client's reel starts spinning;
-- the client only animates toward it (CrateController). A spell you already
-- own pays back coins instead (Spells/Rarity `refund`). The reveal (toast,
-- refund, new spell in the spellbook) waits until the reel has stopped so the
-- summary doesn't spoil the spin. Opening is refused during a match so nobody
-- changes spells mid-fight.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Crates = require(ReplicatedStorage.Shared.Economy.Crates)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local SpellDefinitions = require(ReplicatedStorage.Shared.Spells.SpellDefinitions)
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
	local roll = Crates.roll(profile.spells, rng)
	if not roll then
		return nil, "You already own every spell!"
	end
	if not EconomyService.spend(player, crate.price) then
		return nil, "Not enough coins."
	end
	busyUntil[player] = now + Crates.SPIN_TIME
	local _, equipped = ElementService.grantSpell(player, roll.spell)
	local result: Types.CrateResult = {
		crate = crate.id,
		spell = roll.spell,
		rarity = roll.rarity,
		duplicate = roll.duplicate,
		refund = roll.refund,
		equipped = equipped,
		coins = profile.coins,
	}
	task.delay(Crates.SPIN_TIME, function()
		if not player.Parent then
			return
		end
		if roll.duplicate then
			EconomyService.addCoins(player, roll.refund, "crateRefund")
		else
			EconomyService.sendSummary(player)
		end
		local def = SpellDefinitions.get(roll.spell)
		local name = if def then def.name else roll.spell
		local message = if roll.duplicate
			then `Duplicate {name}! +{roll.refund} coins back.`
			elseif equipped then `New {roll.rarity} spell: {name}, equipped in your loadout!`
			else `New {roll.rarity} spell: {name}! Equip it in the Spellbook.`
		toastRemote:FireClient(player, message, "reward")
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
