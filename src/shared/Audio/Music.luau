--!strict
-- Background music: two short playlists, one for the hub and one for fights
-- (matches and the Battleground). The client's AudioController plays them on a
-- loop, fades between them, and mutes them when the player turns Music off in
-- Settings (profile.settings.music). To swap a track, change its `id`; nothing
-- else needs touching. tests/Audio.spec checks every track's shape.
--
-- All four are royalty-free tracks from Roblox's own audio library (APM Music),
-- picked for being bright and heroic rather than scary, for an all-ages game.
--
--   mood  "hub" plays in the hub, "fight" in matches and the Battleground
--   volume  0..1 relative to the other tracks (the music group sets the rest,
--           see Config.MUSIC.VOLUME)

export type Track = {
	id: string,
	title: string,
	mood: "hub" | "fight",
	volume: number,
}

local Music = {}

Music.TRACKS = {
	{ id = "rbxassetid://9043250631", title = "Into Life", mood = "hub", volume = 0.9 },
	{ id = "rbxassetid://9043599808", title = "Fun Adventures", mood = "hub", volume = 1 },
	{ id = "rbxassetid://9043657042", title = "Star Chasing", mood = "fight", volume = 0.9 },
	{ id = "rbxassetid://9039422512", title = "Deliverance", mood = "fight", volume = 0.9 },
} :: { Track }

-- The tracks of one mood, in play order.
function Music.playlist(mood: "hub" | "fight"): { Track }
	local list = {}
	for _, track in Music.TRACKS do
		if track.mood == mood then
			table.insert(list, track)
		end
	end
	return list
end

return Music
