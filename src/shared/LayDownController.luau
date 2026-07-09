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

-- Internal state
local selectedPose = 1 -- 1 = Face Down, 2 = Back Down, 3 = Left Side, 4 = Right Side
local currentLayTransition = 0 -- 0 = standing, 1 = laying down

-- Model geometry cached during Init
local pivotToGround = 0
local modelExtents = Vector3.new(1, 1, 1)

--- Initialize the lay-down controller with character geometry.
function LayDownController.Init(character: Model, rootPart: BasePart)
	-- Calculate actual model bounds for proper lay-down positioning
	-- This accounts for models like Rex where a large MeshPart extends far
	-- beyond the tiny R6 skeleton parts
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

	-- Fire to server for name hiding replication
	local setFreezeStateEvent = eventsFolder:FindFirstChild("SetFreezeState")
	if setFreezeStateEvent then
		setFreezeStateEvent:FireServer(LayDownController.IsLayingDown)
	end

	if LayDownController.IsLayingDown then
		-- Randomly select a pose
		selectedPose = math.random(1, 4)

		-- Stop any active animation track when laying down
		if currentTrack then
			currentTrack:Stop(0.2)
		end
	end

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

	-- Use actual model bounds for lay-down offset so large-mesh characters
	-- like Rex rest on the ground properly instead of clipping through
	if selectedPose == 1 then
		-- Face Down (X rotation 90): depth (Z) becomes the resting dimension
		layDownRotation = CFrame.Angles(math.rad(90) * currentLayTransition, 0, 0)
		layDownOffsetHeight = -(pivotToGround - (modelExtents.Z / 2)) * currentLayTransition
	elseif selectedPose == 2 then
		-- Back Down (X rotation -90): depth (Z) becomes the resting dimension
		layDownRotation = CFrame.Angles(math.rad(-90) * currentLayTransition, 0, 0)
		layDownOffsetHeight = -(pivotToGround - (modelExtents.Z / 2)) * currentLayTransition
	elseif selectedPose == 3 then
		-- Left Side Down (Z rotation 90): width (X) becomes the resting dimension
		layDownRotation = CFrame.Angles(0, 0, math.rad(90) * currentLayTransition)
		layDownOffsetHeight = -(pivotToGround - (modelExtents.X / 2)) * currentLayTransition
	elseif selectedPose == 4 then
		-- Right Side Down (Z rotation -90): width (X) becomes the resting dimension
		layDownRotation = CFrame.Angles(0, 0, math.rad(-90) * currentLayTransition)
		layDownOffsetHeight = -(pivotToGround - (modelExtents.X / 2)) * currentLayTransition
	end

	local layDownTranslation = CFrame.new(0, layDownOffsetHeight, 0)

	return layDownTranslation, layDownRotation, currentLayTransition
end

return LayDownController
