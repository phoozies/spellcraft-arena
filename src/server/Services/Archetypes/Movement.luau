--!strict
-- Movement archetype: dash (dashSpeed), teleport (teleport + range, must
-- land inside the allowed region), balloon lift (lift).

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Placement = require(ReplicatedStorage.Shared.Spells.Placement)
local DestructibleService = require(script.Parent.Parent.DestructibleService)

local Movement = {}

local function trail(ctx: any)
	DestructibleService.poof(ctx.root.Position, ctx.def.visual.color)
end

function Movement.cast(ctx: any): boolean?
	local stats = ctx.def.stats
	local root: BasePart = ctx.root

	if stats.dashSpeed then
		local toward = ctx.target - root.Position
		local flat = Vector3.new(toward.X, 0, toward.Z)
		local dir = if flat.Magnitude > 1 then flat.Unit else root.CFrame.LookVector
		DestructibleService.boost(ctx.character, dir * stats.dashSpeed + Vector3.new(0, 12, 0))
		trail(ctx)
		return true
	end

	if stats.teleport then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { ctx.character }
		local down =
			workspace:Raycast(ctx.target + Vector3.new(0, 5, 0), Vector3.new(0, -50, 0), params)
		if not down or not Placement.inRegions(down.Position, ctx.buildRegions) then
			return false
		end
		trail(ctx)
		ctx.character:PivotTo(
			CFrame.new(down.Position + Vector3.new(0, 3.5, 0)) * root.CFrame.Rotation
		)
		trail(ctx)
		return true
	end

	if stats.lift then
		local balloon = Instance.new("Part")
		balloon.Shape = Enum.PartType.Ball
		balloon.Size = ctx.def.visual.size
		balloon.Color = ctx.def.visual.color
		balloon.Material = ctx.def.visual.material
		balloon.CanCollide = false
		balloon.CanQuery = false
		balloon.Massless = true
		balloon.CFrame = root.CFrame * CFrame.new(0, 5, 0)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = balloon
		weld.Part1 = root
		weld.Parent = balloon
		balloon.Parent = ctx.character
		Debris:AddItem(balloon, 2)
		DestructibleService.boost(
			ctx.character,
			Vector3.new(0, stats.lift, 0) + root.CFrame.LookVector * 10
		)
		return true
	end
	return false
end

return Movement
