--!strict
-- Plays a spell's cast pose (Spells/CastPoses) on any character. Each pose is
-- turned into a KeyframeSequence at runtime, registered with the
-- KeyframeSequenceProvider (so it needs no uploaded Animation asset), and
-- played through the character's Animator at Action priority: it overrides the
-- idle/walk arms while it plays and blends back out. Works on R15 (arms,
-- elbows, waist lean and twist, legs) and R6 (arm and leg swing only). A pose
-- that never names a leg leaves the walk cycle alone. Purely cosmetic and local:
-- every client plays it for every caster.

local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CastPoses = require(ReplicatedStorage.Shared.Spells.CastPoses)

local CastAnimations = {}

-- Seconds the pose takes to ease back to rest after its last key.
local RETURN_TIME = 0.22

-- Registered animation ids, by pose, rig, and extra hold.
local registered: { [string]: { id: string, length: number } } = {}
-- The playing track per character and pose, so a repeat cast restarts it.
local tracks: { [Model]: { [string]: AnimationTrack } } = setmetatable({}, { __mode = "k" }) :: any

local function pose(name: string, cframe: CFrame, weight: number, parent: Pose?): Pose
	local p = Instance.new("Pose")
	p.Name = name
	p.CFrame = cframe
	p.Weight = weight
	p.EasingStyle = Enum.PoseEasingStyle.Cubic
	p.EasingDirection = Enum.PoseEasingDirection.Out
	if parent then
		parent:AddSubPose(p)
	end
	return p
end

-- An arm's offset. R15 shoulders swing forward about X and out about Z; R6
-- shoulders swing forward about Z in their own frame.
local function armOffset(arm: CastPoses.Arm?, r15: boolean, mirror: number): CFrame
	if not arm then
		return CFrame.identity
	end
	local forward = math.rad(arm.fwd or 0)
	if not r15 then
		return CFrame.Angles(0, 0, forward)
	end
	return CFrame.Angles(forward, 0, math.rad(arm.side or 0) * mirror)
end

local function elbowOffset(arm: CastPoses.Arm?): CFrame
	return CFrame.Angles(math.rad(if arm then arm.elbow or 0 else 0), 0, 0)
end

-- A leg's offset. Hips swing like shoulders (forward about X on R15, about Z on
-- R6), `side` opens the leg outward, and the knee bends the shin backward.
local function legOffset(leg: CastPoses.Leg?, r15: boolean, mirror: number): CFrame
	if not leg then
		return CFrame.identity
	end
	local forward = math.rad(leg.fwd or 0)
	if not r15 then
		return CFrame.Angles(0, 0, forward)
	end
	return CFrame.Angles(forward, 0, math.rad(leg.side or 0) * mirror)
end

local function kneeOffset(leg: CastPoses.Leg?): CFrame
	return CFrame.Angles(-math.rad(if leg then leg.knee or 0 else 0), 0, 0)
end

-- One keyframe: the whole joint tree with this key's angles (nil = at rest).
local function keyframe(time: number, key: CastPoses.Key?, r15: boolean, legs: boolean): Keyframe
	local frame = Instance.new("Keyframe")
	frame.Time = time
	local root = pose("HumanoidRootPart", CFrame.identity, 0)
	if r15 then
		local lower = pose("LowerTorso", CFrame.identity, 0, root)
		local lean = if key then math.rad(-(key.lean or 0)) else 0
		local upper = pose("UpperTorso", CFrame.Angles(lean, 0, 0), 1, lower)
		local right = if key then key.right else nil
		local left = if key then key.left else nil
		local rightUpper = pose("RightUpperArm", armOffset(right, true, 1), 1, upper)
		pose("RightLowerArm", elbowOffset(right), 1, rightUpper)
		local leftUpper = pose("LeftUpperArm", armOffset(left, true, -1), 1, upper)
		pose("LeftLowerArm", elbowOffset(left), 1, leftUpper)
	else
		local torso = pose("Torso", CFrame.identity, 0, root)
		pose("Right Arm", armOffset(if key then key.right else nil, false, 1), 1, torso)
		pose("Left Arm", armOffset(if key then key.left else nil, false, -1), 1, torso)
	end
	frame:AddPose(root)
	return frame
end

-- Registers (once) the animation for a pose and returns its asset id, plus
-- the animation's length in seconds.
local function animationFor(poseName: string, r15: boolean, extraHold: number): (string?, number)
	local keys = CastPoses.POSES[poseName]
	if not keys then
		return nil, 0
	end
	local cacheKey = `{poseName}|{if r15 then "R15" else "R6"}|{math.floor(extraHold * 10 + 0.5)}`
	local known = registered[cacheKey]
	if known then
		return known.id, known.length
	end
	local legs = false
	for _, key in keys do
		legs = legs or key.rightLeg ~= nil or key.leftLeg ~= nil
	end
	local sequence = Instance.new("KeyframeSequence")
	sequence.Name = "Cast_" .. poseName
	sequence.Loop = false
	sequence.Priority = Enum.AnimationPriority.Action3
	local time = 0
	sequence:AddKeyframe(keyframe(0, nil, r15, legs))
	for index, key in keys do
		time += key.d
		sequence:AddKeyframe(keyframe(time, key, r15, legs))
		local hold = (key.hold or 0) + (if index == #keys then extraHold else 0)
		if hold > 0 then
			time += hold
			sequence:AddKeyframe(keyframe(time, key, r15, legs))
		end
	end
	time += RETURN_TIME
	sequence:AddKeyframe(keyframe(time, nil, r15, legs))

	local ok, result = pcall(function()
		return KeyframeSequenceProvider:RegisterKeyframeSequence(sequence)
	end)
	sequence:Destroy()
	if not ok then
		return nil, 0
	end
	registered[cacheKey] = { id = result :: string, length = time }
	return result :: string, time
end

-- Plays `poseName` on `character`. `extraHold` lengthens the final hold
-- (a channelled spell stays in its pose for the whole channel).
function CastAnimations.play(character: Model, poseName: string?, extraHold: number?)
	if not poseName or not CastPoses.POSES[poseName] then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not humanoid or not animator then
		return
	end
	local r15 = humanoid.RigType == Enum.HumanoidRigType.R15
	local id = animationFor(poseName, r15, extraHold or 0)
	if not id then
		return
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = id
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	animation:Destroy()
	if not ok then
		return
	end
	local byPose = tracks[character] or {}
	tracks[character] = byPose
	local previous = byPose[poseName]
	if previous then
		previous:Stop(0.05)
	end
	byPose[poseName] = track
	track.Priority = Enum.AnimationPriority.Action3
	track.Looped = false
	track:Play(0.05)
	track.Stopped:Once(function()
		track:Destroy()
		if byPose[poseName] == track then
			byPose[poseName] = nil
		end
	end)
end

return CastAnimations
