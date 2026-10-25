--!strict
-- Tiny helpers for building maps from code. Maps are code (not .rbxm) so
-- they are versioned, diffable, and rebuilt identically on every server.
--
-- Arena contract (ArenaService relies on these children):
--   Bounds          invisible Part: build/teleport region; below it = void
--   Spawns/Team1_*  Team2_*  spawn Parts (invisible, CanCollide off)
--   SmallModeWalls  Folder of walls enabled only for 1v1 / 2v2
--   Structures      Folder (created by ArenaService) for placed objects

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local ModelKit = require(ReplicatedStorage.Shared.ModelKit)

local MapKit = {}

export type PartProps = {
	size: Vector3,
	cframe: CFrame,
	color: Color3?,
	material: Enum.Material?,
	shape: Enum.PartType?,
	transparency: number?,
	canCollide: boolean?,
	name: string?,
}

function MapKit.part(parent: Instance, props: PartProps): Part
	local p = Instance.new("Part")
	p.Name = props.name or "Part"
	p.Anchored = true
	p.Size = props.size
	p.CFrame = props.cframe
	p.Color = props.color or Color3.fromRGB(200, 200, 200)
	p.Material = props.material or Enum.Material.SmoothPlastic
	p.Shape = props.shape or Enum.PartType.Block
	p.Transparency = props.transparency or 0
	p.CanCollide = if props.canCollide == nil then true else props.canCollide
	-- Invisible markers (spawns, zones, sign anchors) must never block spells.
	if not p.CanCollide and p.Transparency >= 1 then
		p.CanQuery = false
		p.CanTouch = false
	end
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

function MapKit.folder(parent: Instance, name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

function MapKit.spawn(spawns: Instance, name: string, position: Vector3)
	MapKit.part(spawns, {
		name = name,
		size = Vector3.new(4, 1, 4),
		cframe = CFrame.new(position),
		transparency = 1,
		canCollide = false,
	})
end

function MapKit.bounds(model: Instance, size: Vector3, center: Vector3)
	local b = MapKit.part(model, {
		name = "Bounds",
		size = size,
		cframe = CFrame.new(center),
		transparency = 1,
		canCollide = false,
	})
	b.CanQuery = false
	b.CanTouch = false
end

-- Line of 4 spawns per team on opposite ends (Z axis).
function MapKit.teamSpawns(spawns: Instance, center: Vector3, distance: number, y: number?)
	for i = 1, 4 do
		local x = (i - 2.5) * 8
		MapKit.spawn(spawns, `Team1_{i}`, center + Vector3.new(x, y or 0, -distance))
		MapKit.spawn(spawns, `Team2_{i}`, center + Vector3.new(x, y or 0, distance))
	end
end

-- Low perimeter wall square (used for SmallModeWalls to shrink an arena).
function MapKit.ring(
	parent: Instance,
	center: Vector3,
	halfSize: number,
	height: number,
	color: Color3
)
	for _, side in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
		local sx, sz = side[1], side[2]
		local size = if sx ~= 0
			then Vector3.new(2, height, halfSize * 2)
			else Vector3.new(halfSize * 2, height, 2)
		MapKit.part(parent, {
			name = "RingWall",
			size = size,
			cframe = CFrame.new(center + Vector3.new(sx * halfSize, height / 2, sz * halfSize)),
			color = color,
			material = Enum.Material.Glass,
			transparency = 0.6,
		})
	end
end

-- A cover wall made of separately breakable blocks. `base` is the CFrame of
-- the wall's bottom-center; blocks stack along its X (columns) and Y (rows).
-- `makeProp` is the map registrar (ArenaService) or DestructibleService.makeProp.
function MapKit.blockWall(
	parent: Instance,
	base: CFrame,
	columns: number,
	rows: number,
	blockSize: Vector3,
	color: Color3,
	material: Enum.Material,
	health: number,
	makeProp: (Instance, number) -> ()
): Folder
	local folder = MapKit.folder(parent, "BlockWall")
	for row = 1, rows do
		for col = 1, columns do
			local shade = 1 + ((col * 7 + row * 3) % 5 - 2) * 0.03
			local block = MapKit.part(folder, {
				name = "Block",
				size = blockSize - Vector3.new(0.08, 0.08, 0),
				cframe = base * CFrame.new(
					(col - (columns + 1) / 2) * blockSize.X,
					(row - 0.5) * blockSize.Y,
					0
				),
				color = Color3.new(
					math.clamp(color.R * shade, 0, 1),
					math.clamp(color.G * shade, 0, 1),
					math.clamp(color.B * shade, 0, 1)
				),
				material = material,
			})
			makeProp(block, health)
		end
	end
	return folder
end

-- A flat round disc whose TOP face is at `top` (a point on its axis).
function MapKit.disc(
	parent: Instance,
	top: Vector3,
	radius: number,
	thickness: number,
	color: Color3,
	material: Enum.Material,
	name: string?
): Part
	return MapKit.part(parent, {
		name = name or "Disc",
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(thickness, radius * 2, radius * 2),
		cframe = CFrame.new(top - Vector3.new(0, thickness / 2, 0))
			* CFrame.Angles(0, 0, math.pi / 2),
		color = color,
		material = material,
	})
end

-- A tapering rock underside (stacked discs) hanging from a round floor, so an
-- arena or island looks like it floats. `topY` is where the first layer's top
-- sits; it narrows from `radius` to about a sixth of it over `depth` studs.
-- `center` (default the origin) moves it sideways to a floor not at the origin.
function MapKit.underside(
	parent: Instance,
	topY: number,
	radius: number,
	depth: number,
	color: Color3,
	material: Enum.Material,
	center: Vector3?
)
	local layers = 6
	local offset = center or Vector3.zero
	local step = depth / layers
	for i = 1, layers do
		local r = radius * (1 - (i - 1) / layers * 0.85)
		MapKit.disc(
			parent,
			Vector3.new(offset.X, topY - (i - 1) * step, offset.Z),
			r,
			step + 0.2,
			color,
			material,
			"Underside"
		)
	end
end

-- An upright round column standing on `base`.
function MapKit.pillar(
	parent: Instance,
	base: Vector3,
	height: number,
	diameter: number,
	color: Color3,
	material: Enum.Material?
): Part
	return MapKit.part(parent, {
		name = "Pillar",
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(height, diameter, diameter),
		cframe = CFrame.new(base + Vector3.new(0, height / 2, 0))
			* CFrame.Angles(0, 0, math.pi / 2),
		color = color,
		material = material or Enum.Material.Marble,
	})
end

-- A ring of invisible walls (spells pass through: CanQuery off) whose inner
-- face is at `radius`, keeping everyone on a round floor. `y` is the wall's
-- bottom.
function MapKit.barrierRing(parent: Instance, radius: number, height: number, y: number?)
	local barriers = MapKit.folder(parent, "Barriers")
	local segments = math.max(12, math.ceil(radius / 4))
	local width = 2 * math.pi * (radius + 1) / segments + 1
	for i = 1, segments do
		local a = (i / segments) * math.pi * 2
		local position = Vector3.new(
			math.cos(a) * (radius + 1),
			(y or 0) + height / 2,
			math.sin(a) * (radius + 1)
		)
		local wall = MapKit.part(barriers, {
			name = "Barrier",
			size = Vector3.new(width, height, 2),
			cframe = CFrame.lookAt(position, Vector3.new(0, position.Y, 0)),
			transparency = 1,
		})
		wall.CanQuery = false
	end
end

-- A tree standing on `position`: a block-model oak, birch or pine, or a plain
-- trunk-and-ball when the model isn't available.
function MapKit.tree(parent: Instance, position: Vector3, scale: number, rng: Random, kind: string?)
	local kinds = { "TreeOak", "TreeBirch", "TreePine" }
	local tree = ModelKit.clone(kind or kinds[rng:NextInteger(1, #kinds)], "solid", scale)
	if tree then
		tree:PivotTo(CFrame.new(position) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0))
		tree.Parent = parent
		return
	end
	MapKit.part(parent, {
		name = "Trunk",
		size = Vector3.new(2 * scale, 10 * scale, 2 * scale),
		cframe = CFrame.new(position + Vector3.new(0, 5 * scale, 0)),
		color = Color3.fromRGB(110, 80, 56),
		material = Enum.Material.Wood,
	})
	MapKit.part(parent, {
		name = "Leaves",
		shape = Enum.PartType.Ball,
		size = Vector3.new(11, 9, 11) * scale,
		cframe = CFrame.new(position + Vector3.new(0, 12 * scale, 0)),
		color = Color3.fromRGB(72, 150, 72),
		material = Enum.Material.Grass,
	})
end

export type TerrainOptions = {
	cell: number, -- design-size cell width (Config.TERRAIN.CELL)
	health: number, -- what one cell can take (Config.TERRAIN.HEALTH)
	makeProp: (Instance, number) -> (),
	-- Floors and island tops: bolts glide over them, so only a direct strike or
	-- an area spell breaks them (Projectile skips "GroundTile" in its wide sweep).
	ground: boolean?,
	-- Return false to leave a cell out (x, z are the cell's center, relative to
	-- the block's center); used to cut round islands from a square block.
	keep: ((x: number, z: number) -> boolean)?,
}

-- A solid block of terrain built from separately breakable cells (tagged
-- Destructible with the "Terrain" attribute, so DestructibleService splashes
-- each hit onto the neighbours). The block is cut up on X, Y and Z so no cell
-- is wider than `cell`.
function MapKit.terrain(parent: Instance, props: PartProps, options: TerrainOptions): Folder
	local folder = MapKit.folder(parent, props.name or "Terrain")
	local size = props.size
	local nx = math.max(1, math.ceil(size.X / options.cell - 0.01))
	local ny = math.max(1, math.ceil(size.Y / options.cell - 0.01))
	local nz = math.max(1, math.ceil(size.Z / options.cell - 0.01))
	local cellSize = Vector3.new(size.X / nx, size.Y / ny, size.Z / nz)
	local base = props.color or Color3.fromRGB(200, 200, 200)
	for ix = 1, nx do
		for iy = 1, ny do
			for iz = 1, nz do
				local offset = Vector3.new(
					(ix - (nx + 1) / 2) * cellSize.X,
					(iy - (ny + 1) / 2) * cellSize.Y,
					(iz - (nz + 1) / 2) * cellSize.Z
				)
				if options.keep == nil or options.keep(offset.X, offset.Z) then
					local shade = 1 + ((ix * 7 + iy * 3 + iz * 5) % 5 - 2) * 0.025
					local cell = MapKit.part(folder, {
						name = "TerrainCell",
						size = cellSize,
						cframe = props.cframe * CFrame.new(offset),
						color = Color3.new(
							math.clamp(base.R * shade, 0, 1),
							math.clamp(base.G * shade, 0, 1),
							math.clamp(base.B * shade, 0, 1)
						),
						material = props.material,
					})
					cell:SetAttribute("Terrain", true)
					if options.ground then
						cell:SetAttribute("GroundTile", true)
					end
					options.makeProp(cell, options.health)
				end
			end
		end
	end
	return folder
end

-- Ready-made terrain options from Config.TERRAIN: floors and island tops
-- (`ground`, health Ground) and rock such as mesas and boulders (health Rock).
function MapKit.groundTerrain(makeProp: (Instance, number) -> ()): TerrainOptions
	return {
		cell = Config.TERRAIN.CELL,
		health = Config.TERRAIN.HEALTH.Ground,
		makeProp = makeProp,
		ground = true,
	}
end

function MapKit.rockTerrain(makeProp: (Instance, number) -> ()): TerrainOptions
	return {
		cell = Config.TERRAIN.CELL,
		health = Config.TERRAIN.HEALTH.Rock,
		makeProp = makeProp,
	}
end

-- A round floor of breakable terrain whose TOP face is at `top` (a point on
-- its axis), like MapKit.disc. Cells whose center is a little past the radius
-- are kept too, so the rim has no gaps (the overhang is under the barrier).
function MapKit.terrainDisc(
	parent: Instance,
	top: Vector3,
	radius: number,
	thickness: number,
	color: Color3,
	material: Enum.Material,
	name: string,
	options: TerrainOptions
): Folder
	local reach = radius + options.cell * 0.4
	local withShape = table.clone(options)
	withShape.keep = function(x: number, z: number)
		return x * x + z * z <= reach * reach
	end
	return MapKit.terrain(parent, {
		name = name,
		size = Vector3.new(radius * 2, thickness, radius * 2),
		cframe = CFrame.new(top - Vector3.new(0, thickness / 2, 0)),
		color = color,
		material = material,
	}, withShape)
end

-- Launch velocity of a ballistic arc from `from` that lands on `to`, covering
-- the ground at roughly `speed` studs/s (flight time kept between 1 and 2.2 s).
function MapKit.launchVelocity(from: Vector3, to: Vector3, speed: number): Vector3
	local g = workspace.Gravity
	local flat = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	local t = math.clamp(flat.Magnitude / speed, 1, 2.2)
	local vy = ((to.Y - from.Y) + 0.5 * g * t * t) / t
	return flat / t + Vector3.new(0, vy, 0)
end

-- Scales a finished map about its origin (the floor's center, top at y = 0, so
-- the ground stays at y = 0). Jump pads that name a "LaunchTo" landing spot are
-- re-aimed for the new distances.
function MapKit.scale(model: Instance, factor: number, padSpeed: number)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			local cframe = descendant.CFrame
			descendant.Size *= factor
			descendant.CFrame = cframe.Rotation + cframe.Position * factor
		elseif descendant:IsA("Attachment") then
			descendant.Position *= factor
		end
	end
	for _, descendant in model:GetDescendants() do
		local landing = descendant:GetAttribute("LaunchTo")
		if descendant:IsA("BasePart") and typeof(landing) == "Vector3" then
			local to = landing * factor
			descendant:SetAttribute("LaunchTo", to)
			descendant:SetAttribute(
				"LaunchVelocity",
				MapKit.launchVelocity(descendant.Position, to, padSpeed)
			)
		end
	end
end

-- Scatter helper with a fixed seed so maps are identical everywhere.
function MapKit.rng(seed: number): Random
	return Random.new(seed)
end

return MapKit
