--!strict
-- Briefly swaps a hub prop for its "open" block model: the Element Crate for
-- ElementCrateOpen while a crate spins, the Daily Quests chest for
-- QuestChestOpen when a quest is claimed. Local and cosmetic; the closed prop
-- keeps its collision and prompt, and comes back when the time is up. Does
-- nothing when either model is missing.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ModelKit = require(ReplicatedStorage.Shared.ModelKit)

local PropSwap = {}

-- The named model somewhere in the workspace (the hub is built at runtime).
local function findProp(name: string): Model?
	local found = workspace:FindFirstChild(name, true)
	return if found and found:IsA("Model") then found else nil
end

-- Shows `openName` in place of the model called `propName` for `seconds`.
function PropSwap.show(propName: string, openName: string, seconds: number)
	local prop = findProp(propName)
	if not prop or prop:GetAttribute("Swapped") then
		return
	end
	local open = ModelKit.clone(openName, "effect", prop:GetScale())
	if not open then
		return
	end
	prop:SetAttribute("Swapped", true)
	open:PivotTo(prop:GetPivot())
	open.Parent = prop.Parent

	-- Hide the closed one (and remember what to bring back).
	local hidden: { [BasePart]: number } = {}
	for _, part in prop:GetDescendants() do
		if part:IsA("BasePart") and part.Transparency < 1 then
			hidden[part] = part.Transparency
			part.Transparency = 1
		end
	end
	-- A warm glow from the open lid.
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 226, 140)
	light.Range = 14
	light.Brightness = 2
	light.Parent = open.PrimaryPart or open:FindFirstChildWhichIsA("BasePart")

	Debris:AddItem(open, seconds)
	task.delay(seconds, function()
		for part, transparency in hidden do
			if part.Parent then
				part.Transparency = transparency
			end
		end
		if prop.Parent then
			prop:SetAttribute("Swapped", nil)
		end
	end)
end

return PropSwap
