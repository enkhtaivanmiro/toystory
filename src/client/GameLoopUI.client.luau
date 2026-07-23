--[[
	ToyStory - GameLoopUI (LocalScript)
	Generates a premium glassmorphic UI HUD displaying game state, phase timers,
	battery count, captured overlays, and victory/defeat screens.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

local gameStateFolder = ReplicatedStorage:WaitForChild("GameState")
local phaseVal = gameStateFolder:WaitForChild("MatchPhase")
local timerVal = gameStateFolder:WaitForChild("TimeRemaining")
local batteriesVal = gameStateFolder:WaitForChild("BatteriesCollected")

local eventsFolder = ReplicatedStorage:WaitForChild("Events")
local gameEndedEvent = eventsFolder:WaitForChild("GameEnded", 10)
local stunToyEvent = eventsFolder:WaitForChild("StunToy", 10)

-- ========================================
-- UI HUD Elements Creation (Programmatic)
-- ========================================

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "GameLoopGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true

-- Top Status Card
local hudCard = Instance.new("Frame")
hudCard.Name = "HudCard"
hudCard.Size = UDim2.fromOffset(450, 95)
hudCard.Position = UDim2.new(0.5, -225, 0.02, 0)
hudCard.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
hudCard.BackgroundTransparency = 0.25
hudCard.BorderSizePixel = 0
hudCard.Parent = screenGui

local cardCorner = Instance.new("UICorner")
cardCorner.CornerRadius = UDim.new(0, 10)
cardCorner.Parent = hudCard

local cardStroke = Instance.new("UIStroke")
cardStroke.Color = Color3.fromRGB(80, 80, 95)
cardStroke.Thickness = 1.5
cardStroke.Parent = hudCard

-- Phase Label
local phaseLabel = Instance.new("TextLabel")
phaseLabel.Name = "PhaseLabel"
phaseLabel.Size = UDim2.new(1, 0, 0, 30)
phaseLabel.Position = UDim2.fromScale(0, 0)
phaseLabel.BackgroundTransparency = 1
-- Setup initial value
phaseLabel.Text = "WAITING FOR PLAYERS"
phaseLabel.TextColor3 = Color3.fromRGB(160, 160, 180)
phaseLabel.Font = Enum.Font.FredokaOne
phaseLabel.TextSize = 18
phaseLabel.Parent = hudCard

-- Timer Label
local timerLabel = Instance.new("TextLabel")
timerLabel.Name = "TimerLabel"
timerLabel.Size = UDim2.new(1, 0, 0, 25)
timerLabel.Position = UDim2.fromOffset(0, 30)
timerLabel.BackgroundTransparency = 1
timerLabel.Text = "Time: 0:00"
timerLabel.TextColor3 = Color3.fromRGB(240, 240, 245)
timerLabel.Font = Enum.Font.GothamBold
timerLabel.TextSize = 15
timerLabel.Parent = hudCard

-- Objective Label (Visible to all, showing team-specific goals)
local objectiveLabel = Instance.new("TextLabel")
objectiveLabel.Name = "ObjectiveLabel"
objectiveLabel.Size = UDim2.new(1, -20, 0, 30)
objectiveLabel.Position = UDim2.fromOffset(10, 58)
objectiveLabel.BackgroundTransparency = 1
objectiveLabel.TextColor3 = Color3.fromRGB(241, 196, 15) -- Yellow Gold
objectiveLabel.Font = Enum.Font.FredokaOne
objectiveLabel.TextSize = 14
objectiveLabel.Text = "Objective: Wait for game to start..."
objectiveLabel.TextXAlignment = Enum.TextXAlignment.Center
objectiveLabel.TextYAlignment = Enum.TextYAlignment.Center
objectiveLabel.TextWrapped = true
objectiveLabel.Parent = hudCard

print("[ToyStory GameLoopUI] Objective Label created programmatically:", objectiveLabel:GetFullName())

-- Captured Overlay (Toys only)
local capturedFrame = Instance.new("Frame")
capturedFrame.Name = "CapturedOverlay"
capturedFrame.Size = UDim2.fromScale(1, 1)
capturedFrame.BackgroundColor3 = Color3.fromRGB(150, 20, 20)
capturedFrame.BackgroundTransparency = 0.9 -- subtle red tint
capturedFrame.Visible = false
capturedFrame.BorderSizePixel = 0
capturedFrame.Parent = screenGui

local capturedLabel = Instance.new("TextLabel")
capturedLabel.Size = UDim2.new(1, 0, 0, 120)
capturedLabel.Position = UDim2.new(0, 0, 0.4, -60)
capturedLabel.BackgroundTransparency = 1
capturedLabel.TextColor3 = Color3.fromRGB(255, 75, 75)
capturedLabel.Font = Enum.Font.FredokaOne
capturedLabel.TextSize = 36
capturedLabel.Text = "CAPTURED!"
capturedLabel.Parent = capturedFrame

local rescueLabel = Instance.new("TextLabel")
rescueLabel.Size = UDim2.new(1, 0, 0, 40)
rescueLabel.Position = UDim2.new(0, 0, 0.45, 20)
rescueLabel.BackgroundTransparency = 1
rescueLabel.TextColor3 = Color3.fromRGB(240, 240, 240)
rescueLabel.Font = Enum.Font.GothamBold
rescueLabel.TextSize = 18
rescueLabel.Text = "Wait for a teammate to rescue you"
rescueLabel.Parent = capturedFrame

-- Victory/Defeat Overlay
local matchEndedFrame = Instance.new("Frame")
matchEndedFrame.Name = "MatchEndedOverlay"
matchEndedFrame.Size = UDim2.fromScale(1, 1)
matchEndedFrame.BackgroundColor3 = Color3.fromRGB(10, 10, 15)
matchEndedFrame.BackgroundTransparency = 1
matchEndedFrame.Visible = false
matchEndedFrame.BorderSizePixel = 0
matchEndedFrame.Parent = screenGui

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, 0, 0, 100)
statusLabel.Position = UDim2.new(0, 0, 0.35, -50)
statusLabel.BackgroundTransparency = 1
statusLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
statusLabel.Font = Enum.Font.FredokaOne
statusLabel.TextSize = 48
statusLabel.ZIndex = 2
statusLabel.Parent = matchEndedFrame

local subStatusLabel = Instance.new("TextLabel")
subStatusLabel.Size = UDim2.new(1, 0, 0, 40)
subStatusLabel.Position = UDim2.new(0, 0, 0.35, 60)
subStatusLabel.BackgroundTransparency = 1
subStatusLabel.TextColor3 = Color3.fromRGB(180, 180, 200)
subStatusLabel.Font = Enum.Font.GothamBold
subStatusLabel.TextSize = 20
subStatusLabel.ZIndex = 2
subStatusLabel.Parent = matchEndedFrame

screenGui.Parent = playerGui

-- Developer Start Round Button (only for Mir0bn)
local devStartButton = nil
if localPlayer.Name == "Mir0bn" then
	devStartButton = Instance.new("TextButton")
	devStartButton.Name = "DevStartButton"
	devStartButton.Size = UDim2.fromOffset(160, 40)
	devStartButton.Position = UDim2.new(0.5, -80, 0.02, 105)
	devStartButton.BackgroundColor3 = Color3.fromRGB(46, 204, 113) -- Emerald green
	devStartButton.BorderSizePixel = 0
	devStartButton.Font = Enum.Font.FredokaOne
	devStartButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	devStartButton.TextSize = 16
	devStartButton.Text = "START ROUND"
	devStartButton.Visible = (phaseVal.Value == "Lobby")
	devStartButton.Parent = screenGui

	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 8)
	btnCorner.Parent = devStartButton

	local btnStroke = Instance.new("UIStroke")
	btnStroke.Color = Color3.fromRGB(255, 255, 255)
	btnStroke.Thickness = 1.5
	btnStroke.Parent = devStartButton

	devStartButton.MouseButton1Click:Connect(function()
		local forceStartRoundEvent = eventsFolder:FindFirstChild("ForceStartRound")
		if forceStartRoundEvent then
			forceStartRoundEvent:FireServer()
		end
	end)
end

-- ========================================
-- Dynamic Updates / Value Changed Listeners
-- ========================================

-- Format Timer (Seconds -> MM:SS)
local function formatTime(seconds: number): string
	local mins = math.floor(seconds / 60)
	local secs = seconds % 60
	return string.format("%d:%02d", mins, secs)
end

-- Update Timer Label
timerVal.Changed:Connect(function(newVal)
	timerLabel.Text = "Time: " .. formatTime(newVal)
end)

-- Helper function to update the objective text on the screen for both Sid and Toys
local function updateObjectiveText()
	local char = localPlayer.Character
	local charName = char and char:GetAttribute("CharacterName")
	local isSid = (charName == "Sid")

	local phase = phaseVal.Value
	local count = batteriesVal and batteriesVal.Value or 0

	if phase == "Lobby" then
		local toys = gameStateFolder:GetAttribute("LobbyToysCount") or 0
		local sids = gameStateFolder:GetAttribute("LobbySidsCount") or 0
		if toys >= 4 and sids >= 1 then
			objectiveLabel.Text = string.format("Objective: Starting soon! (Toys: %d/4, Sid: %d/1)", toys, sids)
			objectiveLabel.TextColor3 = Color3.fromRGB(46, 204, 113) -- Green
		else
			objectiveLabel.Text = string.format("Objective: Need players (Toys: %d/4, Sid: %d/1)", toys, sids)
			objectiveLabel.TextColor3 = Color3.fromRGB(230, 126, 34) -- Orange
		end
	elseif phase == "Ended" then
		objectiveLabel.Text = "Objective: Round has ended."
		objectiveLabel.TextColor3 = Color3.fromRGB(160, 160, 180)
	elseif phase == "Prep" then
		if isSid then
			objectiveLabel.Text = "Objective: Wait for toys to finish hiding..."
			objectiveLabel.TextColor3 = Color3.fromRGB(160, 160, 180)
		else
			objectiveLabel.Text = "Objective: Hide and look for Batteries!"
			objectiveLabel.TextColor3 = Color3.fromRGB(52, 152, 219) -- Sky Blue
		end
	elseif phase == "Search" then
		if isSid then
			objectiveLabel.Text = string.format("Objective: Capture all toys! (Batteries collected: %d / 5)", count)
			objectiveLabel.TextColor3 = Color3.fromRGB(231, 76, 60) -- Light Red
		else
			objectiveLabel.Text = string.format("Objective: Collect Batteries! (%d / 5)", count)
			objectiveLabel.TextColor3 = Color3.fromRGB(241, 196, 15) -- Yellow Gold
		end
	elseif phase == "Escape" then
		if isSid then
			objectiveLabel.Text = "Objective: Capture the toys before they escape!"
			objectiveLabel.TextColor3 = Color3.fromRGB(231, 76, 60)
		else
			objectiveLabel.Text = "Objective: Head to the escape zone!"
			objectiveLabel.TextColor3 = Color3.fromRGB(46, 204, 113)
		end
	else
		objectiveLabel.Text = "Objective: Wait for match to begin..."
		objectiveLabel.TextColor3 = Color3.fromRGB(160, 160, 180)
	end

	print(string.format("[ToyStory GameLoopUI] updateObjectiveText: char=%s, charName=%s, isSid=%s, phase=%s, count=%d, text=%q",
		tostring(char), tostring(charName), tostring(isSid), tostring(phase), count, objectiveLabel.Text))
end

-- Update Phase Label
phaseVal.Changed:Connect(function(newVal)
	if newVal == "Lobby" then
		phaseLabel.Text = "LOBBY - WAITING FOR PLAYERS"
		phaseLabel.TextColor3 = Color3.fromRGB(160, 160, 180) -- Muted Gray
	elseif newVal == "Prep" then
		phaseLabel.Text = "PREPARATION PHASE"
		phaseLabel.TextColor3 = Color3.fromRGB(52, 152, 219) -- Sky Blue
	elseif newVal == "Search" then
		phaseLabel.Text = "SEARCH PHASE - AVOID SID!"
		phaseLabel.TextColor3 = Color3.fromRGB(230, 126, 34) -- Orange
	elseif newVal == "Escape" then
		phaseLabel.Text = "ESCAPE ROUTE OPEN!"
		phaseLabel.TextColor3 = Color3.fromRGB(46, 204, 113) -- Emerald Green
	elseif newVal == "Ended" then
		phaseLabel.Text = "MATCH OVER"
		phaseLabel.TextColor3 = Color3.fromRGB(231, 76, 60) -- Alizarin Red
	end

	if devStartButton then
		devStartButton.Visible = (newVal == "Lobby")
	end

	updateObjectiveText()
end)

-- Hook up lobby attribute changes to update objective card in real-time
gameStateFolder.AttributeChanged:Connect(function(attr)
	if attr == "LobbyToysCount" or attr == "LobbySidsCount" then
		updateObjectiveText()
	end
end)

-- Update Battery Count
if batteriesVal then
	batteriesVal.Changed:Connect(function(newVal)
		updateObjectiveText()
		-- Flash yellow-gold effect on assembly card
		TweenService:Create(objectiveLabel, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 1, true), { TextColor3 = Color3.fromRGB(46, 204, 113) }):Play()
	end)
end

-- Local Character Connection (handles Captured overlay & Carrier notifications)
local function onCharacterAdded(char)
	-- Update objective immediately when CharacterName replicates
	char:GetAttributeChangedSignal("CharacterName"):Connect(function()
		updateObjectiveText()
	end)

	local function updateResetButton()
		local charName = char:GetAttribute("CharacterName")
		if charName and charName ~= "Sid" then
			local isCaptured = char:GetAttribute("IsCaptured") or false
			task.spawn(function()
				local success = false
				local tries = 0
				while not success and tries < 50 do
					tries = tries + 1
					success = pcall(function()
						game:GetService("StarterGui"):SetCore("ResetButtonCallback", not isCaptured)
					end)
					if not success then
						task.wait(0.2)
					end
				end
			end)
		else
			task.spawn(function()
				local success = false
				local tries = 0
				while not success and tries < 50 do
					tries = tries + 1
					success = pcall(function()
						game:GetService("StarterGui"):SetCore("ResetButtonCallback", true)
					end)
					if not success then
						task.wait(0.2)
					end
				end
			end)
		end
	end

	-- Handle captured overlay visibility dynamically
	char:GetAttributeChangedSignal("IsCaptured"):Connect(function()
		local charName = char:GetAttribute("CharacterName")
		if charName and charName ~= "Sid" then
			local isCaptured = char:GetAttribute("IsCaptured") or false
			capturedFrame.Visible = isCaptured
			if isCaptured then
				capturedFrame.BackgroundTransparency = 0.95
				TweenService:Create(capturedFrame, TweenInfo.new(0.5), { BackgroundTransparency = 0.85 }):Play()
			end
		else
			capturedFrame.Visible = false
		end
		updateResetButton()
	end)

	-- Run initially (if character attributes are already replicated)
	updateObjectiveText()
	updateResetButton()
	local charName = char:GetAttribute("CharacterName")
	if charName and charName ~= "Sid" then
		capturedFrame.Visible = char:GetAttribute("IsCaptured") or false
	else
		capturedFrame.Visible = false
	end
end

localPlayer.CharacterAdded:Connect(onCharacterAdded)
if localPlayer.Character then
	onCharacterAdded(localPlayer.Character)
end

-- GameEnded UI trigger
if gameEndedEvent then
	gameEndedEvent.OnClientEvent:Connect(function(winnerTeam)
		local char = localPlayer.Character
		local charName = char and char:GetAttribute("CharacterName")
		local isToy = charName and charName ~= "Sid"

		matchEndedFrame.Visible = true
		matchEndedFrame.BackgroundTransparency = 1
		TweenService:Create(matchEndedFrame, TweenInfo.new(0.6), { BackgroundTransparency = 0.05 }):Play()

		if winnerTeam == "Toys" then
			statusLabel.TextColor3 = Color3.fromRGB(46, 204, 113) -- Green
			if isToy then
				statusLabel.Text = "VICTORY!"
				subStatusLabel.Text = "You collected all the batteries!"
			else
				statusLabel.Text = "DEFEAT!"
				subStatusLabel.Text = "The toys outsmarted you and collected all the batteries!"
			end
		else
			-- Hunter (Sid) wins
			statusLabel.TextColor3 = Color3.fromRGB(231, 76, 60) -- Red
			if isToy then
				statusLabel.Text = "DEFEAT!"
				subStatusLabel.Text = "Sid captured all the toys!"
			else
				statusLabel.Text = "VICTORY!"
				subStatusLabel.Text = "All toys have been captured and eliminated!"
			end
		end

		-- Pulse UI text
		statusLabel.TextTransparency = 1
		subStatusLabel.TextTransparency = 1
		TweenService:Create(statusLabel, TweenInfo.new(0.5), { TextTransparency = 0 }):Play()
		TweenService:Create(subStatusLabel, TweenInfo.new(0.5), { TextTransparency = 0 }):Play()

		-- Fade out after 8 seconds
		task.delay(8, function()
			TweenService:Create(matchEndedFrame, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
			TweenService:Create(statusLabel, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
			TweenService:Create(subStatusLabel, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
			task.wait(0.5)
			matchEndedFrame.Visible = false
		end)
	end)
end

-- Hide prompts based on role/status:
-- 1. Hide Rescue prompts (RescuePrompt / PrisonRescuePrompt) from Sid or captured teammates
-- 2. Hide Deposit prompt (PrisonDepositPrompt) from toys (non-Sid characters)
ProximityPromptService.PromptShown:Connect(function(prompt)
	local char = localPlayer.Character
	if not char then
		prompt.Enabled = false
		return
	end

	local charName = char:GetAttribute("CharacterName")
	local isCaptured = char:GetAttribute("IsCaptured") or false

	if prompt.Name == "RescuePrompt" or prompt.Name == "PrisonRescuePrompt" then
		if charName == "Sid" or isCaptured then
			prompt.Enabled = false
		end
	elseif prompt.Name == "PrisonDepositPrompt" then
		if charName ~= "Sid" then
			prompt.Enabled = false
		end
	end
end)

-- Listen for StunToy event (BabyFace capture)
if stunToyEvent then
	stunToyEvent.OnClientEvent:Connect(function(duration)
		local stunGui = Instance.new("ScreenGui")
		stunGui.Name = "ToyStunGui"
		stunGui.ResetOnSpawn = true

		local frame = Instance.new("Frame")
		frame.Size = UDim2.fromScale(1, 1)
		frame.BackgroundColor3 = Color3.fromRGB(30, 10, 10)
		frame.BackgroundTransparency = 0.55
		frame.BorderSizePixel = 0
		frame.Parent = stunGui

		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(0, 500, 0, 100)
		label.Position = UDim2.new(0.5, -250, 0.4, -50)
		label.BackgroundTransparency = 1
		label.TextColor3 = Color3.fromRGB(231, 76, 60) -- Bright Red
		label.Font = Enum.Font.FredokaOne
		label.TextSize = 36
		label.Parent = frame

		local subLabel = Instance.new("TextLabel")
		subLabel.Size = UDim2.new(0, 500, 0, 40)
		subLabel.Position = UDim2.new(0.5, -250, 0.4, 40)
		subLabel.BackgroundTransparency = 1
		subLabel.TextColor3 = Color3.fromRGB(240, 240, 240)
		subLabel.Font = Enum.Font.GothamBold
		subLabel.TextSize = 18
		subLabel.Text = "You are frozen in place!"
		subLabel.Parent = frame

		stunGui.Parent = playerGui

		-- Play scary heart beat sound effect locally
		local RunService = game:GetService("RunService")
		local camera = workspace.CurrentCamera
		local start = os.clock()
		
		local connection
		connection = RunService.RenderStepped:Connect(function()
			local elapsed = os.clock() - start
			if elapsed >= duration then
				connection:Disconnect()
				stunGui:Destroy()
			else
				-- Update countdown text
				label.Text = string.format("TRAPPED BY BABYFACE!\n%.1f SECONDS REMAINING", math.max(0, duration - elapsed))
				-- Screen shake
				local shake = Vector3.new(
					math.random(-10, 10) * 0.04,
					math.random(-10, 10) * 0.04,
					0
				)
				camera.CFrame = camera.CFrame * CFrame.new(shake)
			end
		end)
	end)
end

print("[ToyStory GameLoopUI] Client HUD loaded!")
