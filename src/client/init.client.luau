--[[
	ToyStory - Client Core Script
	Handles camera setup and dynamically renders the round HUD and system announcements.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Replicated Values & Remote Events
local gameStateVal = ReplicatedStorage:WaitForChild("GameState")
local gameTimerVal = ReplicatedStorage:WaitForChild("GameTimer")
local batteriesCollectedVal = ReplicatedStorage:WaitForChild("BatteriesCollected")
local eventsFolder = ReplicatedStorage:WaitForChild("Events")
local updateMessageEvent = eventsFolder:WaitForChild("UpdateSystemMessage")

-- ========================================
-- CAMERA SETUP
-- ========================================
local function setupCamera(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 30)
	local rootPart = character:WaitForChild("HumanoidRootPart", 30)

	if not humanoid or not rootPart then
		return
	end

	local camera = workspace.CurrentCamera
	camera.CameraSubject = humanoid
	camera.CameraType = Enum.CameraType.Custom

	print("[ToyStory Client] Camera set up for character:", character.Name)
end

player.CharacterAdded:Connect(function(character)
	task.wait(1)
	if player.Character == character then
		setupCamera(character)
	end
end)

if player.Character then
	task.spawn(function()
		task.wait(1)
		if player.Character then
			setupCamera(player.Character)
		end
	end)
end

-- ========================================
-- HUD & SCREEN EFFECTS CONSTRUCTION
-- ========================================
local hudGui = Instance.new("ScreenGui")
hudGui.Name = "GameHudGui"
hudGui.ResetOnSpawn = false

-- Main Top Bar Panel
local topBar = Instance.new("Frame")
topBar.Name = "TopBar"
topBar.Size = UDim2.new(0, 420, 0, 50)
topBar.Position = UDim2.new(0.5, -210, 0.02, 0)
topBar.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
topBar.BackgroundTransparency = 0.25
topBar.Parent = hudGui

local barCorner = Instance.new("UICorner")
barCorner.CornerRadius = UDim.new(0, 8)
barCorner.Parent = topBar

local barStroke = Instance.new("UIStroke")
barStroke.Color = Color3.fromRGB(255, 200, 50)
barStroke.Thickness = 1.5
barStroke.Parent = topBar

-- Timer Label
local timerLabel = Instance.new("TextLabel")
timerLabel.Name = "TimerLabel"
timerLabel.Size = UDim2.new(0.3, 0, 1, 0)
timerLabel.Position = UDim2.new(0.05, 0, 0, 0)
timerLabel.BackgroundTransparency = 1
timerLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
timerLabel.Font = Enum.Font.FredokaOne
timerLabel.TextSize = 24
timerLabel.Text = "00:00"
timerLabel.Parent = topBar

-- State Label
local stateLabel = Instance.new("TextLabel")
stateLabel.Name = "StateLabel"
stateLabel.Size = UDim2.new(0.35, 0, 1, 0)
stateLabel.Position = UDim2.new(0.35, 0, 0, 0)
stateLabel.BackgroundTransparency = 1
stateLabel.TextColor3 = Color3.fromRGB(255, 200, 50)
stateLabel.Font = Enum.Font.FredokaOne
stateLabel.TextSize = 20
stateLabel.Text = "INTERMISSION"
stateLabel.Parent = topBar

-- Batteries Label
local batteriesLabel = Instance.new("TextLabel")
batteriesLabel.Name = "BatteriesLabel"
batteriesLabel.Size = UDim2.new(0.3, 0, 1, 0)
batteriesLabel.Position = UDim2.new(0.65, 0, 0, 0)
batteriesLabel.BackgroundTransparency = 1
batteriesLabel.TextColor3 = Color3.fromRGB(0, 200, 255)
batteriesLabel.Font = Enum.Font.FredokaOne
batteriesLabel.TextSize = 18
batteriesLabel.Text = "Batteries: 0/3"
batteriesLabel.Parent = topBar

hudGui.Parent = playerGui

-- ========================================
-- SYSTEM ANNOUNCEMENT BANNER
-- ========================================
local bannerFrame = Instance.new("Frame")
bannerFrame.Name = "AnnouncementBanner"
bannerFrame.Size = UDim2.new(1, 0, 0, 60)
bannerFrame.Position = UDim2.new(0, 0, 0.2, -30)
bannerFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
bannerFrame.BackgroundTransparency = 1
bannerFrame.Parent = hudGui

local bannerText = Instance.new("TextLabel")
bannerText.Name = "BannerText"
bannerText.Size = UDim2.new(1, 0, 1, 0)
bannerText.BackgroundTransparency = 1
bannerText.TextColor3 = Color3.fromRGB(255, 255, 255)
bannerText.Font = Enum.Font.FredokaOne
bannerText.TextSize = 36
bannerText.Text = ""
bannerText.Parent = bannerFrame

local function playAnnouncement(text, color)
	bannerText.Text = text
	bannerText.TextColor3 = color or Color3.fromRGB(255, 255, 255)
	
	-- Slide/Fade In animation
	bannerFrame.BackgroundTransparency = 1
	bannerText.TextTransparency = 1
	
	local inTween = TweenService:Create(bannerFrame, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 0.4
	})
	local inTextTween = TweenService:Create(bannerText, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		TextTransparency = 0
	})
	inTween:Play()
	inTextTween:Play()

	task.wait(3.5)

	-- Fade Out animation
	local outTween = TweenService:Create(bannerFrame, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		BackgroundTransparency = 1
	})
	local outTextTween = TweenService:Create(bannerText, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		TextTransparency = 1
	})
	outTween:Play()
	outTextTween:Play()
end

-- ========================================
-- VALUE SYNC LISTENERS
-- ========================================
-- Timer formatting
local function formatTime(seconds: number): string
	local mins = math.floor(seconds / 60)
	local secs = seconds % 60
	return string.format("%02d:%02d", mins, secs)
end

gameTimerVal.Changed:Connect(function(val)
	timerLabel.Text = formatTime(val)
end)

gameStateVal.Changed:Connect(function(val)
	stateLabel.Text = val:upper()
	if val == "Intermission" then
		stateLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
		batteriesLabel.Visible = false
	elseif val == "Hiding" then
		stateLabel.TextColor3 = Color3.fromRGB(50, 150, 255)
		batteriesLabel.Visible = true
		batteriesLabel.Text = "Hide/Explore"
	elseif val == "Hunt" then
		stateLabel.TextColor3 = Color3.fromRGB(255, 50, 50)
		batteriesLabel.Visible = true
		batteriesLabel.Text = "Batteries: " .. batteriesCollectedVal.Value .. "/3"
	elseif val == "Escape" then
		stateLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
		batteriesLabel.Visible = true
		batteriesLabel.Text = "ESCAPE ACTIVE!"
	elseif val == "RoundOver" then
		stateLabel.TextColor3 = Color3.fromRGB(255, 200, 50)
		batteriesLabel.Visible = false
	end
end)

batteriesCollectedVal.Changed:Connect(function(val)
	if gameStateVal.Value == "Hunt" or gameStateVal.Value == "Escape" then
		batteriesLabel.Text = "Batteries: " .. val .. "/3"
	end
end)

updateMessageEvent.OnClientEvent:Connect(function(text, color)
	task.spawn(playAnnouncement, text, color)
end)

print("[ToyStory Client] Client camera and HUD systems loaded!")
