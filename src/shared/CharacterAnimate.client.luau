--[[
	ToyStory - Character Animate Script (LocalScript)
	Core animation controller for all custom R6 characters.
	Reads configurations dynamically based on the character's designated template name.
	Delegates flight, combat, proximity, and lay-down to focused sub-modules.
]]

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")
local Utils = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Utils"))

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

-- Force Camera Mode based on character type
if characterName == "Sid" then
	localPlayer.CameraMode = Enum.CameraMode.LockFirstPerson
else
	localPlayer.CameraMode = Enum.CameraMode.Classic
end

-- Load sub-modules
local FlightController = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("FlightController"))
local ProximityEffects = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ProximityEffects"))
local SidCombatController = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SidCombatController"))
local LayDownController = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("LayDownController"))

-- ========================================
-- Apply stats from config
-- ========================================
local WALK_SPEED = config.WalkSpeed
local RUN_SPEED = config.RunSpeed
humanoid.WalkSpeed = WALK_SPEED

-- ========================================
-- Load animations from config
-- ========================================
local tracks: { [string]: AnimationTrack } = {}
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
local currentTrack: AnimationTrack? = nil
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
-- Movement state
-- ========================================
local isSprinting = false
local isJumping = false
local isFalling = false
local defaultJumpPower = humanoid.JumpPower

-- Forward lean
local currentLean = 0
local targetLean = 0
local LEAN_SMOOTHING = config.LeanAngle ~= 0 and 0.15 or 1

--- Update animation based on current movement speed.
local function updateMovementState(speed: number)
	if LayDownController.IsLayingDown or FlightController.IsFlying then
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

local function showHidingWarning(text: string)
	local screenGui = playerGui:FindFirstChild("ToyWarningGui")
	if not screenGui then
		screenGui = Instance.new("ScreenGui")
		screenGui.Name = "ToyWarningGui"
		screenGui.Parent = playerGui
	end

	local label = screenGui:FindFirstChild("WarningLabel")
	if not label then
		label = Instance.new("TextLabel")
		label.Name = "WarningLabel"
		label.Size = UDim2.new(0, 400, 0, 50)
		label.Position = UDim2.new(0.5, -200, 0.75, 0)
		label.BackgroundTransparency = 1
		label.TextColor3 = Color3.fromRGB(231, 76, 60)
		label.Font = Enum.Font.FredokaOne
		label.TextSize = 22
		label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
		label.TextStrokeTransparency = 0.5
		label.Parent = screenGui
	end

	label.Text = text
	label.TextTransparency = 0
	label.TextStrokeTransparency = 0.5

	local existingTask = label:GetAttribute("FadeTask")
	if existingTask then
		pcall(function() task.cancel(existingTask) end)
	end

	local fadeTask = task.delay(1.5, function()
		TweenService:Create(label, TweenInfo.new(0.5), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	end)
	label:SetAttribute("FadeTask", fadeTask)
end

--- Update humanoid speed and collision state.
local function updateSpeed()
	local isCaptured = character:GetAttribute("IsCaptured") or false
	if isCaptured then
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.PlatformStand = true

		-- Disable all collisions while captured/carried to prevent weld glitches
		for _, desc in character:GetDescendants() do
			if desc:IsA("BasePart") then
				desc.CanCollide = false
			end
		end
		return
	end

	if LayDownController.IsLayingDown or character:GetAttribute("IsHidingTransition") == true then
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0

		-- Anchor the root part to freeze the character in place.
		if rootPart then
			rootPart.Anchored = true
		end

		if LayDownController.IsLayingDown then
			-- Disable collisions on limbs to prevent physics launching from
			-- overlapping geometry (especially important for large MeshParts like Rex).
			for _, desc in character:GetDescendants() do
				if desc:IsA("BasePart") and desc.Name ~= "HumanoidRootPart" then
					desc.CanCollide = false
				end
			end
		end
	elseif FlightController.IsFlying then
		-- Flight speed and physics are handled by BodyVelocity
		return
	else
		if isSprinting then
			humanoid.WalkSpeed = RUN_SPEED
		else
			humanoid.WalkSpeed = WALK_SPEED
		end
		humanoid.JumpPower = defaultJumpPower
		humanoid.PlatformStand = false

		-- Unanchor when standing back up
		if rootPart then
			rootPart.Anchored = false
		end

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
	if isSprinting and humanoid.MoveDirection.Magnitude > 0.1 then
		currentSpeed = RUN_SPEED
	end
	updateMovementState(currentSpeed)
end

-- ========================================
-- Initialize sub-modules
-- ========================================

-- Initialize lay-down controller (all characters except Sid)
LayDownController.Init(character, rootPart)

-- Initialize Buzz flight controller
if characterName == "Buzz" then
	FlightController.Init(character, rootPart, humanoid, playerGui, function(isFlying: boolean)
		if not isFlying then
			targetLean = 0
			updateSpeed()
		else
			isSprinting = false
			LayDownController.IsLayingDown = false
			if currentTrack then
				currentTrack:Stop(0.2)
			end
		end
	end)
end

-- Initialize Sid combat controller
if characterName == "Sid" then
	SidCombatController.Init(character, rootPart, humanoid, playerGui, tracks, ANIM_WEIGHT, function()
		return currentTrack, currentName
	end, function(track, name)
		currentTrack = track
		currentName = name
	end, updateMovementState)
end

-- Initialize proximity effects
if characterName ~= "Sid" then
	ProximityEffects.Init(character, rootPart, humanoid, characterName)
else
	ProximityEffects.InitFootstepVolume(character, rootPart, humanoid, characterName)
end

-- ========================================
-- Input handling
-- ========================================
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end

	local isCaptured = character:GetAttribute("IsCaptured") or false
	if isCaptured then
		return
	end

	-- Shift to Sprint
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		if FlightController.IsFlying then
			return
		end
		isSprinting = true
		updateSpeed()

	-- Mouse 1 or F Key to Lay Down / Play Dead / Freeze (Toys only)
	elseif input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.F then
		if characterName == "Sid" then
			return
		end
		if FlightController.IsFlying then
			return
		end
		-- Block input if transition is active
		if character:GetAttribute("IsHidingTransition") == true then
			return
		end
		-- Debounce: block toggle if cooldown is active
		if LayDownController.IsOnCooldown then
			return
		end
		
		if LayDownController.IsLayingDown then
			-- Standing up is instant
			LayDownController.Toggle(character, currentTrack)
			updateSpeed()
		else
			-- Attempting to hide: visibility check first
			local VisibilityCheck = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("VisibilityCheck"))
			if VisibilityCheck.CanAnySidSeeToy(character) then
				-- Play warning buzzer sound
				local head = character:FindFirstChild("Head")
				if head then
					Utils.PlayOneShot(head, "rbxassetid://4798150495", 0.8)
				end
				
				-- Show warning UI notification
				showHidingWarning("Sid is watching you! Cannot hide!")
				
				-- Apply a short cooldown to prevent spamming
				LayDownController.IsOnCooldown = true
				task.delay(1.0, function()
					LayDownController.IsOnCooldown = false
				end)
				return
			end
			
			-- Not visible: start hiding transition
			isSprinting = false
			character:SetAttribute("IsHidingTransition", true)
			updateSpeed()
			showHidingWarning("Hiding...")
			
			-- Wait transition duration
			task.delay(0.75, function()
				-- Re-check state: if player was captured or dead, or no longer in transition, abort
				local isCaptured = character:GetAttribute("IsCaptured") or false
				local currentHum = character:FindFirstChildOfClass("Humanoid")
				if isCaptured or not currentHum or currentHum.Health <= 0 or character:GetAttribute("IsHidingTransition") ~= true then
					character:SetAttribute("IsHidingTransition", nil)
					updateSpeed()
					return
				end
				
				-- Re-check visibility: did Sid spot the toy during the transition?
				if VisibilityCheck.CanAnySidSeeToy(character) then
					-- Cancel transition
					character:SetAttribute("IsHidingTransition", nil)
					updateSpeed()
					
					-- Play warning buzzer
					local head = character:FindFirstChild("Head")
					if head then
						Utils.PlayOneShot(head, "rbxassetid://4798150495", 0.8)
					end
					showHidingWarning("Sid spotted you! Hide cancelled!")
					return
				end
				
				-- Success! Toggle freeze state
				character:SetAttribute("IsHidingTransition", nil)
				LayDownController.Toggle(character, currentTrack)
				updateSpeed()
			end)
		end

	-- Keypress "1" to Toggle Wings (Buzz only)
	elseif input.KeyCode == Enum.KeyCode.One or input.KeyCode == Enum.KeyCode.KeypadOne then
		if LayDownController.IsLayingDown then
			return
		end
		if characterName == "Buzz" then
			if FlightController.IsOnCooldown() then
				return
			end

			local eventsFolder = ReplicatedStorage:WaitForChild("Events")
			local toggleWingsEvent = eventsFolder:FindFirstChild("ToggleWings")
			if toggleWingsEvent then
				toggleWingsEvent:FireServer()
			end
		end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	local isCaptured = character:GetAttribute("IsCaptured") or false
	if isCaptured then
		return
	end

	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		isSprinting = false
		updateSpeed()
	end
end)

-- ========================================
-- RootJoint tilt (forward lean & lay down)
-- ========================================
local rootJoint = rootPart:WaitForChild("RootJoint", 10)
local originalRootC0 = rootJoint and rootJoint.C0 or nil

if rootJoint and originalRootC0 then
	RunService.RenderStepped:Connect(function()
		-- Update flight UI and physics (Buzz only)
		if characterName == "Buzz" then
			local flightLean = FlightController.UpdateFrame(character, rootPart)
			if FlightController.IsFlying then
				targetLean = flightLean
			end
		end

		-- Update forward lean interpolation
		currentLean = currentLean + (targetLean - currentLean) * LEAN_SMOOTHING

		-- Update lay-down interpolation
		local layTranslation, layRotation, layTransition = LayDownController.UpdateFrame()

		-- Pre-multiply translation and rotation in unrotated HumanoidRootPart space
		rootJoint.C0 = layTranslation
			* layRotation
			* originalRootC0
			* CFrame.Angles(currentLean * (1 - layTransition), 0, 0)
	end)
end

-- ========================================
-- Humanoid state handling
-- ========================================
humanoid.Running:Connect(updateMovementState)

humanoid.Jumping:Connect(function(active)
	if LayDownController.IsLayingDown or FlightController.IsFlying then
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
	if LayDownController.IsLayingDown or FlightController.IsFlying then
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
	if LayDownController.IsLayingDown or FlightController.IsFlying then
		return
	end
	if math.abs(speed) > 0.1 then
		playAnimation("climb")
		targetLean = 0
	end
end)

humanoid.StateChanged:Connect(function(_oldState, newState)
	if LayDownController.IsLayingDown or FlightController.IsFlying then
		return
	end
	if newState == Enum.HumanoidStateType.Landed then
		isJumping = false
		isFalling = false
	end
end)

-- Connect to IsCaptured attribute changed signal
character:GetAttributeChangedSignal("IsCaptured"):Connect(function()
	local isCaptured = character:GetAttribute("IsCaptured") or false
	if isCaptured then
		-- Stop active flight/glide
		if characterName == "Buzz" then
			FlightController.UpdateFlightState(false, rootPart, humanoid)
		end
		-- Stop play dead
		if LayDownController.IsLayingDown then
			LayDownController.Toggle(character, nil)
		end
	else
		humanoid.PlatformStand = false
		-- Ensure rootPart is unanchored when released from capture
		if rootPart then
			rootPart.Anchored = false
		end
	end
	updateSpeed()
end)

-- Start with idle
playAnimation("idle")

print("[ToyStory Animate] Character animation controller loaded for " .. characterName)
