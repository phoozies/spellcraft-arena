--!strict
-- The spell registry (shared/Spells/SpellRegistry) must list every spell with
-- a model, a particle style, a cast pose, and sounds that all exist. Adding a
-- spell without finishing its look fails here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cues = require(ReplicatedStorage.Shared.Audio.Cues)
local ModelKit = require(ReplicatedStorage.Shared.ModelKit)
local CastPoses = require(ReplicatedStorage.Shared.Spells.CastPoses)
local SpellDefinitions = require(ReplicatedStorage.Shared.Spells.SpellDefinitions)
local SpellRegistry = require(ReplicatedStorage.Shared.Spells.SpellRegistry)
local VfxStyles = require(ReplicatedStorage.Shared.Spells.VfxStyles)

-- Models imported as meshes into the place (ReplicatedStorage.Models); every
-- other model a spell names must be a block model built by ModelKit.
local PLACE_MODELS = {
	Fireball = true,
	WaterBubble = true,
	RockWall = true,
	Gust = true,
	Zap = true,
	Heal = true,
	BlackHole = true,
	Turret = true,
}

return function(t: any)
	t.describe("Spell registry", function()
		t.it("lists every spell exactly once, and nothing else", function()
			local count = 0
			for id in SpellRegistry.entries do
				count += 1
				t.expect(SpellDefinitions.get(id) ~= nil).toBeTruthy()
			end
			t.expect(count).toBe(#SpellDefinitions.list)
			t.expect(#SpellRegistry.rows()).toBe(#SpellDefinitions.list)
		end)

		t.it("every spell has a model, and the model can be built", function()
			for _, def in SpellDefinitions.list do
				local name = SpellRegistry.modelFor(def.id)
				t.expect(name ~= nil).toBeTruthy()
				if name and not PLACE_MODELS[name] then
					t.expect(ModelKit.isBlock(name)).toBeTruthy()
					t.expect(ModelKit.get(name) ~= nil).toBeTruthy()
				end
			end
		end)

		t.it("every spell has a particle style and a cast pose that exist", function()
			for _, def in SpellDefinitions.list do
				local entry = SpellRegistry.entry(def.id)
				t.expect(entry ~= nil).toBeTruthy()
				if entry then
					t.expect(VfxStyles.STYLES[entry.vfx] ~= nil).toBeTruthy()
					t.expect(CastPoses.POSES[entry.animation] ~= nil).toBeTruthy()
					t.expect(#entry.fx > 0 and entry.note ~= "").toBeTruthy()
				end
			end
		end)

		t.it("every spell has cast and impact sounds (buffs need no impact)", function()
			for _, def in SpellDefinitions.list do
				local entry = SpellRegistry.entry(def.id) :: any
				local sfx = def.sfx
				t.expect(sfx ~= nil and sfx.cast ~= nil and Cues[sfx.cast] ~= nil).toBeTruthy()
				if entry.noImpact then
					t.expect(def.archetype == "Buff" or def.archetype == "Placeable").toBeTruthy()
				else
					t.expect(sfx ~= nil and sfx.impact ~= nil and Cues[sfx.impact] ~= nil)
						.toBeTruthy()
				end
			end
		end)

		t.it("every buff has an aura style", function()
			for _, def in SpellDefinitions.list do
				if def.archetype == "Buff" then
					local key = SpellRegistry.vfxFor(def.id)
					t.expect(key ~= nil and VfxStyles.AURAS[key] ~= nil).toBeTruthy()
				end
			end
		end)

		t.it("cast poses only use known keys and sane angles", function()
			for name, keys in CastPoses.POSES do
				t.expect(#keys > 0).toBeTruthy()
				for _, key in keys do
					t.expect(key.d > 0 and key.d <= 0.5).toBeTruthy()
					t.expect((key.hold or 0) <= 1).toBeTruthy()
					t.expect(math.abs(key.twist or 0) <= 90).toBeTruthy()
					for _, limb in { key.right, key.left, key.rightLeg, key.leftLeg } do
						local limb: any = limb
						for _, angle in
							{
								limb and limb.fwd or 0,
								limb and limb.side or 0,
								limb and limb.elbow or 0,
								limb and limb.knee or 0,
							}
						do
							t.expect(math.abs(angle) <= 180).toBeTruthy()
						end
					end
				end
				if name == "" then
					error("empty pose name")
				end
			end
		end)

		t.it("no two spells of one element share a cast pose", function()
			local seen: { [string]: string } = {}
			for _, def in SpellDefinitions.list do
				local pose = SpellRegistry.animationFor(def.id) :: string
				local key = def.element .. "|" .. pose
				t.expect(seen[key]).toBeNil()
				seen[key] = def.id
			end
		end)

		t.it("every beat rides on a real pose, lands inside it, and has a known kind", function()
			for name, beat in CastPoses.BEATS do
				local keys = CastPoses.POSES[name]
				t.expect(keys ~= nil).toBeTruthy()
				t.expect(table.find(CastPoses.BEAT_KINDS, beat.kind) ~= nil).toBeTruthy()
				local length = 0
				for _, key in keys do
					length += key.d + (key.hold or 0)
				end
				t.expect(beat.at > 0 and beat.at <= length).toBeTruthy()
				if beat.cue then
					t.expect(Cues[beat.cue] ~= nil).toBeTruthy()
				end
			end
		end)

		t.it("every impact style names a known hit kind", function()
			for _, style in VfxStyles.STYLES do
				if style.hit then
					t.expect(table.find(VfxStyles.HITS, style.hit) ~= nil).toBeTruthy()
				end
				t.expect((style.hitScale or 1) > 0).toBeTruthy()
			end
		end)

		t.it("every projectile spell has its own kind of impact", function()
			for _, def in SpellDefinitions.list do
				if def.archetype == "Projectile" and def.id ~= "Turret" then
					local style = VfxStyles.STYLES[SpellRegistry.vfxFor(def.id) :: string]
					t.expect(style ~= nil and style.hit ~= nil).toBeTruthy()
				end
			end
		end)
	end)
end
