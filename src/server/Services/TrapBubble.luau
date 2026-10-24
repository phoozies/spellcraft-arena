--!strict
-- The glassy bubble that wraps a player caught by a crowd-control spell.
-- With an imported model (Water Lock -> "WaterBubble") the bubble is that
-- coloured model, welded to the victim; otherwise a plain translucent orb.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ModelKit = require(ReplicatedStorage.Shared.ModelKit)

local TrapBubble = {}

local function weldTo(root: BasePart, part: BasePart)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = part
	weld.Part1 = root
	weld.Parent = part
end

function TrapBubble.show(character: Model, duration: number, color: Color3, modelName: string?)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	if modelName then
		-- The bubble should wrap the character: scale it to ~1.6x the root height.
		local bubble = ModelKit.clone(modelName, "attached")
		if bubble then
			local _, size = bubble:GetBoundingBox()
			local scale = (character:GetExtentsSize().Y * 1.5) / size.Y
			bubble:ScaleTo(scale)
			bubble:PivotTo(root.CFrame)
			bubble.Parent = character
			for _, part in bubble:GetDescendants() do
				if part:IsA("BasePart") then
					weldTo(root, part)
				end
			end
			Debris:AddItem(bubble, duration)
			return
		end
	end

	local orb = Instance.new("Part")
	orb.Shape = Enum.PartType.Ball
	orb.Size = Vector3.new(7, 7, 7)
	orb.Color = color
	orb.Material = Enum.Material.Glass
	orb.Transparency = 0.55
	orb.CanCollide = false
	orb.CanQuery = false
	orb.Massless = true
	orb.CFrame = root.CFrame
	weldTo(root, orb)
	orb.Parent = character
	Debris:AddItem(orb, duration)
end

return TrapBubble
