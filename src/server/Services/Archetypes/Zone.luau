--!strict
-- Zone archetype: an area on the ground at the target point.
--   * duration > 0: lingers and ticks 4x/second — applies `status`, pulls
--     toward the center (`pull`), deals damage per second (`damage`), or
--     heals allies (`heal` + teamHeal).
--   * delay (no duration): a telegraphed burst after `delay` seconds —
--     damage + knockback, optionally smashing structures (Meteor, Earthquake).

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local DestructibleService = require(script.Parent.Parent.DestructibleService)
local StatusService = require(script.Parent.Parent.StatusService)

local Zone = {}

local TICK = 0.25

local function groundAt(point: Vector3, ignore: { Instance }): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(point + Vector3.new(0, 8, 0), Vector3.new(0, -60, 0), params)
	return if hit then hit.Position else point
end

local function disc(
	center: Vector3,
	radius: number,
	color: Color3,
	material: Enum.Material,
	transparency: number
): Part
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(0.3, radius * 2, radius * 2)
	part.CFrame = CFrame.new(center + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	part.Color = color
	part.Material = material
	part.Transparency = transparency
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Parent = workspace
	return part
end

local function burst(ctx: any, center: Vector3)
	local stats = ctx.def.stats
	local radius = stats.radius or 10
	local flash = disc(center, radius, ctx.def.visual.color, Enum.Material.Neon, 0.2)
	TweenService:Create(flash, TweenInfo.new(0.5), { Transparency = 1 }):Play()
	Debris:AddItem(flash, 0.6)
	DestructibleService.poof(center, ctx.def.visual.color)

	for _, hit in ctx.enemiesNear(center, radius) do
		if hit.character then
			DestructibleService.damage(hit.character, stats.damage or 0, ctx.player, ctx.def.name)
			if stats.knockback then
				local away = hit.position - center
				local flat = Vector3.new(away.X, 0, away.Z)
				local dir = if flat.Magnitude > 0.1 then flat.Unit else Vector3.zero
				DestructibleService.push(
					hit.character,
					dir * stats.knockback + Vector3.new(0, stats.knockback * 0.6, 0)
				)
			end
		elseif stats.destroysStructures then
			DestructibleService.damage(hit.instance, 10000, ctx.player, ctx.def.name)
		else
			DestructibleService.damage(hit.instance, stats.damage or 0, ctx.player, ctx.def.name)
		end
	end
end

function Zone.cast(ctx: any): boolean?
	local stats = ctx.def.stats
	local visual = ctx.def.visual
	local radius = stats.radius or 10
	local origin = if (stats.range or 0) <= 0 then ctx.root.Position else ctx.target
	local center = groundAt(origin, { ctx.character })

	if stats.delay and not stats.duration then
		-- Telegraph: a pulsing warning circle, plus a falling rock for Meteor.
		local warning = disc(center, radius, Color3.fromRGB(255, 82, 82), Enum.Material.Neon, 0.6)
		Debris:AddItem(warning, stats.delay)
		if visual.shape == "Ball" then
			local rock = Instance.new("Part")
			rock.Shape = Enum.PartType.Ball
			rock.Size = visual.size
			rock.Color = visual.color
			rock.Material = visual.material
			rock.Anchored = true
			rock.CanCollide = false
			rock.CanQuery = false
			rock.CFrame = CFrame.new(center + Vector3.new(0, 80, 0))
			rock.Parent = workspace
			TweenService:Create(
				rock,
				TweenInfo.new(stats.delay, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{
					CFrame = CFrame.new(center),
				}
			):Play()
			Debris:AddItem(rock, stats.delay)
		end
		task.delay(stats.delay, burst, ctx, center)
		return true
	end

	local duration = stats.duration or 3
	local area = disc(center, radius, visual.color, visual.material, visual.transparency or 0.3)
	area.Name = ctx.def.name
	if
		visual.shape == "Ball"
		or (visual.shape == "Cylinder" and not (visual.size.X < visual.size.Y))
	then
		-- Vertical swirl (Tornado, Black Hole) on top of the ground disc.
		local swirl = Instance.new("Part")
		swirl.Shape = if visual.shape == "Ball" then Enum.PartType.Ball else Enum.PartType.Cylinder
		swirl.Size = visual.size
		swirl.Color = visual.color
		swirl.Material = visual.material
		swirl.Transparency = visual.transparency or 0
		swirl.Anchored = true
		swirl.CanCollide = false
		swirl.CanQuery = false
		swirl.CFrame = CFrame.new(center + Vector3.new(0, visual.size.X / 2 + 1, 0))
			* CFrame.Angles(0, 0, math.pi / 2)
		-- Clients spin anything tagged SpinFx locally (no per-frame replication).
		swirl:AddTag("SpinFx")
		swirl.Parent = area
	end
	Debris:AddItem(area, duration)

	task.spawn(function()
		local elapsed = 0
		while elapsed < duration do
			for _, hit in ctx.enemiesNear(center, radius) do
				if hit.character then
					if stats.status then
						StatusService.apply(
							hit.character,
							stats.status,
							stats.statusDuration or TICK * 2
						)
					end
					if stats.damage then
						DestructibleService.damage(
							hit.character,
							stats.damage * TICK,
							ctx.player,
							ctx.def.name
						)
					end
					if stats.pull then
						local toCenter = center - hit.position
						local flat = Vector3.new(toCenter.X, 0, toCenter.Z)
						if flat.Magnitude > 2 then
							DestructibleService.push(
								hit.character,
								flat.Unit * stats.pull + Vector3.new(0, 6, 0)
							)
						end
					end
				end
			end
			if stats.heal then
				for _, ally in ctx.alliesNear(center, radius) do
					DestructibleService.heal(ally, stats.heal * TICK)
				end
			end
			task.wait(TICK)
			elapsed += TICK
		end
	end)
	return true
end

return Zone
