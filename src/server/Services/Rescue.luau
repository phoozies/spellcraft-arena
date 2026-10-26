--!strict
-- Gets players out of places they should not be stuck in, during a match:
--
--   * Water: every arena has water under it (ArenaService). Falling into it
--     costs a splash of damage and a short stun, then throws the player in an arc
--     back onto their team's spawn pad (Config.RESCUE.WATER_*).
--   * Pits: terrain cells can be shot away, which can leave a hole with walls on
--     every side that a jump cannot clear. A player who stands in one for
--     Config.RESCUE.PIT_SECONDS is thrown out over the nearest rim, or put back on
--     the spawn pad when that rim is too high (Config.RESCUE.PIT_*).
--
-- Movement that only helps its owner is applied by their own client
-- (DestructibleService.boost), like dashes and jump pads. If a launch can't be
-- trusted to land (too fast, or no rim to aim at), the player is simply put
-- back on the pad.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Funnels = require(ReplicatedStorage.Shared.Analytics.Funnels)
local Ballistic = require(ReplicatedStorage.Shared.Util.Ballistic)
local Pit = require(ReplicatedStorage.Shared.Util.Pit)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local DestructibleService = require(script.Parent.DestructibleService)
local StatusService = require(script.Parent.StatusService)
local TelemetryService = require(script.Parent.TelemetryService)

local Rescue = {}

local WATER_COLOR = Color3.fromRGB(80, 170, 235)
-- EffectsController clamps a launch to this many studs per second (a little
-- under its own limit, which it applies to any impulse).
local MAX_LAUNCH = 245
-- How wide a body the arc is checked with, in studs.
local ARC_RADIUS = 1.8

local lastSplash: { [Player]: number } = setmetatable({}, { __mode = "k" }) :: any
local stuckFor: { [Player]: number } = setmetatable({}, { __mode = "k" }) :: any

local function rootOf(character: Model): BasePart?
	local root = character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Puts the character on `position` and stops it.
local function place(character: Model, position: Vector3)
	character:PivotTo(CFrame.new(position))
	local root = rootOf(character)
	if root then
		root.AssemblyLinearVelocity = Vector3.zero
	end
end

-- Ray casts that ignore the player's own character.
local function paramsFor(character: Model): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	return params
end

-- True when a body thrown from `from` with `velocity` flies for `time` seconds
-- without bumping into anything (the arena's underside, a wall, scenery).
local function arcIsClear(character: Model, from: Vector3, velocity: Vector3, time: number): boolean
	local params = paramsFor(character)
	local gravity = workspace.Gravity
	local function at(t: number): Vector3
		return from + velocity * t - Vector3.new(0, 0.5 * gravity * t * t, 0)
	end
	local steps = 16
	local previous = from
	for i = 1, steps do
		local point = at(time * i / steps)
		local hit = workspace:Spherecast(previous, ARC_RADIUS, point - previous, params)
		if hit then
			return false
		end
		previous = point
	end
	return true
end

-- Throws the character along an arc from where it is to `to`. Returns false when
-- every arc is too fast to trust or has something in the way (the caller places
-- the player instead).
local function launch(character: Model, to: Vector3, apex: number): boolean
	local root = rootOf(character)
	if not root then
		return false
	end
	-- Try the asked arc, then a higher one that can clear a cliff in the way.
	for _, higher in { 1, 1.5 } do
		local velocity, time =
			Ballistic.velocity(root.Position, to, apex * higher, workspace.Gravity)
		if
			velocity.Magnitude <= MAX_LAUNCH
			and arcIsClear(character, root.Position, velocity, time)
		then
			DestructibleService.boost(character, velocity, time)
			return true
		end
	end
	return false
end

-- The player fell into the arena's water: splash damage, a stun, and an arc back
-- to `pad` (the spawn pad's position). Returns "ko" if the splash finished them,
-- "launched" or "placed" otherwise.
function Rescue.water(player: Player, character: Model, pad: Vector3): string
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = rootOf(character)
	if not humanoid or not root then
		return "placed"
	end
	local now = os.clock()
	local again = now - (lastSplash[player] or -math.huge) < Config.RESCUE.WATER_REPEAT
	-- Still on the way up through the water from the last splash: one splash only.
	if again and root.AssemblyLinearVelocity.Y > 0 then
		return "launched"
	end
	lastSplash[player] = now

	DestructibleService.shockwave(root.Position, 10, WATER_COLOR)
	DestructibleService.poof(root.Position, WATER_COLOR)
	Remotes.get("Fx"):FireAllClients("sfx", "waterSplash", root.Position)
	TelemetryService.event(player, Funnels.EVENTS.WaterRescue, Config.RESCUE.WATER_DAMAGE)

	-- Set directly (not TakeDamage) so a spawn shield can't dodge the splash; the
	-- last enemy to hit the player still gets the knockout.
	humanoid.Health = math.max(0, humanoid.Health - Config.RESCUE.WATER_DAMAGE)
	if humanoid.Health <= 0 then
		return "ko"
	end
	StatusService.apply(character, "Stun", Config.RESCUE.WATER_STUN)
	if not again and launch(character, pad, Config.RESCUE.WATER_APEX) then
		return "launched"
	end
	place(character, pad)
	return "placed"
end

local function terrainCast(character: Model): Pit.Cast
	local params = paramsFor(character)
	return function(origin, direction, length)
		local result = workspace:Raycast(origin, direction * length, params)
		if not result then
			return nil
		end
		return {
			distance = result.Distance,
			isTerrain = result.Instance:GetAttribute("Terrain") == true,
		}
	end
end

-- Call every few tenths of a second with the time since the last call (`dt`).
-- Counts how long the player has been grounded inside a walled-in hole and
-- rescues them past Config.RESCUE.PIT_SECONDS. Returns true when it did.
function Rescue.checkPit(player: Player, character: Model, pad: Vector3, dt: number): boolean
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = rootOf(character)
	if
		not humanoid
		or not root
		or humanoid.Health <= 0
		or root.Anchored
		or humanoid.FloorMaterial == Enum.Material.Air
	then
		stuckFor[player] = nil
		return false
	end
	local feetY = root.Position.Y - (humanoid.HipHeight + root.Size.Y / 2)
	local eye = Vector3.new(root.Position.X, feetY + Config.RESCUE.PIT_CLIMB, root.Position.Z)
	local cast = terrainCast(character)
	local enclosure = Pit.enclosure(eye, Config.RESCUE.PIT_REACH, cast)
	if not enclosure then
		stuckFor[player] = nil
		return false
	end
	local time = (stuckFor[player] or 0) + dt
	stuckFor[player] = time
	if time < Config.RESCUE.PIT_SECONDS then
		return false
	end
	stuckFor[player] = nil
	TelemetryService.event(player, Funnels.EVENTS.PitRescue, 1)

	-- Aim just past the nearest wall, on top of it: find the wall's top surface.
	local wall = eye + enclosure.direction * (enclosure.distance + 2)
	local top = workspace:Raycast(
		wall + Vector3.new(0, Config.RESCUE.PIT_MAX_RIM * 2, 0),
		Vector3.new(0, -Config.RESCUE.PIT_MAX_RIM * 4, 0),
		paramsFor(character)
	)
	if top and top.Position.Y - feetY <= Config.RESCUE.PIT_MAX_RIM then
		local landing = Vector3.new(wall.X, top.Position.Y + 3, wall.Z) + enclosure.direction * 3
		if launch(character, landing, Config.RESCUE.PIT_APEX) then
			return true
		end
	end
	place(character, pad)
	return true
end

function Rescue.clear(player: Player)
	lastSplash[player] = nil
	stuckFor[player] = nil
end

return Rescue
