--!strict
-- Drawing a spell: the client sends the stroke it drew (DrawSpell remote),
-- the server decides what it is.
--
--   DrawSpell(points, spellId?) ──► validate (table of Vector2, count, range, 1s cooldown)
--   ──► GlyphRecognizer (only the equipped element's five shapes) ──► the
--   spell drawn with that shape ──► HandService.grant (hotbar copy; only the equipped
--   element's spells work, in the hub and in matches)
--   ──► GlyphResult(spellId?, glyphId?, quality?) back to the drawer for feedback
--
-- Quality: the recognizer's score for the stroke becomes a 0..1 quality
-- (Spells/Quality) stored on the copy; the better the stroke follows the
-- shape, the stronger the cast (CastService). A client that tapped a spell's
-- card sends that `spellId` as the shape it is tracing: the stroke must be
-- THAT spell's shape (any other shape fizzles); without it, any of the
-- equipped element's shapes is accepted.
--
-- A drawing adds ONE copy of the spell to the hotbar (one copy per spell).
-- Drawings are limited to one per Config.DRAW_COOLDOWN seconds, and only
-- allowed in fights: during a match's rounds and in the Battleground (MatchService
-- installs the rule with setDrawGate; not in the hub, and not while a match counts down).
--
-- Chat is no longer a way to cast: messages starting with Config.ADMIN_PREFIX
-- go to the admin command handler (AdminService installs it); everything else
-- is normal chat.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Config = require(ReplicatedStorage.Shared.Config)
local Elements = require(ReplicatedStorage.Shared.Spells.Elements)
local GlyphRecognizer = require(ReplicatedStorage.Shared.Spells.GlyphRecognizer)
local Quality = require(ReplicatedStorage.Shared.Spells.Quality)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local SpellDefinitions = require(ReplicatedStorage.Shared.Spells.SpellDefinitions)
local ElementService = require(script.Parent.ElementService)
local HandService = require(script.Parent.HandService)

local SpellInputService = {}

local toastRemote: RemoteEvent
local resultRemote: RemoteEvent
local fxRemote: RemoteEvent
local lastDraw: { [Player]: number } = {}
local noDrawCooldown: { [Player]: boolean } = {}

-- (player) -> (allowed, reason). Installed by MatchService.
local drawGate: ((Player) -> (boolean, string?))? = nil

function SpellInputService.setDrawGate(gate: (Player) -> (boolean, string?))
	drawGate = gate
end

-- Per element: shape -> the spell drawn with it. Only an element's own five
-- shapes are ever recognized, so look-alike shapes can't be confused with them.
local SPELL_BY_GLYPH: { [string]: { [string]: string } } = {}
local ALLOWED: { [string]: { [string]: boolean } } = {}
for _, element in Elements.LIST do
	local byGlyph: { [string]: string } = {}
	local allowed: { [string]: boolean } = {}
	for _, id in element.spells do
		local def = SpellDefinitions.get(id)
		if def then
			byGlyph[def.glyph] = def.id
			allowed[def.glyph] = true
		end
	end
	SPELL_BY_GLYPH[element.id] = byGlyph
	ALLOWED[element.id] = allowed
end

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

-- Admin: skip the drawing cooldown for a player.
function SpellInputService.setNoDrawCooldown(player: Player, enabled: boolean)
	noDrawCooldown[player] = if enabled then true else nil
end

-- Seconds until this player may draw another spell.
function SpellInputService.drawCooldownLeft(player: Player): number
	if noDrawCooldown[player] then
		return 0
	end
	return math.max(0, (lastDraw[player] or 0) + Config.DRAW_COOLDOWN - os.clock())
end

-- Returns a clean list of Vector2 from untrusted remote data, or nil.
local function sanitize(raw: any): { Vector2 }?
	if
		typeof(raw) ~= "table"
		or #raw > Config.DRAW_MAX_POINTS
		or #raw < GlyphRecognizer.MIN_POINTS
	then
		return nil
	end
	local limit = Config.DRAW_MAX_COORD
	local points: { Vector2 } = {}
	for i = 1, #raw do
		local p = raw[i]
		if typeof(p) ~= "Vector2" then
			return nil
		end
		-- NaN/inf and far-off-screen values are rejected outright.
		if p.X ~= p.X or p.Y ~= p.Y or math.abs(p.X) > limit or math.abs(p.Y) > limit then
			return nil
		end
		points[i] = p
	end
	return points
end

-- Recognizes a stroke and readies the spell. Returns the granted spell id.
function SpellInputService.submitStroke(
	player: Player,
	points: { Vector2 },
	targetId: string?
): string?
	if drawGate then
		local allowed, reason = drawGate(player)
		if not allowed then
			toastRemote:FireClient(player, reason or "You can't draw right now.", "fizzle")
			resultRemote:FireClient(player, nil, nil)
			return nil
		end
	end
	local left = SpellInputService.drawCooldownLeft(player)
	if left > 0 then
		toastRemote:FireClient(player, `Draw again in {math.ceil(left * 10) / 10}s`, "cooldown")
		return nil
	end
	lastDraw[player] = os.clock()

	local elementId = ElementService.equipped(player)
	local element = if elementId then Elements.get(elementId) else nil
	if not element then
		toastRemote:FireClient(player, "Pick your first element in the Spellbook!", "fizzle")
		resultRemote:FireClient(player, nil, nil)
		return nil
	end
	local target = if targetId then SpellDefinitions.get(targetId) else nil
	if target and target.element ~= element.id then
		target = nil -- not one of your spells: treated as a free drawing
	end
	local glyphId, score = GlyphRecognizer.recognize(points, ALLOWED[element.id])
	local spellId = if glyphId then SPELL_BY_GLYPH[element.id][glyphId] else nil
	if spellId and target and spellId ~= target.id then
		-- Drew a different shape than the one on the card.
		toastRemote:FireClient(player, `That isn't a {target.name}. Follow the shape!`, "fizzle")
		resultRemote:FireClient(player, nil, glyphId)
		return nil
	end
	if not spellId then
		local hints = Config.FIZZLE_HINTS
		toastRemote:FireClient(player, hints[math.random(1, #hints)], "fizzle")
		resultRemote:FireClient(player, nil, nil)
		return nil
	end
	local quality = Quality.fromScore(score)
	local ok, message = HandService.grant(player, spellId, nil, quality)
	if not ok then
		toastRemote:FireClient(player, message or "Fizzle!", "fizzle")
		resultRemote:FireClient(player, nil, glyphId)
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
			`+1 {def.name}! {Quality.tier(quality).name}` .. (if held > 1 then ` (x{held})` else ""),
			"ready"
		)
	end
	resultRemote:FireClient(player, spellId, glyphId, quality)
	-- Everyone nearby sees the glyph pop up over the caster's head.
	local character = player.Character
	if def and character then
		fxRemote:FireAllClients("glyph", character, def.glyph, def.visual.color)
	end
	return spellId
end

local function hookChat()
	if TextChatService.ChatVersion ~= Enum.ChatVersion.TextChatService then
		warn("[SpellInput] Legacy chat detected; admin chat commands disabled.")
		return
	end
	local channels = TextChatService:WaitForChild("TextChannels", 30)
	local general = channels and channels:WaitForChild("RBXGeneral", 30)
	if not general or not general:IsA("TextChannel") then
		warn("[SpellInput] RBXGeneral channel not found; admin chat commands disabled.")
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
		if not handled[message.MessageId] then
			handled[message.MessageId] = true
			task.delay(10, function()
				handled[message.MessageId] = nil
				handled[message.MessageId .. ":cmd"] = nil
			end)
			if player and command then
				-- Non-admins' ";..." messages are delivered as normal chat.
				command = commandHandler ~= nil and commandHandler(player, message.Text)
				handled[message.MessageId .. ":cmd"] = command
			end
		elseif command then
			command = handled[message.MessageId .. ":cmd"] == true
		end
		return not command
	end
end

function SpellInputService.init()
	toastRemote = Remotes.get("Toast")
	resultRemote = Remotes.get("GlyphResult")
	fxRemote = Remotes.get("Fx")
end

function SpellInputService.start()
	Remotes.get("DrawSpell").OnServerEvent:Connect(function(player, raw, targetId)
		local points = sanitize(raw)
		if points then
			SpellInputService.submitStroke(
				player,
				points,
				if typeof(targetId) == "string" then targetId else nil
			)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastDraw[player] = nil
		noDrawCooldown[player] = nil
	end)
	task.spawn(hookChat)
end

return SpellInputService
