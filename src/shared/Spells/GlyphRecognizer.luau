--!strict
-- Recognizes a hand-drawn stroke as one of the Glyphs. This is the "$1
-- unistroke recognizer" (Wobbrock et al.): resample the stroke to a fixed
-- number of points, rotate it so its first point is straight to the right of
-- its center, scale it to a square, then take the average distance to every
-- template and keep the closest. Closed shapes also get a template per start
-- point, and every template is also stored reversed, so where you start and
-- which way you go don't matter.
--
-- On top of plain $1:
--   * the best-fitting rotation starts from its exact least-squares angle
--     (as in Protractor) and is only polished by a short search, which is
--     faster and never settles in the wrong dip of the ±45° range;
--   * a closed shape drawn past its own start has that tail trimmed off;
--   * straight strokes are slashes (by straightness, not templates), and a
--     merely flat stroke still gets template-matched when slashes aren't
--     allowed;
--   * circle-vs-square ties are settled by how much of its box the stroke fills.
--
-- Pure module (no Instances): the server runs it on the points a client
-- sends (SpellInputService), tests/Glyphs.spec runs it on noisy strokes.

local Glyphs = require(script.Parent.Glyphs)

local GlyphRecognizer = {}

local SAMPLES = 64
local SQUARE = 250
local HALF_DIAGONAL = 0.5 * math.sqrt(2 * SQUARE * SQUARE)
local ANGLE_RANGE = math.rad(45)
-- The fine search looks this far either side of the least-squares angle.
local REFINE_RANGE = math.rad(8)
local ANGLE_PRECISION = math.rad(1.5)
local PHI = 0.5 * (-1 + math.sqrt(5))
-- Closed shapes get this many start points.
local START_VARIANTS = 24

-- A stroke needs this many raw points and at least this extent (in the
-- caller's units, e.g. fractions of screen height) to count as a drawing.
GlyphRecognizer.MIN_POINTS = 12
GlyphRecognizer.MIN_EXTENT = 0.12
-- Best score (0..1) needed, and how far ahead of the runner-up it must be.
GlyphRecognizer.MIN_SCORE = 0.8
GlyphRecognizer.MIN_MARGIN = 0.03

local function pathLength(points: { Vector2 }): number
	local total = 0
	for i = 2, #points do
		total += (points[i] - points[i - 1]).Magnitude
	end
	return total
end

local function resample(points: { Vector2 }, count: number): { Vector2 }
	local step = pathLength(points) / (count - 1)
	local out = { points[1] }
	if step <= 0 then
		for _ = 2, count do
			table.insert(out, points[1])
		end
		return out
	end
	local work = table.clone(points)
	local travelled = 0
	local i = 2
	while i <= #work do
		local a, b = work[i - 1], work[i]
		local d = (b - a).Magnitude
		if d > 0 and travelled + d >= step then
			local q = a + (b - a) * ((step - travelled) / d)
			table.insert(out, q)
			table.insert(work, i, q)
			travelled = 0
		else
			travelled += d
		end
		i += 1
	end
	-- Rounding can leave the last point off; pad with the end of the stroke.
	while #out < count do
		table.insert(out, work[#work])
	end
	while #out > count do
		table.remove(out)
	end
	return out
end

local function centroid(points: { Vector2 }): Vector2
	local sum = Vector2.zero
	for _, p in points do
		sum += p
	end
	return sum / #points
end

local function rotateBy(points: { Vector2 }, angle: number): { Vector2 }
	local c = centroid(points)
	local cosA, sinA = math.cos(angle), math.sin(angle)
	local out = {}
	for i, p in points do
		local d = p - c
		out[i] = Vector2.new(d.X * cosA - d.Y * sinA + c.X, d.X * sinA + d.Y * cosA + c.Y)
	end
	return out
end

local function scaleToSquare(points: { Vector2 }): { Vector2 }
	local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
	for _, p in points do
		minX, maxX = math.min(minX, p.X), math.max(maxX, p.X)
		minY, maxY = math.min(minY, p.Y), math.max(maxY, p.Y)
	end
	local w, h = math.max(maxX - minX, 1e-6), math.max(maxY - minY, 1e-6)
	local out = {}
	for i, p in points do
		out[i] = Vector2.new((p.X - minX) * SQUARE / w, (p.Y - minY) * SQUARE / h)
	end
	return out
end

local function translateToOrigin(points: { Vector2 }): { Vector2 }
	local c = centroid(points)
	local out = {}
	for i, p in points do
		out[i] = p - c
	end
	return out
end

local function prepare(points: { Vector2 }): { Vector2 }
	local resampled = resample(points, SAMPLES)
	local c = centroid(resampled)
	local indicative = math.atan2(c.Y - resampled[1].Y, c.X - resampled[1].X)
	local rotated = rotateBy(resampled, -indicative)
	return translateToOrigin(scaleToSquare(rotated))
end

local function pathDistance(a: { Vector2 }, b: { Vector2 }): number
	local total = 0
	for i = 1, #a do
		total += (a[i] - b[i]).Magnitude
	end
	return total / #a
end

local function distanceAtAngle(points: { Vector2 }, template: { Vector2 }, angle: number): number
	return pathDistance(rotateBy(points, angle), template)
end

-- The rotation that best lines `points` up with `template` in the
-- least-squares sense, in closed form (both are centred on the origin by
-- prepare): atan2 of the summed cross and dot products. It is the global best
-- for squared distance, so the search below only has to polish it for the
-- plain distance the score uses, instead of hunting the whole ±45° range
-- (where a golden-section search can settle in the wrong dip).
local function leastSquaresAngle(points: { Vector2 }, template: { Vector2 }): number
	local cross, dot = 0, 0
	for i = 1, #points do
		local p, q = points[i], template[i]
		cross += p.X * q.Y - p.Y * q.X
		dot += p.X * q.X + p.Y * q.Y
	end
	return math.atan2(cross, dot)
end

-- Golden-section search for the rotation (within ±45°) that fits best,
-- around the least-squares angle.
local function distanceAtBestAngle(points: { Vector2 }, template: { Vector2 }): number
	local seed = math.clamp(leastSquaresAngle(points, template), -ANGLE_RANGE, ANGLE_RANGE)
	local a = math.max(-ANGLE_RANGE, seed - REFINE_RANGE)
	local b = math.min(ANGLE_RANGE, seed + REFINE_RANGE)
	local x1 = PHI * a + (1 - PHI) * b
	local f1 = distanceAtAngle(points, template, x1)
	local x2 = (1 - PHI) * a + PHI * b
	local f2 = distanceAtAngle(points, template, x2)
	while math.abs(b - a) > ANGLE_PRECISION do
		if f1 < f2 then
			b, x2, f2 = x2, x1, f1
			x1 = PHI * a + (1 - PHI) * b
			f1 = distanceAtAngle(points, template, x1)
		else
			a, x1, f1 = x1, x2, f2
			x2 = (1 - PHI) * a + PHI * b
			f2 = distanceAtAngle(points, template, x2)
		end
	end
	return math.min(f1, f2, distanceAtAngle(points, template, seed))
end

-- A stroke counts as a straight slash when no point strays far from the
-- line between its ends (a fraction of that line's length) and the ends are
-- well apart (so a closed loop or a squiggle never qualifies).
local STRAIGHT_DEVIATION = 0.22
local STRAIGHT_MIN_CHORD = 0.7 -- chord / path length

-- Returns (straight, deviation): the worst stray as a fraction of the chord.
local function isStraight(points: { Vector2 }): (boolean, number)
	local first, last = points[1], points[#points]
	local chord = last - first
	local chordLength = chord.Magnitude
	if chordLength < 1e-6 or chordLength < pathLength(points) * STRAIGHT_MIN_CHORD then
		return false, 1
	end
	local normal = Vector2.new(-chord.Y, chord.X) / chordLength
	local worst = 0
	for _, p in points do
		worst = math.max(worst, math.abs((p - first):Dot(normal)))
	end
	return worst / chordLength <= STRAIGHT_DEVIATION, worst / chordLength
end

-- A circle and a square look alike to template matching (squash a square and
-- it is nearly round), so when those two are the finalists we ask how much of
-- its tightest bounding box the stroke fills: a square fills 90-100% of it,
-- a circle about 78%.
local SQUARE_FILL = 0.84

local function boxFill(points: { Vector2 }): number
	local area = 0
	for i = 1, #points do
		local a, b = points[i], points[i % #points + 1]
		area += a.X * b.Y - b.X * a.Y
	end
	area = math.abs(area) / 2
	local smallest = math.huge
	for degrees = 0, 85, 5 do
		local angle = math.rad(degrees)
		local cosA, sinA = math.cos(angle), math.sin(angle)
		local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
		for _, p in points do
			local x = p.X * cosA + p.Y * sinA
			local y = -p.X * sinA + p.Y * cosA
			minX, maxX = math.min(minX, x), math.max(maxX, x)
			minY, maxY = math.min(minY, y), math.max(maxY, y)
		end
		smallest = math.min(smallest, (maxX - minX) * (maxY - minY))
	end
	return if smallest > 0 then area / smallest else 0
end

-- People close a shape by running a little past where they started (a circle
-- that loops on, a square whose last side overshoots the corner). That tail
-- is not part of the shape, so when the stroke comes back near its start in
-- its last stretch and then carries on a short way, the tail is cut off.
local CLOSE_SEARCH = 0.65 -- look for the return in the last 35% of the path
local CLOSE_TOLERANCE = 0.15 -- "near the start": this share of the stroke's diagonal
local MAX_TAIL = 0.22 -- longest tail cut, as a share of the path

local function trimOvershoot(points: { Vector2 }): { Vector2 }
	local n = #points
	local total = pathLength(points)
	if n < 3 or total <= 0 then
		return points
	end
	local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
	for _, p in points do
		minX, maxX = math.min(minX, p.X), math.max(maxX, p.X)
		minY, maxY = math.min(minY, p.Y), math.max(maxY, p.Y)
	end
	local tolerance = Vector2.new(maxX - minX, maxY - minY).Magnitude * CLOSE_TOLERANCE
	local start = points[1]
	local travelled = 0
	local best, bestIndex, bestAt = math.huge, n, total
	for i = 2, n do
		travelled += (points[i] - points[i - 1]).Magnitude
		if travelled >= total * CLOSE_SEARCH then
			local d = (points[i] - start).Magnitude
			if d < best then
				best, bestIndex, bestAt = d, i, travelled
			end
		end
	end
	if
		best <= tolerance
		and bestIndex < n
		and total - bestAt <= total * MAX_TAIL
		and bestIndex >= GlyphRecognizer.MIN_POINTS
	then
		return table.move(points, 1, bestIndex, 1, {})
	end
	return points
end

type Template = { glyphId: string, points: { Vector2 } }

local function reversed(points: { Vector2 }): { Vector2 }
	local out = {}
	for i = #points, 1, -1 do
		table.insert(out, points[i])
	end
	return out
end

local templates: { Template } = {}

for _, glyph in Glyphs.LIST do
	if glyph.line then
		continue -- a straight line has no shape to match; see isStraight
	end
	local base = resample(glyph.points, SAMPLES)
	local shapes = { base }
	if glyph.closed then
		-- Every start point around the outline (the shape's last point repeats
		-- its first, so rotate through the first SAMPLES - 1).
		shapes = {}
		for k = 0, START_VARIANTS - 1 do
			local shift = math.floor(k * (SAMPLES - 1) / START_VARIANTS)
			local shifted = {}
			for i = 1, SAMPLES - 1 do
				shifted[i] = base[((i - 1 + shift) % (SAMPLES - 1)) + 1]
			end
			table.insert(shifted, shifted[1])
			table.insert(shapes, shifted)
		end
	end
	for _, shape in shapes do
		table.insert(templates, { glyphId = glyph.id, points = prepare(shape) })
		table.insert(templates, { glyphId = glyph.id, points = prepare(reversed(shape)) })
	end
end

-- Returns (glyphId, score, runnerUpScore). `score` (0..1) is how closely the
-- stroke follows the shape; Spells/Quality turns it into a cast bonus.
-- (Reminder of the rest:) `glyphId` is nil when nothing is
-- close enough or two glyphs are too hard to tell apart; `score` is the best
-- one found either way (for tuning and feedback). Points are in any consistent
-- 2D unit (pixels, screen fractions). `allowed` limits the choice to those
-- glyph ids (a player's equipped element uses just five), which makes
-- look-alike shapes impossible to confuse.
function GlyphRecognizer.recognize(
	points: { Vector2 },
	allowed: { [string]: boolean }?
): (string?, number, number)
	if #points < GlyphRecognizer.MIN_POINTS then
		return nil, 0, 0
	end
	local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
	for _, p in points do
		minX, maxX = math.min(minX, p.X), math.max(maxX, p.X)
		minY, maxY = math.min(minY, p.Y), math.max(maxY, p.Y)
	end
	if math.max(maxX - minX, maxY - minY) < GlyphRecognizer.MIN_EXTENT then
		return nil, 0, 0
	end
	-- A straight stroke is a slash (or nothing, where slashes aren't allowed).
	local straight, deviation = isStraight(points)
	if straight then
		if allowed == nil or allowed.slash then
			-- Straighter is better: 1 for a ruler line, 0.8 at the limit.
			return "slash", 1 - 0.2 * deviation / STRAIGHT_DEVIATION, 0
		end
		-- Clearly a line: nothing else to read. A merely flat stroke (a wide,
		-- shallow V) still gets matched against the shapes below.
		if deviation <= STRAIGHT_DEVIATION * 0.5 then
			return nil, 0, 0
		end
	end
	points = trimOvershoot(points)
	local stroke = prepare(points)

	-- Best distance per glyph (its closest template).
	local best: { [string]: number } = {}
	for _, template in templates do
		if allowed and not allowed[template.glyphId] then
			continue
		end
		local d = distanceAtBestAngle(stroke, template.points)
		if d < (best[template.glyphId] or math.huge) then
			best[template.glyphId] = d
		end
	end
	local ranked: { { id: string, score: number } } = {}
	for id, d in best do
		table.insert(ranked, { id = id, score = 1 - d / HALF_DIAGONAL })
	end
	table.sort(ranked, function(a, b)
		return a.score > b.score
	end)
	local top, runnerUp = ranked[1], ranked[2]
	if top == nil then
		return nil, 0, 0
	end
	local bestScore = top.score
	local secondScore = if runnerUp then runnerUp.score else 0
	if bestScore < GlyphRecognizer.MIN_SCORE then
		return nil, bestScore, secondScore
	end
	-- Circle or square? Decide by how much of its box the stroke fills.
	if
		runnerUp
		and bestScore - secondScore < 0.12
		and (
			(top.id == "circle" and runnerUp.id == "square")
			or (top.id == "square" and runnerUp.id == "circle")
		)
	then
		return if boxFill(points) >= SQUARE_FILL then "square" else "circle", bestScore, secondScore
	end
	if bestScore - secondScore < GlyphRecognizer.MIN_MARGIN then
		return nil, bestScore, secondScore
	end
	return top.id, bestScore, secondScore
end

return GlyphRecognizer
