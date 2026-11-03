--!strict
-- Briefly swaps a hub prop for its "open" block model: a Chest Shop chest for
-- ShopChestOpen (tinted to its rarity) while the reel spins, the Daily Quests
-- chest for QuestChestOpen when a quest is claimed. Local and cosmetic; the
-- closed prop keeps its collision and prompt, and comes back when the time is
-- up. Does nothing when either model is missing.

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
-- `tint` recolours the open model's Chest_Trim and Chest_Gem parts and its glow.
function PropSwap.show(propName: string, openName: string, seconds: number, tint: Color3?)
	local prop = findProp(propName)
	if not prop or prop:GetAttribute("Swapped") then
		return
	end
	local open = ModelKit.clone(openName, "effect", prop:GetScale())
	if not open then
		return
	end
	if tint then
		for _, part in open:GetDescendants() do
			if part:IsA("BasePart") and (part.Name == "Chest_Trim" or part.Name == "Chest_Gem") then
				part.Color = tint
			end
		end
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
	light.Color = tint or Color3.fromRGB(255, 226, 140)
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
