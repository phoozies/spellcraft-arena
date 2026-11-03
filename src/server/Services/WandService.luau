--!strict
-- Every player's wand. Welds the "Wand" block model (Config.WAND.MODEL,
-- Models/BlockModels) to the right hand whenever a character spawns, tints its
-- crystal tip and runes with the equipped element's colour (and again when the
-- element changes), and keeps the character's "Drawing" attribute: true while
-- that player's drawing canvas is open (DrawingState remote), with "DrawLook"
-- the way they face. Every client reads them to raise the wand and open a
-- magic circle in the air in front of them (WandController).
--
-- Live strokes (AirStroke remote): while the canvas is open the drawer's
-- client sends its stroke as air-canvas studs; this checks it (canvas open,
-- batch size, point range, rate, a cap per stroke) and relays it to the
-- players near enough to see it, so everyone watches the shape being drawn.
--
-- Cosmetic only. The wand never decides anything: SpellInputService still
-- recognizes every drawing, and the wand's parts can't collide, be hit, or be
-- touched. Without the block model a plain stick with a glowing ball is used.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Elements = require(ReplicatedStorage.Shared.Spells.Elements)
local ModelKit = require(ReplicatedStorage.Shared.ModelKit)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local WandAir = require(ReplicatedStorage.Shared.Util.WandAir)
local ElementService = require(script.Parent.ElementService)

local WandService = {}

-- Parts of the wand that take the element colour.
local TINTED = { Tip = true, TipGlow = true, Rune = true }

local lastOn: { [Player]: number } = setmetatable({}, { __mode = "k" }) :: any

-- A live stroke being relayed: points sent so far, and a small bucket of
-- batches (refilled one per Config.WAND.STROKE_RATE seconds, up to BURST) so
-- the last batch can follow the one before it closely.
type Stroke = { count: number, tokens: number, lastBatch: number }
local strokes: { [Player]: Stroke } = {}
local lastBegin: { [Player]: number } = {}
local airRemote: RemoteEvent

local STROKE_KINDS = { begin = true, points = true, ["end"] = true, cancel = true }
-- Least seconds between two strokes starting.
local BEGIN_RATE = 0.15
local BURST = 3

-- The colour of a player's wand: their element's, or Arcane purple before
-- they have picked one.
function WandService.colorFor(player: Player): Color3
	local element = ElementService.equipped(player)
	if element and Elements.get(element) then
		return Elements.color(element)
	end
	return Elements.ARCANE.color
end

-- A plain wand for a place without the block model: a stick and a glowing tip.
local function fallbackWand(): Model
	local model = Instance.new("Model")
	model.Name = Config.WAND.MODEL
	local shaft = Instance.new("Part")
	shaft.Name = "Shaft"
	shaft.Size = Vector3.new(0.28, 0.28, 3.2)
	shaft.CFrame = CFrame.new(0, 0, -1.2)
	shaft.Color = Color3.fromRGB(150, 100, 62)
	shaft.Material = Enum.Material.Wood
	shaft.Parent = model
	local tip = Instance.new("Part")
	tip.Name = "Tip"
	tip.Shape = Enum.PartType.Ball
	tip.Size = Vector3.one * 0.5
	tip.CFrame = CFrame.new(0, 0, -2.95)
	tip.Material = Enum.Material.Neon
	tip.Parent = model
	model.WorldPivot = CFrame.new()
	for _, part in model:GetChildren() do
		local p = part :: BasePart
		p.Anchored = false
		p.Massless = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
	end
	return model
end

-- Recolours the tinted parts of a character's wand.
local function tint(wand: Instance, color: Color3)
	for _, part in wand:GetDescendants() do
		if part:IsA("BasePart") and TINTED[part.Name] then
			part.Color = color
		end
	end
end

-- Gives a character its wand (replacing any old one).
function WandService.equip(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	local isR15 = humanoid.RigType == Enum.HumanoidRigType.R15
	local hand = character:WaitForChild(if isR15 then "RightHand" else "Right Arm", 10)
	if not hand or not hand:IsA("BasePart") or not character.Parent then
		return
	end
	local old = character:FindFirstChild(Config.WAND.MODEL)
	if old then
		old:Destroy()
	end
	local wand = ModelKit.clone(Config.WAND.MODEL, "attached") or fallbackWand()
	wand.Name = Config.WAND.MODEL
	wand:PivotTo(hand.CFrame * WandAir.grip(isR15, hand.Size))
	for _, part in wand:GetDescendants() do
		if part:IsA("BasePart") then
			part.CastShadow = false
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = hand
			weld.Part1 = part
			weld.Parent = part
		end
	end
	tint(wand, WandService.colorFor(player))
	wand.Parent = character
end

-- Sets the character's Drawing attribute from the client's DrawingState.
-- Opening is rate limited; closing is always accepted, so the wand never
-- stays raised by mistake.
local function onDrawingState(player: Player, on: any, look: any)
	if typeof(on) ~= "boolean" then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character then
		return
	end
	if not on then
		character:SetAttribute("Drawing", nil)
		strokes[player] = nil
		return
	end
	local now = os.clock()
	if now - (lastOn[player] or 0) < Config.WAND.DRAW_STATE_RATE then
		return
	end
	lastOn[player] = now
	if humanoid and humanoid.Health > 0 then
		local root = character:FindFirstChild("HumanoidRootPart")
		local fallback = if root and root:IsA("BasePart") then root.CFrame.LookVector else nil
		character:SetAttribute("DrawLook", WandAir.cleanLook(look) or fallback)
		character:SetAttribute("Drawing", true)
	end
end

-- Sends a stroke message (data: the points of a batch, or the colour a stroke
-- begins in) to every other player whose character is near the drawer's.
local function relay(player: Player, character: Model, kind: string, data: any)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	for _, other in Players:GetPlayers() do
		local otherCharacter = other.Character
		local otherRoot = otherCharacter and otherCharacter:FindFirstChild("HumanoidRootPart")
		if
			other ~= player
			and otherRoot
			and otherRoot:IsA("BasePart")
			and (otherRoot.Position - root.Position).Magnitude <= Config.WAND.RELAY_RANGE
		then
			airRemote:FireClient(other, character, kind, data)
		end
	end
end

-- AirStroke: a piece of the live stroke. Only while the canvas is open; a
-- stroke has to begin before its points are relayed.
local function onAirStroke(player: Player, kind: any, raw: any)
	if typeof(kind) ~= "string" or not STROKE_KINDS[kind] then
		return
	end
	local character = player.Character
	if not character then
		return
	end
	local now = os.clock()
	if kind == "begin" then
		if
			character:GetAttribute("Drawing") ~= true
			or now - (lastBegin[player] or 0) < BEGIN_RATE
		then
			return
		end
		lastBegin[player] = now
		strokes[player] = { count = 0, tokens = BURST, lastBatch = now }
		relay(player, character, "begin", if typeof(raw) == "Color3" then raw else nil)
		return
	end
	local stroke = strokes[player]
	if not stroke then
		return
	end
	if kind == "points" then
		stroke.tokens =
			math.min(BURST, stroke.tokens + (now - stroke.lastBatch) / Config.WAND.STROKE_RATE)
		stroke.lastBatch = now
		if character:GetAttribute("Drawing") ~= true or stroke.tokens < 1 then
			return
		end
		local points = WandAir.cleanPoints(raw, Config.WAND.STROKE_BATCH)
		if not points or stroke.count + #points > Config.WAND.STROKE_MAX_POINTS then
			return
		end
		stroke.count += #points
		stroke.tokens -= 1
		relay(player, character, "points", points)
	else
		-- "end" (sent to be recognized) or "cancel" (thrown away).
		strokes[player] = nil
		relay(player, character, kind)
	end
end

function WandService.start()
	local function watch(player: Player)
		player.CharacterAdded:Connect(function(character)
			task.spawn(WandService.equip, player, character)
		end)
		if player.Character then
			task.spawn(WandService.equip, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastOn[player] = nil
		strokes[player] = nil
		lastBegin[player] = nil
	end)

	ElementService.Changed:Connect(function(player)
		local wand = player.Character and player.Character:FindFirstChild(Config.WAND.MODEL)
		if wand then
			tint(wand, WandService.colorFor(player))
		end
	end)

	Remotes.get("DrawingState").OnServerEvent:Connect(onDrawingState)
	airRemote = Remotes.get("AirStroke")
	airRemote.OnServerEvent:Connect(onAirStroke)
end

return WandService
