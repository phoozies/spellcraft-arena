--!strict
-- Match boosts: what each player has picked in this match's round drafts
-- (shared/Match/Boosts) and what that does to them.
--
--   BoostService.pick     adds a stack (draft pick or auto-pick)
--   BoostService.roll     the three cards to offer
--   BoostService.applyToCharacter   after every round spawn: max health, walk
--                         speed, and the Health Potion's watcher
--   BoostService.cooldownFactor     CastService shortens spell cooldowns by it
--   BoostService.reset    match over or player left: back to normal
--
-- Damage is read by DestructibleService from the player attribute
-- "BoostDamage"; speed from the character attribute "BoostSpeed" (StatusService).
-- The picks are mirrored to the player attribute "Boosts" ("Power:2,Focus:1")
-- so the HUD can show them.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Boosts = require(ReplicatedStorage.Shared.Match.Boosts)
local Config = require(ReplicatedStorage.Shared.Config)
local DestructibleService = require(script.Parent.DestructibleService)
local StatusService = require(script.Parent.StatusService)

local BoostService = {}

local picks: { [Player]: { [string]: number } } = {}

local function picksOf(player: Player): { [string]: number }
	local list = picks[player]
	if not list then
		list = {}
		picks[player] = list
	end
	return list
end

local function publish(player: Player)
	local totals = Boosts.totals(picksOf(player))
	player:SetAttribute("BoostDamage", if totals.damage > 1 then totals.damage else nil)
	local parts = {}
	for id, stacks in picksOf(player) do
		table.insert(parts, `{id}:{stacks}`)
	end
	table.sort(parts)
	player:SetAttribute("Boosts", if #parts > 0 then table.concat(parts, ",") else nil)
end

function BoostService.stacks(player: Player, boostId: string): number
	return picksOf(player)[boostId] or 0
end

-- Adds a stack. Returns false for an unknown boost or one already at the cap.
function BoostService.pick(player: Player, boostId: string): boolean
	local boost = Boosts.get(boostId)
	local list = picksOf(player)
	if not boost or (list[boostId] or 0) >= Boosts.MAX_STACKS then
		return false
	end
	list[boostId] = (list[boostId] or 0) + 1
	publish(player)
	return true
end

function BoostService.roll(player: Player, rng: Random): { string }
	return Boosts.roll(picksOf(player), rng)
end

function BoostService.cooldownFactor(player: Player): number
	return Boosts.totals(picksOf(player)).cooldownFactor
end

-- Applies the player's boosts to a freshly spawned round character.
function BoostService.applyToCharacter(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid then
		return
	end
	local totals = Boosts.totals(picksOf(player))
	humanoid.MaxHealth = Config.PLAYER_MAX_HEALTH + totals.maxHealth
	humanoid.Health = humanoid.MaxHealth
	character:SetAttribute("BoostSpeed", if totals.speed > 0 then totals.speed else nil)
	StatusService.refresh(character)

	-- Health Potions: each stack heals once per round when you get low.
	local remaining = table.clone(totals.potions)
	if #remaining > 0 then
		humanoid.HealthChanged:Connect(function(health)
			if health <= 0 then
				return
			end
			for i = #remaining, 1, -1 do
				local potion = remaining[i]
				if health / humanoid.MaxHealth < potion.below then
					table.remove(remaining, i)
					DestructibleService.heal(character, potion.heal, nil)
					break -- one potion per drop; the next waits for another dip
				end
			end
		end)
	end
end

-- Back to normal (match ended, or the player left it).
function BoostService.reset(player: Player)
	picks[player] = nil
	player:SetAttribute("BoostDamage", nil)
	player:SetAttribute("Boosts", nil)
	local character = player.Character
	if character then
		character:SetAttribute("BoostSpeed", nil)
		StatusService.refresh(character)
	end
end

function BoostService.start()
	Players.PlayerRemoving:Connect(function(player)
		picks[player] = nil
	end)
end

return BoostService
