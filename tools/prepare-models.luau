-- Run in Studio's command bar (Edit mode) right after File > Import 3D of the
-- FBX files in assets/models. It turns each raw imported model in Workspace
-- into a game-ready one in ReplicatedStorage.Models:
--   * scaled from FBX units (hundreds of studs) to game size
--   * pivot moved to the model's center (the arena: the center of its floor top)
--   * every part coloured / given a material / transparency
--   * collision on for solid models (wall, arena), off for effects
--   * VFX models get an invisible "Root" part (particles/trails attach to it)
-- The originals are removed from Workspace. Safe to re-run: only models that
-- are still in Workspace are processed, and an existing prepared copy of the
-- same name is replaced.
--
-- The game code (FxController, Placeable, Control, HubService) clones these
-- from ReplicatedStorage.Models and falls back to plain shapes if missing.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local M = Enum.Material

local SPECS = {
	Fireball = {
		width = 4.2, -- studs, along X of the whole model
		vfx = true,
		parts = {
			Fireball_Core = { color = rgb(255, 238, 160), material = M.Neon },
			Fireball_Outer = { color = rgb(255, 112, 32), material = M.Neon, transparency = 0.2 },
			Fireball_Tail = { color = rgb(255, 64, 20), material = M.Neon, transparency = 0.35 },
		},
	},
	WaterBubble = {
		width = 7.5, -- the size it wraps a trapped player; scaled down for the bolt
		vfx = true,
		parts = {
			Bubble_Shell = { color = rgb(120, 200, 255), material = M.Glass, transparency = 0.5, reflectance = 0.15 },
			Bubble_Inner = { color = rgb(30, 120, 230), material = M.SmoothPlastic, transparency = 0.68 },
			Bubble_Highlight = { color = rgb(255, 255, 255), material = M.Neon, transparency = 0.2 },
		},
	},
	RockWall = {
		width = 14.4,
		solid = true,
		parts = {
			Wall_Base = { color = rgb(104, 80, 58), material = M.Ground },
			Wall_Pillars = { color = rgb(168, 130, 92), material = M.Sandstone },
			Wall_Rubble = { color = rgb(128, 104, 82), material = M.Pebble },
		},
	},
	Arena = {
		measurePart = "Arena_Floor", -- width is the floor's X size
		width = 46,
		floorPivot = "Arena_Floor", -- pivot = center of the floor's top face
		solid = true,
		parts = {
			Arena_Floor = { color = rgb(88, 84, 100), material = M.Slate, collisionFidelity = Enum.CollisionFidelity.Box },
			Arena_Pillars = { color = rgb(240, 232, 220), material = M.Marble },
			Arena_RuneRing = { color = rgb(124, 92, 255), material = M.Neon, noCollide = true },
			Arena_Seating = { color = rgb(222, 200, 160), material = M.Sandstone },
		},
	},
	Grimoire = {
		width = 3,
		solid = false,
		parts = {
			Grimoire_Cover = { color = rgb(96, 44, 128), material = M.Fabric },
			Grimoire_Pages = { color = rgb(250, 240, 214), material = M.SmoothPlastic },
			Grimoire_Gold = { color = rgb(255, 200, 60), material = M.Metal, reflectance = 0.2 },
			Grimoire_Gem = { color = rgb(0, 226, 255), material = M.Neon },
		},
	},
}

local MIN = 0.001

local folder = ReplicatedStorage:FindFirstChild("Models")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "Models"
	folder.Parent = ReplicatedStorage
end

local report = {}
for name, spec in SPECS do
	local model = workspace:FindFirstChild(name)
	if not model or not model:IsA("Model") then
		table.insert(report, `{name}: not in Workspace, skipped`)
		continue
	end

	local box, size = model:GetBoundingBox()
	local measure = size.X
	local pivot = box.Position
	if spec.measurePart then
		local part = model:FindFirstChild(spec.measurePart) :: BasePart
		measure = part.Size.X
	end
	if spec.floorPivot then
		local floor = model:FindFirstChild(spec.floorPivot) :: BasePart
		pivot = Vector3.new(box.Position.X, floor.Position.Y + floor.Size.Y / 2, box.Position.Z)
	end
	local s = spec.width / measure

	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			local style = spec.parts[part.Name]
			local rotation = part.CFrame.Rotation
			local offset = (part.Position - pivot) * s
			part.Anchored = true
			part.Size = Vector3.new(
				math.max(part.Size.X * s, MIN),
				math.max(part.Size.Y * s, MIN),
				math.max(part.Size.Z * s, MIN)
			)
			part.CFrame = CFrame.new(offset) * rotation
			if style then
				part.Color = style.color
				part.Material = style.material
				part.Transparency = style.transparency or 0
				part.Reflectance = style.reflectance or 0
				if style.collisionFidelity then
					(part :: any).CollisionFidelity = style.collisionFidelity
				end
			end
			local solid = spec.solid and not (style and style.noCollide)
			part.CanCollide = solid == true
			part.CanQuery = solid == true
			part.CanTouch = false
			part.CastShadow = spec.solid == true
			part.Massless = true
		end
	end
	model.WorldPivot = CFrame.new()
	model.PrimaryPart = nil

	if spec.vfx then
		local root = Instance.new("Part")
		root.Name = "Root"
		root.Size = Vector3.one * 0.2
		root.Transparency = 1
		root.Anchored = true
		root.CanCollide = false
		root.CanQuery = false
		root.CanTouch = false
		root.CFrame = CFrame.new()
		root.Parent = model
		model.PrimaryPart = root
	end

	local old = folder:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	model.Parent = folder
	local _, newSize = model:GetBoundingBox()
	table.insert(report, `{name}: scale {string.format("%.4f", s)} -> {string.format("%.1f x %.1f x %.1f", newSize.X, newSize.Y, newSize.Z)} studs`)
end

print("[prepare-models]\n" .. table.concat(report, "\n"))
