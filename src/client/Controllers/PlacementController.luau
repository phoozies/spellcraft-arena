--!strict
-- Ghost preview for placeable spells. While a Placeable spell is readied a
-- translucent copy follows the aim point, tinted green (valid) or red
-- (blocked / out of range / outside the build area). It uses the exact
-- rules the server uses (shared Spells/Placement), so green means it will
-- succeed.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Placement = require(ReplicatedStorage.Shared.Spells.Placement)
local SpellDefinitions = require(ReplicatedStorage.Shared.Spells.SpellDefinitions)
local Types = require(ReplicatedStorage.Shared.Types)
local Theme = require(script.Parent.Parent.UI.Theme)
local ClientState = require(script.Parent.ClientState)
local HudController = require(script.Parent.HudController)

local player = Players.LocalPlayer

local PlacementController = {}

local ghost: Part? = nil
local highlight: Highlight? = nil
local ghostSpell: string? = nil
local rotation = 0
local groundPoint: Vector3? = nil
local valid = false
local rotateButton: TextButton

-- Set by InputController: returns the world point the player is aiming at.
local aimProvider: (() -> (Vector3?, Instance?))? = nil

function PlacementController.setAimProvider(fn: () -> (Vector3?, Instance?))
	aimProvider = fn
end

function PlacementController.isActive(): boolean
	return ghost ~= nil
end

function PlacementController.getPlacement(): (Vector3?, number, boolean)
	return groundPoint, rotation, valid
end

function PlacementController.rotate(step: number)
	rotation = (rotation + step) % (2 * math.pi)
end

function PlacementController.getGhost(): Instance?
	return ghost
end

local function clear()
	if ghost then
		ghost:Destroy()
	end
	ghost, highlight, ghostSpell, groundPoint = nil, nil, nil, nil
	rotateButton.Visible = false
end

local function makeGhost(visual: Types.Visual)
	local part = Instance.new("Part")
	part.Name = "PlacementGhost"
	part.Shape = if visual.shape == "Ball"
		then Enum.PartType.Ball
		elseif visual.shape == "Cylinder" then Enum.PartType.Cylinder
		elseif visual.shape == "Wedge" then Enum.PartType.Wedge
		else Enum.PartType.Block
	part.Size = visual.size
	part.Color = visual.color
	part.Material = Enum.Material.SmoothPlastic
	part.Transparency = 0.55
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	local h = Instance.new("Highlight")
	h.FillTransparency = 0.6
	h.OutlineTransparency = 0
	h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	h.Parent = part
	-- Local-only part (created on the client), so other players never see it.
	part.Parent = workspace
	ghost, highlight = part, h
	rotateButton.Visible = UserInputService.TouchEnabled
end

local function regions(): { BasePart }
	local list = {}
	for _, zone in CollectionService:GetTagged("BuildZone") do
		if zone:IsA("BasePart") then
			table.insert(list, zone)
		end
	end
	for _, model in workspace:GetChildren() do
		if model:IsA("Model") and string.sub(model.Name, 1, 5) == "Arena" then
			local bounds = model:FindFirstChild("Bounds")
			if bounds and bounds:IsA("BasePart") then
				table.insert(list, bounds)
			end
		end
	end
	return list
end

local function update()
	local id = ClientState.readied
	local def = id and SpellDefinitions.get(id)
	if not def or def.archetype ~= "Placeable" then
		if ghost then
			clear()
		end
		return
	end
	if ghostSpell ~= id then
		clear()
		makeGhost(def.visual)
		ghostSpell = id
	end
	local part = ghost :: Part
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local point = if aimProvider then aimProvider() else nil
	if not root or not point then
		part.Transparency = 1
		valid = false
		return
	end

	-- Clamp to placement range, then drop to the ground like the server does.
	local offset = point - root.Position
	if offset.Magnitude > Config.PLACE_RANGE then
		point = root.Position + offset.Unit * Config.PLACE_RANGE
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character :: Model, part }
	local down = workspace:Raycast((point :: Vector3) + Vector3.new(0, 6, 0), Vector3.new(0, -40, 0), params)
	if not down then
		part.Transparency = 1
		valid = false
		return
	end
	groundPoint = down.Position
	local cframe = Placement.cframeFor(def.visual, down.Position, rotation)
	part.CFrame = cframe * Placement.partOffset(def.visual)
	part.Transparency = 0.55

	local ignore: { Instance } = { part }
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(ignore, other.Character)
		end
	end
	valid = Placement.inRegions(down.Position, regions()) and Placement.isClear(def.visual, cframe, ignore)
	local left = ClientState.cooldownLeft(def.id)
	local color = if valid and left <= 0 then Theme.COLORS.good else Theme.COLORS.bad
	part.Color = color
	if highlight then
		highlight.FillColor = color
		highlight.OutlineColor = color
	end
end

function PlacementController.init()
	local root = HudController.getGui():WaitForChild("Root")
	rotateButton = Theme.button(root, "⟳", {
		Name = "Rotate",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -150, 1, -150),
		Size = UDim2.fromOffset(64, 64),
		Visible = false,
	})
	rotateButton.Activated:Connect(function()
		PlacementController.rotate(math.pi / 4)
	end)
end

function PlacementController.start()
	RunService.RenderStepped:Connect(update)
end

return PlacementController
