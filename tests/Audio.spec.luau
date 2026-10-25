--!strict
-- The cue table is data; keep it well-formed and keep every spell's cue
-- names pointing at real cues (a typo would be a silent spell).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Cues = require(ReplicatedStorage.Shared.Audio.Cues)
local Music = require(ReplicatedStorage.Shared.Audio.Music)
local SpellDefinitions = require(ReplicatedStorage.Shared.Spells.SpellDefinitions)

return function(t: any)
	t.describe("Audio cues", function()
		t.it("every cue has a roblox asset id, a sane volume and pitch", function()
			for name, cue in Cues do
				t.expect(string.match(cue.id, "^rbxassetid://%d+$") ~= nil).toBeTruthy()
				t.expect(cue.volume > 0 and cue.volume <= 1).toBeTruthy()
				local pitch = cue.pitch or 1
				t.expect(pitch >= 0.4 and pitch <= 2).toBeTruthy()
				if cue.length then
					t.expect(cue.length > 0 and cue.length <= 6).toBeTruthy()
				end
				if name == "" then
					error("empty cue name")
				end
			end
		end)

		t.it("layered cues point at real, unlayered cues", function()
			for _, cue in Cues do
				for _, other in cue.with or {} do
					t.expect(Cues[other] ~= nil).toBeTruthy()
					t.expect(Cues[other].with).toBeNil()
				end
			end
		end)

		t.it("every projectile spell hits with a sound of its own", function()
			local seen: { [string]: string } = {}
			for _, def in SpellDefinitions.list do
				local impact = def.sfx and def.sfx.impact
				if def.archetype == "Projectile" and impact then
					t.expect(seen[impact]).toBeNil()
					seen[impact] = def.id
				end
			end
		end)

		t.it("the like-and-favourite chime exists", function()
			t.expect(Cues.claimReward ~= nil).toBeTruthy()
		end)

		t.it("every spell's cast and impact cues exist", function()
			for _, def in SpellDefinitions.list do
				local sfx = def.sfx
				t.expect(sfx ~= nil and sfx.cast ~= nil).toBeTruthy() -- every spell sounds when cast
				for _, cueName in { (sfx :: any).cast, (sfx :: any).impact } do
					if cueName then
						t.expect(Cues[cueName] ~= nil).toBeTruthy()
					end
				end
			end
		end)
	end)

	t.describe("Background music", function()
		t.it("has hub and fight playlists of real tracks with sane volumes", function()
			t.expect(#Music.playlist("hub") >= 2).toBeTruthy()
			t.expect(#Music.playlist("fight") >= 2).toBeTruthy()
			local seen: { [string]: boolean } = {}
			for _, track in Music.TRACKS do
				t.expect(string.match(track.id, "^rbxassetid://%d+$") ~= nil).toBeTruthy()
				t.expect(track.volume > 0 and track.volume <= 1).toBeTruthy()
				t.expect(track.title ~= "").toBeTruthy()
				t.expect(seen[track.id]).toBeNil()
				seen[track.id] = true
			end
		end)

		t.it("the music is quiet enough to leave room for spell sounds", function()
			t.expect(Config.MUSIC.VOLUME > 0 and Config.MUSIC.VOLUME <= 0.5).toBeTruthy()
			t.expect(Config.MUSIC.FADE_SECONDS > 0).toBeTruthy()
		end)
	end)
end
