--!strict
-- Single source of truth for every remote in the game. The server creates
-- them (Remotes.setup()) and clients wait for them (Remotes.get(name)).
--
-- Client -> Server payloads are NEVER trusted: every handler re-validates
-- types, ranges, ownership, and rate limits (see roblox-security skill).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "Remotes"

-- name -> description (documentation lives next to the definition).
local DEFINITIONS: { [string]: string } = {
	-- Client -> Server
	DrawSpell = "(points: {Vector2}) a stroke drawn on screen (screen-height units); the server recognizes it",
	SelectSlot = "(slot: number) ready the spell in a hand slot (hotbar tap/keys)",
	CastSpell = "(target: Vector3, rotationY: number?) cast the readied spell at a point",
	PickDraft = "(index: number) choose one of the offered draft cards",
	SetQueue = "(mode: string?) join a queue by mode name, or leave with nil",
	ClaimQuest = "(questId: string) claim a finished daily quest",
	OpenCrate = "(crateId: string) buy and spin a crate (a Rarity name); server validates coins + rate",
	SaveSettings = "(key: string, value: string) save a player setting, e.g. drawKey",
	DebugCommand = "(command: string, arg: any) Studio-only test helpers",

	-- Server -> Client
	HandUpdated = "(hand: {string}, readied: string?) your spells and which one is readied",
	CooldownStarted = "(spellId: string, endsAt: number)",
	Toast = "(message: string, kind: string) short on-screen notification",
	MatchStateChanged = "(state: MatchState) phase, timer, scores",
	DraftOffered = "(cards: {DraftCard}, endsAt: number)",
	ProfileUpdated = "(summary: {coins, ownedSpells, quests, streak, stats, settings})",
	CrateOpened = "(result: CrateResult) the spell a crate spin landed on (client animates the reel)",
	QueueCounts = "(counts: {[mode]: number}) live players waiting per mode",
	Knockout = "(killerName: string?, victimName: string, spellName: string?) kill feed",
	Impulse = "(velocity: Vector3) self-beneficial boost (dash, pads) applied by the owning client",
	Fx = "(kind: string, ...) cosmetic effects rendered by clients: projectile spawn/end, poof, glyph, ...",
	GlyphResult = "(spellId: string?, glyphId: string?) what the player's drawing was (nil = not recognized)",
}

local Remotes = {}

function Remotes.setup()
	assert(RunService:IsServer(), "Remotes.setup() is server-only")
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end
	for name in DEFINITIONS do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
end

function Remotes.get(name: string): RemoteEvent
	assert(DEFINITIONS[name], `unknown remote "{name}"`)
	local folder = ReplicatedStorage:WaitForChild(FOLDER_NAME)
	return folder:WaitForChild(name) :: RemoteEvent
end

return Remotes
