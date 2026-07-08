--[[
	ToyStory - Character Animate Script (LocalScript)
	A generalized animation controller for all custom R6 characters.
	Reads configurations dynamically based on the character's designated template name.
]]

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local eventsFolder = ReplicatedStorage:WaitForChild("Events")

local character = script.Parent
local humanoid = character:WaitForChild("Humanoid", 10)
local rootPart = character:WaitForChild("HumanoidRootPart", 10)

if not humanoid then
	warn("[ToyStory Animate] No Humanoid found!")
	return
end

-- Get character configuration
local CharacterConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CharacterConfig"))

-- Wait for the CharacterName attribute to replicate from the server
local characterName = character:GetAttribute("CharacterName")
while not characterName do
	task.wait()
	characterName = character:GetAttribute("CharacterName")
end

local config = CharacterConfig[characterName]

if not config then
	warn("[ToyStory Animate] Configuration not found for character:", characterName)
	return
end

-- ========================================
-- Apply stats from config
-- ========================================
local WALK_SPEED = config.WalkSpeed
local RUN_SPEED = config.RunSpeed
humanoid.WalkSpeed = WALK_SPEED

-- ========================================
-- Load animations from config
-- ========================================
local tracks = {}
for name, assetId in config.Animations do
	local anim = Instance.new("Animation")
	anim.AnimationId = assetId
	anim.Name = name

	local success, track = pcall(function()
		return humanoid:LoadAnimation(anim)
	end)

	if success and track then
		tracks[name] = track
		if name == "jump" or name == "attack" then
			track.Looped = false
		else
			track.Looped = true
		end
	else
		warn("[ToyStory Animate] Failed to load animation:", name, "for character:", characterName)
	end
end

-- ========================================
-- Animation playback
-- ========================================
local currentTrack = nil
local currentName = ""
local ANIM_WEIGHT = config.AnimWeight or 0.9

local function playAnimation(name: string, speed: number?)
	speed = speed or 1

	if name == currentName then
		if currentTrack then
			currentTrack:AdjustSpeed(speed)
		end
		return
	end

	-- Stop current
	if currentTrack then
		currentTrack:Stop(0.2)
	end

	-- Play new
	local track = tracks[name]
	if track then
		track:Play(0.2, ANIM_WEIGHT)
		track:AdjustSpeed(speed)
		currentTrack = track
		currentName = name
	end
end

-- ========================================
-- Shift-to-run & Lay-Down input handling
-- ========================================
local isSprinting = false
local isLayingDown = false
local defaultJumpPower = humanoid.JumpPower
local selectedPose = 1 -- 1 = Face Down, 2 = Back Down, 3 = Left Side, 4 = Right Side

-- Get parts for collision toggling
local torsoPart = character:WaitForChild("Torso", 5)
local leftArmPart = character:FindFirstChild("Left Arm")
local rightArmPart = character:FindFirstChild("Right Arm")
local leftLegPart = character:FindFirstChild("Left Leg")
local rightLegPart = character:FindFirstChild("Right Leg")

-- Movement state handler: updates animations and lean angles based on current speed
local isJumping = false
local isFalling = false

local isFlying = false
local bodyVelocity = nil
local bodyGyro = nil
local FLY_SPEED = 40

-- Flight & Gliding states
local flightStartTime = 0
local cooldownEndTime = 0
local isGliding = false
local GLIDE_FORWARD_SPEED = 25
local GLIDE_DESCENT_SPEED = -6

-- UI Elements for Buzz Flight Timer / Cooldown
local Players = game:GetService("Players")
local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

local flightGui = nil
local barFrame = nil
local barFill = nil
local barLabel = nil

local function createFlightUI()
	if flightGui then flightGui:Destroy() end
	
	flightGui = Instance.new("ScreenGui")
	flightGui.Name = "FlightUI"
	flightGui.ResetOnSpawn = true
	
	-- Container frame at center-bottom
	barFrame = Instance.new("Frame")
	barFrame.Name = "BarFrame"
	barFrame.Size = UDim2.new(0, 240, 0, 20)
	barFrame.Position = UDim2.new(0.5, -120, 0.82, 0)
	barFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	barFrame.BorderSizePixel = 0
	barFrame.Visible = false
	barFrame.Parent = flightGui
	
	-- UICorner for rounded borders
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = barFrame
	
	-- UIStroke for a sleek outline border
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(60, 60, 60)
	stroke.Thickness = 1.5
	stroke.Parent = barFrame
	
	-- Bar Fill
	barFill = Instance.new("Frame")
	barFill.Name = "BarFill"
	barFill.Size = UDim2.new(1, 0, 1, 0)
	barFill.BackgroundColor3 = Color3.fromRGB(46, 204, 113) -- Emerald Green
	barFill.BorderSizePixel = 0
	barFill.Parent = barFrame
	
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 10)
	fillCorner.Parent = barFill
	
	-- Text Label
	barLabel = Instance.new("TextLabel")
	barLabel.Name = "BarLabel"
	barLabel.Size = UDim2.new(1, 0, 1, 0)
	barLabel.BackgroundTransparency = 1
	barLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	barLabel.Font = Enum.Font.GothamBold
	barLabel.TextSize = 11
	barLabel.Text = "FLYING: 3.0s"
	barLabel.Parent = barFrame
	
	flightGui.Parent = playerGui
end

if characterName == "Buzz" then
	createFlightUI()
end

local function updateFlightState(wingsOut: boolean)
	local wasFlying = isFlying
	isFlying = wingsOut
	if wingsOut then
		isSprinting = false
		isLayingDown = false
		flightStartTime = os.clock()
		isGliding = false

		if not bodyVelocity then
			bodyVelocity = Instance.new("BodyVelocity")
			bodyVelocity.Name = "FlightVelocity"
			bodyVelocity.MaxForce = Vector3.new(100000, 100000, 100000)
			bodyVelocity.Velocity = Vector3.new(0, 0, 0)
			bodyVelocity.Parent = rootPart
		end

		if not bodyGyro then
			bodyGyro = Instance.new("BodyGyro")
			bodyGyro.Name = "FlightGyro"
			bodyGyro.MaxTorque = Vector3.new(400000, 400000, 400000)
			local lookProj = (workspace.CurrentCamera.CFrame.LookVector * Vector3.new(1, 0, 1)).Unit
			bodyGyro.CFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + lookProj)
			bodyGyro.Parent = rootPart
		end

		humanoid.PlatformStand = true
		if currentTrack then
			currentTrack:Stop(0.2)
		end
	else
		if bodyVelocity then
			bodyVelocity:Destroy()
			bodyVelocity = nil
		end
		if bodyGyro then
			bodyGyro:Destroy()
			bodyGyro = nil
		end
		humanoid.PlatformStand = false
		targetLean = 0
		isGliding = false
		
		-- Trigger 5-second cooldown if we were actually flying/gliding before
		if wasFlying then
			cooldownEndTime = os.clock() + 5
		end
		
		updateSpeed()
	end
end

local function updateMovementState(speed: number)
	if isLayingDown or isFlying then
		return
	end

	if isJumping or isFalling then
		return
	end

	if speed < 0.5 then
		playAnimation("idle")
		targetLean = 0
	elseif isSprinting and speed > 1 then
		local runSpeed = math.clamp(speed / (RUN_SPEED * 0.55), 1.0, 2.0)
		playAnimation("run", runSpeed)
		targetLean = config.LeanAngle
	else
		local walkSpeed = math.clamp(speed / WALK_SPEED, 0.5, 1.2)
		playAnimation("walk", walkSpeed)
		targetLean = 0
	end
end

local function updateSpeed()
	if isLayingDown then
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0

		-- Disable collisions on ALL parts while laying down to prevent physics
		-- launching the character (especially important for models with large
		-- MeshParts like Rex that extend far beyond the R6 skeleton)
		for _, desc in character:GetDescendants() do
			if desc:IsA("BasePart") then
				desc.CanCollide = false
			end
		end
	elseif isFlying then
		-- Flight speed and physics are handled by BodyVelocity
		return
	else
		if isSprinting then
			humanoid.WalkSpeed = RUN_SPEED
		else
			humanoid.WalkSpeed = WALK_SPEED
		end
		humanoid.JumpPower = defaultJumpPower

		-- Restore standard R6 collision state when standing up
		for _, desc in character:GetDescendants() do
			if desc:IsA("BasePart") then
				local name = desc.Name
				if name == "Torso" or name == "Left Leg" or name == "Right Leg" or name == "HumanoidRootPart" then
					desc.CanCollide = true
				else
					desc.CanCollide = false
				end
			end
		end
	end

	-- Force update visual movement state immediately
	local currentSpeed = rootPart and rootPart.AssemblyLinearVelocity.Magnitude or 0
	-- If they are pressing movement keys, force speed to be > 1 to instantly trigger the run
	if isSprinting and humanoid.MoveDirection.Magnitude > 0.1 then
		currentSpeed = RUN_SPEED
	end
	updateMovementState(currentSpeed)
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end

	-- Shift to Sprint
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		if isFlying then
			return
		end -- can't sprint while flying
		isSprinting = true
		updateSpeed()

	-- Mouse 1 or Keypress E to Freeze / Play Dead (Toys only)
	elseif input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.E then
		if characterName == "Sid" then
			return
		end
		if isFlying then
			return
		end -- can't lay down while flying
		isLayingDown = not isLayingDown
		updateSpeed()
		character:SetAttribute("IsLayingDown", isLayingDown)

		if isLayingDown then
			-- Character-specific lifeless freeze poses
			if characterName == "PotatoHead" then
				selectedPose = math.random(3, 4) -- Flops on left/right side
			elseif characterName == "Woody" or characterName == "Buzz" then
				selectedPose = math.random(1, 2) -- Falls flat on face/back
			else
				selectedPose = 0 -- Stand rigid upright (Rex, Slinky)
			end

			-- Stop any active animation track when laying down
			if currentTrack then
				currentTrack:Stop(0.2)
			end
			
			-- Hide username name tag
			humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		else
			-- Restore username name tag
			humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
		end

	-- Keypress "1" to Toggle Wings (Buzz only)
	elseif input.KeyCode == Enum.KeyCode.One or input.KeyCode == Enum.KeyCode.KeypadOne then
		if isLayingDown then return end -- can't fly while laying down
		if characterName == "Buzz" then
			-- Enforce flight cooldown on client
			if os.clock() < cooldownEndTime then
				return
			end
			
			local toggleWingsEvent = eventsFolder:FindFirstChild("ToggleWings")
			if toggleWingsEvent then
				toggleWingsEvent:FireServer()
			end
		end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		isSprinting = false
		updateSpeed()
	end
end)

-- ========================================
-- Forward lean & Lay down rotation (RootJoint tilt)
-- ========================================
local rootJoint = rootPart:WaitForChild("RootJoint", 10)
local originalRootC0 = rootJoint and rootJoint.C0 or nil

local currentLean = 0
local targetLean = 0
local LEAN_SMOOTHING = config.LeanAngle ~= 0 and 0.15 or 1

-- Lay down translation/rotation settings
local currentLayTransition = 0 -- 0 = standing, 1 = laying down
local targetLayTransition = 0

-- Calculate actual model bounds for proper lay-down positioning
-- This accounts for models like Rex where a large MeshPart extends far
-- beyond the tiny R6 skeleton parts
local modelBoundsMin = Vector3.new(math.huge, math.huge, math.huge)
local modelBoundsMax = Vector3.new(-math.huge, -math.huge, -math.huge)

for _, desc in character:GetDescendants() do
	if desc:IsA("BasePart") then
		local pos = desc.CFrame.Position
		local half = desc.Size / 2
		modelBoundsMin = Vector3.new(
			math.min(modelBoundsMin.X, pos.X - half.X),
			math.min(modelBoundsMin.Y, pos.Y - half.Y),
			math.min(modelBoundsMin.Z, pos.Z - half.Z)
		)
		modelBoundsMax = Vector3.new(
			math.max(modelBoundsMax.X, pos.X + half.X),
			math.max(modelBoundsMax.Y, pos.Y + half.Y),
			math.max(modelBoundsMax.Z, pos.Z + half.Z)
		)
	end
end

local modelExtents = modelBoundsMax - modelBoundsMin -- full width (X), height (Y), depth (Z)
local pivotToGround = rootPart.Position.Y - modelBoundsMin.Y -- how high pivot is above feet

-- Keep torsoSize as a fallback reference for ground collision ray
local torsoSize = character:WaitForChild("Torso").Size
local legSize = character:FindFirstChild("Left Leg") and character["Left Leg"].Size or Vector3.new(0, torsoSize.Y, 0)

local function checkGroundCollision()
	local rayOrigin = rootPart.Position
	-- Check if feet are within 2.0 studs of the ground (cuts glide a little above the ground)
	local rayDirection = Vector3.new(0, -(torsoSize.Y / 2 + legSize.Y + 4.0), 0)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterDescendantsInstances = { character }
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude

	local result = workspace:Raycast(rayOrigin, rayDirection, raycastParams)
	return result ~= nil
end

if rootJoint and originalRootC0 then
	RunService.RenderStepped:Connect(function()
		-- Update Flight/Cooldown Progression UI dynamically
		if characterName == "Buzz" and barFrame and barFill and barLabel then
			local now = os.clock()
			
			if isFlying then
				barFrame.Visible = true
				if not isGliding then
					local elapsed = now - flightStartTime
					local remaining = math.max(0, 3 - elapsed)
					local pct = remaining / 3
					
					barFill.Size = UDim2.new(pct, 0, 1, 0)
					barFill.BackgroundColor3 = Color3.fromRGB(46, 204, 113) -- Emerald Green
					barLabel.Text = string.format("FLYING: %.1fs", remaining)
				else
					barFill.Size = UDim2.new(1, 0, 1, 0)
					barFill.BackgroundColor3 = Color3.fromRGB(231, 76, 60) -- Alizarin Red
					barLabel.Text = "FALLING WITH STYLE (GLIDING)"
				end
			elseif now < cooldownEndTime then
				barFrame.Visible = true
				local remaining = cooldownEndTime - now
				local pct = 1 - (remaining / 5)
				
				barFill.Size = UDim2.new(pct, 0, 1, 0)
				barFill.BackgroundColor3 = Color3.fromRGB(230, 126, 34) -- Carrot Orange (Recharging)
				barLabel.Text = string.format("RECHARGING: %.1fs", remaining)
			else
				-- Ready and not flying
				if barFrame.Visible then
					barFill.Size = UDim2.new(1, 0, 1, 0)
					barFill.BackgroundColor3 = Color3.fromRGB(46, 204, 113) -- Emerald Green
					barLabel.Text = "WINGS READY!"
					
					task.delay(1, function()
						if not isFlying and os.clock() >= cooldownEndTime then
							barFrame.Visible = false
						end
					end)
				end
			end
		end

		-- If flying, handle flight/glide physics and movement controls
		if isFlying and bodyVelocity and bodyGyro then
			local camera = workspace.CurrentCamera
			local camCF = camera.CFrame

			local elapsed = os.clock() - flightStartTime
			if elapsed > 3 then
				isGliding = true
			end

			-- Automatic landing detection (retract wings and recover)
			if elapsed > 0.5 and checkGroundCollision() then
				local toggleWingsEvent = eventsFolder:FindFirstChild("ToggleWings")
				if toggleWingsEvent then
					updateFlightState(false) -- Instantly shut down flight physics on client to prevent multiple fires
					toggleWingsEvent:FireServer()
				end
				return
			end

			local isW = UserInputService:IsKeyDown(Enum.KeyCode.W)
			local isS = UserInputService:IsKeyDown(Enum.KeyCode.S)
			local isA = UserInputService:IsKeyDown(Enum.KeyCode.A)
			local isD = UserInputService:IsKeyDown(Enum.KeyCode.D)

			if isGliding then
				-- GLIDING MODE: Slow descent, horizontal steering with WASD
				local moveDir = Vector3.new(0, 0, 0)
				local horizontalProj = (camCF.LookVector * Vector3.new(1, 0, 1)).Unit
				local rightProj = camCF.RightVector

				if isW then
					moveDir = moveDir + horizontalProj
				end
				if isS then
					moveDir = moveDir - horizontalProj
				end
				if isA then
					moveDir = moveDir - rightProj
				end
				if isD then
					moveDir = moveDir + rightProj
				end

				if moveDir.Magnitude > 0 then
					moveDir = moveDir.Unit
				else
					-- If hands off keyboard, glide forward in the direction he faces
					moveDir = (rootPart.CFrame.LookVector * Vector3.new(1, 0, 1)).Unit
				end

				bodyVelocity.Velocity = moveDir * GLIDE_FORWARD_SPEED + Vector3.new(0, GLIDE_DESCENT_SPEED, 0)
				targetLean = math.rad(60) -- same 60 degree tilt while gliding
			else
				-- ACTIVE FLYING MODE (Under 3 seconds): Space/Ctrl and camera height steering
				local isSpace = UserInputService:IsKeyDown(Enum.KeyCode.Space)
				local isCtrl = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)

				local flyDir = Vector3.new(0, 0, 0)
				if isW then
					flyDir = flyDir + camCF.LookVector
				end
				if isS then
					flyDir = flyDir - camCF.LookVector
				end
				if isA then
					flyDir = flyDir - camCF.RightVector
				end
				if isD then
					flyDir = flyDir + camCF.RightVector
				end
				if isSpace then
					flyDir = flyDir + Vector3.new(0, 1, 0)
				end
				if isCtrl then
					flyDir = flyDir - Vector3.new(0, 1, 0)
				end

				if flyDir.Magnitude > 0 then
					flyDir = flyDir.Unit
					bodyVelocity.Velocity = flyDir * FLY_SPEED

					-- Lean forward heavily when moving
					if isW or isS or isA or isD then
						targetLean = math.rad(60) -- Superman flying tilt
					else
						targetLean = 0
					end
				else
					bodyVelocity.Velocity = Vector3.new(0, 0, 0)
					targetLean = 0
				end
			end

			-- Rotate character to match horizontal camera direction
			local lookProj = (camCF.LookVector * Vector3.new(1, 0, 1)).Unit
			if lookProj.Magnitude > 0 then
				bodyGyro.CFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + lookProj)
			end
		end

		-- Update forward lean interpolation
		currentLean = currentLean + (targetLean - currentLean) * LEAN_SMOOTHING

		-- Update lay down interpolation
		targetLayTransition = isLayingDown and 1 or 0
		currentLayTransition = currentLayTransition + (targetLayTransition - currentLayTransition) * 0.2

		-- Calculate rotation and vertical offset based on selected random pose
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
		else
			-- selectedPose == 0: Stand rigid upright (no tilt/offset)
			layDownRotation = CFrame.new()
			layDownOffsetHeight = 0
		end

		local layDownTranslation = CFrame.new(0, layDownOffsetHeight, 0)

		-- Pre-multiply translation and rotation in unrotated HumanoidRootPart space (far left)
		rootJoint.C0 = layDownTranslation
			* layDownRotation
			* originalRootC0
			* CFrame.Angles(currentLean * (1 - currentLayTransition), 0, 0)
	end)
end

-- ========================================
-- State handling
-- ========================================
local isJumping = false
local isFalling = false

humanoid.Running:Connect(updateMovementState)

humanoid.Jumping:Connect(function(active)
	if isLayingDown or isFlying then
		return
	end
	if active then
		isJumping = true
		isFalling = false
		playAnimation("jump")
		targetLean = 0
	end
end)

humanoid.FreeFalling:Connect(function(active)
	if isLayingDown or isFlying then
		return
	end
	if active then
		isFalling = true
		isJumping = false
		playAnimation("fall")
		targetLean = 0
	end
end)

humanoid.Climbing:Connect(function(speed)
	if isLayingDown or isFlying then
		return
	end
	if math.abs(speed) > 0.1 then
		playAnimation("climb")
		targetLean = 0
	end
end)

humanoid.StateChanged:Connect(function(_oldState, newState)
	if isLayingDown or isFlying then
		return
	end
	if newState == Enum.HumanoidStateType.Landed then
		isJumping = false
		isFalling = false
	end
end)

-- Connect WingsOut attribute changed listener to trigger flight mechanics
character:GetAttributeChangedSignal("WingsOut"):Connect(function()
	local wingsOut = character:GetAttribute("WingsOut") or false
	updateFlightState(wingsOut)
end)

-- Check initial state on load
local initialWings = character:GetAttribute("WingsOut") or false
if initialWings then
	updateFlightState(true)
end

-- Start with idle
playAnimation("idle")

-- ========================================
-- FOOTSTEP SOUND ADJUSTMENT
-- ========================================
-- Sid walking sound is much louder and heavier; toys are quiet
task.spawn(function()
	local runningSound = torsoPart:WaitForChild("Running", 8) or character:WaitForChild("Head", 8):WaitForChild("Running", 8)
	if runningSound and runningSound:IsA("Sound") then
		if characterName == "Sid" then
			runningSound.Volume = 3.0
			runningSound.PlaybackSpeed = 0.8
		else
			runningSound.Volume = 0.15
		end
	end
end)

-- ========================================
-- SID CAPTURE & MISTAKE MECHANICS
-- ========================================
if characterName == "Sid" then
	local camera = workspace.CurrentCamera
	local mouse = localPlayer:GetMouse()

	-- Create Mistakes GUI for Sid
	local mistakesGui = Instance.new("ScreenGui")
	mistakesGui.Name = "SidMistakesGui"
	mistakesGui.ResetOnSpawn = true

	local label = Instance.new("TextLabel")
	label.Name = "MistakesLabel"
	label.Size = UDim2.new(0, 300, 0, 50)
	label.Position = UDim2.new(0.5, -150, 0.05, 0)
	label.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
	label.BackgroundTransparency = 0.3
	label.TextColor3 = Color3.fromRGB(255, 75, 75)
	label.Font = Enum.Font.FredokaOne
	label.TextSize = 22
	label.Text = "MISTAKES: 0 / 3"
	label.Parent = mistakesGui

	-- Add UICorner & Stroke for premium look
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = label

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 75, 75)
	stroke.Thickness = 1.5
	stroke.Parent = label

	mistakesGui.Parent = playerGui

	-- Listen for mistake updates from server
	localPlayer:GetAttributeChangedSignal("SidMistakes"):Connect(function()
		local mistakes = localPlayer:GetAttribute("SidMistakes") or 0
		label.Text = string.format("MISTAKES: %d / 3", mistakes)
		if mistakes >= 3 then
			label.TextColor3 = Color3.fromRGB(255, 0, 0)
			label.Text = "GAME OVER - TOO MANY MISTAKES!"
		end
	end)

	local lastAttackTime = 0
	local function playAttackAnimation()
		local track = tracks["attack"]
		if track then
			-- Temporarily stop the current movement track
			if currentTrack then
				currentTrack:Stop(0.1)
			end
			
			local prevName = currentName
			currentTrack = track
			currentName = "attack"
			track:Play(0.1, ANIM_WEIGHT)
			
			-- Once attack finishes, resume idle/walk animation state
			task.delay(track.Length > 0 and track.Length or 0.6, function()
				if currentName == "attack" then
					currentTrack = nil
					currentName = ""
					local speed = rootPart and rootPart.AssemblyLinearVelocity.Magnitude or 0
					updateMovementState(speed)
				end
			end)
		end
	end

	-- Sid Attack/Capture Click Input
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end

		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			local now = os.clock()
			if now - lastAttackTime < 0.8 then return end -- Attack cooldown
			lastAttackTime = now

			-- Play attack animation locally
			playAttackAnimation()

			-- Raycast from mouse to find clicked character
			local ray = camera:ScreenPointToRay(mouse.X, mouse.Y)
			local raycastParams = RaycastParams.new()
			raycastParams.FilterDescendantsInstances = { character }
			raycastParams.FilterType = Enum.RaycastFilterType.Exclude

			local result = workspace:Raycast(ray.Origin, ray.Direction * 150, raycastParams)
			if result and result.Instance then
				-- Find character model
				local targetModel = result.Instance:FindFirstAncestorOfClass("Model")
				if targetModel and targetModel:GetAttribute("IsCustomCharacter") then
					local targetName = targetModel:GetAttribute("CharacterName")
					if targetName and targetName ~= "Sid" then
						-- Range check: Sid must be close enough (e.g. 50 studs)
						local dist = (rootPart.Position - result.Position).Magnitude
						if dist <= 50 then
							-- Request capture
							local captureToyEvent = eventsFolder:FindFirstChild("CaptureToy")
							if captureToyEvent then
								captureToyEvent:FireServer(targetModel)
							end
						end
					end
				end
			end
		end
	end)
end

-- ========================================
-- STUN HUNTER EFFECT (Sid only)
-- ========================================
if characterName == "Sid" then
	local stunEvent = eventsFolder:WaitForChild("StunHunter", 8)
	if stunEvent then
		stunEvent.OnClientEvent:Connect(function(duration)
			-- Show Screen Stun Text
			local stunGui = Instance.new("ScreenGui")
			stunGui.Name = "StunGui"
			
			local text = Instance.new("TextLabel")
			text.Size = UDim2.new(0, 400, 0, 80)
			text.Position = UDim2.new(0.5, -200, 0.4, -40)
			text.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
			text.BackgroundTransparency = 0.5
			text.TextColor3 = Color3.fromRGB(255, 50, 50)
			text.Font = Enum.Font.FredokaOne
			text.TextSize = 36
			text.Text = "STUNNED & EMBARRASSED!"
			text.Parent = stunGui

			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, 12)
			corner.Parent = text
			
			stunGui.Parent = playerGui

			-- Play camera shake during stun
			local camera = workspace.CurrentCamera
			local start = os.clock()
			local connection
			connection = RunService.RenderStepped:Connect(function()
				local elapsed = os.clock() - start
				if elapsed >= duration then
					connection:Disconnect()
					stunGui:Destroy()
				else
					-- Random shake
					local shake = Vector3.new(
						math.random(-10, 10) * 0.05,
						math.random(-10, 10) * 0.05,
						0
					)
					camera.CFrame = camera.CFrame * CFrame.new(shake)
				end
			end)
		end)
	end
end

-- ========================================
-- DYNAMIC SOUNDS & PROXIMITY VFX (Toys only)
-- ========================================
if characterName ~= "Sid" then
	local camera = workspace.CurrentCamera

	-- Heartbeat sound loop
	local heartbeatSound = Instance.new("Sound")
	heartbeatSound.Name = "HeartbeatLoop"
	heartbeatSound.SoundId = "rbxassetid://9114227181"
	heartbeatSound.Volume = 0
	heartbeatSound.Looped = true
	heartbeatSound.Parent = rootPart
	heartbeatSound:Play()

	-- Track Land Noise
	humanoid.StateChanged:Connect(function(oldState, newState)
		if newState == Enum.HumanoidStateType.Landed then
			-- Loud landing noise!
			local landSound = Instance.new("Sound")
			landSound.SoundId = "rbxassetid://9114223126" -- deep thump landing sound
			landSound.Volume = 0.8
			landSound.Parent = rootPart
			landSound:Play()
			game:GetService("Debris"):AddItem(landSound, 3)

			-- Temporarily alert the game of land noise
			character:SetAttribute("LandedNoise", true)
			task.delay(1.5, function()
				character:SetAttribute("LandedNoise", false)
			end)
		end
	end)

	-- Proximity Loop: Footstep vibration, heartbeat speed, object shaking
	task.spawn(function()
		while true do
			task.wait(0.1)

			-- Find the Hunter player (Sid)
			local hunterChar = nil
			for _, otherPlayer in Players:GetPlayers() do
				local otherChar = otherPlayer.Character
				if otherChar and otherChar:GetAttribute("CharacterName") == "Sid" then
					hunterChar = otherChar
					break
				end
			end

			if hunterChar and hunterChar:FindFirstChild("HumanoidRootPart") then
				local hunterRoot = hunterChar.HumanoidRootPart
				local hunterHum = hunterChar:FindFirstChildOfClass("Humanoid")
				
				local dist = (rootPart.Position - hunterRoot.Position).Magnitude

				-- 1. Heartbeat VFX/SFX volume scaling
				if dist < 80 then
					heartbeatSound.Volume = math.clamp((80 - dist) / 60 * 0.8, 0.1, 0.8)
					heartbeatSound.PlaybackSpeed = math.clamp(1.0 + (80 - dist) / 80 * 0.7, 1.0, 1.7)
				else
					heartbeatSound.Volume = 0
				end

				-- 2. Footstep Screen Shake
				-- Only shakes screen if Sid is active/moving
				if dist < 60 and hunterHum and hunterHum.MoveDirection.Magnitude > 0 then
					local shakeFactor = math.clamp((60 - dist) / 60, 0, 1)
					local intensity = shakeFactor * 0.25
					
					-- Apply quick random shake
					local shake = Vector3.new(
						math.random(-10, 10) * 0.01 * intensity,
						math.random(-10, 10) * 0.01 * intensity,
						0
					)
					camera.CFrame = camera.CFrame * CFrame.new(shake)
				end
			else
				heartbeatSound.Volume = 0
			end
		end
	end)
end

-- ========================================
-- DYNAMIC SURFACE FOOTSTEP VOLUME LOOP (All)
-- ========================================
task.spawn(function()
	local runningSound = torsoPart:WaitForChild("Running", 8) or character:WaitForChild("Head", 8):WaitForChild("Running", 8)
	if runningSound and runningSound:IsA("Sound") then
		local baseMaxVolume = characterName == "Sid" and 3.0 or 0.15

		while true do
			task.wait(0.25)
			if humanoid.MoveDirection.Magnitude > 0.01 then
				-- Raycast down to find ground material
				local raycastParams = RaycastParams.new()
				raycastParams.FilterDescendantsInstances = { character }
				raycastParams.FilterType = Enum.RaycastFilterType.Exclude

				local result = workspace:Raycast(rootPart.Position, Vector3.new(0, -10, 0), raycastParams)
				if result then
					local mat = result.Material
					local multiplier = 1.0

					if mat == Enum.Material.Fabric or mat == Enum.Material.Sand or mat == Enum.Material.Grass then
						multiplier = 0.2 -- Carpet/Soft (very quiet)
					elseif mat == Enum.Material.Wood or mat == Enum.Material.WoodPlanks then
						multiplier = 0.65 -- Wood (moderate)
					elseif mat == Enum.Material.Concrete or mat == Enum.Material.Metal or mat == Enum.Material.DiamondPlate then
						multiplier = 1.0 -- Concrete/Metal (loud)
					elseif mat == Enum.Material.Plastic or mat == Enum.Material.SmoothPlastic then
						multiplier = 1.5 -- Plastic Blocks (extremely loud)
					end

					runningSound.Volume = baseMaxVolume * multiplier
				end
			end
		end
	end
end)

-- ========================================
-- DISTORTED VISION (Sid 2nd mistake penalty)
-- ========================================
if characterName == "Sid" then
	local lighting = game:GetService("Lighting")
	local blurEffect = nil
	local ccEffect = nil

	localPlayer:GetAttributeChangedSignal("SidDistorted"):Connect(function()
		local distorted = localPlayer:GetAttribute("SidDistorted") or false
		if distorted then
			-- Apply heavy screen blur & color distortion
			if not blurEffect then
				blurEffect = Instance.new("BlurEffect")
				blurEffect.Size = 24
				blurEffect.Parent = camera
			end
			if not ccEffect then
				ccEffect = Instance.new("ColorCorrectionEffect")
				ccEffect.Saturation = -0.6
				ccEffect.Contrast = 0.4
				ccEffect.Parent = lighting
			end
		else
			-- Clean up effects
			if blurEffect then
				blurEffect:Destroy()
				blurEffect = nil
			end
			if ccEffect then
				ccEffect:Destroy()
				ccEffect = nil
			end
		end
	end)
end

print("[ToyStory Animate] Character animation controller loaded for " .. characterName)
