--!strict
-- The flat duel arena every map is built from. Fights are first person with
-- auto-aim, so the floor is one level plane (no ramps, mesas, bridges or
-- ledges): what matters is cover and line of sight. Each map is a Theme (its
-- colours, materials, floor shape, layout, and a few props of its own) handed
-- to FlatArena.build, which makes:
--
--   floor    a board of breakable terrain tiles, top at y = 0, painted tile by
--            tile: a soft checkerboard, the Blue half (-Z) and the Red half (+Z)
--            tinted toward their team colour, a centre line and a centre mark,
--            so you always know which side of the board you're on
--   edge     a low curb of breakable rock round the board and a tapering rock
--            underside (arenas float below the hub). `walled` themes add an
--            invisible ring that keeps everyone on the board (spells pass it);
--            open ones let knockback ring players out into the water
--   cover    the layout is given for the Blue half and mirrored through the
--            centre for Red (point symmetry), so both teams get the same map.
--            "wall" (3 rows of bricks: hides you), "low" (2 rows: peek over),
--            "pillar" (a tall square column), "block" (a waist-high cube),
--            "tree" (a breakable tree); `center = true` places one piece in the
--            middle instead of a mirrored pair
--   pads     a glowing spawn pad per spawn in the team's colour, and team-coloured
--            lights round the curb
--   small    1v1 and 2v2 fight inside a smaller ring (SmallModeWalls: an invisible
--            wall and a glowing line on the floor), larger modes use the whole board
--
-- Every solid piece is breakable (terrain cells or props via makeProp); glow
-- and paint pieces don't collide or block spells. Same arena contract as
-- MapKit (Bounds, Spawns/Team1_* Team2_*, SmallModeWalls).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local MapKit = require(script.Parent.MapKit)

type Registrar = (instance: Instance, health: number) -> ()

export type Cover = {
	kind: "wall" | "low" | "pillar" | "block" | "tree",
	x: number,
	z: number,
	angle: number?, -- degrees about Y
	length: number?, -- bricks along a wall (default 4)
	center: boolean?, -- one piece here, not a mirrored pair
}

export type Theme = {
	name: string,
	seed: number,
	-- "round": a disc of `radius`; "rect": `halfX` by `halfZ` (teams at the Z ends).
	shape: "round" | "rect",
	radius: number?,
	halfX: number?,
	halfZ: number?,
	floor: Color3,
	floorMaterial: Enum.Material,
	accent: Color3, -- the centre line and centre mark
	curb: Color3,
	curbMaterial: Enum.Material,
	underside: Color3,
	undersideMaterial: Enum.Material,
	cover: Color3,
	coverMaterial: Enum.Material,
	pillar: Color3,
	pillarMaterial: Enum.Material,
	walled: boolean,
	spawnDistance: number,
	layout: { Cover },
	-- Props of the map's own (must be breakable or non-colliding).
	decor: ((model: Model, rng: Random, makeProp: Registrar) -> ())?,
}

local FlatArena = {}

FlatArena.BLUE = Color3.fromRGB(66, 135, 245)
FlatArena.RED = Color3.fromRGB(239, 83, 80)

local CELL = Config.TERRAIN.CELL
local FLOOR_THICKNESS = 4
local CURB_HEIGHT = 1.5
local CURB_WIDTH = 4
local BRICK = Vector3.new(3, 2.5, 2)

local function mix(a: Color3, b: Color3, t: number): Color3
	return a:Lerp(b, math.clamp(t, 0, 1))
end

-- A glowing piece that never collides or blocks spells (paint, pads, lights).
local function glowPart(parent: Instance, props: MapKit.PartProps): Part
	local part = MapKit.part(parent, props)
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = props.material or Enum.Material.Neon
	return part
end

-- Is (x, z) on the board?
local function onBoard(theme: Theme, x: number, z: number, inset: number): boolean
	if theme.shape == "round" then
		local r = (theme.radius :: number) - inset
		return x * x + z * z <= r * r
	end
	return math.abs(x) <= (theme.halfX :: number) - inset
		and math.abs(z) <= (theme.halfZ :: number) - inset
end

-- The tile colour at (x, z): checkerboard, team halves, centre line and mark.
local function painter(theme: Theme): (number, number) -> Color3
	local light = mix(theme.floor, Color3.new(1, 1, 1), 0.1)
	local dark = mix(theme.floor, Color3.new(0, 0, 0), 0.08)
	local reach = theme.spawnDistance
	return function(x: number, z: number): Color3
		local checker = (math.floor(x / CELL + 0.5) + math.floor(z / CELL + 0.5)) % 2 == 0
		local color = if checker then light else dark
		-- The centre mark and the line splitting the halves.
		if x * x + z * z <= (CELL * 1.1) ^ 2 then
			return theme.accent
		end
		if math.abs(z) < CELL * 0.5 then
			return mix(color, theme.accent, 0.55)
		end
		-- Each half leans toward its team colour, more so near its spawn.
		local team = if z < 0 then FlatArena.BLUE else FlatArena.RED
		local depth = math.clamp(math.abs(z) / reach, 0, 1)
		return mix(color, team, 0.06 + 0.16 * depth)
	end
end

local function buildFloor(model: Model, theme: Theme, makeProp: Registrar)
	local options = MapKit.groundTerrain(makeProp)
	options.paint = painter(theme)
	if theme.shape == "round" then
		MapKit.terrainDisc(
			model,
			Vector3.zero,
			theme.radius :: number,
			FLOOR_THICKNESS,
			theme.floor,
			theme.floorMaterial,
			"Floor",
			options
		)
	else
		MapKit.terrain(model, {
			name = "Floor",
			size = Vector3.new(
				(theme.halfX :: number) * 2,
				FLOOR_THICKNESS,
				(theme.halfZ :: number) * 2
			),
			cframe = CFrame.new(0, -FLOOR_THICKNESS / 2, 0),
			color = theme.floor,
			material = theme.floorMaterial,
		}, options)
	end
end

-- The curb and the rock underside.
local function buildEdge(model: Model, theme: Theme, makeProp: Registrar)
	local rock = MapKit.rockTerrain(makeProp)
	if theme.shape == "round" then
		local radius = theme.radius :: number
		-- One ring of cells just outside the floor's (the floor keeps cells out
		-- to radius + 0.4 cell), so the two never overlap and the curb has no gaps.
		MapKit.terrainDisc(
			model,
			Vector3.new(0, CURB_HEIGHT, 0),
			radius + CELL,
			CURB_HEIGHT + FLOOR_THICKNESS,
			theme.curb,
			theme.curbMaterial,
			"Curb",
			rock,
			radius + CELL * 0.4 + 0.01
		)
		MapKit.underside(
			model,
			-FLOOR_THICKNESS,
			radius + CELL * 1.2,
			radius * 0.8,
			theme.underside,
			theme.undersideMaterial
		)
		return
	end
	local hx, hz = theme.halfX :: number, theme.halfZ :: number
	for _, side in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
		local sx, sz = side[1], side[2]
		local size = if sx ~= 0
			then Vector3.new(CURB_WIDTH, CURB_HEIGHT + FLOOR_THICKNESS, hz * 2 + CURB_WIDTH * 2)
			else Vector3.new(hx * 2, CURB_HEIGHT + FLOOR_THICKNESS, CURB_WIDTH)
		MapKit.terrain(model, {
			name = "Curb",
			size = size,
			cframe = CFrame.new(
				sx * (hx + CURB_WIDTH / 2),
				(CURB_HEIGHT - FLOOR_THICKNESS) / 2,
				sz * (hz + CURB_WIDTH / 2)
			),
			color = theme.curb,
			material = theme.curbMaterial,
		}, rock)
	end
	-- A stepped rock slab under the board, narrowing as it hangs down.
	local layers = 5
	for i = 1, layers do
		local f = 1 - (i - 1) / layers * 0.8
		local underside = MapKit.part(model, {
			name = "Underside",
			size = Vector3.new((hx + CURB_WIDTH) * 2 * f, 8, (hz + CURB_WIDTH) * 2 * f),
			cframe = CFrame.new(0, -FLOOR_THICKNESS - 4 - (i - 1) * 8, 0),
			color = theme.underside,
			material = theme.undersideMaterial,
		})
		underside.CanQuery = false
	end
end

local function placeCover(
	model: Model,
	theme: Theme,
	piece: Cover,
	frame: CFrame,
	makeProp: Registrar,
	rng: Random
)
	if piece.kind == "wall" or piece.kind == "low" then
		MapKit.blockWall(
			model,
			frame,
			piece.length or 4,
			if piece.kind == "wall" then 3 else 2,
			BRICK,
			theme.cover,
			theme.coverMaterial,
			Config.PROPS.Brick,
			makeProp
		)
	elseif piece.kind == "pillar" then
		MapKit.terrain(model, {
			name = "Pillar",
			size = Vector3.new(6, 14, 6),
			cframe = frame * CFrame.new(0, 7, 0),
			color = theme.pillar,
			material = theme.pillarMaterial,
		}, MapKit.rockTerrain(makeProp))
	elseif piece.kind == "block" then
		local block = MapKit.part(model, {
			name = "CoverBlock",
			size = Vector3.new(5, 4.5, 5),
			cframe = frame * CFrame.new(0, 2.25, 0),
			color = theme.pillar,
			material = theme.pillarMaterial,
		})
		makeProp(block, Config.PROPS.Medium)
	elseif piece.kind == "tree" then
		MapKit.tree(model, frame.Position, 1, rng, nil, makeProp, Config.PROPS.Medium)
	end
end

local function buildCover(model: Model, theme: Theme, makeProp: Registrar, rng: Random)
	for _, piece in theme.layout do
		local yaw = math.rad(piece.angle or 0)
		local frame = CFrame.new(piece.x, 0, piece.z) * CFrame.Angles(0, yaw, 0)
		placeCover(model, theme, piece, frame, makeProp, rng)
		if not piece.center then
			-- The Red half mirrors the Blue half through the centre.
			placeCover(
				model,
				theme,
				piece,
				CFrame.new(-piece.x, 0, -piece.z) * CFrame.Angles(0, yaw + math.pi, 0),
				makeProp,
				rng
			)
		end
	end
end

-- Spawn pads in team colours, and lights round the curb.
local function buildGlow(model: Model, theme: Theme)
	local glow = MapKit.folder(model, "Glow")
	for i = 1, 4 do
		local x = (i - 2.5) * 8
		for _, team in
			{
				{ z = -theme.spawnDistance, color = FlatArena.BLUE },
				{ z = theme.spawnDistance, color = FlatArena.RED },
			}
		do
			glowPart(glow, {
				name = "SpawnPad",
				size = Vector3.new(6, 0.2, 6),
				cframe = CFrame.new(x, 0.1, team.z),
				color = team.color,
				transparency = 0.25,
			})
		end
	end
	-- Lamp posts on the curb: blue on the Blue half, red on the Red half, the
	-- accent colour on the centre line.
	local posts: { Vector3 } = {}
	if theme.shape == "round" then
		local radius = (theme.radius :: number) + CELL * 0.9
		for i = 0, 15 do
			local a = i / 16 * math.pi * 2
			table.insert(
				posts,
				Vector3.new(math.sin(a) * radius, CURB_HEIGHT, -math.cos(a) * radius)
			)
		end
	else
		local hx, hz =
			(theme.halfX :: number) + CURB_WIDTH / 2, (theme.halfZ :: number) + CURB_WIDTH / 2
		for _, x in { -hx, hx } do
			for k = 0, 6 do
				table.insert(posts, Vector3.new(x, CURB_HEIGHT, -hz + k * hz / 3))
			end
		end
	end
	for _, at in posts do
		local color = if math.abs(at.Z) < 4
			then theme.accent
			elseif at.Z < 0 then FlatArena.BLUE
			else FlatArena.RED
		local lamp = glowPart(glow, {
			name = "EdgeLight",
			size = Vector3.new(1.2, 4, 1.2),
			cframe = CFrame.new(at + Vector3.new(0, 2, 0)),
			color = color,
		})
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = 14
		light.Brightness = 1.2
		light.Parent = lamp
	end
end

-- 1v1 and 2v2: an invisible wall a little behind the spawns, drawn on the floor
-- as a glowing line (round boards get a ring, long boards two end lines).
local function buildSmallModeWalls(model: Model, theme: Theme)
	local folder = MapKit.folder(model, "SmallModeWalls")
	local reach = theme.spawnDistance + 10
	if theme.shape == "round" and reach < (theme.radius :: number) - 4 then
		MapKit.barrierRing(folder, reach, 30)
		for i = 1, 48 do
			local a = i / 48 * math.pi * 2
			glowPart(folder, {
				name = "SmallModeLine",
				size = Vector3.new(reach * 2 * math.pi / 48 + 0.2, 0.15, 0.6),
				cframe = CFrame.new(math.cos(a) * reach, 0.1, math.sin(a) * reach)
					* CFrame.Angles(0, -a + math.pi / 2, 0),
				color = theme.accent,
				transparency = 0.3,
			})
		end
	elseif theme.shape == "rect" and reach < (theme.halfZ :: number) - 4 then
		for _, z in { -reach, reach } do
			local wall = MapKit.part(folder, {
				name = "Barrier",
				size = Vector3.new((theme.halfX :: number) * 2, 30, 2),
				cframe = CFrame.new(0, 15, z + math.sign(z)),
				transparency = 1,
			})
			wall.CanQuery = false
			glowPart(folder, {
				name = "SmallModeLine",
				size = Vector3.new((theme.halfX :: number) * 2, 0.15, 0.6),
				cframe = CFrame.new(0, 0.1, z),
				color = theme.accent,
				transparency = 0.3,
			})
		end
	end
end

function FlatArena.build(theme: Theme, makeProp: Registrar): Model
	local model = Instance.new("Model")
	model.Name = theme.name
	local rng = MapKit.rng(theme.seed)

	buildFloor(model, theme, makeProp)
	buildEdge(model, theme, makeProp)
	buildCover(model, theme, makeProp, rng)
	buildGlow(model, theme)
	if theme.decor then
		theme.decor(model, rng, makeProp)
	end
	if theme.walled then
		if theme.shape == "round" then
			MapKit.barrierRing(model, (theme.radius :: number) + CELL * 1.4, 40)
		else
			local barriers = MapKit.folder(model, "Barriers")
			local hx, hz =
				(theme.halfX :: number) + CURB_WIDTH, (theme.halfZ :: number) + CURB_WIDTH
			for _, side in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
				local sx, sz = side[1], side[2]
				local wall = MapKit.part(barriers, {
					name = "Barrier",
					size = if sx ~= 0
						then Vector3.new(2, 40, hz * 2 + 4)
						else Vector3.new(hx * 2 + 4, 40, 2),
					cframe = CFrame.new(sx * (hx + 1), 20, sz * (hz + 1)),
					transparency = 1,
				})
				wall.CanQuery = false
			end
		end
	end

	local spawns = MapKit.folder(model, "Spawns")
	MapKit.teamSpawns(spawns, Vector3.zero, theme.spawnDistance, 0.5)
	buildSmallModeWalls(model, theme)

	-- The build and teleport region: the board itself.
	local width = if theme.shape == "round"
		then (theme.radius :: number) * 2
		else (theme.halfX :: number) * 2
	local depth = if theme.shape == "round"
		then (theme.radius :: number) * 2
		else (theme.halfZ :: number) * 2
	MapKit.bounds(model, Vector3.new(width, 80, depth), Vector3.new(0, 30, 0))
	return model
end

-- True when (x, z) is on the theme's board at least `inset` studs from its edge
-- (for decor functions that scatter props).
FlatArena.onBoard = onBoard

return FlatArena
