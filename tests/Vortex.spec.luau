--!strict
-- Black Hole and Turret reach dummies and Battleground NPCs, and both have
-- their own effects and sounds.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Cues = require(ReplicatedStorage.Shared.Audio.Cues)
local CastPoses = require(ReplicatedStorage.Shared.Spells.CastPoses)
local SpellDefinitions = require(ReplicatedStorage.Shared.Spells.SpellDefinitions)
local SpellRegistry = require(ReplicatedStorage.Shared.Spells.SpellRegistry)
local VfxStyles = require(ReplicatedStorage.Shared.Spells.VfxStyles)

return function(t: any)
	t.describe("Black Hole and Turret", function()
		local DestructibleService =
			require(ServerScriptService.Server.Services.DestructibleService) :: any

		local function prop(attributes: { [string]: any }): Model
			local model = Instance.new("Model")
			for name, value in attributes do
				model:SetAttribute(name, value)
			end
			CollectionService:AddTag(model, "Destructible")
			return model
		end

		t.it(
			"training dummies and Battleground NPCs count as targets, plain props do not",
			function()
				local dummy = prop({ Dummy = true })
				local npc = prop({ NpcType = "Goblin" })
				local rock = prop({})
				t.expect(DestructibleService.isTrainingTarget(dummy)).toBe(true)
				t.expect(DestructibleService.isTrainingTarget(npc)).toBe(true)
				t.expect(DestructibleService.isTrainingTarget(rock)).toBe(false)
				-- A part inside a dummy resolves to the dummy.
				local limb = Instance.new("Part")
				limb.Parent = dummy
				t.expect(DestructibleService.isTrainingTarget(limb)).toBe(true)
				for _, model in { dummy, npc, rock } do
					model:Destroy()
				end
			end
		)

		t.it("Black Hole pulls and holds, and Turret shoots", function()
			local hole = SpellDefinitions.get("BlackHole")
			t.expect(hole ~= nil and hole.stats.hold == true and hole.stats.pull ~= nil)
				.toBeTruthy()
			t.expect(hole ~= nil and (hole.stats.damage or 0) > 0).toBeTruthy()
			local turret = SpellDefinitions.get("Turret")
			t.expect(turret ~= nil and turret.stats.turret == true).toBeTruthy()
		end)

		t.it("both name the effects clients draw for them", function()
			local hole = SpellRegistry.entry("BlackHole") :: any
			local turret = SpellRegistry.entry("Turret") :: any
			t.expect(table.find(hole.fx, "vortex") ~= nil and table.find(hole.fx, "suck") ~= nil)
				.toBeTruthy()
			t.expect(
				table.find(turret.fx, "muzzle") ~= nil and table.find(turret.fx, "deploy") ~= nil
			)
				.toBeTruthy()
		end)

		t.it("their poses ride on a beat, and Black Hole's gather uses both hands", function()
			t.expect(CastPoses.BEATS.Conjure.kind).toBe("gather")
			t.expect(CastPoses.BEATS.Conjure.two).toBe(true)
			t.expect(CastPoses.BEATS.Deploy.kind).toBe("build")
		end)

		t.it("the hum loops, the bullets have a hit sound, and the shot is layered", function()
			t.expect(Cues.blackHoleHum.loop).toBe(true)
			t.expect(Cues.turretOnline ~= nil and Cues.voidPull ~= nil).toBeTruthy()
			local bullet = VfxStyles.STYLES.Bullet
			t.expect(bullet.hitCue ~= nil and Cues[bullet.hitCue :: string] ~= nil).toBeTruthy()
			t.expect(Cues.turretShot.with ~= nil).toBeTruthy()
		end)
	end)
end
