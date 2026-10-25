--!strict
-- All the game's sound, from the cue table (shared/Audio/Cues). Other
-- controllers ask for a cue by name (or a spell's cast/impact cue) and a
-- place in the world; this one makes the Sound, applies distance falloff,
-- throttles spam, runs the hub's ambience loop, and plays the background music
-- (a looping playlist per mood, muted by the Music setting).
--
-- Local only: every client plays its own copy of what the server announced.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Cues = require(ReplicatedStorage.Shared.Audio.Cues)
local Music = require(ReplicatedStorage.Shared.Audio.Music)
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
local musicGroup: SoundGroup
local musicSound: Sound? = nil
local musicMood: string? = nil
local musicIndex: { [string]: number } = { hub = 0, fight = 0 }
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
	for _, other in cue.with or {} do
		AudioController.play(other, at)
	end

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
		local length = cue.length / sound.PlaybackSpeed
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

-- Plays a looping cue (one marked `loop`, like the black hole's hum) from a
-- place in the world for `seconds`, fading in and out.
function AudioController.loop(cueName: string, at: Vector3, seconds: number)
	local cue = Cues[cueName]
	local camera = workspace.CurrentCamera
	if
		not cue
		or cue.id == ""
		or not cue.world
		or not camera
		or (camera.CFrame.Position - at).Magnitude > HEAR_DISTANCE
	then
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
	local sound = Instance.new("Sound")
	sound.SoundId = cue.id
	sound.Looped = true
	sound.Volume = 0
	sound.PlaybackSpeed = cue.pitch or 1
	sound.SoundGroup = sfxGroup
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = ROLLOFF_MIN
	sound.RollOffMaxDistance = ROLLOFF_MAX
	sound.Parent = anchor
	sound:Play()
	TweenService:Create(sound, TweenInfo.new(0.4), { Volume = cue.volume }):Play()
	task.delay(math.max(0, seconds - 0.4), function()
		if sound.Parent then
			TweenService:Create(sound, TweenInfo.new(0.4), { Volume = 0 }):Play()
		end
	end)
	Debris:AddItem(anchor, seconds + 0.1)
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

-- ---------------------------------------------------------------------
-- Background music
-- ---------------------------------------------------------------------

-- Music is on unless the player turned it off (profile.settings.music).
function AudioController.musicEnabled(): boolean
	local profile = ClientState.profile
	return not (profile and profile.settings and profile.settings.music == false)
end

local function fighting(): boolean
	return ClientState.match.phase ~= "Idle"
		or Players.LocalPlayer:GetAttribute("InBattleground") == true
end

local function fadeOutAndRemove(sound: Sound)
	local tween =
		TweenService:Create(sound, TweenInfo.new(Config.MUSIC.FADE_SECONDS), { Volume = 0 })
	tween.Completed:Once(function()
		sound:Destroy()
	end)
	tween:Play()
end

local playNext: (mood: "hub" | "fight") -> ()

playNext = function(mood)
	local list = Music.playlist(mood)
	if #list == 0 then
		return
	end
	musicIndex[mood] = musicIndex[mood] % #list + 1
	local track = list[musicIndex[mood]]
	local sound = Instance.new("Sound")
	sound.Name = "Music_" .. track.title
	sound.SoundId = track.id
	sound.Volume = 0
	sound.SoundGroup = musicGroup
	sound.Parent = SoundService
	musicSound = sound
	sound:Play()
	TweenService:Create(sound, TweenInfo.new(Config.MUSIC.FADE_SECONDS), { Volume = track.volume })
		:Play()
	-- On to the next track when this one ends, or when it never loads (a blocked asset).
	sound.Ended:Once(function()
		if musicSound == sound and musicMood == mood then
			playNext(mood)
		end
	end)
	task.delay(10, function()
		if musicSound == sound and not sound.IsLoaded then
			sound:Destroy()
			playNext(mood)
		end
	end)
end

-- Starts, switches, or stops the music to match the setting and where the
-- player is (hub tracks in the hub, fight tracks in matches and the Battleground).
local function refreshMusic()
	if not AudioController.musicEnabled() then
		if musicSound then
			fadeOutAndRemove(musicSound)
		end
		musicSound = nil
		musicMood = nil
		return
	end
	local mood: "hub" | "fight" = if fighting() then "fight" else "hub"
	if musicSound and musicMood == mood then
		return
	end
	if musicSound then
		fadeOutAndRemove(musicSound)
	end
	musicMood = mood
	playNext(mood)
end

function AudioController.init()
	folder = Instance.new("Folder")
	folder.Name = "ClientAudio"
	folder.Parent = workspace
	sfxGroup = makeGroup("Spellcraft_Sfx", 1)
	ambientGroup = makeGroup("Spellcraft_Ambient", 1)
	musicGroup = makeGroup("Spellcraft_Music", Config.MUSIC.VOLUME)
end

function AudioController.start()
	startAmbience()
	refreshAmbience()
	ClientState.MatchChanged:Connect(refreshAmbience)
	-- Music follows the setting and the player's whereabouts.
	ClientState.MatchChanged:Connect(refreshMusic)
	ClientState.ProfileChanged:Connect(refreshMusic)
	Players.LocalPlayer:GetAttributeChangedSignal("InBattleground"):Connect(refreshMusic)
	refreshMusic()
	Remotes.get("GlyphResult").OnClientEvent:Connect(function(spellId: string?)
		AudioController.play(if spellId then "glyphGood" else "glyphBad")
	end)
end

return AudioController
