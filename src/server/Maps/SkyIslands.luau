--!strict
-- Sky Islands — floating islands over the void with jump pads between
-- them. Knockback spells shine here (ring-outs). Great for 4v4.

local MapKit = require(script.Parent.MapKit)

type Registrar = (instance: Instance, health: number) -> ()

local GRASS = Color3.fromRGB(129, 199, 132)
local DIRT = Color3.fromRGB(161, 136, 127)

local function island(parent: Instance, center: Vector3, radius: number, name: string)
	MapKit.part(parent, {
		name = name,
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(4, radius * 2, radius * 2),
		cframe = CFrame.new(center - Vector3.new(0, 2, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		color = GRASS,
		material = Enum.Material.Grass,
	})
	-- Rocky underside.
	MapKit.part(parent, {
		name = name .. "Rock",
		shape = Enum.PartType.Ball,
		size = Vector3.new(radius * 1.6, radius * 1.2, radius * 1.6),
		cframe = CFrame.new(center - Vector3.new(0, radius * 0.6, 0)),
		color = DIRT,
		material = Enum.Material.Rock,
	})
end

local function jumpPad(parent: Instance, from: Vector3, to: Vector3)
	local pad = MapKit.part(parent, {
		name = "JumpPad",
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(0.6, 7, 7),
		cframe = CFrame.new(from + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		color = Color3.fromRGB(255, 64, 129),
		material = Enum.Material.Neon,
	})
	-- Ballistic launch that lands near `to` (g = workspace gravity).
	local g = workspace.Gravity
	local flat = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	local t = math.clamp(flat.Magnitude / 45, 1, 2.2)
	local vy = ((to.Y - from.Y) + 0.5 * g * t * t) / t
	pad:SetAttribute("LaunchVelocity", flat / t + Vector3.new(0, vy, 0))
	pad:AddTag("JumpPad")
end

return function(makeProp: Registrar): Model
	local model = Instance.new("Model")
	model.Name = "SkyIslands"

	island(model, Vector3.zero, 26, "MainIsland")
	local satellites = {}
	for i = 1, 4 do
		local a = (i / 4) * math.pi * 2 + math.pi / 4
		local center = Vector3.new(math.cos(a) * 62, if i % 2 == 0 then 6 else -2, math.sin(a) * 62)
		table.insert(satellites, center)
		island(model, center, 15, `Island{i}`)
		-- Pads both ways between each satellite and the main island.
		local inward = (Vector3.zero - center) * Vector3.new(1, 0, 1)
		jumpPad(model, center + inward.Unit * 9, Vector3.new(0, 0, 0) - inward.Unit * 10)
		jumpPad(model, -inward.Unit * 18, center)
	end

	-- Breakable cloud blocks and pillars for cover.
	for i, center in satellites do
		local pillar = MapKit.part(model, {
			name = "CloudBlock",
			size = Vector3.new(6, 6, 6),
			cframe = CFrame.new(center + Vector3.new(0, 3, 0)) * CFrame.Angles(0, i, 0),
			color = Color3.fromRGB(255, 255, 255),
			material = Enum.Material.SmoothPlastic,
		})
		makeProp(pillar, 160)
	end
	for _, offset in
		{
			Vector3.new(10, 3, 0),
			Vector3.new(-10, 3, 0),
			Vector3.new(0, 3, 10),
			Vector3.new(0, 3, -10),
		}
	do
		local block = MapKit.part(model, {
			name = "CloudBlock",
			size = Vector3.new(5, 6, 5),
			cframe = CFrame.new(offset),
			color = Color3.fromRGB(236, 239, 241),
			material = Enum.Material.SmoothPlastic,
		})
		makeProp(block, 160)
	end

	-- Breakable cloud-brick walls on the main island: knock holes for sightlines.
	for _, angle in { 0, math.pi / 2 } do
		MapKit.blockWall(
			model,
			CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, 17),
			4,
			2,
			Vector3.new(3, 2.5, 2),
			Color3.fromRGB(245, 245, 255),
			Enum.Material.SmoothPlastic,
			25,
			makeProp
		)
	end

	local spawns = MapKit.folder(model, "Spawns")
	-- Teams start on opposite islands (1 and 3).
	for i = 1, 4 do
		local offset = Vector3.new((i - 2.5) * 4, 3, 0)
		MapKit.spawn(spawns, `Team1_{i}`, satellites[1] + offset)
		MapKit.spawn(spawns, `Team2_{i}`, satellites[3] + offset)
	end

	local small = MapKit.folder(model, "SmallModeWalls")
	-- Small modes play on the main island plus the two team islands; glass
	-- domes close the other two so fights stay close.
	for _, i in { 2, 4 } do
		local center = satellites[i]
		MapKit.part(small, {
			name = "ClosedIsland",
			size = Vector3.new(32, 14, 32),
			cframe = CFrame.new(center + Vector3.new(0, 7, 0)),
			color = Color3.fromRGB(129, 212, 250),
			material = Enum.Material.Glass,
			transparency = 0.7,
		})
	end

	MapKit.bounds(model, Vector3.new(170, 90, 170), Vector3.new(0, 30, 0))
	return model
end
