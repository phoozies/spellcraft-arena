--!strict
-- The duel maps and the floating hub: all 8 maps follow the arena contract
-- (Bounds, 4 spawns per team, SmallModeWalls), arenas are summoned below the
-- hub island (not on it, not overlapping, above the kill height), the hub keeps
-- every tag its services look for, and the dash is a short leap.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.Config)

local EXPECTED_MAPS = {
	"CrayonCanyon",
	"SkyIslands",
	"SparringArena",
	"FrostHollow",
	"EmberForge",
	"MossRuins",
	"TidalTemple",
	"SkyBridge",
}

return function(t: any)
	t.describe("Maps", function()
		local server = ServerScriptService:FindFirstChild("Server")
		local maps = server and server:FindFirstChild("Maps")
		local services = server and server:FindFirstChild("Services")
		local arenaService = if services and services:FindFirstChild("ArenaService")
			then require(services.ArenaService :: ModuleScript) :: any
			else nil

		t.it("there are eight maps, each with a display name", function()
			if not arenaService then
				return -- server scripts aren't present in this context
			end
			t.expect(#arenaService.MAP_NAMES).toBe(#EXPECTED_MAPS)
			for _, name in EXPECTED_MAPS do
				t.expect(table.find(arenaService.MAP_NAMES, name) ~= nil).toBeTruthy()
				t.expect(typeof(arenaService.DISPLAY_NAMES[name])).toBe("string")
			end
		end)

		t.it("every map follows the arena contract", function()
			if not maps then
				return
			end
			for _, name in EXPECTED_MAPS do
				local builder = require(maps:FindFirstChild(name) :: ModuleScript) :: any
				local model = builder(function() end) :: Model
				t.expect(model:FindFirstChild("Bounds") ~= nil).toBeTruthy()
				t.expect(model:FindFirstChild("SmallModeWalls") ~= nil).toBeTruthy()
				local spawns = model:FindFirstChild("Spawns")
				t.expect(spawns ~= nil).toBeTruthy()
				if spawns then
					local team1, team2 = 0, 0
					for _, spawn in spawns:GetChildren() do
						if string.find(spawn.Name, "^Team1_") then
							team1 += 1
						elseif string.find(spawn.Name, "^Team2_") then
							team2 += 1
						end
					end
					t.expect(team1 >= 4 and team2 >= 4).toBeTruthy()
				end
				model:Destroy()
			end
		end)

		t.it("pickMap always returns a known map", function()
			if not arenaService then
				return
			end
			for _, mode in { "1v1", "2v2", "3v3", "4v4" } do
				for _ = 1, 40 do
					t.expect(table.find(arenaService.MAP_NAMES, arenaService.pickMap(mode)) ~= nil)
						.toBeTruthy()
				end
			end
			-- The compact floors are never picked for 4v4.
			for _ = 1, 80 do
				t.expect(arenaService.pickMap("4v4") ~= "SparringArena").toBeTruthy()
			end
		end)

		t.it("arenas are summoned below the hub island, apart from each other", function()
			if not arenaService then
				return
			end
			local origins: { Vector3 } = {}
			for slot = 1, Config.ARENA.PER_RING * 2 do
				local position = (arenaService.slotOrigin(slot) :: CFrame).Position
				t.expect(position.Y).toBe(Config.ARENA.Y)
				-- Outside the island's footprint, so the rim looks down on them.
				t.expect(Vector3.new(position.X, 0, position.Z).Magnitude > Config.HUB.RADIUS + 100)
					.toBeTruthy()
				for _, other in origins do
					t.expect((other - position).Magnitude >= 400).toBeTruthy()
				end
				table.insert(origins, position)
			end
			-- Far enough under the island's rock cone, but above the ocean and the
			-- height at which Roblox deletes falling parts.
			t.expect(Config.ARENA.Y < -200).toBeTruthy()
			t.expect(Config.HUB.OCEAN_Y < Config.ARENA.Y + Config.ARENA_VOID_DEPTH - 20)
				.toBeTruthy()
			t.expect(Config.HUB.OCEAN_Y > workspace.FallenPartsDestroyHeight).toBeTruthy()
		end)
	end)

	t.describe("Hub", function()
		local server = ServerScriptService:FindFirstChild("Server")
		local maps = server and server:FindFirstChild("Maps")
		local builder = if maps and maps:FindFirstChild("InkwellPlaza")
			then require(maps.InkwellPlaza :: ModuleScript) :: any
			else nil

		t.it("is a round island that keeps every tag the services need", function()
			if not builder then
				return
			end
			local model = builder() :: Model
			local counts: { [string]: number } = {}
			local outermost = 0
			for _, part in model:GetDescendants() do
				if part:IsA("BasePart") then
					for _, tag in
						{
							"HubSpawn",
							"TeamPad",
							"PracticeZone",
							"BattlegroundPortal",
							"WinsBoard",
							"PodiumSpot",
							"LikeGift",
							"DummySpot",
						}
					do
						if part:HasTag(tag) then
							counts[tag] = (counts[tag] or 0) + 1
						end
					end
					if not part:IsDescendantOf(model:FindFirstChild("Ocean") :: Instance) then
						local flat = Vector3.new(part.Position.X, 0, part.Position.Z).Magnitude
						outermost = math.max(outermost, flat)
					end
				end
			end
			t.expect(counts.HubSpawn).toBe(1)
			t.expect(counts.TeamPad).toBe(12) -- six boxes, two sides each
			t.expect(counts.PracticeZone).toBe(1)
			t.expect(counts.BattlegroundPortal).toBe(1)
			t.expect(counts.WinsBoard).toBe(1)
			t.expect(counts.PodiumSpot).toBe(3)
			t.expect(counts.LikeGift).toBe(1)
			t.expect(counts.DummySpot >= 6).toBeTruthy()
			-- Nothing sticks out past the island's rim.
			t.expect(outermost <= Config.HUB.RADIUS).toBeTruthy()
			for _, name in { "SpellbookKiosk", "DailyChest", "Crate_Spell" } do
				t.expect(model:FindFirstChild(name) ~= nil).toBeTruthy()
			end
			model:Destroy()
		end)
	end)

	t.describe("Dash", function()
		t.it("is a short low leap with wind streaks", function()
			local dash = Config.DASH
			t.expect(dash.TRAILS >= 1).toBeTruthy()
			-- The hop's airtime roughly matches the dash, so you land as it ends.
			local airtime = 2 * dash.HOP / workspace.Gravity
			t.expect(airtime >= dash.DURATION * 0.6 and airtime <= dash.DURATION * 1.2).toBeTruthy()
		end)
	end)
end
