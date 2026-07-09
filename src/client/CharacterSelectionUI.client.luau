--[[
	ToyStory - Character Selection UI (LocalScript)
	Generates a sleek, modern UI selection menu for selecting a character on join.
	Fires a remote event to request character spawning.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Configuration
local CharacterConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CharacterConfig"))
local eventsFolder = ReplicatedStorage:WaitForChild("Events")

-- Wait for the RemoteEvent to be ready
local selectCharacterEvent = eventsFolder:WaitForChild("SelectCharacter", 10)
if not selectCharacterEvent then
	warn("[ToyStory UI] SelectCharacter RemoteEvent not found!")
	return
end

-- Wait for Characters folder
local charactersFolder = ReplicatedStorage:WaitForChild("Characters", 10)
if not charactersFolder then
	warn("[ToyStory UI] Characters folder not found in ReplicatedStorage!")
	return
end

-- ========================================
-- UI Creation (Programmatic, Rojo-friendly)
-- ========================================

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "CharacterSelectionGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true

-- Main background overlay
local overlay = Instance.new("Frame")
overlay.Name = "Overlay"
overlay.Size = UDim2.fromScale(1, 1)
overlay.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
overlay.BackgroundTransparency = 0.45
overlay.BorderSizePixel = 0
overlay.Parent = screenGui

-- Main container frame (Center card)
local card = Instance.new("Frame")
card.Name = "Card"
card.Size = UDim2.fromOffset(450, 320)
card.Position = UDim2.fromScale(0.5, 0.5)
card.AnchorPoint = Vector2.new(0.5, 0.5)
card.BackgroundColor3 = Color3.fromRGB(24, 24, 32)
card.BorderSizePixel = 0
card.Parent = overlay

-- Round card corners
local cardCorner = Instance.new("UICorner")
cardCorner.CornerRadius = UDim.new(0, 12)
cardCorner.Parent = card

-- Outer glow/stroke
local cardStroke = Instance.new("UIStroke")
cardStroke.Color = Color3.fromRGB(80, 80, 100)
cardStroke.Thickness = 1.5
cardStroke.Transparency = 0.5
cardStroke.Parent = card

-- Title label
local title = Instance.new("TextLabel")
title.Name = "Title"
title.Size = UDim2.new(1, 0, 0, 60)
title.Position = UDim2.fromOffset(0, 20)
title.BackgroundTransparency = 1
title.Text = "SELECT YOUR TOY"
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.Font = Enum.Font.FredokaOne
title.TextSize = 28
title.Parent = card

-- Subtitle label
local subtitle = Instance.new("TextLabel")
subtitle.Name = "Subtitle"
subtitle.Size = UDim2.new(1, 0, 0, 20)
subtitle.Position = UDim2.fromOffset(0, 80)
subtitle.BackgroundTransparency = 1
subtitle.Text = "Choose a character to enter the game"
subtitle.TextColor3 = Color3.fromRGB(160, 160, 180)
subtitle.Font = Enum.Font.SourceSansItalic
subtitle.TextSize = 16
subtitle.Parent = card

-- Character button container
local container = Instance.new("Frame")
container.Name = "Container"
container.Size = UDim2.new(1, -40, 0, 140)
container.Position = UDim2.fromOffset(20, 130)
container.BackgroundTransparency = 1
container.Parent = card

-- List layout
local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.VerticalAlignment = Enum.VerticalAlignment.Center
layout.Padding = UDim.new(0, 20)
layout.Parent = container

-- Function to create a sleek button for a character
local function createCharacterButton(name: string)
	local button = Instance.new("TextButton")
	button.Name = name .. "Button"
	button.Size = UDim2.fromOffset(160, 100)
	button.BackgroundColor3 = Color3.fromRGB(36, 36, 48)
	button.BorderSizePixel = 0
	button.Text = name:upper()
	button.Font = Enum.Font.FredokaOne
	button.TextSize = 20
	button.TextColor3 = Color3.fromRGB(240, 240, 240)
	button.AutoButtonColor = false

	local buttonCorner = Instance.new("UICorner")
	buttonCorner.CornerRadius = UDim.new(0, 8)
	buttonCorner.Parent = button

	local buttonStroke = Instance.new("UIStroke")
	buttonStroke.Color = Color3.fromRGB(60, 60, 80)
	buttonStroke.Thickness = 1.5
	buttonStroke.Parent = button

	-- Hover/Click Animations
	local hoverTween = TweenService:Create(button, TweenInfo.new(0.2), {
		BackgroundColor3 = Color3.fromRGB(50, 50, 70),
		TextColor3 = Color3.fromRGB(255, 255, 255)
	})
	local normalTween = TweenService:Create(button, TweenInfo.new(0.2), {
		BackgroundColor3 = Color3.fromRGB(36, 36, 48),
		TextColor3 = Color3.fromRGB(240, 240, 240)
	})

	button.MouseEnter:Connect(function()
		hoverTween:Play()
		TweenService:Create(buttonStroke, TweenInfo.new(0.2), { Color = Color3.fromRGB(120, 120, 160) }):Play()
	end)

	button.MouseLeave:Connect(function()
		normalTween:Play()
		TweenService:Create(buttonStroke, TweenInfo.new(0.2), { Color = Color3.fromRGB(60, 60, 80) }):Play()
	end)

	button.MouseButton1Click:Connect(function()
		-- Play click flash effect
		button.BackgroundColor3 = Color3.fromRGB(80, 80, 110)
		task.wait(0.1)
		
		-- Fire spawn request to server
		selectCharacterEvent:FireServer(name)

		-- Fade out the UI smoothly
		local fadeOverlay = TweenService:Create(overlay, TweenInfo.new(0.4), { BackgroundTransparency = 1 })
		local fadeCard = TweenService:Create(card, TweenInfo.new(0.4), { BackgroundTransparency = 1 })
		
		-- Fade all sub-elements
		for _, child in card:GetChildren() do
			if child:IsA("TextLabel") then
				TweenService:Create(child, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
			elseif child:IsA("Frame") then
				for _, sub in child:GetChildren() do
					if sub:IsA("TextButton") then
						TweenService:Create(sub, TweenInfo.new(0.3), { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
						local stroke = sub:FindFirstChildOfClass("UIStroke")
						if stroke then
							TweenService:Create(stroke, TweenInfo.new(0.3), { Transparency = 1 }):Play()
						end
					end
				end
			end
		end
		
		local stroke = card:FindFirstChildOfClass("UIStroke")
		if stroke then
			TweenService:Create(stroke, TweenInfo.new(0.3), { Transparency = 1 }):Play()
		end

		fadeOverlay:Play()
		fadeCard:Play()
		
		fadeOverlay.Completed:Connect(function()
			screenGui:Destroy()
		end)
	end)

	return button
end

-- ========================================
-- Populate Selection Menu
-- ========================================

-- Scan character folder and configurations to display valid options
local hasCharacters = false
task.wait(0.2) -- small delay to let replication finish on join

-- Helper to check if a character template exists
local function findCharacterTemplate(name: string): Instance?
	-- 1. Try Characters folder
	if charactersFolder then
		local found = charactersFolder:FindFirstChild(name)
		if found then return found end
		-- Fallback for PotatoHead if it is named "Model"
		if name == "PotatoHead" then
			local foundModel = charactersFolder:FindFirstChild("Model")
			if foundModel then return foundModel end
		end
	end
	-- 2. Fallback to ReplicatedStorage directly
	local foundDirect = ReplicatedStorage:FindFirstChild(name)
	if foundDirect and foundDirect:IsA("Model") then
		return foundDirect
	end
	if name == "PotatoHead" then
		local foundModelDirect = ReplicatedStorage:FindFirstChild("Model")
		if foundModelDirect and foundModelDirect:IsA("Model") then
			return foundModelDirect
		end
	end
	-- 3. Fallback to workspace (for models placed directly in the game world)
	local foundWorkspace = workspace:FindFirstChild(name) or workspace:FindFirstChild(name:lower())
	if foundWorkspace and foundWorkspace:IsA("Model") then
		return foundWorkspace
	end
	return nil
end

-- Print ReplicatedStorage details if not found to help the user debug
local function printDebugDetails()
	print("[ToyStory UI] Character models not found. Debugging ReplicatedStorage:")
	print("  - Characters Folder exists:", charactersFolder ~= nil)
	if charactersFolder then
		print("  - Contents of ReplicatedStorage.Characters:")
		for _, child in charactersFolder:GetChildren() do
			print("    -", child.Name, "(" .. child.ClassName .. ")")
		end
	end
	print("  - Direct children of ReplicatedStorage:")
	for _, child in ReplicatedStorage:GetChildren() do
		if child.Name ~= "Shared" and child.Name ~= "Events" and child.Name ~= "Characters" then
			print("    -", child.Name, "(" .. child.ClassName .. ")")
		end
	end
end

for charName, charData in pairs(CharacterConfig) do
	if type(charData) == "table" and charData.Height then
		if findCharacterTemplate(charName) then
			local btn = createCharacterButton(charName)
			btn.Parent = container
			hasCharacters = true
		end
	end
end

if not hasCharacters then
	subtitle.Text = "Please wait, syncing character models..."
	subtitle.TextColor3 = Color3.fromRGB(255, 100, 100)
	printDebugDetails()
	
	-- Keep checking periodically
	task.spawn(function()
		local lastWarn = tick()
		while not hasCharacters do
			task.wait(1)
			
			if tick() - lastWarn > 5 then
				printDebugDetails()
				lastWarn = tick()
			end

			for charName, charData in pairs(CharacterConfig) do
				if type(charData) == "table" and charData.Height then
					if findCharacterTemplate(charName) then
						subtitle.Text = "Choose a character to enter the game"
						subtitle.TextColor3 = Color3.fromRGB(160, 160, 180)
						local btn = createCharacterButton(charName)
						btn.Parent = container
						hasCharacters = true
					end
				end
			end
		end
	end)
end

-- Show the UI
screenGui.Parent = playerGui
print("[ToyStory UI] Character selection menu initialized!")
