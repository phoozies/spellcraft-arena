--!strict
-- Access to the game's 3D models. Two sources, checked in this order:
--   1. ReplicatedStorage.Models: imported, coloured meshes stored in the place
--      (see tools/prepare-models.luau and assets/models/README.md). They live
--      in the place file, not the Rojo project, so they may be missing.
--   2. Models/BlockModels: the classic blocky models (generated from the
--      Blender spec in tools/blender/block_models.py), built from plain Parts
--      the first time they're asked for. These exist in every place.
-- A name in neither returns nil, and every caller must fall back to plain
-- shapes in that case.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BlockModels = require(script.Parent.Models.BlockModels)

local ModelKit = {}

local built: { [string]: Model } = {}

local function color(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function vector(v: { number }): Vector3
	return Vector3.new(v[1], v[2], v[3])
end

-- Builds a BlockModels entry into a model centered on its origin. A `vfx`
-- model also gets an invisible "Root" part (particles and trails hang on it).
local function build(name: string): Model?
	local spec = BlockModels[name]
	if not spec then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = name
	for _, part in spec.parts do
		local p = Instance.new("Part")
		p.Name = part.n
		p.Size = vector(part.s)
		local rotation = part.r
		local cframe = CFrame.new(vector(part.p))
		if rotation then
			cframe *= CFrame.fromEulerAnglesYXZ(
				math.rad(rotation[1]),
				math.rad(rotation[2]),
				math.rad(rotation[3])
			)
		end
		p.CFrame = cframe
		p.Color = color(part.c)
		p.Material = (Enum.Material :: any)[part.m]
		p.Transparency = part.t or 0
		if part.sh == "Ball" then
			p.Shape = Enum.PartType.Ball
		elseif part.sh == "Cylinder" then
			p.Shape = Enum.PartType.Cylinder
		end
		p.Anchored = true
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		local collides = if part.k ~= nil then part.k else spec.solid
		p.CanCollide = collides
		p.CanQuery = collides
		p.CanTouch = false
		p.CastShadow = spec.solid
		p.Massless = true
		p.Parent = model
	end
	model.WorldPivot = CFrame.new()
	if spec.vfx then
		local root = Instance.new("Part")
		root.Name = "Root"
		root.Size = Vector3.one * 0.2
		root.Transparency = 1
		root.Anchored = true
		root.CanCollide = false
		root.CanQuery = false
		root.CanTouch = false
		root.Parent = model
		model.PrimaryPart = root
	end
	return model
end

-- The stored model (do not parent or modify it; use clone), or nil.
function ModelKit.get(name: string): Model?
	local folder = ReplicatedStorage:FindFirstChild("Models")
	local model = folder and folder:FindFirstChild(name)
	if model and model:IsA("Model") then
		return model
	end
	local cached = built[name]
	if not cached then
		cached = build(name)
		if cached then
			built[name] = cached
		end
	end
	return cached
end

-- True when the model is a classic block model built from BlockModels rather
-- than an imported mesh from the place.
function ModelKit.isBlock(name: string): boolean
	return BlockModels[name] ~= nil
end

-- A fresh copy, optionally scaled (uniformly, about its pivot), with every
-- part set up for the given use:
--   "effect"   anchored, no collision/queries/touch (client visuals)
--   "solid"    anchored, collides and can be hit (walls, arenas, scenery)
--   "attached" unanchored + massless, no collision (rides on a character;
--              the caller welds it)
function ModelKit.clone(name: string, use: "effect" | "solid" | "attached", scale: number?): Model?
	local source = ModelKit.get(name)
	if not source then
		return nil
	end
	local model = source:Clone()
	if scale and math.abs(scale - 1) > 0.001 then
		model:ScaleTo(scale)
	end
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = use ~= "attached"
			part.Massless = true
			part.CanTouch = false
			-- "solid" keeps the collision settings baked in (prepare-models, or
			-- the part's own `k` flag in BlockModels).
			if use ~= "solid" then
				part.CanCollide = false
				part.CanQuery = false
			end
		end
	end
	return model
end

-- Every block-model name (for tests and the spell registry).
function ModelKit.blockNames(): { string }
	local names = {}
	for name in BlockModels do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

return ModelKit
