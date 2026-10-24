--!strict
-- Turns typed or spoken text into a spell id.
--
--   matchWord("Fire-ball!")          --> "Fireball"   (normalization)
--   matchWord("firebal")             --> "Fireball"   (1 typo allowed for 5+ letters)
--   findInText("um I cast rock wall") --> "RockWall"  (voice transcripts)
--
-- Pure module (no Instances), so it is unit-tested in tests/WordMatcher.spec.

local SpellDefinitions = require(script.Parent.SpellDefinitions)

local WordMatcher = {}

-- Lowercase, strip anything that isn't a letter/digit/space, collapse spaces.
function WordMatcher.normalize(text: string): string
	local lowered = string.lower(text)
	local cleaned = string.gsub(lowered, "[^%w%s]", "")
	cleaned = string.gsub(cleaned, "%s+", " ")
	cleaned = string.gsub(cleaned, "^%s+", "")
	cleaned = string.gsub(cleaned, "%s+$", "")
	return cleaned
end

local function despace(text: string): string
	return (string.gsub(text, " ", ""))
end

-- Exact lookup table: normalized alias (with and without spaces) -> spell id.
local exact: { [string]: string } = {}
local keys: { string } = {}

local function addKey(key: string, id: string)
	if key == "" then
		return
	end
	local existing = exact[key]
	if existing ~= nil and existing ~= id then
		warn(
			`[WordMatcher] alias "{key}" is claimed by both {existing} and {id}; keeping {existing}`
		)
		return
	end
	if existing == nil then
		exact[key] = id
		table.insert(keys, key)
	end
end

for _, def in SpellDefinitions.list do
	local names = table.clone(def.aliases)
	table.insert(names, def.name)
	for _, alias in names do
		local normalized = WordMatcher.normalize(alias)
		addKey(normalized, def.id)
		addKey(despace(normalized), def.id)
	end
end

-- Classic Levenshtein with an early exit once every cell in a row exceeds `limit`.
function WordMatcher.distance(a: string, b: string, limit: number): number
	local la, lb = #a, #b
	if math.abs(la - lb) > limit then
		return limit + 1
	end
	local prev = table.create(lb + 1, 0)
	for j = 0, lb do
		prev[j + 1] = j
	end
	for i = 1, la do
		local cur = table.create(lb + 1, 0)
		cur[1] = i
		local rowMin = i
		local ca = string.byte(a, i)
		for j = 1, lb do
			local cost = if ca == string.byte(b, j) then 0 else 1
			local v = math.min(prev[j + 1] + 1, cur[j] + 1, prev[j] + cost)
			cur[j + 1] = v
			if v < rowMin then
				rowMin = v
			end
		end
		if rowMin > limit then
			return limit + 1
		end
		prev = cur
	end
	return prev[lb + 1]
end

local function typoBudget(len: number): number
	if len >= 9 then
		return 2
	elseif len >= 5 then
		return 1
	end
	return 0
end

-- Matches a whole message against the dictionary. Returns nil if the text is
-- not a spell (so normal chat is left alone).
function WordMatcher.matchWord(text: string): string?
	local normalized = WordMatcher.normalize(text)
	if normalized == "" or #normalized > 32 then
		return nil
	end
	local hit = exact[normalized] or exact[despace(normalized)]
	if hit then
		return hit
	end

	local candidate = despace(normalized)
	local budget = typoBudget(#candidate)
	if budget == 0 then
		return nil
	end
	local bestId: string? = nil
	local bestDistance = budget + 1
	local tied = false
	for _, key in keys do
		if not string.find(key, " ", 1, true) then
			local d = WordMatcher.distance(candidate, key, budget)
			if d < bestDistance then
				bestDistance = d
				bestId = exact[key]
				tied = false
			elseif d == bestDistance and exact[key] ~= bestId then
				tied = true
			end
		end
	end
	if tied then
		return nil
	end
	return bestId
end

-- Scans free-form text (voice transcripts) for the first spell mentioned.
-- Two-word phrases are checked before single words so "rock wall" beats "rock".
function WordMatcher.findInText(text: string): string?
	local words = string.split(WordMatcher.normalize(text), " ")
	for i = 1, #words do
		if i < #words then
			local pair = exact[words[i] .. " " .. words[i + 1]]
			if pair then
				return pair
			end
		end
		local single = WordMatcher.matchWord(words[i])
		if single then
			return single
		end
	end
	return nil
end

return WordMatcher
