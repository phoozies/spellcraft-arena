--!strict
-- Control archetype: crowd control.
--   * With `speed`: a projectile that applies `status` on hit (Water Lock,
--     Magnet via negative knockback, Shrink).
--   * Without `speed`: an instant area at the target (`range` 0 = centered
--     on the caster) that applies `status` to every enemy in `radius`
--     (Vine Snare, Time Stop).

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local DestructibleService = require(script.Parent.Parent.DestructibleService)
local StatusService = require(script.Parent.Parent.StatusService)
local Projectile = require(script.Parent.Projectile)

local Control = {}

local function bubble(character: Model, color: Color3, duration: number)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local orb = Instance.new("Part")
	orb.Shape = Enum.PartType.Ball
	orb.Size = Vector3.new(7, 7, 7)
	orb.Color = color
	orb.Material = Enum.Material.Glass
	orb.Transparency = 0.55
	orb.CanCollide = false
	orb.CanQuery = false
	orb.Massless = true
	orb.CFrame = root.CFrame
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = orb
	weld.Part1 = root
	weld.Parent = orb
	orb.Parent = character
	Debris:AddItem(orb, duration)
end

function Control.cast(ctx: any): boolean?
	local stats = ctx.def.stats
	if stats.speed then
		local origin, direction = Projectile.originFor(ctx.root, ctx.target)
		Projectile.launch({
			caster = ctx.player,
			origin = origin,
			direction = direction,
			stats = stats,
			visual = ctx.def.visual,
			spellName = ctx.def.name,
			ignore = { ctx.character },
		})
		return true
	end

	local center = if (stats.range or 0) <= 0 then ctx.root.Position else ctx.target
	local radius = stats.radius or 10

	-- Expanding ring so everyone can see the area.
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.4, 1, 1)
	ring.CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.pi / 2)
	ring.Color = ctx.def.visual.color
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.4
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.Parent = workspace
	TweenService:Create(ring, TweenInfo.new(0.35), { Size = Vector3.new(0.4, radius * 2, radius * 2), Transparency = 0.8 })
		:Play()
	Debris:AddItem(ring, 0.6)

	for _, hit in ctx.enemiesNear(center, radius) do
		if hit.character then
			if stats.damage then
				DestructibleService.damage(hit.character, stats.damage, ctx.player, ctx.def.name)
			end
			if stats.status then
				StatusService.apply(hit.character, stats.status, stats.statusDuration or 1)
				bubble(hit.character, ctx.def.visual.color, stats.statusDuration or 1)
			end
		end
	end
	return true
end

return Control
