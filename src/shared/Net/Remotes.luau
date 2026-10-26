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
	DrawSpell = "(points: {Vector2}, spellId: string?) a stroke drawn on screen (screen-height units); the server recognizes it and scores how well it follows the shape. spellId = the spell card being traced",
	SelectSlot = "(slot: number) ready the spell in a hand slot (hotbar tap/keys)",
	CastSpell = "(target: Vector3, rotationY: number?) cast the readied spell at a point",
	PickDraft = "(index: number) choose one of the offered draft cards",
	SetQueue = "(mode: string?) join a queue by mode name, or leave with nil",
	ClaimQuest = "(questId: string) claim a finished daily quest",
	OpenCrate = "(crateId: string) buy and spin a Spell Crate; server validates coins + rate",
	ChooseElement = "(elementId: string) pick your free first element, or equip one you own",
	BuyElement = "(elementId: string) buy another base element with coins",
	SetLoadout = "(slot: number, spellId: string?) put an owned crate spell in loadout slot 1 or 2, or empty the slot with nil; the server checks ownership and that its shape is not already in your loadout",
	TutorialDone = "() the first-join tutorial was finished or skipped; saved so it never shows again",
	SaveSettings = "(key: string, value: string | boolean) save a player setting: drawKey (a key name), or music / sfx / shake (boolean)",
	LeaveBattleground = "() leave the Battleground and return to the hub",
	Dash = "(direction: Vector3?) dash the way the player is heading (their move direction); the server checks the cooldown and state",
	MapVote = "(mapName: string) your pick in the pre-match map vote (duels); can be changed until the vote closes",
	PartyAction = "(action: string, userId: number?) party intent: invite / accept / decline / kick take a userId, leave takes none",
	AdminCommand = "(text: string) run an admin command from the admin panel (the ; prefix is optional); ignored unless the server says you are an admin",
	DebugCommand = "(command: string, arg: any) Studio-only test helpers",

	-- Server -> Client
	HandUpdated = "(hand: {string}, readiedSlot: number?, spellbook: {string}?, qualities: {number}) your spell copies, which slot is readied, and how well each was drawn",
	CooldownStarted = "(spellId: string, endsAt: number)",
	DashStarted = "(endsAt: number, direction: Vector3) the dash was allowed: go that way now; the dash can be used again at endsAt (server time)",
	MapVoteState = "(state: {mode, maps: {{id, name, votes}}, myPick: string?, endsAt: number}?) the open map vote and its tally; nil closes it",
	PartyState = "(state: {leaderId: number?, members: {{userId, name}}, invites: {{userId, name, secondsLeft}}}) your party and pending invites",
	Toast = "(message: string, kind: string) short on-screen notification",
	AdminLog = "(message: string) a command's result, shown in the admin panel's log (admins only)",
	MatchStateChanged = "(state: MatchState) phase, timer, scores",
	DraftOffered = "(cards: {DraftCard}, endsAt: number)",
	ProfileUpdated = "(summary: {coins, elements, element, spells, loadout, tutorial, quests, streak, stats, settings, rewards: {likeFav, likeReadyAt}})",
	CrateOpened = "(result: CrateResult) the spell a crate spin landed on (client animates the reel)",
	QueueCounts = "(counts: {[mode]: number}) live players waiting per mode",
	Knockout = "(killerName: string?, victimName: string, spellName: string?) kill feed",
	Impulse = "(velocity: Vector3, hold: number?) self-beneficial boost (dash, pads, rescue arcs) applied by the owning client; hold makes it an arc: the velocity follows the launch under gravity for that many seconds",
	Fx = "(kind: string, ...) cosmetic effects rendered by clients: projectile spawn/end, poof, glyph, ...",
	GlyphResult = "(spellId: string?, glyphId: string?, quality: number?) what the player's drawing was (nil = not recognized) and how well it followed the shape (0..1)",
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
