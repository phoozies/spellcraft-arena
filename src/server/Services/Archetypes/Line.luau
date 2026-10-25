--!strict
-- Line archetype: a row of bursts that erupts one after another in the
-- direction the caster aims (Earth Pillar).
--
-- Reads stats: damage, radius, count (bursts), spacing (studs between them),
-- step (seconds between one burst and the next), delay (seconds before the
-- first), knockback. A player is hurt by at most one pillar of a line.
-- Clients draw the pillars rising (Fx "rise").

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local DestructibleService = require(script.Parent.Parent.DestructibleService)

local Line = {}

local fxRemote = Remotes.get("Fx")

local function groundAt(point: Vector3, ignore: { Instance }): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(point + Vector3.new(0, 8, 0), Vector3.new(0, -60, 0), params)
	return if hit then hit.Position else point
end

function Line.cast(ctx: any): boolean?
	local stats = ctx.def.stats
	local visual = ctx.def.visual
	local radius = stats.radius or 4
	local count = stats.count or 5
	local spacing = stats.spacing or radius * 1.6
	local step = stats.step or 0.1
	local delay = stats.delay or 0.3

	local toward = ctx.target - ctx.root.Position
	local flat = Vector3.new(toward.X, 0, toward.Z)
	local direction = if flat.Magnitude > 1 then flat.Unit else ctx.root.CFrame.LookVector
	local start = ctx.root.Position + direction * (radius + 2)

	local hitOnce: { [Model]: boolean } = {}
	for i = 1, count do
		local center = groundAt(start + direction * spacing * (i - 1), { ctx.character })
		local wait = delay + (i - 1) * step
		fxRemote:FireAllClients(
			"rise",
			center,
			radius,
			wait,
			visual.color,
			"pillar",
			visual.size.Y,
			visual.model
		)
		task.delay(wait, function()
			DestructibleService.shockwave(center, radius, visual.color)
			for _, hit in ctx.enemiesNear(center, radius) do
				if hit.character then
					if not hitOnce[hit.character] then
						hitOnce[hit.character] = true
						DestructibleService.damage(
							hit.character,
							stats.damage or 0,
							ctx.player,
							ctx.def.name
						)
						if stats.knockback then
							local away = hit.position - center
							local out = Vector3.new(away.X, 0, away.Z)
							local push = if out.Magnitude > 0.1 then out.Unit else direction
							DestructibleService.push(
								hit.character,
								push * stats.knockback + Vector3.new(0, stats.knockback * 0.7, 0)
							)
						end
					end
				else
					DestructibleService.damage(
						hit.instance,
						stats.damage or 0,
						ctx.player,
						ctx.def.name
					)
				end
			end
		end)
	end
	return true
end

return Line
