--!strict
-- The cue table is data; keep it well-formed and keep every spell's cue
-- names pointing at real cues (a typo would be a silent spell).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cues = require(ReplicatedStorage.Shared.Audio.Cues)
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
end
