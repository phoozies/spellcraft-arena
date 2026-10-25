--!strict
-- The Training Grove: the one place in the hub where spells can be drawn and
-- cast. The hub builder tags its volume "PracticeZone" (tags replicate), and
-- both the server (MatchService.canDraw) and the client (ClientState.canDraw)
-- ask this module whether a point is inside it.

local CollectionService = game:GetService("CollectionService")

local PracticeZone = {}

PracticeZone.TAG = "PracticeZone"

-- True when `position` is inside any tagged zone volume.
function PracticeZone.contains(position: Vector3): boolean
	for _, zone in CollectionService:GetTagged(PracticeZone.TAG) do
		if zone:IsA("BasePart") then
			local p = zone.CFrame:PointToObjectSpace(position)
			local half = zone.Size / 2
			if math.abs(p.X) <= half.X and math.abs(p.Y) <= half.Y and math.abs(p.Z) <= half.Z then
				return true
			end
		end
	end
	return false
end

return PracticeZone
