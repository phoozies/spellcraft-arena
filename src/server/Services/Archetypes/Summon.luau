--!strict
-- Summon archetype: a destructible creature that fights for its owner.
-- Bodies are anchored and moved by CFrame on the server (cheap, exploit-safe).
--   decoy  — stands still; turrets and summons target it first.
--   melee  — walks to the nearest enemy and punches (damage every second).
--   flier  — hovers above and shoots fireballs.
--   none   — stationary slam: damages every enemy in `radius` (Kraken).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Placement = require(ReplicatedStorage.Shared.Spells.Placement)
local DestructibleService = require(script.Parent.Parent.DestructibleService)
local Projectile = require(script.Parent.Projectile)

local Summon = {}

local STEP = 0.1
local WALK_SPEED = 14

local function nearestEnemy(ctx: any, from: Vector3, range: number): any?
	local best, bestDist = nil, range
	for _, hit in ctx.enemiesNear(from, range) do
		if hit.character then
			local d = (hit.position - from).Magnitude
			if d < bestDist then
				best, bestDist = hit, d
			end
		end
	end
	return best
end

function Summon.cast(ctx: any): boolean?
	local def = ctx.def
	local stats = def.stats
	local visual = def.visual

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { ctx.character }
	local spot = ctx.root.Position + ctx.root.CFrame.LookVector * 6
	local down = workspace:Raycast(spot + Vector3.new(0, 5, 0), Vector3.new(0, -40, 0), params)
	if not down or not Placement.inRegions(down.Position, ctx.buildRegions) then
		return false -- summons follow the same build areas as placeables
	end
	local ground = down.Position

	local model = DestructibleService.build(def.name, visual, stats.health or 100, ctx.player, ctx.team)
	model:SetAttribute("SpellId", def.id)
	if stats.decoy then
		model:SetAttribute("Decoy", true)
	end
	local body = model.PrimaryPart :: BasePart
	local hover = if stats.flier then 8 else 0
	local height = Placement.height(visual)
	body.CFrame = CFrame.new(ground + Vector3.new(0, height / 2 + hover, 0)) * Placement.partOffset(visual)

	-- Simple face so summons read as creatures, not crates.
	local face = Instance.new("Decal")
	face.Texture = "rbxasset://textures/face.png"
	face.Face = Enum.NormalId.Front
	face.Parent = body
	model.Parent = ctx.structures

	task.spawn(function()
		local expires = os.clock() + (stats.lifetime or 15)
		local nextAttack = 0
		while model.Parent and os.clock() < expires do
			task.wait(STEP)
			if stats.decoy then
				continue
			end
			local now = os.clock()
			local target = nearestEnemy(ctx, body.Position, stats.range or 60)
			if not target then
				continue
			end
			local toTarget = target.position - body.Position
			local flat = Vector3.new(toTarget.X, 0, toTarget.Z)

			if flat.Magnitude < 0.1 then
				flat = Vector3.new(0, 0, 1)
			end
			if stats.melee then
				if flat.Magnitude > 4 then
					local stepVec = flat.Unit * math.min(WALK_SPEED * STEP, flat.Magnitude - 3)
					body.CFrame = CFrame.lookAt(body.Position + stepVec, body.Position + stepVec + flat.Unit)
				elseif now >= nextAttack then
					nextAttack = now + 1
					DestructibleService.damage(target.instance, stats.damage or 10, ctx.player, def.name)
					DestructibleService.push(target.instance, flat.Unit * 50 + Vector3.new(0, 20, 0))
				end
			elseif stats.flier then
				local desired = target.position + Vector3.new(0, 10, 0) - flat.Unit * 12
				body.CFrame = body.CFrame:Lerp(CFrame.lookAt(desired, target.position), 0.08)
				if now >= nextAttack then
					nextAttack = now + 1.5
					local direction = (target.position - body.Position).Unit
					Projectile.launch({
						caster = ctx.player,
						origin = body.Position + direction * 4,
						direction = direction,
						stats = { damage = stats.damage or 10, speed = 90, range = 90, radius = 1.5 },
						visual = {
							shape = "Ball",
							size = Vector3.new(1.6, 1.6, 1.6),
							color = Color3.fromRGB(255, 112, 40),
							material = Enum.Material.Neon,
						},
						spellName = def.name,
						ignore = { model },
					})
				end
			elseif now >= nextAttack then
				-- Stationary slam (Kraken)
				nextAttack = now + 2
				local radius = stats.radius or 14
				DestructibleService.poof(body.Position, visual.color)
				for _, hit in ctx.enemiesNear(body.Position, radius) do
					if hit.character then
						DestructibleService.damage(hit.character, stats.damage or 15, ctx.player, def.name)
						local away = hit.position - body.Position
						local awayFlat = Vector3.new(away.X, 0, away.Z)
						local dir = if awayFlat.Magnitude > 0.1 then awayFlat.Unit else Vector3.zero
						DestructibleService.push(hit.character, dir * 60 + Vector3.new(0, 40, 0))
					end
				end
			end
		end
		if model.Parent then
			DestructibleService.poof(body.Position, visual.color)
			model:Destroy()
		end
	end)
	return true
end

return Summon
