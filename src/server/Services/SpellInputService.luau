--!strict
-- Every way a player can "say" a spell funnels into SpellInputService.submit():
--   * Chat: a chat message that is exactly a spell word is consumed (not
--     broadcast) and grants that spell.
--   * The on-screen spell box (SubmitWord remote) — works with on-screen
--     keyboards on mobile, console, and VR. Pasting is blocked client-side.
--   * Voice (VoiceService calls submit with source "voice").
--
-- A word adds ONE copy of the spell to the hotbar (HandService.grant; up to
-- 5 copies, duplicates allowed). Words are limited to one per
-- Config.TYPE_COOLDOWN seconds per player across all sources.
--
-- Messages starting with Config.ADMIN_PREFIX go to the admin command handler
-- (AdminService installs it) instead, from chat or the spell box.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local SpellDefinitions = require(ReplicatedStorage.Shared.Spells.SpellDefinitions)
local WordMatcher = require(ReplicatedStorage.Shared.Spells.WordMatcher)
local HandService = require(script.Parent.HandService)

type Source = "chat" | "box" | "voice"

local SpellInputService = {}

local toastRemote: RemoteEvent
local lastWord: { [Player]: number } = {}
local noTypeCooldown: { [Player]: boolean } = {}

-- (player, text) -> handled. Installed by AdminService; returns true when
-- the player is an admin and the text was a command. Must not yield (it runs
-- inside ShouldDeliverCallback); the handler defers the actual work.
local commandHandler: ((Player, string) -> boolean)? = nil

function SpellInputService.setCommandHandler(handler: (Player, string) -> boolean)
	commandHandler = handler
end

local function isCommand(text: string): boolean
	return string.sub(text, 1, #Config.ADMIN_PREFIX) == Config.ADMIN_PREFIX
end

-- Admin: skip the typing cooldown for a player.
function SpellInputService.setNoTypeCooldown(player: Player, enabled: boolean)
	noTypeCooldown[player] = if enabled then true else nil
end

-- Seconds until this player may type another word.
function SpellInputService.typeCooldownLeft(player: Player): number
	if noTypeCooldown[player] then
		return 0
	end
	return math.max(0, (lastWord[player] or 0) + Config.TYPE_COOLDOWN - os.clock())
end

-- Returns the spell id that was granted, or nil.
function SpellInputService.submit(player: Player, text: string, source: Source): string?
	local left = SpellInputService.typeCooldownLeft(player)
	if left > 0 then
		toastRemote:FireClient(player, `Typing cooldown ({math.ceil(left * 10) / 10}s)`, "cooldown")
		return nil
	end
	lastWord[player] = os.clock()

	local spellId = if source == "voice"
		then WordMatcher.findInText(text)
		else WordMatcher.matchWord(text)
	if not spellId then
		local hints = Config.FIZZLE_HINTS
		toastRemote:FireClient(player, hints[math.random(1, #hints)], "fizzle")
		return nil
	end
	local ok, message = HandService.grant(player, spellId)
	if not ok then
		toastRemote:FireClient(player, message or "Fizzle!", "fizzle")
		return nil
	end
	local def = SpellDefinitions.get(spellId)
	if def then
		local held = 0
		for _, id in HandService.getCopies(player) do
			if id == spellId then
				held += 1
			end
		end
		toastRemote:FireClient(
			player,
			`+1 {def.name}!` .. (if held > 1 then ` (x{held})` else ""),
			"ready"
		)
	end
	return spellId
end

local function runCommand(player: Player, text: string): boolean
	return commandHandler ~= nil and commandHandler(player, text)
end

local function hookChat()
	if TextChatService.ChatVersion ~= Enum.ChatVersion.TextChatService then
		warn(
			"[SpellInput] Legacy chat detected; chat casting disabled (spell box and voice still work)."
		)
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
		local player = Players:GetPlayerByUserId(source.UserId)
		local command = player ~= nil and isCommand(message.Text)
		local isSpell = not command and WordMatcher.matchWord(message.Text) ~= nil
		if not handled[message.MessageId] then
			handled[message.MessageId] = true
			task.delay(10, function()
				handled[message.MessageId] = nil
				handled[message.MessageId .. ":cmd"] = nil
			end)
			if player and command then
				-- Non-admins' ";..." messages are delivered as normal chat.
				command = runCommand(player, message.Text)
				handled[message.MessageId .. ":cmd"] = command
			elseif player and isSpell then
				task.spawn(SpellInputService.submit, player, message.Text, "chat")
			end
		elseif command then
			command = handled[message.MessageId .. ":cmd"] == true
		end
		return not (isSpell or command)
	end
end

function SpellInputService.init()
	toastRemote = Remotes.get("Toast")
end

function SpellInputService.start()
	Remotes.get("SubmitWord").OnServerEvent:Connect(function(player, text)
		if typeof(text) ~= "string" or #text == 0 or #text > 120 then
			return
		end
		if isCommand(text) and runCommand(player, text) then
			return
		end
		if #text > 64 then
			return
		end
		SpellInputService.submit(player, text, "box")
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastWord[player] = nil
		noTypeCooldown[player] = nil
	end)
	task.spawn(hookChat)
end

return SpellInputService
