--[[
	ToyStory - CharacterRigger (ModuleScript)
	Builds playable R6-skeleton characters from visual model templates.
	Handles scaling, skeleton generation, visual welding, Motor6D joints,
	wing accessories, and Humanoid creation.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CharacterConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CharacterConfig"))
local Utils = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Utils"))
local AutoGrouper = require(script.Parent:WaitForChild("AutoGrouper"))

local CharacterRigger = {}

--- Remove scripts from cloned model templates to prevent unintended execution.
local function removeScripts(model: Model)
	for _, desc in model:GetDescendants() do
		if desc:IsA("BaseScript") or desc:IsA("ModuleScript") then
			desc:Destroy()
		end
	end
end

--- Scale model uniformly around its pivot point.
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

--- Find a child Instance by name (Part or Model wrapper).
local function findVisualGroup(parent: Model, name: string): Instance?
	return parent:FindFirstChild(name)
end

--- Get the CFrame and Size of a visual group (whether it is a Part or Model).
local function getGroupBounds(instance: Instance): (CFrame, Vector3)
	if instance:IsA("BasePart") then
		return instance.CFrame, instance.Size
	elseif instance:IsA("Model") then
		return instance:GetPivot(), instance:GetExtentsSize()
	end
	return CFrame.new(), Vector3.new(1, 1, 1)
end

--- Weld all BaseParts inside an instance to a target skeleton part.
local function weldGroupToSkeletonPart(group: Instance, skeletonPart: BasePart)
	if group:IsA("BasePart") then
		group.Anchored = false
		group.CanCollide = false

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = skeletonPart
		weld.Part1 = group
		weld.Parent = group
	end

	-- Weld any nested BaseParts (e.g., children of parts like wings, accessories inside models)
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

--- Determine the forward-facing direction of the character model based on facial features.
--- Falls back to torso-to-head direction, then to pivot LookVector.
local function getVisualForwardDirection(visualModel: Model, originalTemplate: Model, torsoPos: Vector3): Vector3
	local faceParts = {}
	for _, desc in visualModel:GetDescendants() do
		if desc:IsA("BasePart") then
			local name = desc.Name:lower()
			if
				name:find("nose")
				or name:find("mouth")
				or name:find("eye")
				or name:find("jaw")
				or name:find("teeth")
				or name:find("snout")
			then
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
	local vHead = visualModel:FindFirstChild("Head")
	if vHead then
		local headCF = getGroupBounds(vHead)
		local dir = (headCF.Position - torsoPos) * Vector3.new(1, 0, 1)
		if dir.Magnitude > 0.1 then
			return dir.Unit
		end
	end

	-- Fallback 2: Horizontal lookVector from the original template's pivot CFrame
	local pivotLook = (originalTemplate:GetPivot().LookVector * Vector3.new(1, 0, 1))
	if pivotLook.Magnitude > 0.1 then
		return pivotLook.Unit
	end
	return Vector3.new(0, 0, -1) -- default Roblox forward
end

--- Create a fresh Humanoid with standard R6 settings and an Animator.
local function createHumanoid(character: Model, hipHeight: number): Humanoid
	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R6
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
	humanoid.HealthDisplayDistance = 0
	humanoid.NameDisplayDistance = 0
	humanoid.HipHeight = hipHeight
	humanoid.Parent = character

	local animator = Instance.new("Animator")
	animator.Parent = humanoid

	return humanoid
end

--- Create an invisible R6 skeleton part with given properties.
local function createSkeletonPart(name: string, size: Vector3, cf: CFrame, canCollide: boolean): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Transparency = 1
	part.CanCollide = canCollide
	part.Anchored = false
	part.CFrame = cf
	return part
end

--- Create a Motor6D joint connecting two skeleton parts.
local function createMotor6D(name: string, part0: BasePart, part1: BasePart, c0: CFrame, c1: CFrame, parent: BasePart): Motor6D
	local motor = Instance.new("Motor6D")
	motor.Name = name
	motor.Part0 = part0
	motor.Part1 = part1
	motor.C0 = c0
	motor.C1 = c1
	motor.Parent = parent
	return motor
end

--- Build a playable custom character from a model template.
--- Handles both pre-rigged R6 models (like Rex) and unstructured models
--- that need auto-grouping and full skeleton generation.
function CharacterRigger.Build(template: Model, characterName: string, targetHeight: number): Model?
	local config = CharacterConfig[characterName]
	if not config then
		warn("[ToyStory CharacterRigger] No config found for character:", characterName)
		return nil
	end

	-- 1. Clone and clean the visual template
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
		local minY, maxY = Utils.GetModelBoundsY(character)
		local currentHeight = maxY - minY
		if currentHeight > 0 then
			local scaleFactor = targetHeight / currentHeight
			scaleModel(character, scaleFactor)
		end

		local rootPos = existingRoot.Position.Y
		local feetDistance = rootPos - minY
		local exactHipHeight = feetDistance - (existingRoot.Size.Y / 2)

		createHumanoid(character, math.max(0.5, exactHipHeight))
		character.PrimaryPart = existingRoot
		character:SetAttribute("IsCustomCharacter", true)
		character:SetAttribute("CharacterName", characterName)

		return character
	end

	-- 2. Remove existing joints/welds that would conflict with the new R6 skeleton
	for _, desc in visualTemplate:GetDescendants() do
		if desc:IsA("JointInstance") or desc:IsA("WeldConstraint") then
			desc:Destroy()
		end
	end

	-- 3. Auto-group loose parts if needed
	AutoGrouper.AutoGroup(visualTemplate, characterName)

	-- 4. Scale the visual template
	local minY, maxY = Utils.GetModelBoundsY(visualTemplate)
	local currentHeight = maxY - minY
	if characterName == "Sid" then
		targetHeight = currentHeight -- Bypass scaling to keep original size
	end
	if currentHeight > 0 then
		local scaleFactor = targetHeight / currentHeight
		scaleModel(visualTemplate, scaleFactor)
		minY, maxY = Utils.GetModelBoundsY(visualTemplate) -- Recalculate
	end

	-- 5. Find visual groups in the scaled template
	local vTorso = findVisualGroup(visualTemplate, "Chest") or findVisualGroup(visualTemplate, "Torso")
	local vHead = findVisualGroup(visualTemplate, "Head")
	local vLeftArm = findVisualGroup(visualTemplate, "Left Arm")
	local vRightArm = findVisualGroup(visualTemplate, "Right Arm")
	local vLeftLeg = findVisualGroup(visualTemplate, "Left Leg")
	local vRightLeg = findVisualGroup(visualTemplate, "Right Leg")

	if not vTorso then
		warn("[ToyStory CharacterRigger] Chest/Torso visual group not found in template:", characterName)
		visualTemplate:Destroy()
		return nil
	end

	-- 6. Create the playable character Model wrapper
	local character = Instance.new("Model")
	character.Name = characterName .. "Character"
	visualTemplate.Parent = character

	-- Calculate standard R6 scale factor (standard R6 height is 5.0 studs)
	local scale = targetHeight / 5.0

	-- 7. Determine character facing direction
	local torsoCF = getGroupBounds(vTorso)
	local torsoPosition = torsoCF.Position
	local lookDir = getVisualForwardDirection(visualTemplate, template, torsoPosition)
	local torsoRotationCF = CFrame.lookAt(torsoPosition, torsoPosition + lookDir, Vector3.new(0, 1, 0))

	-- 8. Create invisible R6 skeleton parts
	local torso = createSkeletonPart("Torso", Vector3.new(2 * scale, 2 * scale, 1 * scale), torsoRotationCF, true)
	torso.Parent = character

	local rootPart = createSkeletonPart("HumanoidRootPart", Vector3.new(2 * scale, 2 * scale, 1 * scale), torsoRotationCF, false)
	rootPart.Parent = character

	local head = createSkeletonPart("Head", Vector3.new(1.2 * scale, 1.2 * scale, 1.2 * scale), torsoRotationCF * CFrame.new(0, 1.5 * scale, 0), false)
	head.Parent = character

	local leftArm = createSkeletonPart("Left Arm", Vector3.new(1 * scale, 2 * scale, 1 * scale), torsoRotationCF * CFrame.new(-1.5 * scale, 0, 0), false)
	leftArm.Parent = character

	local rightArm = createSkeletonPart("Right Arm", Vector3.new(1 * scale, 2 * scale, 1 * scale), torsoRotationCF * CFrame.new(1.5 * scale, 0, 0), false)
	rightArm.Parent = character

	local leftLeg = createSkeletonPart("Left Leg", Vector3.new(1 * scale, 2 * scale, 1 * scale), torsoRotationCF * CFrame.new(-0.5 * scale, -2 * scale, 0), true)
	leftLeg.Parent = character

	local rightLeg = createSkeletonPart("Right Leg", Vector3.new(1 * scale, 2 * scale, 1 * scale), torsoRotationCF * CFrame.new(0.5 * scale, -2 * scale, 0), true)
	rightLeg.Parent = character

	-- 9. Weld visual groups to skeleton parts
	weldGroupToSkeletonPart(vTorso, torso)
	if vHead then weldGroupToSkeletonPart(vHead, head) end
	if vLeftArm then weldGroupToSkeletonPart(vLeftArm, leftArm) end
	if vRightArm then weldGroupToSkeletonPart(vRightArm, rightArm) end
	if vLeftLeg then weldGroupToSkeletonPart(vLeftLeg, leftLeg) end
	if vRightLeg then weldGroupToSkeletonPart(vRightLeg, rightLeg) end

	-- 10. Create R6 Motor6D joints
	-- RootJoint
	createMotor6D("RootJoint", rootPart, torso,
		CFrame.new(0, 0, 0) * CFrame.Angles(math.rad(-90), 0, math.rad(180)),
		CFrame.new(0, 0, 0) * CFrame.Angles(math.rad(-90), 0, math.rad(180)),
		rootPart)

	-- Neck
	createMotor6D("Neck", torso, head,
		CFrame.new(0, 1 * scale, 0) * CFrame.Angles(math.rad(-90), 0, math.rad(180)),
		CFrame.new(0, -0.5 * scale, 0) * CFrame.Angles(math.rad(-90), 0, math.rad(180)),
		torso)

	-- Left Shoulder
	createMotor6D("Left Shoulder", torso, leftArm,
		CFrame.new(-1 * scale, 0.5 * scale, 0) * CFrame.Angles(0, math.rad(-90), 0),
		CFrame.new(0.5 * scale, 0.5 * scale, 0) * CFrame.Angles(0, math.rad(-90), 0),
		torso)

	-- Right Shoulder
	createMotor6D("Right Shoulder", torso, rightArm,
		CFrame.new(1 * scale, 0.5 * scale, 0) * CFrame.Angles(0, math.rad(90), 0),
		CFrame.new(-0.5 * scale, 0.5 * scale, 0) * CFrame.Angles(0, math.rad(90), 0),
		torso)

	-- Left Hip
	createMotor6D("Left Hip", torso, leftLeg,
		CFrame.new(-0.5 * scale, -1 * scale, 0) * CFrame.Angles(0, math.rad(-90), 0),
		CFrame.new(0, 1 * scale, 0) * CFrame.Angles(0, math.rad(-90), 0),
		torso)

	-- Right Hip
	createMotor6D("Right Hip", torso, rightLeg,
		CFrame.new(0.5 * scale, -1 * scale, 0) * CFrame.Angles(0, math.rad(90), 0),
		CFrame.new(0, 1 * scale, 0) * CFrame.Angles(0, math.rad(90), 0),
		torso)

	-- 11. Create the Humanoid
	local exactHipHeight = (characterName == "Sid" and 1.0 or 2.0) * scale
	createHumanoid(character, exactHipHeight)
	character.PrimaryPart = rootPart

	-- 12. Handle wing accessory (Buzz only)
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

	-- 13. Setup metadata attributes
	character:SetAttribute("IsCustomCharacter", true)
	character:SetAttribute("CharacterName", characterName)

	return character
end

return CharacterRigger
