--!strict
-- Zone archetype: an area on the ground at the target point.
--   * duration > 0: lingers and ticks 4x/second — applies `status`, pulls
--     toward the center (`pull`), deals damage per second (`damage`), or
--     heals allies (`heal` + teamHeal).
--   * delay (no duration): a telegraphed burst after `delay` seconds —
--     damage + knockback, optionally smashing structures. With `pillar` the
--     clients draw the element's column erupting (Fx "pillar": Fire Pillar,
--     Water Nebula, Earthquake); `rise` pops a boulder up out of the ground
--     (Earth Punch); `channel` roots the caster for the delay (Earthquake).
--     Those three draw `visual.model` themselves (SpellVfx); any other burst
--     with a model has it strike down from the sky.
--   * hold (Black Hole): enemies pulled into the core (HOLD_RADIUS) are
--     Rooted there until the zone ends: sucked in, then trapped. Players,
--     Battleground NPCs, and training dummies all feel it (dummies are posts:
--     they take the damage but do not move). Clients draw the vortex (Fx
--     "vortex") and a spiral of motes streaming off each victim ("suck").
--   * visual.model: the lingering swirl is that model (spun by clients via
--     the SpinFx tag) instead of a primitive.

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ModelKit = require(ReplicatedStorage.Shared.ModelKit)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local DestructibleService = require(script.Parent.Parent.DestructibleService)
local StatusService = require(script.Parent.Parent.StatusService)

local Zone = {}

local TICK = 0.25
-- Black Hole (`hold`): how close to the center counts as "in the core".
local HOLD_RADIUS = 4

local fxRemote = Remotes.get("Fx")

-- player -> spellId -> live zone discs (oldest first). Lingering zones are
-- capped per spell (stats.maxActive, default 1); casting another replaces
-- the oldest, so re-drawing every second can't carpet the map.
local activeZones: { [Player]: { [string]: { BasePart } } } = setmetatable({}, { __mode = "k" }) :: any

local function trackZone(player: Player, spellId: string, area: BasePart, maxActive: number)
	local bySpell = activeZones[player] or {}
	activeZones[player] = bySpell
	local list = bySpell[spellId] or {}
	bySpell[spellId] = list
	for i = #list, 1, -1 do
		if list[i].Parent == nil then
			table.remove(list, i)
		end
	end
	while #list >= maxActive do
		table.remove(list, 1):Destroy()
	end
	table.insert(list, area)
end

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
	-- A caster who is knocked out mid-channel loses the spell.
	if stats.channel then
		local humanoid = ctx.character:FindFirstChildOfClass("Humanoid")
		if not ctx.character.Parent or not humanoid or humanoid.Health <= 0 then
			return
		end
	end
	if stats.pillar then
		-- Clients draw the element's column erupting.
		fxRemote:FireAllClients(
			"pillar",
			center,
			radius,
			ctx.def.visual.color,
			ctx.def.element,
			ctx.def.id
		)
	end
	local flash = disc(center, radius, ctx.def.visual.color, Enum.Material.Neon, 0.2)
	TweenService:Create(flash, TweenInfo.new(0.5), { Transparency = 1 }):Play()
	Debris:AddItem(flash, 0.6)
	DestructibleService.poof(center, ctx.def.visual.color)
	DestructibleService.shockwave(center, radius, ctx.def.visual.color)

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
		if visual.shape == "Ball" and not stats.rise then
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
		if stats.rise then
			-- Earth Punch: a boulder bursts up out of the ground at the burst.
			fxRemote:FireAllClients(
				"rise",
				center,
				radius,
				stats.delay,
				visual.color,
				"boulder",
				visual.size.Y,
				visual.model
			)
		end
		if stats.channel then
			-- Earthquake: the caster can't move or cast while the ground shakes.
			StatusService.apply(ctx.character, "Channel", stats.delay)
			fxRemote:FireAllClients(
				"quake",
				center,
				radius,
				stats.delay,
				visual.color,
				visual.model
			)
		end
		-- Pillar, rise, and channel spells use their model in their own effect
		-- (SpellVfx); any other burst with a model has it strike down from the sky.
		if visual.model and not (stats.pillar or stats.rise or stats.channel) then
			-- Clients draw the model striking down at the burst (Zap's bolt).
			fxRemote:FireAllClients(
				"strike",
				center,
				radius,
				stats.delay,
				visual.model,
				visual.color,
				ctx.def.id
			)
		end
		task.delay(stats.delay, burst, ctx, center)
		return true
	end

	local duration = stats.duration or 3
	-- Black Hole: clients draw the whirling vortex hovering over the disc.
	local coreHeight = visual.size.Y / 2 + 1
	if stats.hold then
		fxRemote:FireAllClients(
			"vortex",
			center,
			radius,
			duration,
			visual.color,
			coreHeight,
			ctx.def.id
		)
	end
	local area = disc(center, radius, visual.color, visual.material, visual.transparency or 0.3)
	area.Name = ctx.def.name
	trackZone(ctx.player, ctx.def.id, area, stats.maxActive or 1)
	local look = if visual.model then ModelKit.clone(visual.model, "effect") else nil
	if look then
		-- Imported swirl (Black Hole): sized to the visual, hovering over the
		-- disc. Clients spin models tagged SpinFx about their vertical axis.
		local _, size = look:GetBoundingBox()
		look:ScaleTo(visual.size.X / math.max(size.X, size.Z, 0.01))
		look:PivotTo(CFrame.new(center + Vector3.new(0, visual.size.Y / 2 + 1, 0)))
		look:AddTag("SpinFx")
		look.Parent = area
	elseif
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
		local held: { [Model]: boolean } = {}
		local sucked: { [Model]: boolean } = {}
		local limp: { [Humanoid]: boolean } = {}
		while elapsed < duration and area.Parent do
			for _, hit in ctx.enemiesNear(center, radius) do
				-- A player, or a dummy / Battleground NPC standing in for one.
				local victim: Model? = hit.character
				if not victim and DestructibleService.isTrainingTarget(hit.instance) then
					victim = if hit.instance:IsA("Model") then hit.instance else nil
				end
				if victim then
					-- Only things that can move (players, NPCs) are pulled and held.
					local mover = StatusService.targetOf(victim)
					local root = victim:FindFirstChild("HumanoidRootPart")
					if stats.hold and not sucked[victim] then
						-- Everyone caught gets the streaming spiral, once.
						sucked[victim] = true
						fxRemote:FireAllClients(
							"suck",
							victim,
							center,
							duration - elapsed,
							ctx.def.visual.color,
							coreHeight
						)
					end
					if
						stats.hold
						and mover
						and root
						and root:IsA("BasePart")
						and not held[victim]
					then
						local offset = root.Position - center
						if Vector3.new(offset.X, 0, offset.Z).Magnitude <= HOLD_RADIUS then
							-- Dragged to the very center and held for the rest of the
							-- zone. Root stops moving, not casting.
							held[victim] = true
							StatusService.apply(victim, "Root", duration - elapsed)
							root.AssemblyLinearVelocity = Vector3.zero
							root.CFrame = CFrame.new(center.X, root.Position.Y, center.Z)
								* root.CFrame.Rotation
						end
					end
					if stats.status and mover then
						StatusService.apply(victim, stats.status, stats.statusDuration or TICK * 2)
					end
					if stats.damage then
						DestructibleService.damage(
							victim,
							stats.damage * TICK,
							ctx.player,
							ctx.def.name
						)
					end
					if stats.pull and mover and not held[victim] then
						local toCenter = center - hit.position
						local flat = Vector3.new(toCenter.X, 0, toCenter.Z)
						if flat.Magnitude > 2 then
							local pull = flat.Unit * stats.pull + Vector3.new(0, 6, 0)
							if hit.character then
								DestructibleService.push(victim, pull)
							elseif root and root:IsA("BasePart") then
								-- A Battleground NPC: the server owns it. It goes limp so its
								-- walking can't fight the pull, then is flung toward the core.
								local npcHumanoid = victim:FindFirstChildOfClass("Humanoid")
								if npcHumanoid then
									npcHumanoid.PlatformStand = true
									limp[npcHumanoid] = true
								end
								root.AssemblyLinearVelocity = pull
							end
						end
					end
				end
			end
			if stats.heal then
				for _, ally in ctx.alliesNear(center, radius) do
					DestructibleService.heal(ally, stats.heal * TICK, ctx.player)
				end
			end
			task.wait(TICK)
			elapsed += TICK
		end
		-- Pulled NPCs get back on their feet when the hole closes.
		for npcHumanoid in limp do
			if npcHumanoid.Parent then
				npcHumanoid.PlatformStand = false
			end
		end
	end)
	return true
end

return Zone
