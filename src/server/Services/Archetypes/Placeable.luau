--!strict
-- Placeable archetype: objects players put into the world. All have health
-- and break when destroyed. Optional behaviors from stats:
--   turret (fires at the nearest enemy every `fireInterval`s: a player, a
--   decoy, a training dummy, or a Battleground NPC), trap (applies status to the first
--   enemy who touches it, then breaks), bounce (launches anyone touching it),
--   hazardDps + radius (burns nearby enemies).
-- Each player may have `maxActive` of a given spell (oldest is removed) and
-- Config.MAX_PLACED_PER_PLAYER total.
-- `visual.model` (e.g. Turret) skins the body with an imported model: the
-- primitive body stays as the invisible hitbox and the model is welded on.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local ModelKit = require(ReplicatedStorage.Shared.ModelKit)
local Placement = require(ReplicatedStorage.Shared.Spells.Placement)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local DestructibleService = require(script.Parent.Parent.DestructibleService)
local StatusService = require(script.Parent.Parent.StatusService)
local Projectile = require(script.Parent.Projectile)

local Placeable = {}

-- player -> list of their live structures (oldest first)
local placed: { [Player]: { Model } } = {}

local function track(player: Player, model: Model, spellId: string, maxActive: number)
	local list = placed[player] or {}
	placed[player] = list
	-- Prune destroyed entries.
	for i = #list, 1, -1 do
		if list[i].Parent == nil then
			table.remove(list, i)
		end
	end
	local function countSpell(): (number, number?)
		local count, oldest = 0, nil
		for i, existing in list do
			if existing:GetAttribute("SpellId") == spellId then
				count += 1
				oldest = oldest or i
			end
		end
		return count, oldest
	end
	local count, oldest = countSpell()
	while count >= maxActive and oldest do
		table.remove(list, oldest):Destroy()
		count, oldest = countSpell()
	end
	while #list >= Config.MAX_PLACED_PER_PLAYER do
		table.remove(list, 1):Destroy()
	end
	table.insert(list, model)
end

local function enemyCharacterFrom(ctx: any, part: BasePart): Model?
	local target, owner, isCharacter = DestructibleService.resolve(part)
	if
		target
		and isCharacter
		and owner ~= ctx.player
		and DestructibleService.canHarm(ctx.player, target)
	then
		return target :: Model
	end
	return nil
end

local function addBehaviors(ctx: any, model: Model, body: BasePart)
	local stats = ctx.def.stats

	if stats.bounce then
		local debounce: { [Model]: number } = {}
		body.Touched:Connect(function(part)
			local character = part.Parent
			if
				character
				and character:IsA("Model")
				and Players:GetPlayerFromCharacter(character)
			then
				local now = os.clock()
				if (debounce[character] or 0) < now then
					debounce[character] = now + 0.6
					DestructibleService.boost(character, Vector3.new(0, stats.bounce, 0))
				end
			end
		end)
	end

	if stats.trap then
		body.CanCollide = false
		local sprung = false
		body.Touched:Connect(function(part)
			if sprung then
				return
			end
			local victim = enemyCharacterFrom(ctx, part)
			if victim then
				sprung = true
				if stats.status then
					StatusService.apply(victim, stats.status, stats.statusDuration or 1)
				end
				local root = victim:FindFirstChild("HumanoidRootPart") :: BasePart?
				if root then
					DestructibleService.push(
						victim,
						root.CFrame.LookVector * 60 + Vector3.new(0, 20, 0)
					)
				end
				DestructibleService.poof(body.Position, body.Color)
				model:Destroy()
			end
		end)
	end

	if stats.turret then
		task.spawn(function()
			while model.Parent do
				task.wait(stats.fireInterval or 1.5)
				if not model.Parent then
					break
				end
				local origin = body.Position + Vector3.new(0, 1.5, 0)
				local best = nil
				local bestDist = stats.range or 60
				for _, hit in ctx.enemiesNear(origin, bestDist) do
					-- Decoys draw fire first.
					local isDecoy = hit.instance:GetAttribute("Decoy") == true
					local d = (hit.position - origin).Magnitude - (if isDecoy then 1000 else 0)
					local targetable = hit.character ~= nil
						or isDecoy
						or DestructibleService.isTrainingTarget(hit.instance)
					if targetable and d < bestDist then
						best, bestDist = hit, d
					end
				end
				if best then
					local direction = (best.position - origin).Unit
					-- Turn to face the target (a cylinder's axis is its X, so
					-- it needs a quarter turn; blocks and skins face -Z).
					local facing = CFrame.lookAt(
						body.Position,
						body.Position + Vector3.new(direction.X, 0, direction.Z)
					)
					body.CFrame = if ctx.def.visual.shape == "Cylinder"
						then facing * CFrame.Angles(0, math.pi / 2, 0)
						else facing
					-- Muzzle flash, smoke, and the shot's sound at the barrel.
					Remotes.get("Fx")
						:FireAllClients("muzzle", origin + direction * 3, direction, ctx.def.id)
					Projectile.launch({
						caster = ctx.player,
						origin = origin + direction * 3,
						direction = direction,
						stats = {
							damage = stats.damage or 10,
							speed = 110,
							range = (stats.range or 60) + 10,
							radius = 1,
						},
						visual = {
							shape = "Ball",
							size = Vector3.new(0.8, 0.8, 0.8),
							color = Color3.fromRGB(255, 213, 79),
							material = Enum.Material.Neon,
						},
						spellName = ctx.def.name,
						fxKey = "Bullet",
						ignore = { model },
					})
				end
			end
		end)
	end

	if stats.hazardDps then
		task.spawn(function()
			while model.Parent do
				task.wait(0.5)
				for _, hit in ctx.enemiesNear(body.Position, stats.radius or 10) do
					if hit.character then
						DestructibleService.damage(
							hit.character,
							stats.hazardDps * 0.5,
							ctx.player,
							ctx.def.name
						)
					end
				end
			end
		end)
	end
end

-- Replaces the primitive look with `visual.model` (scaled to the visual's
-- height): the body becomes an invisible hitbox and the model is welded to
-- it, so it rises, turns (turrets), and is destroyed with the body.
local function skin(model: Model, body: BasePart, visual: any)
	if not visual.model then
		return
	end
	local look = ModelKit.clone(visual.model, "attached")
	if not look then
		return
	end
	local _, size = look:GetBoundingBox()
	look:ScaleTo(visual.size.Y / math.max(size.Y, 0.01))
	look:PivotTo(body.CFrame)
	for _, part in look:GetDescendants() do
		if part:IsA("BasePart") then
			part:SetAttribute("BaseColor", part.Color)
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = body
			weld.Part1 = part
			weld.Parent = part
		end
	end
	body.Transparency = 1
	look.Name = "Look"
	look.Parent = model
end

-- Builds a wall out of a grid of separately breakable blocks (Rock Wall,
-- Castle). The grid is an untagged Model holding one Destructible model per
-- block; it removes itself once every block is broken.
local function buildSegmented(ctx: any, cframe: CFrame): Model
	local def = ctx.def
	local visual = def.visual
	local stats = def.stats
	local grid = stats.segments :: { x: number, y: number }
	local count = grid.x * grid.y
	local blockSize = Vector3.new(visual.size.X / grid.x, visual.size.Y / grid.y, visual.size.Z)

	local wall = Instance.new("Model")
	wall.Name = def.name
	wall:SetAttribute("SpellId", def.id)
	wall:SetAttribute("OwnerUserId", ctx.player.UserId)
	wall.Parent = ctx.structures

	local blockVisual = table.clone(visual)
	blockVisual.size = blockSize - Vector3.new(0.08, 0.08, 0) -- tiny gaps read as masonry
	for row = 1, grid.y do
		for col = 1, grid.x do
			local block = DestructibleService.build(
				`{def.name}Block`,
				blockVisual,
				(stats.health or 100) / count,
				ctx.player,
				ctx.team
			)
			block:SetAttribute("HitByAll", stats.hitByAll)
			local body = block.PrimaryPart :: BasePart
			-- Slight per-block color variation so the wall looks hand-built.
			local shade = 1 + (math.random() - 0.5) * 0.12
			body.Color = Color3.new(
				math.clamp(visual.color.R * shade, 0, 1),
				math.clamp(visual.color.G * shade, 0, 1),
				math.clamp(visual.color.B * shade, 0, 1)
			)
			body:SetAttribute("BaseColor", body.Color)
			local offset = Vector3.new(
				(col - (grid.x + 1) / 2) * blockSize.X,
				(row - (grid.y + 1) / 2) * blockSize.Y,
				0
			)
			local final = cframe * CFrame.new(offset)
			-- Each row rises out of the ground a beat after the one below it.
			body.CFrame = final - Vector3.new(0, visual.size.Y, 0)
			block.Parent = wall
			task.delay((row - 1) * 0.06, function()
				for i = 1, 6 do
					if not body.Parent then
						return
					end
					body.CFrame = final - Vector3.new(0, visual.size.Y * (1 - i / 6), 0)
					task.wait()
				end
			end)
		end
	end
	DestructibleService.dust(
		cframe.Position - Vector3.new(0, visual.size.Y / 2, 0),
		visual.size.X,
		visual.color
	)
	wall.ChildRemoved:Connect(function()
		if #wall:GetChildren() == 0 then
			wall:Destroy()
		end
	end)
	return wall
end

-- Builds a wall from an imported model (stats.model): every mesh part of the
-- model becomes its own chunk (e.g. Rock Wall = base, pillars, rubble). The
-- chunks share ONE damage budget (stats.health, on the wall as WallHealth):
-- a hit on any chunk drains it, chunks break one by one as it drains (lowest
-- pieces first, the tall stones when it's gone), and the whole wall is gone
-- once it reaches 0. Returns nil when the model isn't in the place (caller
-- falls back).
local function buildModelWall(ctx: any, cframe: CFrame): Model?
	local def = ctx.def
	local stats = def.stats
	local source = ModelKit.clone(stats.model, "solid")
	if not source then
		return nil
	end
	local meshParts: { BasePart } = {}
	for _, child in source:GetChildren() do
		if child:IsA("BasePart") and child.CanCollide then
			table.insert(meshParts, child)
		end
	end
	if #meshParts == 0 then
		return nil
	end
	-- Lowest pieces first: they break earlier as the budget drains.
	table.sort(meshParts, function(a, b)
		return a.Size.Y < b.Size.Y
	end)

	local budget = stats.health or 100
	local wall = Instance.new("Model")
	wall.Name = def.name
	wall:SetAttribute("SpellId", def.id)
	wall:SetAttribute("OwnerUserId", ctx.player.UserId)
	wall:SetAttribute("WallHealth", budget)
	wall:SetAttribute("WallMaxHealth", budget)
	wall.Parent = ctx.structures

	local height = def.visual.size.Y
	for index, part in meshParts do
		local chunk = Instance.new("Model")
		chunk.Name = `{def.name}Chunk`
		part.Parent = chunk
		chunk.PrimaryPart = part
		part:SetAttribute("BaseColor", part.Color)
		local final = cframe * part.CFrame
		-- Every chunk's bar shows the wall's remaining budget.
		DestructibleService.wrap(chunk, part, budget, ctx.player, ctx.team, part.Size.Y)
		chunk:SetAttribute("HitByAll", stats.hitByAll)
		-- Breaks when the remaining budget falls to this share of it:
		-- 2/3, 1/3, ... for the low pieces, 0 for the tallest.
		chunk:SetAttribute("BreakAt", (#meshParts - index) / #meshParts)
		-- Rises out of the ground, tall pieces a beat after the low ones.
		part.CFrame = final - Vector3.new(0, height, 0)
		chunk.Parent = wall
		task.spawn(function()
			task.wait(if part.Size.Y > height * 0.5 then 0.08 else 0)
			for i = 1, 8 do
				if not part.Parent then
					return
				end
				part.CFrame = final - Vector3.new(0, height * (1 - i / 8), 0)
				task.wait()
			end
		end)
	end
	source:Destroy()
	DestructibleService.dust(
		cframe.Position - Vector3.new(0, height / 2, 0),
		def.visual.size.X,
		def.visual.color
	)
	wall.ChildRemoved:Connect(function()
		if #wall:GetChildren() == 0 then
			wall:Destroy()
		end
	end)
	return wall
end

function Placeable.cast(ctx: any): boolean?
	local def = ctx.def
	local visual = def.visual
	local stats = def.stats

	-- Snap the requested point to the ground beneath it.
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { ctx.character }
	local down =
		workspace:Raycast(ctx.target + Vector3.new(0, 6, 0), Vector3.new(0, -40, 0), params)
	if not down then
		return false
	end
	local ground = down.Position
	if not Placement.inRegions(ground, ctx.buildRegions) then
		return false
	end
	local cframe = Placement.cframeFor(visual, ground, ctx.rotationY)
	local ignore = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			-- Players block placement only when standing inside it (checked below).
			table.insert(ignore, player.Character)
		end
	end
	if not Placement.isClear(visual, cframe, ignore) then
		return false
	end
	-- Don't entomb anyone.
	for _, player in Players:GetPlayers() do
		local root = player.Character
			and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local localPoint = cframe:PointToObjectSpace(root.Position)
			local half = Placement.boundsSize(visual) / 2 + Vector3.new(1, 2, 1)
			if
				math.abs(localPoint.X) < half.X
				and math.abs(localPoint.Y) < half.Y
				and math.abs(localPoint.Z) < half.Z
			then
				return false
			end
		end
	end

	-- Walls: the imported model if present, else the block-grid fallback.
	local wall: Model? = nil
	if stats.model then
		wall = buildModelWall(ctx, cframe)
	end
	if not wall and stats.segments then
		wall = buildSegmented(ctx, cframe)
	end
	if wall then
		local builtWall = wall :: Model
		track(ctx.player, builtWall, def.id, stats.maxActive or 2)
		if stats.lifetime then
			task.delay(stats.lifetime, function()
				if builtWall.Parent then
					for _, block in builtWall:GetChildren() do
						if block:IsA("Model") then
							DestructibleService.shatter(block)
						end
					end
					builtWall:Destroy()
				end
			end)
		end
		return true
	end

	local model =
		DestructibleService.build(def.name, visual, stats.health or 100, ctx.player, ctx.team)
	model:SetAttribute("SpellId", def.id)
	local body = model.PrimaryPart :: BasePart
	body.CFrame = cframe * Placement.partOffset(visual)
	skin(model, body, visual)

	-- Rise-from-the-ground animation with a dust burst.
	DestructibleService.dust(ground, math.max(visual.size.X, visual.size.Z), visual.color)
	local finalCFrame = body.CFrame
	body.CFrame = finalCFrame - Vector3.new(0, Placement.height(visual), 0)
	model.Parent = ctx.structures
	task.spawn(function()
		for i = 1, 8 do
			body.CFrame = finalCFrame - Vector3.new(0, Placement.height(visual) * (1 - i / 8), 0)
			task.wait()
		end
		body.CFrame = finalCFrame
	end)

	track(ctx.player, model, def.id, stats.maxActive or 2)
	addBehaviors(ctx, model, body)
	if stats.turret then
		-- Clients play the "online" scan ring and chime as it finishes rising.
		task.delay(0.15, function()
			Remotes.get("Fx"):FireAllClients("deploy", ground, visual.color, def.id)
		end)
	end
	if stats.lifetime then
		task.delay(stats.lifetime, function()
			if model.Parent then
				DestructibleService.poof(body.Position, body.Color)
				model:Destroy()
			end
		end)
	end
	return true
end

-- Removes every structure a player placed (round resets / leaving).
function Placeable.clearFor(player: Player)
	local list = placed[player]
	if list then
		for _, model in list do
			model:Destroy()
		end
	end
	placed[player] = nil
end

Players.PlayerRemoving:Connect(Placeable.clearFor)

return Placeable
