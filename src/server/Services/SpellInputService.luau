--!strict
-- Drawing a spell: the client sends the stroke it drew (DrawSpell remote),
-- the server decides what it is.
--
--   DrawSpell(points, spellId?, aim, rotationY?) ──► validate (table of Vector2,
--   count, range, 1s cooldown) ──► GlyphRecognizer (only the shapes the player
--   can draw) ──► the spell drawn with that shape ──► CastService.cast at once,
--   at the point under their crosshair (nothing is ever stored or clicked)
--   ──► GlyphResult(spellId?, glyphId?, quality?) back to the drawer for feedback,
--   and Fx "glyph" (cast) or "glyphFail" (fizzled) to everyone, so the stroke
--   they watched being drawn in the air (WandService relays it) lands or crumbles
--
-- Quality: the recognizer's score for the stroke becomes a 0..1 quality
-- (Spells/Quality); the better the stroke follows the shape, the stronger the
-- cast. A client that tapped a spell's card sends that `spellId` as the shape
-- it is tracing: the stroke must be THAT spell's shape (any other shape
-- fizzles); without it, any of the player's shapes is accepted.
--
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
local GlyphRecognizer = require(ReplicatedStorage.Shared.Spells.GlyphRecognizer)
local Quality = require(ReplicatedStorage.Shared.Spells.Quality)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local SpellDefinitions = require(ReplicatedStorage.Shared.Spells.SpellDefinitions)
local CastService = require(script.Parent.CastService)
local SpellbookService = require(script.Parent.SpellbookService)
local TelemetryService = require(script.Parent.TelemetryService)

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

-- Tells the drawer their drawing failed, and everyone that its stroke in the
-- air crumbles.
local function reject(player: Player, glyphId: string?)
	resultRemote:FireClient(player, nil, glyphId)
	local character = player.Character
	if character then
		fxRemote:FireAllClients("glyphFail", character)
	end
end

-- Recognizes a stroke and casts the spell at `aim`. Returns the cast spell id.
function SpellInputService.submitStroke(
	player: Player,
	points: { Vector2 },
	targetId: string?,
	aim: any,
	rotationY: any
): string?
	-- The cooldown comes first: every refusal below is broadcast to all clients.
	local left = SpellInputService.drawCooldownLeft(player)
	if left > 0 then
		toastRemote:FireClient(player, `Draw again in {math.ceil(left * 10) / 10}s`, "error")
		return nil
	end
	lastDraw[player] = os.clock()
	if drawGate then
		local allowed, reason = drawGate(player)
		if not allowed then
			toastRemote:FireClient(player, reason or "You can't draw right now.", "error")
			reject(player)
			return nil
		end
	end

	-- Only the shapes of the player's spells are ever recognized (a loadout
	-- never repeats a shape), so look-alike shapes can't be confused with them.
	local loadout = SpellbookService.drawable(player)
	if #loadout == 0 then
		toastRemote:FireClient(player, "Pick your first element in the Spellbook!", "error")
		reject(player)
		return nil
	end
	local spellByGlyph: { [string]: string } = {}
	local allowed: { [string]: boolean } = {}
	for _, id in loadout do
		local candidate = SpellDefinitions.get(id)
		if candidate then
			spellByGlyph[candidate.glyph] = candidate.id
			allowed[candidate.glyph] = true
		end
	end
	local target = if targetId then SpellDefinitions.get(targetId) else nil
	if target and not table.find(loadout, target.id) then
		target = nil -- not one of your spells: treated as a free drawing
	end
	local glyphId, score = GlyphRecognizer.recognize(points, allowed)
	local spellId = if glyphId then spellByGlyph[glyphId] else nil
	if spellId and target and spellId ~= target.id then
		-- Drew a different shape than the one on the card.
		toastRemote:FireClient(player, `That isn't a {target.name}. Follow the shape!`, "error")
		reject(player, glyphId)
		return nil
	end
	if not spellId then
		local hints = Config.FIZZLE_HINTS
		toastRemote:FireClient(player, hints[math.random(1, #hints)], "error")
		reject(player)
		return nil
	end
	local quality = Quality.fromScore(score)
	local ok, message = CastService.cast(player, spellId, aim, rotationY, quality)
	if not ok then
		toastRemote:FireClient(player, message or "Fizzle!", "error")
		reject(player, glyphId)
		return nil
	end
	TelemetryService.onboarding(player, "FirstSpellDrawn")
	local def = SpellDefinitions.get(spellId)
	resultRemote:FireClient(player, spellId, glyphId, quality)
	-- Everyone nearby sees the glyph traced in the air by the caster's wand
	-- and pulled into it (Fx/WandVfx), coloured by how well it was drawn.
	local character = player.Character
	if def and character then
		fxRemote:FireAllClients("glyph", character, def.glyph, def.visual.color, quality)
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
	Remotes.get("DrawSpell").OnServerEvent:Connect(function(player, raw, targetId, aim, rotationY)
		local points = sanitize(raw)
		if points then
			SpellInputService.submitStroke(
				player,
				points,
				if typeof(targetId) == "string" then targetId else nil,
				aim,
				rotationY
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
