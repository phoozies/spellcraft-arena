--!strict
-- Crate opening: the only way to unlock non-starter spells.
--
--   client OpenCrate(crateId) ──► validate (known crate, not mid-spin, in the
--   hub, enough coins) ──► EconomyService.spend ──► Crates.roll ──► own it?
--   refund : add to profile.ownedSpells ──► CrateOpened(result) to the opener
--
-- The server decides the result before the client's reel starts spinning;
-- the client only animates toward it (CrateController). Opening is refused
-- during a match so nobody gains spells mid-fight.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Crates = require(ReplicatedStorage.Shared.Economy.Crates)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local SpellDefinitions = require(ReplicatedStorage.Shared.Spells.SpellDefinitions)
local Types = require(ReplicatedStorage.Shared.Types)
local EconomyService = require(script.Parent.EconomyService)
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
	local spellId, rarity = Crates.roll(crate, rng)
	if not spellId or not rarity then
		return nil, "That crate is empty right now."
	end
	if not EconomyService.spend(player, crate.price) then
		return nil, "Not enough coins."
	end
	busyUntil[player] = now + Crates.SPIN_TIME

	local duplicate = table.find(profile.ownedSpells, spellId) ~= nil
	local refund = 0
	if duplicate then
		refund = Crates.refundFor(crate)
		-- Credited now (safe if they leave mid-spin), shown at the reveal.
		EconomyService.addCoins(player, refund, "crateDuplicate", true)
	else
		table.insert(profile.ownedSpells, spellId)
	end
	local result: Types.CrateResult = {
		crate = crate.id,
		spellId = spellId,
		rarity = rarity,
		duplicate = duplicate,
		refund = refund,
		coins = profile.coins,
	}
	-- Reveal (toast + refund) only once the reel has stopped, so the
	-- balance and spellbook don't spoil the spin.
	task.delay(Crates.SPIN_TIME, function()
		if not player.Parent then
			return
		end
		EconomyService.sendSummary(player)
		local def = SpellDefinitions.get(spellId)
		local name = if def then def.name else spellId
		toastRemote:FireClient(
			player,
			if duplicate
				then `Duplicate {name}! +{refund} coins back.`
				else `Unlocked {name}! Type "{if def then def.aliases[1] else name}" to cast it.`,
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
