--!strict
-- Custom join screen (ReplicatedFirst runs before anything else loads).
-- Shows the game title, a rotating tip, and a thin progress bar that fills as
-- the game loads, then fades into the hub. The same quiet look as the rest of
-- the UI (client/UI/Theme, which can't be loaded this early).

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer

ReplicatedFirst:RemoveDefaultLoadingScreen()

local TIPS = {
	"Press 1-5 and trace a shape: the spell flies where you look.",
	"Open a chest for new spells, then equip two of them in your loadout!",
	"Circle, slash, square, triangle, lightning, V, star: each shape is the same kind of move in every element.",
	"Star is your ultimate: big damage, long recharge.",
	"Win coins to buy new elements and open chests for rarer spells.",
	"Big, smooth shapes work best. Don't worry about drawing it perfectly!",
	"Look at your target first: the spell flies the moment you finish its shape.",
	"Your own spells fly through your Earth Wall, but enemy spells smash it block by block!",
	"After each round you pick a boost: more damage, health, speed, or faster spells.",
	"Change the draw key in Settings.",
}

local gui = Instance.new("ScreenGui")
gui.Name = "SpellcraftLoading"
gui.IgnoreGuiInset = true
gui.DisplayOrder = 100
gui.ResetOnSpawn = false

local back = Instance.new("Frame")
back.Size = UDim2.fromScale(1, 1)
back.BorderSizePixel = 0
back.BackgroundColor3 = Color3.fromRGB(16, 17, 22)
back.Parent = gui

local function label(text: string, y: number, height: number, color: Color3): TextLabel
	local l = Instance.new("TextLabel")
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.Position = UDim2.fromScale(0.5, y)
	l.Size = UDim2.new(0.8, 0, 0, height)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.BuilderSansBold
	l.TextScaled = true
	l.TextColor3 = color
	l.TextStrokeTransparency = 1
	l.Text = text
	l.Parent = back
	return l
end

label("Spellcraft Arena", 0.46, 40, Color3.fromRGB(240, 240, 243))
local tip = label(TIPS[math.random(1, #TIPS)], 0.53, 18, Color3.fromRGB(150, 152, 162))

local barBack = Instance.new("Frame")
barBack.AnchorPoint = Vector2.new(0.5, 0.5)
barBack.Position = UDim2.fromScale(0.5, 0.6)
barBack.Size = UDim2.new(0.2, 0, 0, 2)
barBack.BackgroundColor3 = Color3.fromRGB(36, 38, 46)
barBack.BorderSizePixel = 0
barBack.Parent = back
local barFill = Instance.new("Frame")
barFill.Size = UDim2.fromScale(0, 1)
barFill.BackgroundColor3 = Color3.fromRGB(232, 200, 120)
barFill.BorderSizePixel = 0
barFill.Parent = barBack

gui.Parent = player:WaitForChild("PlayerGui")

local start = os.clock()
local nextTip = start + 3
-- Done when the game is loaded and our HUD exists (client bootstrapped),
-- with a short minimum so the screen doesn't just flash.
while true do
	local loaded = game:IsLoaded() and player.PlayerGui:FindFirstChild("SpellcraftHud") ~= nil
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
