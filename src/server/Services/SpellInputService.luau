--!strict
-- Every way a player can "say" a spell funnels into SpellInputService.submit():
--   * Chat: a chat message that is exactly a spell word is consumed (not
--     broadcast) and readies that spell.
--   * The on-screen spell box (SubmitWord remote) — works with on-screen
--     keyboards on mobile, console, and VR.
--   * Voice (VoiceService calls submit with source "voice").
-- Rate limited per player across all sources.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local SpellDefinitions = require(ReplicatedStorage.Shared.Spells.SpellDefinitions)
local WordMatcher = require(ReplicatedStorage.Shared.Spells.WordMatcher)
local HandService = require(script.Parent.HandService)

local SpellInputService = {}

local toastRemote: RemoteEvent
local recent: { [Player]: { number } } = {}

local function allow(player: Player): boolean
	local now = os.clock()
	local list = recent[player] or {}
	recent[player] = list
	while list[1] and now - list[1] > 1 do
		table.remove(list, 1)
	end
	if #list >= Config.WORD_RATE_PER_SECOND then
		return false
	end
	table.insert(list, now)
	return true
end

-- Returns the spell id that was readied, or nil.
function SpellInputService.submit(player: Player, text: string, source: "chat" | "box" | "voice"): string?
	if not allow(player) then
		return nil
	end
	local spellId = if source == "voice" then WordMatcher.findInText(text) else WordMatcher.matchWord(text)
	if not spellId then
		if source ~= "chat" then
			local hints = Config.FIZZLE_HINTS
			toastRemote:FireClient(player, hints[math.random(1, #hints)], "fizzle")
		end
		return nil
	end
	local ok, reason = HandService.ready(player, spellId)
	if not ok then
		toastRemote:FireClient(player, reason or "Fizzle!", "fizzle")
		return nil
	end
	local def = SpellDefinitions.get(spellId)
	if def then
		toastRemote:FireClient(player, `{def.name} ready!`, "ready")
	end
	return spellId
end

local function hookChat()
	if TextChatService.ChatVersion ~= Enum.ChatVersion.TextChatService then
		warn("[SpellInput] Legacy chat detected; chat casting disabled (spell box and voice still work).")
		return
	end
	local channels = TextChatService:WaitForChild("TextChannels", 30)
	local general = channels and channels:WaitForChild("RBXGeneral", 30)
	if not general or not general:IsA("TextChannel") then
		warn("[SpellInput] RBXGeneral channel not found; chat casting disabled.")
		return
	end
	-- ShouldDeliverCallback runs once per recipient, so de-dupe by MessageId.
	local handled: { [string]: boolean } = {}
	general.ShouldDeliverCallback = function(message: TextChatMessage, _target: TextSource)
		local source = message.TextSource
		if not source then
			return true
		end
		local isSpell = WordMatcher.matchWord(message.Text) ~= nil
		if not handled[message.MessageId] then
			handled[message.MessageId] = true
			task.delay(10, function()
				handled[message.MessageId] = nil
			end)
			local player = Players:GetPlayerByUserId(source.UserId)
			if player and isSpell then
				task.spawn(SpellInputService.submit, player, message.Text, "chat")
			end
		end
		return not isSpell
	end
end

function SpellInputService.init()
	toastRemote = Remotes.get("Toast")
end

function SpellInputService.start()
	Remotes.get("SubmitWord").OnServerEvent:Connect(function(player, text)
		if typeof(text) ~= "string" or #text == 0 or #text > 64 then
			return
		end
		SpellInputService.submit(player, text, "box")
	end)
	Players.PlayerRemoving:Connect(function(player)
		recent[player] = nil
	end)
	task.spawn(hookChat)
end

return SpellInputService
