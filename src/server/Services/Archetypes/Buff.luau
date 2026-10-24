--!strict
-- Buff archetype: effects on the caster.
-- Reads stats: heal, shield (absorb HP), duration, reflect, scale (Giant),
-- revive (Phoenix), cooldownCut (Wizard Hat).

local Debris = game:GetService("Debris")

local DestructibleService = require(script.Parent.Parent.DestructibleService)
local StatusService = require(script.Parent.Parent.StatusService)

local Buff = {}

local function aura(ctx: any, duration: number)
	local visual = ctx.def.visual
	local orb = Instance.new("Part")
	orb.Shape = Enum.PartType.Ball
	orb.Size = Vector3.new(7, 7, 7)
	orb.Color = visual.color
	orb.Material = if visual.material == Enum.Material.Neon
		then Enum.Material.ForceField
		else visual.material
	orb.Transparency = math.max(visual.transparency or 0.5, 0.5)
	orb.CanCollide = false
	orb.CanQuery = false
	orb.CanTouch = false
	orb.Massless = true
	orb.CFrame = ctx.root.CFrame
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = orb
	weld.Part1 = ctx.root
	weld.Parent = orb
	orb.Parent = ctx.character
	Debris:AddItem(orb, duration)
end

function Buff.cast(ctx: any): boolean?
	local stats = ctx.def.stats
	local character = ctx.character
	local duration = stats.duration or 0.6

	if stats.heal then
		DestructibleService.heal(character, stats.heal)
	end
	if stats.shield then
		character:SetAttribute("Shield", (character:GetAttribute("Shield") or 0) + stats.shield)
		-- Only the latest cast's timer may clear the shield (recasts extend it).
		local token = (character:GetAttribute("ShieldToken") or 0) + 1
		character:SetAttribute("ShieldToken", token)
		task.delay(duration, function()
			if character.Parent and character:GetAttribute("ShieldToken") == token then
				character:SetAttribute("Shield", nil)
			end
		end)
	end
	if stats.reflect then
		StatusService.apply(character, "Reflect", duration)
	end
	if stats.scale then
		StatusService.apply(character, "Giant", duration)
	end
	if stats.revive then
		StatusService.apply(character, "Revive", duration)
	end
	if stats.cooldownCut then
		StatusService.apply(character, "CooldownCut", duration)
	end
	aura(ctx, duration)
	return true
end

return Buff
