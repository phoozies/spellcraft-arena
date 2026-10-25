--!strict
-- Breakable terrain and bigger arenas: MapKit.terrain cuts blocks into cells,
-- MapKit.scale enlarges a finished map, and every cell's health is small
-- enough that real spells can carve it (the harder the hit, the sooner it goes).
-- The baseplate is much tougher than the scenery: floors take dozens of hits,
-- trees, rocks and pillars only a few.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.Config)
local SpellDefinitions = require(ReplicatedStorage.Shared.Spells.SpellDefinitions)

return function(t: any)
	t.describe("Terrain", function()
		local server = ServerScriptService:FindFirstChild("Server")
		local maps = server and server:FindFirstChild("Maps")
		local mapKit = if maps and maps:FindFirstChild("MapKit")
			then require(maps.MapKit :: ModuleScript) :: any
			else nil

		local function noop(_: Instance, _: number) end

		t.it("has sane config: arenas are doubled", function()
			t.expect(Config.ARENA_SCALE).toBe(2)
			t.expect(Config.TERRAIN.CELL > 0).toBeTruthy()
			t.expect(Config.TERRAIN.SPLASH > 0 and Config.TERRAIN.SPLASH < 1).toBeTruthy()
		end)

		t.it("the baseplate is way tougher than the scenery", function()
			local ground = Config.TERRAIN.HEALTH.Ground
			local strong = (SpellDefinitions.get("Fireball") :: any).stats.damage
			-- Many hits to break one floor cell, and far more than the heaviest prop.
			t.expect(math.ceil(ground / strong) >= 10).toBeTruthy()
			t.expect(ground >= Config.PROPS.Heavy * 3).toBeTruthy()
			t.expect(ground >= Config.TERRAIN.HEALTH.Rock * 4).toBeTruthy()
		end)

		t.it("scenery health tiers are ordered and a few hits fell even the heaviest", function()
			local props = Config.PROPS
			t.expect(props.Light < props.Medium and props.Medium < props.Heavy).toBeTruthy()
			local strong = (SpellDefinitions.get("Fireball") :: any).stats.damage
			t.expect(math.ceil(props.Heavy / strong) <= 6).toBeTruthy()
			t.expect(math.ceil(props.Light / strong) <= 2).toBeTruthy()
			t.expect(math.ceil(Config.TERRAIN.HEALTH.Rock / strong) <= 4).toBeTruthy()
		end)

		t.it("no map has solid scenery that spells can't break (except rock undersides)", function()
			if not maps then
				return
			end
			-- The Sparring Arena's imported colosseum and statue are single meshes.
			for _, name in {
				"CrayonCanyon",
				"FrostHollow",
				"EmberForge",
				"MossRuins",
				"TidalTemple",
				"SkyBridge",
			} do
				local props: { [Instance]: boolean } = {}
				local model = (require(maps:FindFirstChild(name) :: ModuleScript) :: any)(
					function(instance: Instance)
						props[instance] = true
					end
				) :: Model
				for _, part in model:GetDescendants() do
					if
						part:IsA("BasePart")
						and part.CanCollide
						and part.CanQuery
						and part.Transparency < 1
						and part.Name ~= "Underside"
						and not part:GetAttribute("Terrain")
					then
						local covered = false
						local node: Instance? = part
						while node and node ~= model do
							if props[node] then
								covered = true
								break
							end
							node = node.Parent
						end
						if not covered then
							error(`{name}: {part.Name} is solid but not breakable`)
						end
					end
				end
				model:Destroy()
			end
		end)

		t.it("a strong spell breaks a cell in fewer hits than a weak one", function()
			local strong = (SpellDefinitions.get("Fireball") :: any).stats.damage
			local weak = (SpellDefinitions.get("FireSlash") :: any).stats.damage
			t.expect(strong > weak).toBeTruthy()
			local health = Config.TERRAIN.HEALTH.Ground
			t.expect(math.ceil(health / strong) <= math.ceil(health / weak)).toBeTruthy()
			t.expect(math.ceil(health / strong) >= 2).toBeTruthy()
		end)

		t.it("cuts a block into cells no wider than the cell size", function()
			if not mapKit then
				return
			end
			local folder = Instance.new("Folder")
			local count = 0
			mapKit.terrain(folder, {
				name = "Test",
				size = Vector3.new(40, 4, 25),
				cframe = CFrame.new(100, 0, 0),
			}, {
				cell = 10,
				health = 50,
				makeProp = function(_: Instance, health: number)
					count += 1
					t.expect(health).toBe(50)
				end,
			})
			local cells = folder:FindFirstChild("Test"):GetChildren()
			t.expect(#cells).toBe(4 * 1 * 3)
			t.expect(count).toBe(#cells)
			for _, cell in cells do
				local part = cell :: BasePart
				t.expect(part:GetAttribute("Terrain")).toBe(true)
				t.expect(part.Size.X <= 10.001 and part.Size.Z <= 10.001).toBeTruthy()
			end
			folder:Destroy()
		end)

		t.it("a keep filter cuts a round island and ground cells are marked", function()
			if not mapKit then
				return
			end
			local folder = Instance.new("Folder")
			mapKit.terrain(folder, {
				name = "Island",
				size = Vector3.new(60, 4, 60),
				cframe = CFrame.new(),
			}, {
				cell = 10,
				health = 50,
				makeProp = noop,
				ground = true,
				keep = function(x: number, z: number)
					return x * x + z * z <= 30 * 30
				end,
			})
			local cells = folder:FindFirstChild("Island"):GetChildren()
			t.expect(#cells < 36).toBeTruthy()
			t.expect(#cells > 20).toBeTruthy()
			t.expect((cells[1] :: BasePart):GetAttribute("GroundTile")).toBe(true)
			folder:Destroy()
		end)

		t.it("scale grows a map about its origin", function()
			if not mapKit then
				return
			end
			local model = Instance.new("Model")
			local floor = Instance.new("Part")
			floor.Size = Vector3.new(10, 2, 20)
			floor.CFrame = CFrame.new(5, -1, 0)
			floor.Parent = model
			mapKit.scale(model, 2)
			t.expect(floor.Size.X).toBe(20)
			t.expect(floor.Size.Z).toBe(40)
			t.expect(floor.Position.X).toBe(10)
			-- The floor's top stays at y = 0.
			t.expect(floor.Position.Y + floor.Size.Y / 2).toBeNear(0, 0.001)
			model:Destroy()
		end)

		t.it("every duel map has breakable terrain and a cell for the floor", function()
			if not maps then
				return
			end
			for _, name in {
				"CrayonCanyon",
				"SparringArena",
				"FrostHollow",
				"EmberForge",
				"MossRuins",
				"TidalTemple",
				"SkyBridge",
			} do
				local props = 0
				local model = (require(maps:FindFirstChild(name) :: ModuleScript) :: any)(
					function(instance: Instance, health: number)
						if instance:GetAttribute("Terrain") then
							props += 1
							t.expect(health > 0).toBeTruthy()
						end
					end
				) :: Model
				t.expect(props >= 4).toBeTruthy()
				model:Destroy()
			end
		end)

		t.it("the dash recharges in 8 seconds", function()
			t.expect(Config.DASH.COOLDOWN).toBe(8)
		end)
	end)
end
