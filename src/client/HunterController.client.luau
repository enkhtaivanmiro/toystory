--[[
	ToyStory - HunterController (LocalScript)
	Handles client-side actions for the Hunter (Sid).
	Includes Flashlight toggle, Listen ability (focused sound direction),
	cooldown UI, and screen lock overlay.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

local eventsFolder = ReplicatedStorage:WaitForChild("Events")
local toggleFlashlightEvent = eventsFolder:WaitForChild("ToggleFlashlight", 10)
local lockHunterEvent = eventsFolder:WaitForChild("LockHunter", 10)

-- Run only if character is Sid
local function initializeHunterController(char)
	task.wait(1) -- wait for replication
	local characterName = char:GetAttribute("CharacterName")
	if characterName ~= "Sid" then return end

	local rootPart = char:WaitForChild("HumanoidRootPart", 10)
	local humanoid = char:WaitForChild("Humanoid", 10)
	if not rootPart or not humanoid then return end

	print("[ToyStory HunterController] Initialized for Sid:", localPlayer.Name)

	-- Variables
	local lastListenTime = 0
	local LISTEN_COOLDOWN = 12 -- 12 seconds cooldown
	local LISTEN_DURATION = 3.0
	local isListening = false
	local flashlightOn = false

	-- Setup Listen UI (cooldown bar)
	local hunterGui = Instance.new("ScreenGui")
	hunterGui.Name = "HunterGui"
	hunterGui.ResetOnSpawn = true

	local listenBarFrame = Instance.new("Frame")
	listenBarFrame.Name = "ListenBarFrame"
	listenBarFrame.Size = UDim2.new(0, 200, 0, 16)
	listenBarFrame.Position = UDim2.new(0.5, -100, 0.88, 0)
	listenBarFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	listenBarFrame.BorderSizePixel = 0
	listenBarFrame.Parent = hunterGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = listenBarFrame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(60, 60, 60)
	stroke.Thickness = 1.5
	stroke.Parent = listenBarFrame

	local listenBarFill = Instance.new("Frame")
	listenBarFill.Name = "ListenBarFill"
	listenBarFill.Size = UDim2.new(1, 0, 1, 0)
	listenBarFill.BackgroundColor3 = Color3.fromRGB(52, 152, 219) -- Blue
	listenBarFill.BorderSizePixel = 0
	listenBarFill.Parent = listenBarFrame

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 8)
	fillCorner.Parent = listenBarFill

	local listenLabel = Instance.new("TextLabel")
	listenLabel.Name = "ListenLabel"
	listenLabel.Size = UDim2.new(1, 0, 1, 0)
	listenLabel.BackgroundTransparency = 1
	listenLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	listenLabel.Font = Enum.Font.GothamBold
	listenLabel.TextSize = 10
	listenLabel.Text = "LISTEN (Q) - READY"
	listenLabel.Parent = listenBarFrame

	-- Lock/Blackout overlay for Prep Phase
	local blackoutFrame = Instance.new("Frame")
	blackoutFrame.Name = "Blackout"
	blackoutFrame.Size = UDim2.fromScale(1, 1)
	blackoutFrame.BackgroundColor3 = Color3.fromRGB(5, 5, 8)
	blackoutFrame.BackgroundTransparency = 1
	blackoutFrame.Visible = false
	blackoutFrame.BorderSizePixel = 0
	blackoutFrame.Parent = hunterGui

	local blackoutLabel = Instance.new("TextLabel")
	blackoutLabel.Size = UDim2.new(1, 0, 0, 100)
	blackoutLabel.Position = UDim2.new(0, 0, 0.4, 0)
	blackoutLabel.BackgroundTransparency = 1
	blackoutLabel.TextColor3 = Color3.fromRGB(255, 75, 75)
	blackoutLabel.Font = Enum.Font.FredokaOne
	blackoutLabel.TextSize = 36
	blackoutLabel.Text = "TOYS ARE HIDING...\nPREPARE TO SEARCH"
	blackoutLabel.Parent = blackoutFrame

	hunterGui.Parent = playerGui

	-- Listen for Hunter locking from server (Prep phase)
	if lockHunterEvent then
		lockHunterEvent.OnClientEvent:Connect(function(locked)
			if locked then
				blackoutFrame.Visible = true
				TweenService:Create(blackoutFrame, TweenInfo.new(0.3), { BackgroundTransparency = 0.05 }):Play()
				TweenService:Create(blackoutLabel, TweenInfo.new(0.3), { TextTransparency = 0 }):Play()
			else
				TweenService:Create(blackoutFrame, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
				TweenService:Create(blackoutLabel, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
				task.delay(0.5, function()
					blackoutFrame.Visible = false
				end)
			end
		end)
	end

	-- Sound direction focus (listen ability) logic
	local function triggerListenAbility()
		if isListening or os.clock() - lastListenTime < LISTEN_COOLDOWN then
			return
		end

		isListening = true
		lastListenTime = os.clock()

		print("[ToyStory HunterController] Focus listening activated...")
		listenLabel.Text = "FOCUS LISTENING..."
		listenBarFill.BackgroundColor3 = Color3.fromRGB(231, 76, 60) -- Red while active

		-- Play deep breathing focus sound locally
		local focusSound = Instance.new("Sound")
		focusSound.SoundId = "rbxassetid://9114227181" -- high-pitch focus loop
		focusSound.Volume = 0.95
		focusSound.PlaybackSpeed = 0.85
		focusSound.Parent = rootPart
		focusSound:Play()
		Debris:AddItem(focusSound, 4)

		-- Show visual focus vignette
		local vignette = Instance.new("ImageLabel")
		vignette.Name = "Vignette"
		vignette.Size = UDim2.fromScale(1, 1)
		vignette.BackgroundTransparency = 1
		vignette.Image = "rbxassetid://10228392138" -- classic heavy vignette asset
		vignette.ImageColor3 = Color3.fromRGB(20, 0, 0)
		vignette.ImageTransparency = 1
		vignette.Parent = hunterGui

		TweenService:Create(vignette, TweenInfo.new(0.5), { ImageTransparency = 0.25 }):Play()

		-- Anchor Sid locally during listening
		rootPart.Anchored = true

		-- Track active listening indicators
		local activeIndicators = {}

		local searchConnection
		searchConnection = RunService.Heartbeat:Connect(function()
			-- Find moving toys
			for _, otherPlayer in Players:GetPlayers() do
				if otherPlayer ~= localPlayer then
					local otherChar = otherPlayer.Character
					if otherChar and otherChar:GetAttribute("IsCustomCharacter") then
						local name = otherChar:GetAttribute("CharacterName")
						local otherRoot = otherChar:FindFirstChild("HumanoidRootPart")
						local otherHum = otherChar:FindFirstChildOfClass("Humanoid")
						local isCaptured = otherChar:GetAttribute("IsCaptured") or false

						if name ~= "Sid" and otherRoot and not isCaptured then
							local speed = otherRoot.AssemblyLinearVelocity.Magnitude
							local dist = (rootPart.Position - otherRoot.Position).Magnitude

							-- If they are moving or landed heavily, reveal direction
							if (speed > 1.5 or otherChar:GetAttribute("LandedNoise") == true) and dist <= 90 then
								-- Render a focused warning ring at their position
								local indicator = activeIndicators[otherPlayer]
								if not indicator then
									indicator = Instance.new("BillboardGui")
									indicator.Name = "SoundIndicator"
									indicator.Size = UDim2.fromOffset(24, 24)
									indicator.AlwaysOnTop = true
									
									local circle = Instance.new("Frame")
									circle.Size = UDim2.fromScale(1, 1)
									circle.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
									circle.BorderSizePixel = 0
									circle.Parent = indicator

									local uiCorner = Instance.new("UICorner")
									uiCorner.CornerRadius = UDim.new(1, 0)
									uiCorner.Parent = circle

									indicator.Adornee = otherRoot
									indicator.Parent = hunterGui
									activeIndicators[otherPlayer] = indicator
									
									-- Pulse effect
									local scaleInfo = TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
									TweenService:Create(circle, scaleInfo, { BackgroundTransparency = 0.5, Size = UDim2.fromScale(1.4, 1.4) }):Play()
								end
							else
								-- Remove if stopped moving
								if activeIndicators[otherPlayer] then
									activeIndicators[otherPlayer]:Destroy()
									activeIndicators[otherPlayer] = nil
								end
							end
						end
					end
				end
			end
		end)

		-- Release listening after duration
		task.delay(LISTEN_DURATION, function()
			isListening = false
			searchConnection:Disconnect()

			-- Clear indicators
			for _, indicator in pairs(activeIndicators) do
				indicator:Destroy()
			end
			activeIndicators = {}

			-- Restore normal state
			rootPart.Anchored = false
			TweenService:Create(vignette, TweenInfo.new(0.5), { ImageTransparency = 1 }):Play()
			task.delay(0.5, function() vignette:Destroy() end)

			-- Cooldown progression loop
			task.spawn(function()
				while os.clock() - lastListenTime < LISTEN_COOLDOWN do
					local elapsed = os.clock() - lastListenTime
					local pct = elapsed / LISTEN_COOLDOWN
					listenBarFill.Size = UDim2.new(pct, 0, 1, 0)
					listenBarFill.BackgroundColor3 = Color3.fromRGB(230, 126, 34) -- Orange
					listenLabel.Text = string.format("RECHARGING: %.1fs", LISTEN_COOLDOWN - elapsed)
					task.wait(0.1)
				end
				listenBarFill.Size = UDim2.new(1, 0, 1, 0)
				listenBarFill.BackgroundColor3 = Color3.fromRGB(52, 152, 219) -- Blue
				listenLabel.Text = "LISTEN (Q) - READY"
			end)
		end)
	end

	-- Key inputs
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end

		-- Q to listen
		if input.KeyCode == Enum.KeyCode.Q then
			triggerListenAbility()
		-- F to toggle flashlight
		elseif input.KeyCode == Enum.KeyCode.F then
			if toggleFlashlightEvent then
				toggleFlashlightEvent:FireServer()
				flashlightOn = not flashlightOn
				
				-- Play mechanical switch sound locally
				local clickSound = Instance.new("Sound")
				clickSound.SoundId = "rbxassetid://12222229"
				clickSound.Volume = 0.5
				clickSound.Parent = rootPart
				clickSound:Play()
				Debris:AddItem(clickSound, 2)
			end
		end
	end)
end

-- Hook up joins
localPlayer.CharacterAdded:Connect(initializeHunterController)
if localPlayer.Character then
	initializeHunterController(localPlayer.Character)
end
