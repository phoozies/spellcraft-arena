--!strict
-- All the game's sound, from the cue table (shared/Audio/Cues). Other
-- controllers ask for a cue by name (or a spell's cast/impact cue) and a
-- place in the world; this one makes the Sound, applies distance falloff,
-- throttles spam, and runs the hub's ambience loop.
--
-- Local only: every client plays its own copy of what the server announced.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Cues = require(ReplicatedStorage.Shared.Audio.Cues)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local SpellDefinitions = require(ReplicatedStorage.Shared.Spells.SpellDefinitions)
local ClientState = require(script.Parent.ClientState)

local AudioController = {}

-- Sounds farther than this from the camera aren't made at all.
local HEAR_DISTANCE = 260
local ROLLOFF_MIN = 14
local ROLLOFF_MAX = 220
-- Seconds before the same cue may play again (shattering walls fire dozens
-- of events at once). Anything not listed uses DEFAULT_GAP.
local DEFAULT_GAP = 0.05
local GAPS: { [string]: number } = { rockBreak = 0.35, hit = 0.12, turretShot = 0.15 }

local folder: Folder
local sfxGroup: SoundGroup
local ambientGroup: SoundGroup
local ambience: Sound? = nil
local lastPlayed: { [string]: number } = {}

local function makeGroup(name: string, volume: number): SoundGroup
	local group = Instance.new("SoundGroup")
	group.Name = name
	group.Volume = volume
	group.Parent = SoundService
	return group
end

-- Plays a cue. `at` places it in the world (cues with world = true); without
-- it the cue plays in the listener's ears.
function AudioController.play(cueName: string, at: Vector3?)
	local cue = Cues[cueName]
	if not cue or cue.id == "" or cue.loop then
		return
	end
	local now = os.clock()
	if now - (lastPlayed[cueName] or 0) < (GAPS[cueName] or DEFAULT_GAP) then
		return
	end
	lastPlayed[cueName] = now

	local sound = Instance.new("Sound")
	sound.SoundId = cue.id
	sound.Volume = cue.volume
	sound.PlaybackSpeed = (cue.pitch or 1) * (0.96 + math.random() * 0.08) -- a touch of variety
	sound.SoundGroup = sfxGroup
	local holder: Instance
	if cue.world and at then
		local camera = workspace.CurrentCamera
		if camera and (camera.CFrame.Position - at).Magnitude > HEAR_DISTANCE then
			sound:Destroy()
			return
		end
		local anchor = Instance.new("Part")
		anchor.Name = "SoundAnchor"
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.CanTouch = false
		anchor.Transparency = 1
		anchor.Size = Vector3.one * 0.2
		anchor.CFrame = CFrame.new(at)
		anchor.Parent = folder
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMinDistance = ROLLOFF_MIN
		sound.RollOffMaxDistance = ROLLOFF_MAX
		holder = anchor
	else
		holder = sound
	end
	sound.Parent = if holder == sound then folder else holder
	sound:Play()

	local function cleanup()
		if holder.Parent then
			holder:Destroy()
		end
	end
	if cue.length then
		-- Long recording, short moment: fade the tail out instead of cutting.
		local length = cue.length / (sound.PlaybackSpeed)
		task.delay(math.max(0, length - 0.2), function()
			if sound.Parent then
				TweenService:Create(sound, TweenInfo.new(0.2), { Volume = 0 }):Play()
			end
		end)
		Debris:AddItem(holder, length + 0.3)
	else
		sound.Ended:Connect(cleanup)
		Debris:AddItem(holder, 12)
	end
end

-- Plays a spell's own cue ("cast" or "impact") from SpellDefinitions.sfx.
function AudioController.playSpell(spellId: string, which: "cast" | "impact", at: Vector3?)
	local def = SpellDefinitions.get(spellId)
	local sfx = def and def.sfx
	local cueName = sfx and sfx[which]
	if cueName then
		AudioController.play(cueName, at)
	end
end

local function startAmbience()
	local cue = Cues.hubCrowd
	if not cue or cue.id == "" then
		return
	end
	local sound = Instance.new("Sound")
	sound.Name = "HubCrowd"
	sound.SoundId = cue.id
	sound.Looped = true
	sound.Volume = 0
	sound.SoundGroup = ambientGroup
	sound.Parent = SoundService
	sound:Play()
	ambience = sound
end

-- The hub murmurs with a distant arena crowd; matches are loud enough without it.
local function refreshAmbience()
	local sound = ambience
	local cue = Cues.hubCrowd
	if not sound or not cue then
		return
	end
	local target = if ClientState.match.phase == "Idle" then cue.volume else 0
	TweenService:Create(sound, TweenInfo.new(1.5), { Volume = target }):Play()
end

function AudioController.init()
	folder = Instance.new("Folder")
	folder.Name = "ClientAudio"
	folder.Parent = workspace
	sfxGroup = makeGroup("Wordcraft_Sfx", 1)
	ambientGroup = makeGroup("Wordcraft_Ambient", 1)
end

function AudioController.start()
	startAmbience()
	refreshAmbience()
	ClientState.MatchChanged:Connect(refreshAmbience)
	Remotes.get("GlyphResult").OnClientEvent:Connect(function(spellId: string?)
		AudioController.play(if spellId then "glyphGood" else "glyphBad")
	end)
end

return AudioController
