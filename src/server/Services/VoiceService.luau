--!strict
-- Speak-a-spell using AudioSpeechToText. The client holds a push-to-talk
-- button (VoiceListen remote); while held, the player's AudioDeviceInput is
-- wired into a per-player AudioSpeechToText and transcripts are matched
-- with WordMatcher.findInText.
--
-- Requirements (Game Settings > Communication): microphone input enabled
-- and the new audio API. If AudioSpeechToText is unavailable, the feature
-- disables itself and the client hides the mic button.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local SpellInputService = require(script.Parent.SpellInputService)

local VoiceService = {}

type Session = { stt: Instance, wire: Instance, connection: RBXScriptConnection }

local sessions: { [Player]: Session } = {}
local available = false
local heardRemote: RemoteEvent

local function findDeviceInput(player: Player): Instance?
	return player:FindFirstChildWhichIsA("AudioDeviceInput", true)
end

local function stop(player: Player)
	local session = sessions[player]
	if session then
		sessions[player] = nil
		session.connection:Disconnect()
		session.wire:Destroy()
		session.stt:Destroy()
	end
end

local function begin(player: Player)
	if sessions[player] then
		return
	end
	local input = findDeviceInput(player)
	if not input then
		return
	end
	local ok, stt = pcall(Instance.new, "AudioSpeechToText")
	if not ok then
		return
	end
	local wire = Instance.new("Wire")
	wire.SourceInstance = input
	wire.TargetInstance = stt
	wire.Parent = stt
	stt.Parent = input
	local connection = stt:GetPropertyChangedSignal("Text"):Connect(function()
		local text = (stt :: any).Text :: string
		if text and #text > 0 then
			heardRemote:FireClient(player, string.sub(text, 1, 80))
			SpellInputService.submit(player, text, "voice")
		end
	end)
	sessions[player] = { stt = stt, wire = wire, connection = connection }
	pcall(function()
		(stt :: any).Enabled = true
	end)
	-- AudioSpeechToText stops on its own after ~10s; mirror that here.
	task.delay(10, function()
		if sessions[player] and sessions[player].stt == stt then
			stop(player)
		end
	end)
end

function VoiceService.init()
	heardRemote = Remotes.get("VoiceHeard")
	local ok = pcall(function()
		local probe = Instance.new("AudioSpeechToText")
		probe:Destroy()
	end)
	available = ok
	ReplicatedStorage:SetAttribute("VoiceSpellsEnabled", available)
	if not available then
		warn("[VoiceService] AudioSpeechToText unavailable; voice spells disabled.")
	end
end

function VoiceService.start()
	Remotes.get("VoiceListen").OnServerEvent:Connect(function(player, listening)
		if not available or typeof(listening) ~= "boolean" then
			return
		end
		if listening then
			begin(player)
		else
			-- Give the recognizer a moment to finish the last word, but don't
			-- end a newer session started by a quick re-press.
			local session = sessions[player]
			task.delay(0.6, function()
				if session and sessions[player] == session then
					stop(player)
				end
			end)
		end
	end)
	Players.PlayerRemoving:Connect(stop)
end

return VoiceService
