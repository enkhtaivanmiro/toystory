--[[
	ToyStory - Server Character Selection & Rigging Script
	Handles client-server requests to select a character.
	Generates standard R6 skeleton rigs for custom models, preventing joint break deaths
	and matching the height of the player's original avatar.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Get character configs
local CharacterConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CharacterConfig"))

-- Initialize folders
local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
if not eventsFolder then
	eventsFolder = Instance.new("Folder")
	eventsFolder.Name = "Events"
	eventsFolder.Parent = ReplicatedStorage
end

local charactersFolder = ReplicatedStorage:FindFirstChild("Characters")
if not charactersFolder then
	charactersFolder = Instance.new("Folder")
	charactersFolder.Name = "Characters"
	charactersFolder.Parent = ReplicatedStorage
end

-- Initialize RemoteEvent
local selectCharacterEvent = eventsFolder:FindFirstChild("SelectCharacter")
if not selectCharacterEvent then
	selectCharacterEvent = Instance.new("RemoteEvent")
	selectCharacterEvent.Name = "SelectCharacter"
	selectCharacterEvent.Parent = eventsFolder
end

-- Track player selections
local playerSelections: { [Player]: string } = {}
local swapping: { [Player]: boolean } = {}

--- Remove scripts from clones
local function removeScripts(model: Model)
	for _, desc in model:GetDescendants() do
		if desc:IsA("BaseScript") or desc:IsA("ModuleScript") then
			desc:Destroy()
		end
	end
end

--- Calculate bounding box height of a model
local function getModelBoundsY(model: Model): (number, number)
	local minY = math.huge
	local maxY = -math.huge

	for _, desc in model:GetDescendants() do
		if desc:IsA("BasePart") then
			local pos = desc.CFrame.Position
			local halfY = desc.Size.Y / 2
			minY = math.min(minY, pos.Y - halfY)
			maxY = math.max(maxY, pos.Y + halfY)
		end
	end

	return minY, maxY
end

--- Scale model uniformly
local function scaleModel(model: Model, scaleFactor: number)
	local pivot = model:GetPivot().Position

	for _, desc in model:GetDescendants() do
		if desc:IsA("BasePart") then
			if desc.Name ~= "wing" then
				desc.Size = desc.Size * scaleFactor
			end
			local offset = desc.CFrame.Position - pivot
			local newPos = pivot + (offset * scaleFactor)
			desc.CFrame = CFrame.new(newPos) * (desc.CFrame - desc.CFrame.Position)
		end
	end
end

-- Helper to find a child (either Part or Model wrapper)
local function findVisualGroup(parent: Model, name: string): Instance?
	return parent:FindFirstChild(name)
end

-- Helper to get size and CFrame of a visual group (whether it is a Part or Model)
local function getGroupBounds(instance: Instance): (CFrame, Vector3)
	if instance:IsA("BasePart") then
		return instance.CFrame, instance.Size
	elseif instance:IsA("Model") then
		return instance:GetPivot(), instance:GetExtentsSize()
	end
	return CFrame.new(), Vector3.new(1, 1, 1)
end

-- Helper to weld all parts inside an instance to a target part
local function weldGroupToSkeletonPart(group: Instance, skeletonPart: BasePart)
	if group:IsA("BasePart") then
		group.Anchored = false
		group.CanCollide = false

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = skeletonPart
		weld.Part1 = group
		weld.Parent = group
	end

	-- Welds any nested baseparts (e.g., children of parts like wings, accessories inside models)
	for _, desc in group:GetDescendants() do
		if desc:IsA("BasePart") then
			desc.Anchored = false
			desc.CanCollide = false

			local weld = Instance.new("WeldConstraint")
			weld.Part0 = skeletonPart
			weld.Part1 = desc
			weld.Parent = desc
		end
	end
end

--- Auto-groups Slinky's unstructured detailed parts into proper R6 visual models
local function autoGroupSlinky(visualTemplate: Model)
	local function getOrCreateGroup(name: string): Model
		local group = visualTemplate:FindFirstChild(name)
		if not group then
			group = Instance.new("Model")
			group.Name = name
			group.Parent = visualTemplate
		end
		return group
	end

	local chestGroup = getOrCreateGroup("Chest")
	local headGroup = getOrCreateGroup("Head")
	local leftArmGroup = getOrCreateGroup("Left Arm")
	local rightArmGroup = getOrCreateGroup("Right Arm")
	local leftLegGroup = getOrCreateGroup("Left Leg")
	local rightLegGroup = getOrCreateGroup("Right Leg")

	local allParts = {}
	local dogEars = visualTemplate:FindFirstChild("Dog Ears")
	local leftEye = visualTemplate:FindFirstChild("Left eye")
	local headAnchor = nil

	if dogEars and dogEars:IsA("BasePart") then
		headAnchor = dogEars.Position
	elseif leftEye then
		if leftEye:IsA("BasePart") then
			headAnchor = leftEye.Position
		elseif leftEye:IsA("Model") then
			headAnchor = leftEye:GetPivot().Position
		end
	end

	-- Retrieve all BaseParts in the model (direct or nested inside other models)
	local children = visualTemplate:GetChildren()
	for _, child in children do
		if child:IsA("BasePart") and child.Name ~= "HumanoidRootPart" then
			table.insert(allParts, child)
		elseif
			child:IsA("Model")
			and child.Name ~= "Chest"
			and child.Name ~= "Head"
			and child.Name ~= "Left Arm"
			and child.Name ~= "Right Arm"
			and child.Name ~= "Left Leg"
			and child.Name ~= "Right Leg"
		then
			for _, subChild in child:GetDescendants() do
				if subChild:IsA("BasePart") then
					table.insert(allParts, subChild)
				end
			end
		end
	end

	if #allParts == 0 then
		return
	end

	-- Find default head anchor if not found via names
	if not headAnchor then
		local highestY = -math.huge
		for _, part in allParts do
			if part.Position.Y > highestY then
				highestY = part.Position.Y
				headAnchor = part.Position
			end
		end
	end

	-- PHASE 1: Separate the Head parts (using a tight 2.2-stud radius around the head anchor)
	local headRadius = 2.2
	local bodyParts = {}

	for _, part in allParts do
		local dist = (part.Position - headAnchor).Magnitude
		if
			dist < headRadius
			or part.Name == "Dog Ears"
			or part.Name == "Left eye"
			or part.Parent.Name == "Left eye"
		then
			part.Parent = headGroup
		else
			table.insert(bodyParts, part)
		end
	end

	-- PHASE 2: Find bounds of the REMAINING body parts (keeps the head out of body bounds math)
	local minY = math.huge
	local maxY = -math.huge
	local minZ = math.huge
	local maxZ = -math.huge
	local sumPos = Vector3.new(0, 0, 0)

	for _, part in bodyParts do
		local pos = part.Position
		minY = math.min(minY, pos.Y)
		maxY = math.max(maxY, pos.Y)
		minZ = math.min(minZ, pos.Z)
		maxZ = math.max(maxZ, pos.Z)
		sumPos = sumPos + pos
	end

	local bodyCenter = sumPos / #bodyParts
	local bodyLength = maxZ - minZ

	-- Thresholds (for a 5-stud tall scaled Slinky)
	local legYCutoff = minY + 1.8 -- legs are in the lower 1.8 studs
	local isHeadFrontZPositive = headAnchor.Z > bodyCenter.Z

	-- PHASE 3: Classify remaining body parts into Legs vs Torso/Coils
	for _, part in bodyParts do
		local pos = part.Position

		-- Leg check: must be low enough, and must NOT be in the middle 50% of the body (coils zone)
		local relativeZ = (pos.Z - minZ) / bodyLength
		local isMiddleCoils = (relativeZ > 0.25 and relativeZ < 0.75)

		if pos.Y < legYCutoff and not isMiddleCoils then
			-- Classify as one of the 4 legs
			local isLeft = pos.X > bodyCenter.X
			local isFront = false
			if isHeadFrontZPositive then
				isFront = pos.Z > bodyCenter.Z
			else
				isFront = pos.Z <= bodyCenter.Z
			end

			if isFront then
				if isLeft then
					part.Parent = leftArmGroup
				else
					part.Parent = rightArmGroup
				end
			else
				if isLeft then
					part.Parent = leftLegGroup
				else
					part.Parent = rightLegGroup
				end
			end
		else
			-- Torso/Spring coils/Back-body/Tail -> Chest
			part.Parent = chestGroup
		end
	end

	-- Clean up empty models
	for _, child in visualTemplate:GetChildren() do
		if
			child:IsA("Model")
			and child.Name ~= "Chest"
			and child.Name ~= "Head"
			and child.Name ~= "Left Arm"
			and child.Name ~= "Right Arm"
			and child.Name ~= "Left Leg"
			and child.Name ~= "Right Leg"
		then
			if #child:GetChildren() == 0 then
				child:Destroy()
			end
		end
	end
end

--- Auto-groups Mr. Potato Head's loose parts programmatically into standard R6 visual groups
local function autoGroupPotatoHead(visualTemplate: Model)
	local function getOrCreateGroup(name: string): Model
		local group = visualTemplate:FindFirstChild(name)
		if not group then
			group = Instance.new("Model")
			group.Name = name
			group.Parent = visualTemplate
		end
		return group
	end

	local chestGroup = getOrCreateGroup("Chest")
	local headGroup = getOrCreateGroup("Head")
	local leftArmGroup = getOrCreateGroup("Left Arm")
	local rightArmGroup = getOrCreateGroup("Right Arm")
	local leftLegGroup = getOrCreateGroup("Left Leg")
	local rightLegGroup = getOrCreateGroup("Right Leg")

	-- Pre-pass: extract nested model wrappers (e.g., "Model > Left Arm" → move "Left Arm" to top level)
	for _, child in visualTemplate:GetChildren() do
		if child:IsA("Model") and child.Name == "Model" then
			for _, sub in child:GetChildren() do
				sub.Parent = visualTemplate
			end
			child:Destroy()
		end
	end

	local children = visualTemplate:GetChildren()

	-- Locate the main potato body
	local bodyPart = visualTemplate:FindFirstChild("Body")
	if not bodyPart then
		local biggestSize = 0
		for _, child in children do
			if child:IsA("BasePart") and child.Name ~= "HumanoidRootPart" then
				local sz = child.Size.X * child.Size.Y * child.Size.Z
				if sz > biggestSize then
					biggestSize = sz
					bodyPart = child
				end
			end
		end
	end

	local bodyCenter = bodyPart and bodyPart.Position or Vector3.new(0, 0, 0)
	local bodySize = bodyPart and bodyPart.Size or Vector3.new(3, 3, 3)

	for _, child in children do
		if
			child.Name == "Chest"
			or child.Name == "Head"
			or child.Name == "Left Arm"
			or child.Name == "Right Arm"
			or child.Name == "Left Leg"
			or child.Name == "Right Leg"
		then
			continue
		end

		local name = child.Name:lower()

		if name:find("foot") or name:find("leg") or name:find("boot") or name:find("shoe") then
			if name:find("left") then
				child.Parent = leftLegGroup
			elseif name:find("right") then
				child.Parent = rightLegGroup
			else
				if child:GetPivot().Position.X > bodyCenter.X then
					child.Parent = leftLegGroup
				else
					child.Parent = rightLegGroup
				end
			end
		elseif name:find("arm") or name:find("hand") or name:find("glove") then
			if name:find("left") then
				child.Parent = leftArmGroup
			elseif name:find("right") then
				child.Parent = rightArmGroup
			else
				if child:GetPivot().Position.X > bodyCenter.X then
					child.Parent = leftArmGroup
				else
					child.Parent = rightArmGroup
				end
			end
		elseif
			name:find("eye")
			or name:find("ear")
			or name:find("nose")
			or name:find("mustache")
			or name:find("mouth")
			or name:find("tongue")
			or name:find("hat")
			or name:find("bowler")
		then
			child.Parent = headGroup
		elseif child == bodyPart or name:find("body") or name:find("torso") or name:find("chest") then
			child.Parent = chestGroup
		else
			-- Spatial fallback for unnamed parts (like Model or Part)
			local pos = child:GetPivot().Position
			local yDiff = pos.Y - bodyCenter.Y

			if pos.Y < bodyCenter.Y - bodySize.Y * 0.4 then
				if pos.X > bodyCenter.X then
					child.Parent = leftLegGroup
				else
					child.Parent = rightLegGroup
				end
			elseif pos.X > bodyCenter.X + bodySize.X * 0.4 then
				child.Parent = leftArmGroup
			elseif pos.X < bodyCenter.X - bodySize.X * 0.4 then
				child.Parent = rightArmGroup
			elseif yDiff > -bodySize.Y * 0.2 then
				child.Parent = headGroup
			else
				child.Parent = chestGroup
			end
		end
	end

	-- Clean up empty models
	for _, child in visualTemplate:GetChildren() do
		if
			child:IsA("Model")
			and child.Name ~= "Chest"
			and child.Name ~= "Head"
			and child.Name ~= "Left Arm"
			and child.Name ~= "Right Arm"
			and child.Name ~= "Left Leg"
			and child.Name ~= "Right Leg"
		then
			if #child:GetChildren() == 0 then
				child:Destroy()
			end
		end
	end
end

--- Auto-groups Sid's parts programmatically into standard R6 visual groups
local function autoGroupSid(visualTemplate: Model)
	local function getOrCreateGroup(name: string): Model
		local group = visualTemplate:FindFirstChild(name)
		if not group then
			group = Instance.new("Model")
			group.Name = name
			group.Parent = visualTemplate
		end
		return group
	end

	local chestGroup = getOrCreateGroup("Chest")
	local headGroup = getOrCreateGroup("Head")
	local leftArmGroup = getOrCreateGroup("Left Arm")
	local rightArmGroup = getOrCreateGroup("Right Arm")
	local leftLegGroup = getOrCreateGroup("Left Leg")
	local rightLegGroup = getOrCreateGroup("Right Leg")

	-- Collect all BaseParts (including nested ones under other models)
	local allParts = {}
	for _, desc in visualTemplate:GetDescendants() do
		if desc:IsA("BasePart") and desc.Name ~= "HumanoidRootPart" then
			table.insert(allParts, desc)
		end
	end

	-- Identify the main Torso part by volume (it's the largest part by far)
	local torsoPart = nil
	local biggestVolume = 0
	for _, part in allParts do
		if part.Name == "Part" then
			local vol = part.Size.X * part.Size.Y * part.Size.Z
			if vol > biggestVolume then
				biggestVolume = vol
				torsoPart = part
			end
		end
	end

	if not torsoPart then
		warn("[ToyStory Server] Torso part not found for Sid!")
		return
	end

	local torsoCenter = torsoPart.Position

	for _, part in allParts do
		if part.Name == "Head" then
			part.Parent = headGroup
		elseif part == torsoPart then
			part.Parent = chestGroup
		else
			-- Classify based on position relative to torsoCenter
			local pos = part.Position
			local diffX = pos.X - torsoCenter.X
			local diffY = pos.Y - torsoCenter.Y

			if diffY < -6 then
				-- Leg zone
				if diffX < 0 then
					part.Parent = leftLegGroup
				else
					part.Parent = rightLegGroup
				end
			else
				-- Arm/Shoulder zone
				if diffX < 0 then
					part.Parent = leftArmGroup
				else
					part.Parent = rightArmGroup
				end
			end
		end
	end

	-- Clean up empty models
	for _, child in visualTemplate:GetChildren() do
		if
			child:IsA("Model")
			and child.Name ~= "Chest"
			and child.Name ~= "Head"
			and child.Name ~= "Left Arm"
			and child.Name ~= "Right Arm"
			and child.Name ~= "Left Leg"
			and child.Name ~= "Right Leg"
		then
			if #child:GetChildren() == 0 then
				child:Destroy()
			end
		end
	end
end


--- Build a playable custom character from a model template
local function buildCustomCharacter(template: Model, characterName: string, targetHeight: number): Model?
	local config = CharacterConfig[characterName]
	if not config then
		warn("[ToyStory Server] No config found for character:", characterName)
		return nil
	end

	-- 1. Clone and scale the visual template
	local visualTemplate = template:Clone()
	visualTemplate.Name = "Visuals"
	removeScripts(visualTemplate)

	-- Check if the template is already a pre-rigged R6 model (like Rex)
	-- These models already have Torso, Head, HumanoidRootPart with Motor6Ds
	local existingTorso = visualTemplate:FindFirstChild("Torso")
	local existingRoot = visualTemplate:FindFirstChild("HumanoidRootPart")
	if existingTorso and existingTorso:IsA("BasePart") and existingRoot and existingRoot:IsA("BasePart") then
		-- Pre-rigged R6: use the clone directly as the character
		local character = visualTemplate
		character.Name = characterName .. "Character"

		-- Remove old Humanoid (we'll create a fresh one)
		local oldHumanoid = character:FindFirstChildOfClass("Humanoid")
		if oldHumanoid then
			oldHumanoid:Destroy()
		end

		-- Scale to target height
		local minY, maxY = getModelBoundsY(character)
		local currentHeight = maxY - minY
		if currentHeight > 0 then
			local scaleFactor = targetHeight / currentHeight
			scaleModel(character, scaleFactor)
		end

		-- Create fresh Humanoid
		local humanoid = Instance.new("Humanoid")
		humanoid.RigType = Enum.HumanoidRigType.R6
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
		humanoid.HealthDisplayDistance = 0
		humanoid.NameDisplayDistance = 0
		humanoid.HipHeight = 0
		humanoid.Parent = character

		local animator = Instance.new("Animator")
		animator.Parent = humanoid

		character.PrimaryPart = existingRoot
		character:SetAttribute("IsCustomCharacter", true)
		character:SetAttribute("CharacterName", characterName)

		return character
	end

	-- Remove existing joints/welds that would conflict with the new R6 skeleton
	-- (ManualWelds between parts in different R6 groups would fight the new skeleton welds)
	for _, desc in visualTemplate:GetDescendants() do
		if desc:IsA("JointInstance") or desc:IsA("WeldConstraint") then
			desc:Destroy()
		end
	end

	-- If this is Slinky, group his loose parts programmatically first
	if characterName == "Slinky" then
		autoGroupSlinky(visualTemplate)
	elseif characterName == "PotatoHead" then
		autoGroupPotatoHead(visualTemplate)
	elseif characterName == "Sid" then
		autoGroupSid(visualTemplate)
	end

	local minY, maxY = getModelBoundsY(visualTemplate)
	local currentHeight = maxY - minY
	if characterName == "Sid" then
		targetHeight = currentHeight -- Bypass scaling to keep original size
	end
	if currentHeight > 0 then
		local scaleFactor = targetHeight / currentHeight
		scaleModel(visualTemplate, scaleFactor)
		minY, maxY = getModelBoundsY(visualTemplate) -- Recalculate
	end

	-- Find visual groups in the scaled template
	local vTorso = findVisualGroup(visualTemplate, "Chest") or findVisualGroup(visualTemplate, "Torso")
	local vHead = findVisualGroup(visualTemplate, "Head")
	local vLeftArm = findVisualGroup(visualTemplate, "Left Arm")
	local vRightArm = findVisualGroup(visualTemplate, "Right Arm")
	local vLeftLeg = findVisualGroup(visualTemplate, "Left Leg")
	local vRightLeg = findVisualGroup(visualTemplate, "Right Leg")

	if not vTorso then
		warn("[ToyStory Server] Chest/Torso visual group not found in template:", characterName)
		visualTemplate:Destroy()
		return nil
	end

	-- 2. Create the playable character Model wrapper
	local character = Instance.new("Model")
	character.Name = characterName .. "Character"
	visualTemplate.Parent = character

	-- Calculate standard R6 scale factor based on target height (standard R6 height is 5.0 studs)
	local scale = targetHeight / 5.0

	-- Helper to determine the upright forward direction of the character based on facial features
	local function getVisualForwardDirection(model: Model, torsoPos: Vector3): Vector3
		local faceParts = {}
		for _, desc in model:GetDescendants() do
			if desc:IsA("BasePart") then
				local name = desc.Name:lower()
				if name:find("nose") or name:find("mouth") or name:find("eye") or name:find("jaw") or name:find("teeth") or name:find("snout") then
					table.insert(faceParts, desc.Position)
				end
			end
		end

		if #faceParts > 0 then
			local sum = Vector3.new(0, 0, 0)
			for _, pos in faceParts do
				sum = sum + pos
			end
			local facePos = sum / #faceParts
			local dir = (facePos - torsoPos) * Vector3.new(1, 0, 1) -- keep it strictly horizontal
			if dir.Magnitude > 0.1 then
				return dir.Unit
			end
		end

		-- Fallback 1: Direction from Torso to Head
		local vHead = model:FindFirstChild("Head")
		if vHead then
			local headCF = getGroupBounds(vHead)
			local dir = (headCF.Position - torsoPos) * Vector3.new(1, 0, 1)
			if dir.Magnitude > 0.1 then
				return dir.Unit
			end
		end

		-- Fallback 2: Horizontal lookVector from the model's pivot CFrame
		local pivotLook = (template:GetPivot().LookVector * Vector3.new(1, 0, 1))
		if pivotLook.Magnitude > 0.1 then
			return pivotLook.Unit
		end
		return Vector3.new(0, 0, -1) -- default Roblox forward
	end

	-- 3. Create the invisible R6 Skeleton parts using standard scaled R6 proportions
	local torsoCF = getGroupBounds(vTorso)
	local torsoPosition = torsoCF.Position
	local lookDir = getVisualForwardDirection(visualTemplate, torsoPosition)
	local torsoRotationCF = CFrame.lookAt(torsoPosition, torsoPosition + lookDir, Vector3.new(0, 1, 0))

	-- Torso Part
	local torso = Instance.new("Part")
	torso.Name = "Torso"
	torso.Size = Vector3.new(2 * scale, 2 * scale, 1 * scale)
	torso.Transparency = 1
	torso.CanCollide = true
	torso.Anchored = false
	torso.CFrame = torsoRotationCF
	torso.Parent = character

	-- HumanoidRootPart
	local rootPart = Instance.new("Part")
	rootPart.Name = "HumanoidRootPart"
	rootPart.Size = Vector3.new(2 * scale, 2 * scale, 1 * scale)
	rootPart.Transparency = 1
	rootPart.CanCollide = false
	rootPart.Anchored = false
	rootPart.CFrame = torsoRotationCF
	rootPart.Parent = character

	-- Head Part (Standard R6 height is 1.0, positioned 1.5 above torso center)
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(1.2 * scale, 1.2 * scale, 1.2 * scale)
	head.Transparency = 1
	head.CanCollide = false
	head.Anchored = false
	head.CFrame = torsoRotationCF * CFrame.new(0, 1.5 * scale, 0)
	head.Parent = character

	-- Standard scaled limbs
	local leftArm = Instance.new("Part")
	leftArm.Name = "Left Arm"
	leftArm.Size = Vector3.new(1 * scale, 2 * scale, 1 * scale)
	leftArm.Transparency = 1
	leftArm.CanCollide = false -- arms usually non-collidable in R6
	leftArm.CFrame = torsoRotationCF * CFrame.new(-1.5 * scale, 0, 0)
	leftArm.Parent = character

	local rightArm = Instance.new("Part")
	rightArm.Name = "Right Arm"
	rightArm.Size = Vector3.new(1 * scale, 2 * scale, 1 * scale)
	rightArm.Transparency = 1
	rightArm.CanCollide = false
	rightArm.CFrame = torsoRotationCF * CFrame.new(1.5 * scale, 0, 0)
	rightArm.Parent = character

	local leftLeg = Instance.new("Part")
	leftLeg.Name = "Left Leg"
	leftLeg.Size = Vector3.new(1 * scale, 2 * scale, 1 * scale)
	leftLeg.Transparency = 1
	leftLeg.CanCollide = true
	leftLeg.CFrame = torsoRotationCF * CFrame.new(-0.5 * scale, -2 * scale, 0)
	leftLeg.Parent = character

	local rightLeg = Instance.new("Part")
	rightLeg.Name = "Right Leg"
	rightLeg.Size = Vector3.new(1 * scale, 2 * scale, 1 * scale)
	rightLeg.Transparency = 1
	rightLeg.CanCollide = true
	rightLeg.CFrame = torsoRotationCF * CFrame.new(0.5 * scale, -2 * scale, 0)
	rightLeg.Parent = character

	-- 4. Weld the Visual models to the corresponding standard skeleton parts
	weldGroupToSkeletonPart(vTorso, torso)
	if vHead and head then
		weldGroupToSkeletonPart(vHead, head)
	end
	if vLeftArm and leftArm then
		weldGroupToSkeletonPart(vLeftArm, leftArm)
	end
	if vRightArm and rightArm then
		weldGroupToSkeletonPart(vRightArm, rightArm)
	end
	if vLeftLeg and leftLeg then
		weldGroupToSkeletonPart(vLeftLeg, leftLeg)
	end
	if vRightLeg and rightLeg then
		weldGroupToSkeletonPart(vRightLeg, rightLeg)
	end

	-- 5. Setup R6 Motor6D joints connecting the skeleton parts using standard scaled offsets
	-- RootJoint
	local rootJoint = Instance.new("Motor6D")
	rootJoint.Name = "RootJoint"
	rootJoint.Part0 = rootPart
	rootJoint.Part1 = torso
	rootJoint.C0 = CFrame.new(0, 0, 0) * CFrame.Angles(math.rad(-90), 0, math.rad(180))
	rootJoint.C1 = CFrame.new(0, 0, 0) * CFrame.Angles(math.rad(-90), 0, math.rad(180))
	rootJoint.Parent = rootPart

	-- Neck
	local neck = Instance.new("Motor6D")
	neck.Name = "Neck"
	neck.Part0 = torso
	neck.Part1 = head
	neck.C0 = CFrame.new(0, 1 * scale, 0) * CFrame.Angles(math.rad(-90), 0, math.rad(180))
	neck.C1 = CFrame.new(0, -0.5 * scale, 0) * CFrame.Angles(math.rad(-90), 0, math.rad(180))
	neck.Parent = torso

	-- Left Shoulder
	local leftShoulder = Instance.new("Motor6D")
	leftShoulder.Name = "Left Shoulder"
	leftShoulder.Part0 = torso
	leftShoulder.Part1 = leftArm
	leftShoulder.C0 = CFrame.new(-1 * scale, 0.5 * scale, 0) * CFrame.Angles(0, math.rad(-90), 0)
	leftShoulder.C1 = CFrame.new(0.5 * scale, 0.5 * scale, 0) * CFrame.Angles(0, math.rad(-90), 0)
	leftShoulder.Parent = torso

	-- Right Shoulder
	local rightShoulder = Instance.new("Motor6D")
	rightShoulder.Name = "Right Shoulder"
	rightShoulder.Part0 = torso
	rightShoulder.Part1 = rightArm
	rightShoulder.C0 = CFrame.new(1 * scale, 0.5 * scale, 0) * CFrame.Angles(0, math.rad(90), 0)
	rightShoulder.C1 = CFrame.new(-0.5 * scale, 0.5 * scale, 0) * CFrame.Angles(0, math.rad(90), 0)
	rightShoulder.Parent = torso

	-- Left Hip
	local leftHip = Instance.new("Motor6D")
	leftHip.Name = "Left Hip"
	leftHip.Part0 = torso
	leftHip.Part1 = leftLeg
	leftHip.C0 = CFrame.new(-0.5 * scale, -1 * scale, 0) * CFrame.Angles(0, math.rad(-90), 0)
	leftHip.C1 = CFrame.new(0, 1 * scale, 0) * CFrame.Angles(0, math.rad(-90), 0)
	leftHip.Parent = torso

	-- Right Hip
	local rightHip = Instance.new("Motor6D")
	rightHip.Name = "Right Hip"
	rightHip.Part0 = torso
	rightHip.Part1 = rightLeg
	rightHip.C0 = CFrame.new(0.5 * scale, -1 * scale, 0) * CFrame.Angles(0, math.rad(90), 0)
	rightHip.C1 = CFrame.new(0, 1 * scale, 0) * CFrame.Angles(0, math.rad(90), 0)
	rightHip.Parent = torso

	-- 6. Create the Humanoid
	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R6
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
	humanoid.HealthDisplayDistance = 0
	humanoid.NameDisplayDistance = 0
	humanoid.HipHeight = 0
	humanoid.Parent = character

	local animator = Instance.new("Animator")
	animator.Parent = humanoid

	character.PrimaryPart = rootPart

	-- Find wing part inside Buzz visual torso recursively and make it invisible by default
	local wingPart = vTorso:FindFirstChild("wing", true)
	if wingPart and wingPart:IsA("BasePart") then
		wingPart.Transparency = 1
		character:SetAttribute("WingsOut", false)

		-- Apply custom wing scaling if defined in config
		local wingScale = config.WingScale or 1.0
		if wingScale ~= 1.0 then
			local mesh = wingPart:FindFirstChildOfClass("SpecialMesh") or wingPart:FindFirstChildOfClass("FileMesh")
			if mesh then
				mesh.Scale = mesh.Scale * wingScale
			else
				wingPart.Size = wingPart.Size * wingScale
			end
		end
	end

	-- Setup metadata attributes
	character:SetAttribute("IsCustomCharacter", true)
	character:SetAttribute("CharacterName", characterName)

	return character
end

-- Create the ToggleWings RemoteEvent for network replication
local toggleWingsEvent = eventsFolder:FindFirstChild("ToggleWings")
if not toggleWingsEvent then
	toggleWingsEvent = Instance.new("RemoteEvent")
	toggleWingsEvent.Name = "ToggleWings"
	toggleWingsEvent.Parent = eventsFolder
end

toggleWingsEvent.OnServerEvent:Connect(function(player)
	local char = player.Character
	if char and char:GetAttribute("CharacterName") == "Buzz" then
		local visuals = char:FindFirstChild("Visuals")
		local vTorso = visuals and (visuals:FindFirstChild("Chest") or visuals:FindFirstChild("Torso"))
		local wing = vTorso and vTorso:FindFirstChild("wing", true)

		if wing and wing:IsA("BasePart") then
			local current = char:GetAttribute("WingsOut") or false
			local newStatus = not current

			char:SetAttribute("WingsOut", newStatus)
			wing.Transparency = newStatus and 0 or 1

			-- Play wing pop-out/retract mechanical click sound
			local sound = wing:FindFirstChild("PopSound")
			if not sound then
				sound = Instance.new("Sound")
				sound.Name = "PopSound"
				sound.SoundId = "rbxassetid://12222229" -- classic system click sound
				sound.Volume = 0.65
				sound.Parent = wing
			end
			sound:Play()
		end
	end
end)

-- Create the CaptureToy RemoteEvent
local captureToyEvent = eventsFolder:FindFirstChild("CaptureToy")
if not captureToyEvent then
	captureToyEvent = Instance.new("RemoteEvent")
	captureToyEvent.Name = "CaptureToy"
	captureToyEvent.Parent = eventsFolder
end

captureToyEvent.OnServerEvent:Connect(function(player, targetToy)
	local char = player.Character
	if not char or char:GetAttribute("CharacterName") ~= "Sid" then
		return
	end

	-- Make sure target is a valid custom toy character
	if not targetToy or not targetToy:IsA("Model") or not targetToy:GetAttribute("IsCustomCharacter") then
		return
	end

-- Create the BindableEvent for round end signaling
local endRoundBindable = eventsFolder:FindFirstChild("EndRoundBindable")
if not endRoundBindable then
	endRoundBindable = Instance.new("Bindable") -- Wait, in Roblox it's BindableEvent
	-- Let's make sure it is a BindableEvent
	local bindable = Instance.new("BindableEvent")
	bindable.Name = "EndRoundBindable"
	bindable.Parent = eventsFolder
	endRoundBindable = bindable
end

-- Create the StunHunter RemoteEvent
local stunHunterEvent = eventsFolder:FindFirstChild("StunHunter")
if not stunHunterEvent then
	stunHunterEvent = Instance.new("RemoteEvent")
	stunHunterEvent.Name = "StunHunter"
	stunHunterEvent.Parent = eventsFolder
end

captureToyEvent.OnServerEvent:Connect(function(player, targetToy)
	local char = player.Character
	if not char or char:GetAttribute("CharacterName") ~= "Sid" then
		return
	end

	-- Verify Sid is not currently stunned (WalkSpeed = 0)
	local sidHum = char:FindFirstChildOfClass("Humanoid")
	if sidHum and sidHum.WalkSpeed == 0 then
		return
	end

	-- Make sure target is a valid custom toy character
	if not targetToy or not targetToy:IsA("Model") or not targetToy:GetAttribute("IsCustomCharacter") then
		return
	end

	local targetName = targetToy:GetAttribute("CharacterName")
	if targetName == "Sid" then
		return
	end

	-- Check if target is already captured/caged
	if targetToy:GetAttribute("Captured") then
		return
	end

	local isLayingDown = targetToy:GetAttribute("IsLayingDown") or false

	if not isLayingDown then
		-- SUCCESS: Sid caught a toy moving!
		print("[ToyStory Server] Sid captured moving toy:", targetName)

		-- Play cartoon/crunch capture sound
		local head = char:FindFirstChild("Head")
		if head then
			local sound = Instance.new("Sound")
			sound.SoundId = "rbxassetid://2801263" -- classic crunch/destruction sound
			sound.Volume = 1.0
			sound.Parent = head
			sound:Play()
			game:GetService("Debris"):AddItem(sound, 3)
		end

		-- SPLIT THE TOY: Spawn a visual debris duplicate at the capture spot that tumbles/breaks apart!
		local visuals = targetToy:FindFirstChild("Visuals")
		if visuals then
			local clone = visuals:Clone()
			clone.Parent = workspace
			clone:PivotTo(targetToy:GetPivot())

			-- Strip joints/welds inside the clone
			for _, desc in clone:GetDescendants() do
				if desc:IsA("JointInstance") or desc:IsA("WeldConstraint") then
					desc:Destroy()
				end
			end

			-- Enable collisions and unanchor clone parts
			local rng = Random.new()
			for _, desc in clone:GetDescendants() do
				if desc:IsA("BasePart") then
					desc.CanCollide = true
					desc.Anchored = false
					desc.AssemblyLinearVelocity = Vector3.new(
						rng:NextNumber(-20, 20),
						rng:NextNumber(15, 30),
						rng:NextNumber(-20, 20)
					)
				end
			end
			game:GetService("Debris"):AddItem(clone, 8)
		end

		-- Teleport target player to Cage, set Captured attribute, and freeze movement
		targetToy:SetAttribute("Captured", true)
		targetToy:PivotTo(CFrame.new(0, 5, 40)) -- Teleport inside dynamic cage
		
		local targetHum = targetToy:FindFirstChildOfClass("Humanoid")
		if targetHum then
			targetHum.WalkSpeed = 0
			targetHum.JumpPower = 0
		end
	else
		-- MISTAKE: Attacked a toy that was playing dead!
		local mistakes = player:GetAttribute("SidMistakes") or 0
		mistakes = mistakes + 1
		player:SetAttribute("SidMistakes", mistakes)
		print("[ToyStory Server] Sid made a mistake! Total mistakes:", mistakes)

		-- Play buzz/error sound
		local head = char:FindFirstChild("Head")
		if head then
			local sound = Instance.new("Sound")
			sound.SoundId = "rbxassetid://4798150495" -- buzzer sound
			sound.Volume = 0.8
			sound.Parent = head
			sound:Play()
			game:GetService("Debris"):AddItem(sound, 3)
		end

		-- Apply penalties based on mistake count
		if mistakes == 1 then
			-- 1st Mistake: 4 seconds stun
			if sidHum then
				local config = CharacterConfig["Sid"]
				sidHum.WalkSpeed = 0
				sidHum.JumpPower = 0
				stunHunterEvent:FireClient(player, 4) -- Stun visual effect for 4s
				
				task.delay(4, function()
					if char and char.Parent then
						sidHum.WalkSpeed = config and config.WalkSpeed or 16
						sidHum.JumpPower = 50
					end
				end)
			end
		elseif mistakes == 2 then
			-- 2nd Mistake: Vision Distortion
			player:SetAttribute("SidDistorted", true)
		elseif mistakes >= 3 then
			-- 3rd Mistake: Immediate defeat! Fires round end to game manager
			local endRoundEvent = eventsFolder:FindFirstChild("EndRoundBindable")
			if endRoundEvent then
				endRoundEvent:Fire("ToysWin", "Sid made 3 mistakes! Toys Victory!")
			end
			player:SetAttribute("SidMistakes", 0)
			player:SetAttribute("SidDistorted", false)
		end
	end
end)

--- Swap current character with custom character
local function swapCharacter(player: Player, currentCharacter: Model, characterName: string)
	if swapping[player] then
		return
	end
	swapping[player] = true

	local template = nil
	if charactersFolder then
		template = charactersFolder:FindFirstChild(characterName)
		if not template and characterName == "PotatoHead" then
			template = charactersFolder:FindFirstChild("Model")
		end
	end
	if not template then
		template = ReplicatedStorage:FindFirstChild(characterName)
		if not template and characterName == "PotatoHead" then
			template = ReplicatedStorage:FindFirstChild("Model")
		end
	end
	-- Fallback: check workspace (for models placed directly in the game world)
	if not template then
		template = workspace:FindFirstChild(characterName)
			or workspace:FindFirstChild(characterName:lower())
	end

	if not template then
		warn(
			"[ToyStory Server] Template model not found for:",
			characterName,
			"(or 'Model') under ReplicatedStorage.Characters or ReplicatedStorage!"
		)
		swapping[player] = nil
		return
	end

	-- Get spawn position
	local spawnCFrame = currentCharacter:GetPivot()

	-- Analyze the old character's height so the custom one matches it exactly!
	local minY, maxY = getModelBoundsY(currentCharacter)
	local defaultHeight = math.max(5, maxY - minY)

	-- Get Animate LocalScript
	local animateSource = ReplicatedStorage:FindFirstChild("Shared")
		and ReplicatedStorage.Shared:FindFirstChild("CharacterAnimate")

	-- Build new custom character model
	local customCharacter = buildCustomCharacter(template, characterName, defaultHeight)
	if not customCharacter then
		swapping[player] = nil
		return
	end

	customCharacter.Name = player.Name

	-- Setup Animate script
	if animateSource then
		local animClone = animateSource:Clone()
		animClone.Name = "Animate"
		animClone.Disabled = true
		animClone.Parent = customCharacter
	end

	customCharacter:PivotTo(spawnCFrame)

	-- Destroy old character
	currentCharacter:Destroy()

	-- Parent and set character
	customCharacter.Parent = workspace
	player.Character = customCharacter

	-- Enable Animate script
	task.defer(function()
		local animScript = customCharacter:FindFirstChild("Animate")
		if animScript then
			animScript.Disabled = false
		end
	end)

	swapping[player] = nil
	print(
		"[ToyStory Server]",
		player.Name,
		"spawned as custom character:",
		characterName,
		"with height:",
		defaultHeight
	)
end

-- Listen to selection request
selectCharacterEvent.OnServerEvent:Connect(function(player, characterName)
	playerSelections[player] = characterName
	if player.Character then
		swapCharacter(player, player.Character, characterName)
	end
end)

-- Handle joins and respawns
local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character)
		task.wait(0.5)
		local selected = playerSelections[player]
		if selected and player.Character == character and not character:GetAttribute("IsCustomCharacter") then
			swapCharacter(player, character, selected)
		end
	end)
end

Players.PlayerRemoving:Connect(function(player)
	playerSelections[player] = nil
	swapping[player] = nil
end)

for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end
Players.PlayerAdded:Connect(onPlayerAdded)

print("[ToyStory Server] Selection and rigging systems initialized!")
