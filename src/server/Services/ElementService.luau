--!strict
-- Which elements a player owns and which one is equipped.
--
--   * The FIRST element is a free pick (ChooseElement from the Spellbook's
--     picker), any of the four.
--   * Every other element is unlocked from a crate (CrateService calls
--     ElementService.grant).
--   * Owned elements can be switched in the hub. In a match the element is
--     locked in: the equipped element's five spells are the match spellbook.
--
-- Owns profile.elements and profile.element (EconomyService only mirrors
-- them to the client in its profile summary).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Elements = require(ReplicatedStorage.Shared.Spells.Elements)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local EconomyService = require(script.Parent.EconomyService)
local PlayerDataService = require(script.Parent.PlayerDataService)

local ElementService = {}

-- Fired with (player) whenever their owned or equipped element changes.
ElementService.Changed = Signal.new() :: Signal.Signal<Player>

local toastRemote: RemoteEvent
-- Set by HandService: true while the player is locked into a match.
local lockCheck: ((Player) -> boolean)? = nil

function ElementService.setLockCheck(fn: (Player) -> boolean)
	lockCheck = fn
end

function ElementService.owned(player: Player): { string }
	local profile = PlayerDataService.get(player)
	return if profile then profile.elements else {}
end

function ElementService.owns(player: Player, elementId: string): boolean
	return table.find(ElementService.owned(player), elementId) ~= nil
end

-- The equipped element id, or nil before the first pick.
function ElementService.equipped(player: Player): string?
	local profile = PlayerDataService.get(player)
	if profile and profile.element ~= "" and Elements.get(profile.element) then
		return profile.element
	end
	return nil
end

-- Unlocks an element (and equips it when it's the player's first). Returns
-- false if they already had it or it doesn't exist. The caller sends the
-- profile summary when it wants the client to see it.
function ElementService.grant(player: Player, elementId: string): boolean
	local profile = PlayerDataService.get(player)
	if not profile or not Elements.get(elementId) or table.find(profile.elements, elementId) then
		return false
	end
	table.insert(profile.elements, elementId)
	if profile.element == "" then
		profile.element = elementId
	end
	ElementService.Changed:Fire(player)
	return true
end

-- Equips an owned element. Returns (ok, reason).
function ElementService.equip(player: Player, elementId: string): (boolean, string?)
	local profile = PlayerDataService.get(player)
	if not profile then
		return false, "Your spellbook is still loading."
	end
	if not Elements.get(elementId) then
		return false, "That element doesn't exist."
	end
	if lockCheck and lockCheck(player) then
		return false, "You can't change element during a match."
	end
	if not table.find(profile.elements, elementId) then
		return false, `You haven't unlocked {elementId} yet. Open an Element Crate in the hub!`
	end
	if profile.element ~= elementId then
		profile.element = elementId
		ElementService.Changed:Fire(player)
	end
	return true, nil
end

function ElementService.init()
	toastRemote = Remotes.get("Toast")
end

function ElementService.start()
	-- (elementId) -> picks the free first element, or equips an owned one.
	Remotes.get("ChooseElement").OnServerEvent:Connect(function(player, elementId)
		if typeof(elementId) ~= "string" or #elementId > 16 then
			return
		end
		local profile = PlayerDataService.get(player)
		if not profile or not Elements.get(elementId) then
			return
		end
		if #profile.elements == 0 then
			ElementService.grant(player, elementId)
			toastRemote:FireClient(player, `You chose {elementId}! Draw its shapes to cast.`, "reward")
		else
			local ok, reason = ElementService.equip(player, elementId)
			if not ok and reason then
				toastRemote:FireClient(player, reason, "fizzle")
				return
			end
			toastRemote:FireClient(player, `{elementId} equipped.`, "ready")
		end
		EconomyService.sendSummary(player)
	end)
end

return ElementService
