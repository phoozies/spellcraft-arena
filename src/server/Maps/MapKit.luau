--!strict
-- Tiny helpers for building maps from code. Maps are code (not .rbxm) so
-- they are versioned, diffable, and rebuilt identically on every server.
--
-- Arena contract (ArenaService relies on these children):
--   Bounds          invisible Part: build/teleport region; below it = void
--   Spawns/Team1_*  Team2_*  FFA_*  spawn Parts (invisible, CanCollide off)
--   SmallModeWalls  Folder of walls enabled only for 1v1 / 2v2
--   Structures      Folder (created by ArenaService) for placed objects

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

-- Ring of spawns for FFA around a center.
function MapKit.ffaSpawns(spawns: Instance, center: Vector3, radius: number, count: number)
	for i = 1, count do
		local a = (i / count) * math.pi * 2
		MapKit.spawn(
			spawns,
			`FFA_{i}`,
			center + Vector3.new(math.cos(a) * radius, 0, math.sin(a) * radius)
		)
	end
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

-- Scatter helper with a fixed seed so maps are identical everywhere.
function MapKit.rng(seed: number): Random
	return Random.new(seed)
end

return MapKit
