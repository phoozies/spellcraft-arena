--!strict
-- Chest opening: the gacha that wins chest spells (five chests, one per
-- rarity, in shared/Economy/Chests).
--
--   client OpenChest(chestId) ──► validate (known chest, not mid-spin, not in
--   a match, an element picked, enough coins, a spell left to win from that
--   chest) ──► EconomyService.spend ──► Chests.roll (rarity, then spell) ──►
--   ElementService.grantSpell ──► ChestOpened(result) to the opener
--
-- The server decides the result before the client's reel starts spinning;
-- the client only animates toward it (ChestController). A spell you already
-- own pays back coins instead (Chests.refund). The reveal (toast, refund, new
-- spell in the spellbook) waits until the reel has stopped so the summary
-- doesn't spoil the spin. Opening is refused during a match so nobody changes
-- spells mid-fight.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Chests = require(ReplicatedStorage.Shared.Economy.Chests)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local SpellDefinitions = require(ReplicatedStorage.Shared.Spells.SpellDefinitions)
local Types = require(ReplicatedStorage.Shared.Types)
local EconomyService = require(script.Parent.EconomyService)
local ElementService = require(script.Parent.ElementService)
local MatchService = require(script.Parent.MatchService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local TelemetryService = require(script.Parent.TelemetryService)

local ChestService = {}

local rng = Random.new()
local busyUntil: { [Player]: number } = {}
local toastRemote: RemoteEvent
local openedRemote: RemoteEvent

-- Opens a chest for a player. Returns the result, or (nil, reason).
-- Exposed for admin/debug and tests; the remote handler calls it too.
function ChestService.open(player: Player, chestId: string): (Types.ChestResult?, string?)
	local chest = Chests.get(chestId)
	if not chest then
		return nil, "That chest doesn't exist."
	end
	local profile = PlayerDataService.get(player)
	if not profile then
		return nil, "Your spellbook is still loading."
	end
	if #profile.elements == 0 then
		return nil, "Pick your first element in the Spellbook before opening chests!"
	end
	if MatchService.isInMatch(player) then
		return nil, "Open chests in the hub, after your match."
	end
	local now = os.clock()
	if (busyUntil[player] or 0) > now then
		return nil, "Your chest is still opening!"
	end
	if profile.coins < chest.price then
		return nil,
			`You need {chest.price - profile.coins} more coins for the {chest.name}. Win matches to earn coins!`
	end
	local roll = Chests.roll(chest.id, profile.spells, rng, profile.pity)
	if not roll then
		return nil, `You already own every spell the {chest.name} can give!`
	end
	if not EconomyService.spend(player, chest.price, `chest{chest.id}`) then
		return nil, "Not enough coins."
	end
	TelemetryService.onboarding(player, "FirstChestOpen")
	profile.pity = Chests.nextPity(profile.pity, roll.rarity)
	busyUntil[player] = now + Chests.SPIN_TIME
	local _, equipped = ElementService.grantSpell(player, roll.spell)
	local result: Types.ChestResult = {
		chest = chest.id,
		spell = roll.spell,
		rarity = roll.rarity,
		duplicate = roll.duplicate,
		refund = roll.refund,
		equipped = equipped,
		pity = profile.pity,
		coins = profile.coins,
	}
	task.delay(Chests.SPIN_TIME, function()
		if not player.Parent then
			return
		end
		if roll.duplicate then
			EconomyService.addCoins(player, roll.refund, "chestRefund")
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

-- Admin reset: the next guaranteed hit is a full PITY.SPINS chests away again.
function ChestService.resetPity(player: Player)
	local profile = PlayerDataService.get(player)
	if profile then
		profile.pity = 0
		EconomyService.sendSummary(player)
	end
end

function ChestService.init()
	toastRemote = Remotes.get("Toast")
	openedRemote = Remotes.get("ChestOpened")
end

function ChestService.start()
	Remotes.get("OpenChest").OnServerEvent:Connect(function(player, chestId)
		if typeof(chestId) ~= "string" or #chestId > 20 then
			return
		end
		local result, reason = ChestService.open(player, chestId)
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

return ChestService
