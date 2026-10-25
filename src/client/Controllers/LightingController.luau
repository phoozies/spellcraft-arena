--!strict
-- The mood of the world. The hub is a sunlit arena (a warm late-afternoon sun
-- and a touch of glow); match arenas keep the server's neutral daylight so
-- fights are easy to read. This only changes the local player's Lighting, and
-- fades between the two when a match starts or ends.

local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local ClientState = require(script.Parent.ClientState)

local LightingController = {}

local FADE = 1.5

type Mood = {
	lighting: { [string]: any },
	atmosphere: { [string]: any },
	bloom: { [string]: any },
	color: { [string]: any },
}

local HUB: Mood = {
	lighting = {
		ClockTime = 15.5,
		Brightness = 2.8,
		Ambient = Color3.fromRGB(150, 146, 140),
		OutdoorAmbient = Color3.fromRGB(165, 160, 150),
		ExposureCompensation = 0.1,
	},
	atmosphere = {
		-- Thin air: duels are fought on arenas hundreds of studs below the island,
		-- and hub players should see them clearly.
		Density = 0.12,
		Offset = 0.1,
		Color = Color3.fromRGB(214, 226, 245),
		Decay = Color3.fromRGB(232, 208, 170),
		Glare = 0.2,
		Haze = 0.2,
	},
	bloom = { Intensity = 0.25, Size = 24, Threshold = 1.4 },
	color = { Saturation = 0.1, Contrast = 0.05, TintColor = Color3.fromRGB(255, 248, 235) },
}

local arena: Mood = {
	lighting = {},
	atmosphere = {},
	bloom = { Intensity = 0, Size = 24, Threshold = 2 },
	color = { Saturation = 0, Contrast = 0, TintColor = Color3.new(1, 1, 1) },
}

local atmosphere: Atmosphere
local bloom: BloomEffect
local colorCorrection: ColorCorrectionEffect
local current: "hub" | "arena" | nil = nil

local function ensure<T>(className: string): T
	local existing = Lighting:FindFirstChildOfClass(className)
	if existing then
		return existing :: any
	end
	local created = Instance.new(className)
	created.Parent = Lighting
	return created :: any
end

local function snapshot(instance: Instance, props: { [string]: any }): { [string]: any }
	local out = {}
	for name in props do
		out[name] = (instance :: any)[name]
	end
	return out
end

local function apply(instance: Instance, props: { [string]: any })
	TweenService:Create(instance, TweenInfo.new(FADE, Enum.EasingStyle.Sine), props):Play()
end

local function setMood(which: "hub" | "arena")
	if current == which then
		return
	end
	current = which
	local mood = if which == "hub" then HUB else arena
	apply(Lighting, mood.lighting)
	apply(atmosphere, mood.atmosphere)
	apply(bloom, mood.bloom)
	apply(colorCorrection, mood.color)
end

local function refresh()
	setMood(if ClientState.match.phase == "Idle" then "hub" else "arena")
end

function LightingController.init()
	atmosphere = ensure("Atmosphere")
	bloom = ensure("BloomEffect")
	colorCorrection = ensure("ColorCorrectionEffect")
	-- Whatever the server set is the arena's look; remember it to fade back.
	arena.lighting = snapshot(Lighting, HUB.lighting)
	arena.atmosphere = snapshot(atmosphere, HUB.atmosphere)
	if not Lighting:FindFirstChildOfClass("Sky") then
		Instance.new("Sky").Parent = Lighting
	end
	-- Start in the hub's night without a fade (players spawn there).
	for name, value in HUB.lighting do
		(Lighting :: any)[name] = value
	end
	for name, value in HUB.atmosphere do
		(atmosphere :: any)[name] = value
	end
	for name, value in HUB.bloom do
		(bloom :: any)[name] = value
	end
	for name, value in HUB.color do
		(colorCorrection :: any)[name] = value
	end
	current = "hub"
end

function LightingController.start()
	ClientState.MatchChanged:Connect(refresh)
	refresh()
end

return LightingController
