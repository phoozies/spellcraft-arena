--!strict
-- Timed status effects and buffs on characters. Effects are stored as
-- expiry times; movement stats are recomputed from scratch whenever an
-- effect starts or ends, so overlapping effects never "stick".
--
-- Client-visible state is mirrored as character attributes (Status_<Kind>)
-- so the client can show visuals and handle physics-only effects
-- (Slippery lowers friction locally).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)

local BASE_WALKSPEED = 18
local BASE_JUMP = 50

local StatusService = {}

type Effects = { [string]: number } -- kind -> expiresAt (os.clock)

local effects: { [Model]: Effects } = {}

local function humanoidOf(character: Model): Humanoid?
	return character:FindFirstChildOfClass("Humanoid")
end

local function rootOf(character: Model): BasePart?
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function active(character: Model, kind: string): boolean
	local list = effects[character]
	return list ~= nil and list[kind] ~= nil and list[kind] > os.clock()
end

local function recompute(character: Model)
	local humanoid = humanoidOf(character)
	local root = rootOf(character)
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	local speed = BASE_WALKSPEED
	local jump = BASE_JUMP
	if active(character, "Slow") then
		speed *= 0.5
	end
	if active(character, "Shrink") then
		speed *= 0.8
	end
	if active(character, "Root") or active(character, "TimeStop") then
		speed = 0
		jump = 0
	end
	humanoid.UseJumpPower = true
	humanoid.WalkSpeed = speed
	humanoid.JumpPower = jump
	if root then
		root.Anchored = active(character, "TimeStop") or character:GetAttribute("Frozen") == true
	end

	-- Size changes: Shrink wins over Giant.
	local targetScale = 1
	if active(character, "Shrink") then
		targetScale = 0.5
	elseif active(character, "Giant") then
		targetScale = 1.6
	end
	if math.abs(character:GetScale() - targetScale) > 0.01 then
		pcall(function()
			character:ScaleTo(targetScale)
		end)
	end

	for _, kind in { "Root", "Slow", "Shrink", "TimeStop", "Slippery", "Giant", "Reflect", "Revive", "CooldownCut" } do
		character:SetAttribute("Status_" .. kind, if active(character, kind) then true else nil)
	end
end

-- Applies (or extends) an effect. `kind` is a StatusKind or a buff name
-- ("Giant", "Reflect", "Revive", "CooldownCut").
function StatusService.apply(character: Model, kind: Types.StatusKind | string, duration: number)
	local list = effects[character]
	if not list then
		list = {}
		effects[character] = list
		character.Destroying:Connect(function()
			effects[character] = nil
		end)
	end
	local expires = os.clock() + duration
	list[kind] = math.max(list[kind] or 0, expires)
	recompute(character)
	task.delay(duration + 0.05, function()
		if character.Parent then
			recompute(character)
		end
	end)
end

function StatusService.has(character: Model, kind: string): boolean
	return active(character, kind)
end

function StatusService.clear(character: Model, kind: string)
	local list = effects[character]
	if list then
		list[kind] = nil
		recompute(character)
	end
end

function StatusService.clearAll(character: Model)
	effects[character] = nil
	character:SetAttribute("Frozen", nil)
	recompute(character)
end

-- Freezes a character in place (used during round countdowns).
function StatusService.setFrozen(character: Model, frozen: boolean)
	character:SetAttribute("Frozen", if frozen then true else nil)
	recompute(character)
end

return StatusService
