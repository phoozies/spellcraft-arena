--!strict
-- Access to the imported, coloured 3D models stored in the place under
-- ReplicatedStorage.Models (see tools/prepare-models.luau and
-- assets/models/README.md). The models live in the place file, not in the
-- Rojo project, so they may be missing (e.g. in a place built by CI). Every
-- caller must therefore fall back to plain shapes when `get` returns nil.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ModelKit = {}

-- The stored model (do not parent or modify it; use clone), or nil.
function ModelKit.get(name: string): Model?
	local folder = ReplicatedStorage:FindFirstChild("Models")
	local model = folder and folder:FindFirstChild(name)
	if model and model:IsA("Model") then
		return model
	end
	return nil
end

-- A fresh copy, optionally scaled (uniformly, about its pivot), with every
-- part set up for the given use:
--   "effect"   anchored, no collision/queries/touch (client visuals)
--   "solid"    anchored, collides and can be hit (walls, arenas)
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
			-- "solid" keeps the collision settings baked in by prepare-models.
			if use ~= "solid" then
				part.CanCollide = false
				part.CanQuery = false
			end
		end
	end
	return model
end

return ModelKit
