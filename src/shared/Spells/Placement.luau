--!strict
-- Placement rules shared by the client ghost preview and the server, so the
-- preview's green/red always agrees with what the server will accept.

local Types = require(script.Parent.Parent.Types)

local Placement = {}

-- Cylinders in Roblox are aligned to the X axis. Visuals whose X is the
-- smallest dimension are flat discs (pads, puddles) and get stood upright.
function Placement.isDisc(visual: Types.Visual): boolean
	return visual.shape == "Cylinder" and visual.size.X < visual.size.Y
end

-- Height of the object once placed (used to rest it on the ground).
function Placement.height(visual: Types.Visual): number
	if Placement.isDisc(visual) then
		return visual.size.X
	end
	return visual.size.Y
end

-- Bounding box of the placed object, in its own placed orientation.
function Placement.boundsSize(visual: Types.Visual): Vector3
	if Placement.isDisc(visual) then
		return Vector3.new(visual.size.Y, visual.size.X, visual.size.Z)
	end
	return visual.size
end

-- World CFrame for an object resting on `groundPoint`, turned by `rotationY` radians.
function Placement.cframeFor(visual: Types.Visual, groundPoint: Vector3, rotationY: number): CFrame
	local base = CFrame.new(groundPoint + Vector3.new(0, Placement.height(visual) / 2, 0))
		* CFrame.Angles(0, rotationY, 0)
	return base
end

-- Orientation applied to the part itself (on top of cframeFor) so discs lie flat.
function Placement.partOffset(visual: Types.Visual): CFrame
	if Placement.isDisc(visual) then
		return CFrame.Angles(0, 0, math.pi / 2)
	end
	return CFrame.identity
end

-- True when nothing solid overlaps the object's footprint. The box is shrunk
-- slightly so resting on the ground or touching a neighbor is allowed.
function Placement.isClear(visual: Types.Visual, cframe: CFrame, ignore: { Instance }): boolean
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.RespectCanCollide = true
	local bounds = Placement.boundsSize(visual)
	local size = Vector3.new(bounds.X * 0.85, math.max(bounds.Y * 0.85 - 0.3, 0.05), bounds.Z * 0.85)
	local hits = workspace:GetPartBoundsInBox(cframe, size, params)
	return #hits == 0
end

-- True when the point sits inside one of the region parts (XZ footprint, generous Y).
function Placement.inRegions(point: Vector3, regions: { BasePart }): boolean
	for _, region in regions do
		local localPoint = region.CFrame:PointToObjectSpace(point)
		local half = region.Size / 2
		if math.abs(localPoint.X) <= half.X and math.abs(localPoint.Z) <= half.Z and math.abs(localPoint.Y) <= half.Y then
			return true
		end
	end
	return false
end

return Placement
