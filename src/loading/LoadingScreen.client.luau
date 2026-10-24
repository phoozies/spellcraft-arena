--!strict
-- Custom join screen (ReplicatedFirst runs before anything else loads).
-- Shows the game title, a bouncing spell glyph, a rotating tip, and a
-- progress bar that fills as the game loads, then fades into the hub.

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer

ReplicatedFirst:RemoveDefaultLoadingScreen()

local TIPS = {
	"Type a spell word to get it — you can hold up to 5!",
	"Copies of the same spell share one cooldown.",
	"Water Lock, then Lightning = double damage!",
	"Rock Walls break block by block. Knock a hole and fire through!",
	"No health regen in the arena — bring a Heal Leaf.",
	"Change the type-a-spell key in Settings.",
}

local gui = Instance.new("ScreenGui")
gui.Name = "WordcraftLoading"
gui.IgnoreGuiInset = true
gui.DisplayOrder = 100
gui.ResetOnSpawn = false

local back = Instance.new("Frame")
back.Size = UDim2.fromScale(1, 1)
back.BorderSizePixel = 0
back.BackgroundColor3 = Color3.fromRGB(20, 18, 40)
back.Parent = gui
local gradient = Instance.new("UIGradient")
gradient.Rotation = 90
gradient.Color = ColorSequence.new(Color3.fromRGB(60, 50, 120), Color3.fromRGB(15, 12, 30))
gradient.Parent = back

local function label(text: string, y: number, height: number, color: Color3): TextLabel
	local l = Instance.new("TextLabel")
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.Position = UDim2.fromScale(0.5, y)
	l.Size = UDim2.new(0.8, 0, 0, height)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne
	l.TextScaled = true
	l.TextColor3 = color
	l.Text = text
	l.Parent = back
	return l
end

local glyph = label("★", 0.3, 90, Color3.fromRGB(255, 202, 40))
label("WORDCRAFT ARENA", 0.45, 70, Color3.new(1, 1, 1))
local tip = label(TIPS[math.random(1, #TIPS)], 0.62, 28, Color3.fromRGB(197, 202, 233))

local barBack = Instance.new("Frame")
barBack.AnchorPoint = Vector2.new(0.5, 0.5)
barBack.Position = UDim2.fromScale(0.5, 0.72)
barBack.Size = UDim2.new(0.4, 0, 0, 14)
barBack.BackgroundColor3 = Color3.fromRGB(40, 36, 70)
barBack.BorderSizePixel = 0
barBack.Parent = back
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0.5, 0)
corner.Parent = barBack
local barFill = Instance.new("Frame")
barFill.Size = UDim2.fromScale(0, 1)
barFill.BackgroundColor3 = Color3.fromRGB(255, 202, 40)
barFill.BorderSizePixel = 0
barFill.Parent = barBack
corner:Clone().Parent = barFill

gui.Parent = player:WaitForChild("PlayerGui")

-- Bounce the glyph and cycle tips while we wait.
local bounce = TweenService:Create(
	glyph,
	TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
	{ Position = UDim2.fromScale(0.5, 0.27), Rotation = 15 }
)
bounce:Play()

local start = os.clock()
local nextTip = start + 3
-- Done when the game is loaded and our HUD exists (client bootstrapped),
-- with a short minimum so the screen doesn't just flash.
while true do
	local loaded = game:IsLoaded() and player.PlayerGui:FindFirstChild("WordcraftHud") ~= nil
	local elapsed = os.clock() - start
	local progress = if loaded then 1 else math.min(0.9, elapsed / 6)
	barFill.Size = UDim2.fromScale(progress, 1)
	if os.clock() > nextTip then
		nextTip = os.clock() + 3
		tip.Text = TIPS[math.random(1, #TIPS)]
	end
	if loaded and elapsed > 1.5 then
		break
	end
	if elapsed > 30 then
		break -- never trap players behind the loading screen
	end
	task.wait(0.1)
end

bounce:Cancel()
local fadeInfo = TweenInfo.new(0.6)
TweenService:Create(back, fadeInfo, { BackgroundTransparency = 1 }):Play()
for _, d in back:GetDescendants() do
	if d:IsA("TextLabel") then
		TweenService:Create(d, fadeInfo, { TextTransparency = 1 }):Play()
	elseif d:IsA("Frame") then
		TweenService:Create(d, fadeInfo, { BackgroundTransparency = 1 }):Play()
	end
end
task.wait(0.7)
gui:Destroy()
