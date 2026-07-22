--[[
	ToyStory - LayDownController (ModuleScript)
	Handles the toy "play dead" / freeze mechanic: toggle input, random pose
	selection, RootJoint rotation math, and server freeze state replication.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local eventsFolder = ReplicatedStorage:WaitForChild("Events")

local LayDownController = {}

-- State
LayDownController.IsLayingDown = false
LayDownController.IsOnCooldown = false
LayDownController.selectedPose = 1 -- 1 = Face Down, 2 = Back Down, 3 = Left Side, 4 = Right Side

local TOGGLE_COOLDOWN = 1.0 -- seconds between toggles

-- Internal state
local currentLayTransition = 0 -- 0 = standing, 1 = laying down
local originalRootC0 = nil

-- Model geometry cached during Init
local pivotToGround = 0
local modelExtents = Vector3.new(1, 1, 1)
local GROUND_HUG_OFFSET = 0.3 -- extra studs downward to compensate for AABB overestimation

--- Initialize the lay-down controller with character geometry.
function LayDownController.Init(character: Model, rootPart: BasePart)
	local rootJoint = rootPart:WaitForChild("RootJoint", 10)
	if rootJoint then
		originalRootC0 = rootJoint.C0
	end

	-- Calculate actual model bounds for proper lay-down positioning
	local boundsMin = Vector3.new(math.huge, math.huge, math.huge)
	local boundsMax = Vector3.new(-math.huge, -math.huge, -math.huge)

	for _, desc in character:GetDescendants() do
		if desc:IsA("BasePart") then
			local pos = desc.CFrame.Position
			local half = desc.Size / 2
			boundsMin = Vector3.new(
				math.min(boundsMin.X, pos.X - half.X),
				math.min(boundsMin.Y, pos.Y - half.Y),
				math.min(boundsMin.Z, pos.Z - half.Z)
			)
			boundsMax = Vector3.new(
				math.max(boundsMax.X, pos.X + half.X),
				math.max(boundsMax.Y, pos.Y + half.Y),
				math.max(boundsMax.Z, pos.Z + half.Z)
			)
		end
	end

	modelExtents = boundsMax - boundsMin
	pivotToGround = rootPart.Position.Y - boundsMin.Y
end

--- Toggle the lay-down state. Returns the new isLayingDown value.
function LayDownController.Toggle(character: Model, currentTrack: AnimationTrack?): boolean
	LayDownController.IsLayingDown = not LayDownController.IsLayingDown

	character:SetAttribute("IsLayingDown", LayDownController.IsLayingDown)

	local targetC0 = originalRootC0

	if LayDownController.IsLayingDown then
		-- Randomly select a pose
		LayDownController.selectedPose = math.random(1, 4)

		-- Stop any active animation track when laying down
		if currentTrack then
			currentTrack:Stop(0.2)
		end

		-- Calculate the final target CFrame directly on the client to send to the server
		local layDownRotation = CFrame.new()
		local layDownOffsetHeight = 0

		if LayDownController.selectedPose == 1 then
			layDownRotation = CFrame.Angles(math.rad(90), 0, 0)
			layDownOffsetHeight = -(pivotToGround - (modelExtents.Z / 2)) - GROUND_HUG_OFFSET
		elseif LayDownController.selectedPose == 2 then
			layDownRotation = CFrame.Angles(math.rad(-90), 0, 0)
			layDownOffsetHeight = -(pivotToGround - (modelExtents.Z / 2)) - GROUND_HUG_OFFSET
		elseif LayDownController.selectedPose == 3 then
			layDownRotation = CFrame.Angles(0, 0, math.rad(90))
			layDownOffsetHeight = -(pivotToGround - (modelExtents.X / 2)) - GROUND_HUG_OFFSET
		elseif LayDownController.selectedPose == 4 then
			layDownRotation = CFrame.Angles(0, 0, math.rad(-90))
			layDownOffsetHeight = -(pivotToGround - (modelExtents.X / 2)) - GROUND_HUG_OFFSET
		end

		local layDownTranslation = CFrame.new(0, layDownOffsetHeight, 0)
		if originalRootC0 then
			targetC0 = layDownTranslation * layDownRotation * originalRootC0
		end
	end

	-- Fire to server for replication (replicates exact joint CFrame directly)
	local setFreezeStateEvent = eventsFolder:FindFirstChild("SetFreezeState")
	if setFreezeStateEvent then
		setFreezeStateEvent:FireServer(LayDownController.IsLayingDown, targetC0)
	end

	-- Start cooldown to prevent spam-toggling
	LayDownController.IsOnCooldown = true
	task.delay(TOGGLE_COOLDOWN, function()
		LayDownController.IsOnCooldown = false
	end)

	return LayDownController.IsLayingDown
end

--- Calculate the RootJoint CFrame modifiers for the current lay-down state.
--- Called each frame from RenderStepped to smoothly interpolate the transition.
--- Returns (layDownTranslation, layDownRotation, updatedTransition).
function LayDownController.UpdateFrame(): (CFrame, CFrame, number)
	local targetTransition = LayDownController.IsLayingDown and 1 or 0
	currentLayTransition = currentLayTransition + (targetTransition - currentLayTransition) * 0.2

	local layDownRotation = CFrame.new()
	local layDownOffsetHeight = 0

	if LayDownController.selectedPose == 1 then
		layDownRotation = CFrame.Angles(math.rad(90) * currentLayTransition, 0, 0)
		layDownOffsetHeight = (-(pivotToGround - (modelExtents.Z / 2)) - GROUND_HUG_OFFSET) * currentLayTransition
	elseif LayDownController.selectedPose == 2 then
		layDownRotation = CFrame.Angles(math.rad(-90) * currentLayTransition, 0, 0)
		layDownOffsetHeight = (-(pivotToGround - (modelExtents.Z / 2)) - GROUND_HUG_OFFSET) * currentLayTransition
	elseif LayDownController.selectedPose == 3 then
		layDownRotation = CFrame.Angles(0, 0, math.rad(90) * currentLayTransition)
		layDownOffsetHeight = (-(pivotToGround - (modelExtents.X / 2)) - GROUND_HUG_OFFSET) * currentLayTransition
	elseif LayDownController.selectedPose == 4 then
		layDownRotation = CFrame.Angles(0, 0, math.rad(-90) * currentLayTransition)
		layDownOffsetHeight = (-(pivotToGround - (modelExtents.X / 2)) - GROUND_HUG_OFFSET) * currentLayTransition
	end

	local layDownTranslation = CFrame.new(0, layDownOffsetHeight, 0)

	return layDownTranslation, layDownRotation, currentLayTransition
end

return LayDownController
