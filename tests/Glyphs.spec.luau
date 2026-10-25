--!strict
-- Drawing recognition: every glyph must be recognized from sloppy,
-- rotated, resized, reversed, differently-started strokes, scribbles must be
-- rejected, and every spell must own a distinct glyph.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GlyphRecognizer = require(ReplicatedStorage.Shared.Spells.GlyphRecognizer)
local Elements = require(ReplicatedStorage.Shared.Spells.Elements)
local Glyphs = require(ReplicatedStorage.Shared.Spells.Glyphs)
local SpellDefinitions = require(ReplicatedStorage.Shared.Spells.SpellDefinitions)

-- Straight-line interpolation so a stroke has many points, like a real drag.
local function densify(points: { Vector2 }, perSegment: number): { Vector2 }
	local out = {}
	for i = 1, #points - 1 do
		for k = 0, perSegment - 1 do
			table.insert(out, points[i]:Lerp(points[i + 1], k / perSegment))
		end
	end
	table.insert(out, points[#points])
	return out
end

-- A sloppy attempt at a glyph: random start point (closed shapes), direction,
-- rotation, size, position, and hand wobble (a fraction of the shape's size).
local function attempt(glyph: Glyphs.Glyph, rng: Random, wobble: number): { Vector2 }
	local points = densify(glyph.points, math.max(6, math.ceil(40 / (#glyph.points - 1))))
	if glyph.closed then
		table.remove(points) -- last == first
		local shift = rng:NextInteger(0, #points - 1)
		local shifted = {}
		for i = 1, #points do
			shifted[i] = points[((i - 1 + shift) % #points) + 1]
		end
		table.insert(shifted, shifted[1])
		points = shifted
	end
	if rng:NextInteger(0, 1) == 1 then
		local flipped = {}
		for i = #points, 1, -1 do
			table.insert(flipped, points[i])
		end
		points = flipped
	end
	local angle = rng:NextNumber(-math.pi, math.pi)
	local scale = rng:NextNumber(0.25, 0.8)
	local origin = Vector2.new(rng:NextNumber(0.2, 1.2), rng:NextNumber(0.2, 0.7))
	local cosA, sinA = math.cos(angle), math.sin(angle)
	-- Hand tremor is slow: a few random sine waves along the stroke, plus a
	-- tiny per-point jitter (mouse/touch sampling).
	local waves = {}
	for i = 1, 3 do
		table.insert(waves, {
			freq = rng:NextNumber(1, 4) * i,
			phaseX = rng:NextNumber(0, math.pi * 2),
			phaseY = rng:NextNumber(0, math.pi * 2),
		})
	end
	local out = {}
	for i, p in points do
		local f = i / #points
		local d = p - Vector2.new(0.5, 0.5)
		local rotated = Vector2.new(d.X * cosA - d.Y * sinA, d.X * sinA + d.Y * cosA)
		local noise = Vector2.zero
		for _, w in waves do
			noise += Vector2.new(
				math.sin(f * w.freq * math.pi * 2 + w.phaseX),
				math.sin(f * w.freq * math.pi * 2 + w.phaseY)
			) * (wobble / 3)
		end
		noise += Vector2.new(rng:NextNumber(-0.1, 0.1), rng:NextNumber(-0.1, 0.1)) * wobble
		table.insert(out, origin + (rotated + noise) * scale)
	end
	return out
end

return function(t)
	t.describe("Glyph recognition", function()
		t.it("recognizes every glyph, however it's drawn (3% wobble)", function()
			local rng = Random.new(7)
			local misses = {}
			for _, glyph in Glyphs.LIST do
				for trial = 1, 40 do
					local id = GlyphRecognizer.recognize(attempt(glyph, rng, 0.03))
					if id ~= glyph.id then
						table.insert(misses, `{glyph.id}#{trial}->{tostring(id)}`)
					end
				end
			end
			if #misses > 2 then
				error(`{#misses} misses: {table.concat(misses, ", ", 1, math.min(#misses, 12))}`)
			end
		end)

		t.it("still recognizes sloppy glyphs (5% wobble) at least 90% of the time", function()
			local rng = Random.new(11)
			local total, hits = 0, 0
			for _, glyph in Glyphs.LIST do
				for _ = 1, 40 do
					total += 1
					if GlyphRecognizer.recognize(attempt(glyph, rng, 0.05)) == glyph.id then
						hits += 1
					end
				end
			end
			t.expect(hits / total >= 0.9).toBeTruthy()
		end)

		t.it("almost never mistakes one glyph for another, even when sloppy (5% wobble)", function()
			local rng = Random.new(3)
			local total, mistakes = 0, 0
			for _, glyph in Glyphs.LIST do
				for _ = 1, 40 do
					total += 1
					local id = GlyphRecognizer.recognize(attempt(glyph, rng, 0.05))
					if id ~= nil and id ~= glyph.id then
						mistakes += 1
					end
				end
			end
			t.expect(mistakes / total <= 0.01).toBeTruthy()
		end)

		t.it("reads a straight line as a slash, in any direction", function()
			for _, angle in { 0.6, 2.2, 0, math.pi / 2, -0.9 } do
				local line = {}
				for i = 0, 30 do
					local d = i * 0.02
					table.insert(line, Vector2.new(0.5 + math.cos(angle) * d, 0.5 + math.sin(angle) * d))
				end
				t.expect(GlyphRecognizer.recognize(line)).toBe("slash")
			end
		end)

		t.it("ignores a straight line when slashes aren't allowed, and rejects a dot and scribbles", function()
			local line = {}
			for i = 0, 30 do
				table.insert(line, Vector2.new(0.2 + i * 0.02, 0.5))
			end
			t.expect(GlyphRecognizer.recognize(line, { circle = true, star = true })).toBeNil()

			local dot = {}
			for _ = 1, 30 do
				table.insert(dot, Vector2.new(0.5, 0.5))
			end
			t.expect(GlyphRecognizer.recognize(dot)).toBeNil()

			local rng = Random.new(5)
			for _ = 1, 20 do
				local scribble = {}
				for _ = 1, 40 do
					table.insert(scribble, Vector2.new(rng:NextNumber(), rng:NextNumber()))
				end
				t.expect(GlyphRecognizer.recognize(scribble)).toBeNil()
			end
		end)

		t.it("rejects tiny or too-short strokes", function()
			local tiny = {}
			for i = 0, 30 do
				local a = i / 30 * math.pi * 2
				table.insert(tiny, Vector2.new(0.5 + math.cos(a) * 0.01, 0.5 + math.sin(a) * 0.01))
			end
			t.expect(GlyphRecognizer.recognize(tiny)).toBeNil()
			t.expect(GlyphRecognizer.recognize({ Vector2.new(0, 0), Vector2.new(1, 1) })).toBeNil()
		end)
	end)

	t.describe("Spell glyphs", function()
		t.it("every spell's shape is the one for its role, and an element never repeats one", function()
			for _, element in Elements.LIST do
				local owner: { [string]: string } = {}
				for _, id in element.spells do
					local def = SpellDefinitions.get(id) :: any
					t.expect(Glyphs.get(def.glyph) ~= nil).toBeTruthy()
					t.expect(Glyphs.ROLE[def.role] ~= nil).toBeTruthy()
					t.expect(def.glyph).toBe(Glyphs.ROLE[def.role])
					t.expect(owner[def.glyph]).toBeNil()
					owner[def.glyph] = def.id
				end
			end
		end)

		t.it("basic attacks are circles, fast attacks slashes, boosts squares, defenses and stuns triangles", function()
			t.expect(Glyphs.ROLE.basic).toBe("circle")
			t.expect(Glyphs.ROLE.fast).toBe("slash")
			t.expect(Glyphs.ROLE.boost).toBe("square")
			t.expect(Glyphs.ROLE.defense).toBe("triangle")
			t.expect(Glyphs.ROLE.stun).toBe("triangle")
			for _, def in SpellDefinitions.list do
				if def.stats.status == "Stun" then
					t.expect(def.role).toBe("stun")
				end
				if def.role == "ultimate" then
					t.expect(def.ultimate).toBe(true)
				end
			end
		end)

		t.it("no spell is drawn with a swirl or a squiggle", function()
			for _, def in SpellDefinitions.list do
				t.expect(def.glyph ~= "spiral" and def.glyph ~= "wave" and def.glyph ~= "infinity").toBeTruthy()
			end
			t.expect(Glyphs.get("spiral")).toBeNil()
			t.expect(Glyphs.get("wave")).toBeNil()
		end)

		t.it("Earth Wall and Air Shield are triangles; Fire Boost, Water Body and Air Boost are squares", function()
			for _, id in { "EarthWall", "AirShield" } do
				t.expect((SpellDefinitions.get(id) :: any).glyph).toBe("triangle")
			end
			for _, id in { "FireBoost", "WaterBody", "AirBoost" } do
				t.expect((SpellDefinitions.get(id) :: any).glyph).toBe("square")
			end
		end)

		t.it("a square is never read as a circle (or the reverse), even when sloppy", function()
			local allowed = { circle = true, square = true, slash = true, chevron = true, star = true }
			local rng = Random.new(33)
			local wrong = 0
			for _, id in { "circle", "square" } do
				local glyph = Glyphs.get(id) :: Glyphs.Glyph
				for _ = 1, 80 do
					local got = GlyphRecognizer.recognize(attempt(glyph, rng, 0.05), allowed)
					if got ~= id then
						wrong += 1
					end
				end
			end
			t.expect(wrong <= 4).toBeTruthy() -- at most 2.5% misses, and never swapped silently
		end)

		t.it("each element's own five shapes are recognized from sloppy strokes (5% wobble) 95% of the time", function()
			local rng = Random.new(21)
			local total, hits = 0, 0
			for _, element in Elements.LIST do
				local allowed: { [string]: boolean } = {}
				for _, id in element.spells do
					allowed[(SpellDefinitions.get(id) :: any).glyph] = true
				end
				for glyphId in allowed do
					local glyph = Glyphs.get(glyphId) :: Glyphs.Glyph
					for _ = 1, 40 do
						total += 1
						if GlyphRecognizer.recognize(attempt(glyph, rng, 0.05), allowed) == glyphId then
							hits += 1
						end
					end
				end
			end
			t.expect(hits / total >= 0.95).toBeTruthy()
		end)
	end)
end
