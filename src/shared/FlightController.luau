--[[
	ToyStory - FlightController (ModuleScript)
	Handles Buzz Lightyear's flight mechanics: wing toggle, BodyVelocity/BodyGyro
	management, active flying, gliding, ground-landing detection, and flight UI bar.
]]

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local eventsFolder = ReplicatedStorage:WaitForChild("Events")
local localPlayer = Players.LocalPlayer

local FlightController = {}

-- Flight state
FlightController.IsFlying = false
FlightController.IsGliding = false

-- Internal state
local bodyVelocity: BodyVelocity? = nil
local bodyGyro: BodyGyro? = nil
local flightStartTime = 0
local cooldownEndTime = 0

-- Constants
local FLY_SPEED = 40
local GLIDE_FORWARD_SPEED = 25
local GLIDE_DESCENT_SPEED = -6

-- UI references
local flightGui: ScreenGui? = nil
local barFrame: Frame? = nil
local barFill: Frame? = nil
local barLabel: TextLabel? = nil

-- External callbacks (set during Init)
local onFlightStateChanged: ((isFlying: boolean) -> ())? = nil

--- Create the flight UI bar (cooldown/timer).
local function createFlightUI(playerGui: PlayerGui)
	if flightGui then
		flightGui:Destroy()
	end

	flightGui = Instance.new("ScreenGui")
	flightGui.Name = "FlightUI"
	flightGui.ResetOnSpawn = true

	barFrame = Instance.new("Frame")
	barFrame.Name = "BarFrame"
	barFrame.Size = UDim2.new(0, 240, 0, 20)
	barFrame.Position = UDim2.new(0.5, -120, 0.82, 0)
	barFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	barFrame.BorderSizePixel = 0
	barFrame.Visible = false
	barFrame.Parent = flightGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = barFrame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(60, 60, 60)
	stroke.Thickness = 1.5
	stroke.Parent = barFrame

	barFill = Instance.new("Frame")
	barFill.Name = "BarFill"
	barFill.Size = UDim2.new(1, 0, 1, 0)
	barFill.BackgroundColor3 = Color3.fromRGB(46, 204, 113) -- Emerald Green
	barFill.BorderSizePixel = 0
	barFill.Parent = barFrame

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 10)
	fillCorner.Parent = barFill

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

--- Check if the character is close to the ground (for auto-landing).
local function checkGroundCollision(character: Model, rootPart: BasePart): boolean
	local torso = character:FindFirstChild("Torso")
	local leftLeg = character:FindFirstChild("Left Leg")
	local torsoSize = torso and torso.Size or Vector3.new(2, 2, 1)
	local legSize = leftLeg and leftLeg.Size or Vector3.new(1, torsoSize.Y, 1)

	local rayDirection = Vector3.new(0, -(torsoSize.Y / 2 + legSize.Y + 4.0), 0)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterDescendantsInstances = { character }
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude

	local result = workspace:Raycast(rootPart.Position, rayDirection, raycastParams)
	return result ~= nil
end

--- Update flight physics state (called when wings toggle).
function FlightController.UpdateFlightState(wingsOut: boolean, rootPart: BasePart, humanoid: Humanoid)
	local wasFlying = FlightController.IsFlying
	FlightController.IsFlying = wingsOut

	if wingsOut then
		flightStartTime = os.clock()
		FlightController.IsGliding = false

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
		FlightController.IsGliding = false

		-- Trigger 5-second cooldown if we were actually flying/gliding before
		if wasFlying then
			cooldownEndTime = os.clock() + 5
		end
	end

	if onFlightStateChanged then
		onFlightStateChanged(wingsOut)
	end
end

--- Returns whether flight is currently on cooldown.
function FlightController.IsOnCooldown(): boolean
	return os.clock() < cooldownEndTime
end

--- Process flight physics each frame (called from RenderStepped).
--- Returns the target lean angle for the character.
function FlightController.UpdateFrame(character: Model, rootPart: BasePart): number
	local targetLean = 0

	-- Update Flight/Cooldown UI
	if barFrame and barFill and barLabel then
		local now = os.clock()

		if FlightController.IsFlying then
			barFrame.Visible = true
			if not FlightController.IsGliding then
				local elapsed = now - flightStartTime
				local remaining = math.max(0, 3 - elapsed)
				local pct = remaining / 3

				barFill.Size = UDim2.new(pct, 0, 1, 0)
				barFill.BackgroundColor3 = Color3.fromRGB(46, 204, 113)
				barLabel.Text = string.format("FLYING: %.1fs", remaining)
			else
				barFill.Size = UDim2.new(1, 0, 1, 0)
				barFill.BackgroundColor3 = Color3.fromRGB(231, 76, 60)
				barLabel.Text = "FALLING WITH STYLE (GLIDING)"
			end
		elseif now < cooldownEndTime then
			barFrame.Visible = true
			local remaining = cooldownEndTime - now
			local pct = 1 - (remaining / 5)

			barFill.Size = UDim2.new(pct, 0, 1, 0)
			barFill.BackgroundColor3 = Color3.fromRGB(230, 126, 34)
			barLabel.Text = string.format("RECHARGING: %.1fs", remaining)
		else
			if barFrame.Visible then
				barFill.Size = UDim2.new(1, 0, 1, 0)
				barFill.BackgroundColor3 = Color3.fromRGB(46, 204, 113)
				barLabel.Text = "WINGS READY!"

				task.delay(1, function()
					if not FlightController.IsFlying and os.clock() >= cooldownEndTime then
						barFrame.Visible = false
					end
				end)
			end
		end
	end

	-- Flight physics
	if FlightController.IsFlying and bodyVelocity and bodyGyro then
		local camera = workspace.CurrentCamera
		local camCF = camera.CFrame

		local elapsed = os.clock() - flightStartTime
		if elapsed > 3 then
			FlightController.IsGliding = true
		end

		-- Automatic landing detection
		if elapsed > 0.5 and checkGroundCollision(character, rootPart) then
			local toggleWingsEvent = eventsFolder:FindFirstChild("ToggleWings")
			if toggleWingsEvent then
				FlightController.UpdateFlightState(false, rootPart, character:FindFirstChildOfClass("Humanoid"))
				toggleWingsEvent:FireServer()
			end
			return 0
		end

		local isW = UserInputService:IsKeyDown(Enum.KeyCode.W)
		local isS = UserInputService:IsKeyDown(Enum.KeyCode.S)
		local isA = UserInputService:IsKeyDown(Enum.KeyCode.A)
		local isD = UserInputService:IsKeyDown(Enum.KeyCode.D)

		if FlightController.IsGliding then
			-- GLIDING MODE: Slow descent, horizontal steering
			local moveDir = Vector3.new(0, 0, 0)
			local horizontalProj = (camCF.LookVector * Vector3.new(1, 0, 1)).Unit
			local rightProj = camCF.RightVector

			if isW then moveDir = moveDir + horizontalProj end
			if isS then moveDir = moveDir - horizontalProj end
			if isA then moveDir = moveDir - rightProj end
			if isD then moveDir = moveDir + rightProj end

			if moveDir.Magnitude > 0 then
				moveDir = moveDir.Unit
			else
				moveDir = (rootPart.CFrame.LookVector * Vector3.new(1, 0, 1)).Unit
			end

			bodyVelocity.Velocity = moveDir * GLIDE_FORWARD_SPEED + Vector3.new(0, GLIDE_DESCENT_SPEED, 0)
			targetLean = math.rad(60)
		else
			-- ACTIVE FLYING MODE (under 3 seconds)
			local isSpace = UserInputService:IsKeyDown(Enum.KeyCode.Space)
			local isCtrl = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)

			local flyDir = Vector3.new(0, 0, 0)
			if isW then flyDir = flyDir + camCF.LookVector end
			if isS then flyDir = flyDir - camCF.LookVector end
			if isA then flyDir = flyDir - camCF.RightVector end
			if isD then flyDir = flyDir + camCF.RightVector end
			if isSpace then flyDir = flyDir + Vector3.new(0, 1, 0) end
			if isCtrl then flyDir = flyDir - Vector3.new(0, 1, 0) end

			if flyDir.Magnitude > 0 then
				flyDir = flyDir.Unit
				bodyVelocity.Velocity = flyDir * FLY_SPEED
				if isW or isS or isA or isD then
					targetLean = math.rad(60)
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

	return targetLean
end

--- Initialize the flight controller for Buzz.
function FlightController.Init(
	character: Model,
	rootPart: BasePart,
	humanoid: Humanoid,
	playerGui: PlayerGui,
	flightStateCallback: (isFlying: boolean) -> ()
)
	onFlightStateChanged = flightStateCallback
	createFlightUI(playerGui)

	-- Connect WingsOut attribute changed listener
	character:GetAttributeChangedSignal("WingsOut"):Connect(function()
		local wingsOut = character:GetAttribute("WingsOut") or false
		FlightController.UpdateFlightState(wingsOut, rootPart, humanoid)
	end)

	-- Check initial state on load
	local initialWings = character:GetAttribute("WingsOut") or false
	if initialWings then
		FlightController.UpdateFlightState(true, rootPart, humanoid)
	end
end

return FlightController
