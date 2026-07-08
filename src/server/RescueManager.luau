--[[
	ToyStory - RescueManager (ModuleScript)
	Handles cage generation, teleporting captured toys, health decay,
	and creating ProximityPrompts for other toys to rescue them.
]]

local Players = game:GetService("Players")
local Debris = game:GetService("Debris")

local RescueManager = {}
local activeCage = nil
local CAGE_POSITION = Vector3.new(0, 3, 40) -- Default location (can be customized)

local captureConnections = {}
local damageTasks = {}
local rescuePrompts = {}

-- Create a visual cage programmatically if it doesn't exist
local function createVisualCage()
	if activeCage and activeCage.Parent then
		return activeCage
	end

	local cageModel = Instance.new("Model")
	cageModel.Name = "CaptureCage"

	-- Main Floor
	local floor = Instance.new("Part")
	floor.Name = "Floor"
	floor.Size = Vector3.new(16, 1, 16)
	floor.Position = CAGE_POSITION - Vector3.new(0, 0.5, 0)
	floor.Anchored = true
	floor.Material = Enum.Material.Metal
	floor.Color = Color3.fromRGB(80, 80, 80)
	floor.Parent = cageModel

	-- Cage walls (Semi-transparent bars style)
	local wallParams = {
		{Size = Vector3.new(16, 12, 1), Position = CAGE_POSITION + Vector3.new(0, 5.5, 8)},
		{Size = Vector3.new(16, 12, 1), Position = CAGE_POSITION + Vector3.new(0, 5.5, -8)},
		{Size = Vector3.new(1, 12, 16), Position = CAGE_POSITION + Vector3.new(8, 5.5, 0)},
		{Size = Vector3.new(1, 12, 16), Position = CAGE_POSITION + Vector3.new(-8, 5.5, 0)},
	}

	for i, param in wallParams do
		local wall = Instance.new("Part")
		wall.Name = "Wall" .. i
		wall.Size = param.Size
		wall.Position = param.Position
		wall.Anchored = true
		wall.Material = Enum.Material.Glass
		wall.Color = Color3.fromRGB(150, 50, 50)
		wall.Transparency = 0.6
		wall.Parent = cageModel
	end

	-- Ceiling
	local ceiling = Instance.new("Part")
	ceiling.Name = "Ceiling"
	ceiling.Size = Vector3.new(16, 1, 16)
	ceiling.Position = CAGE_POSITION + Vector3.new(0, 11.5, 0)
	ceiling.Anchored = true
	ceiling.Material = Enum.Material.Metal
	ceiling.Color = Color3.fromRGB(50, 50, 50)
	ceiling.Parent = cageModel

	cageModel.Parent = workspace
	activeCage = cageModel
	return cageModel
end

function RescueManager.Capture(toyCharacter: Model)
	local player = Players:GetPlayerFromCharacter(toyCharacter)
	if not player then return end

	-- Teleport inside cage
	createVisualCage()
	toyCharacter:PivotTo(CFrame.new(CAGE_POSITION + Vector3.new(0, 1, 0)))

	-- Anchor Root
	local root = toyCharacter.PrimaryPart
	if root then
		root.Anchored = true
	end

	toyCharacter:SetAttribute("IsCaptured", true)
	print("[ToyStory RescueManager] Toy captured:", player.Name)

	-- Create Rescue ProximityPrompt on Torso
	local torso = toyCharacter:FindFirstChild("Torso")
	if torso then
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "RescuePrompt"
		prompt.ObjectText = player.Name
		prompt.ActionText = "Rescue Teammate"
		prompt.HoldDuration = 3.0
		prompt.MaxActivationDistance = 8
		prompt.RequiresLineOfSight = false
		prompt.Parent = torso

		rescuePrompts[player] = prompt

		-- Setup Prompt Trigger
		local conn
		conn = prompt.Triggered:Connect(function(rescuingPlayer)
			-- Ensure rescuer is an active toy and not captured/hunter
			local rescuerChar = rescuingPlayer.Character
			if rescuerChar and rescuerChar:GetAttribute("IsCustomCharacter") then
				local name = rescuerChar:GetAttribute("CharacterName")
				local isCaptured = rescuerChar:GetAttribute("IsCaptured") or false
				if name ~= "Sid" and not isCaptured then
					RescueManager.Release(player)
				end
			end
		end)
		captureConnections[player] = conn
	end

	-- Slowly decay health while captured (5 health per second)
	local humanoid = toyCharacter:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Health = 100
		
		local taskRef
		taskRef = task.spawn(function()
			while toyCharacter:GetAttribute("IsCaptured") == true and humanoid.Health > 0 do
				task.wait(1.0)
				pcall(function()
					humanoid.Health = humanoid.Health - 5
				end)
			end
			
			if humanoid.Health <= 0 then
				-- Eliminate player
				print("[ToyStory RescueManager] Captured toy died in cage:", player.Name)
				humanoid:BreakJoints()
				RescueManager.CleanUpPlayer(player)
			end
		end)
		damageTasks[player] = taskRef
	end
end

function RescueManager.Release(player: Player)
	local char = player.Character
	if not char then return end

	print("[ToyStory RescueManager] Toy rescued:", player.Name)

	-- Teleport outside cage
	char:PivotTo(CFrame.new(CAGE_POSITION + Vector3.new(0, 1, -12)))

	-- Unanchor
	local root = char.PrimaryPart
	if root then
		root.Anchored = false
	end

	char:SetAttribute("IsCaptured", false)

	-- Clean up rescue connection / tasks
	RescueManager.CleanUpPlayer(player)

	-- Play rescue sound
	local head = char:FindFirstChild("Head")
	if head then
		local sound = Instance.new("Sound")
		sound.SoundId = "rbxassetid://9114226176" -- success chime sound
		sound.Volume = 0.8
		sound.Parent = head
		sound:Play()
		Debris:AddItem(sound, 3)
	end
end

function RescueManager.CleanUpPlayer(player: Player)
	if captureConnections[player] then
		captureConnections[player]:Disconnect()
		captureConnections[player] = nil
	end
	if damageTasks[player] then
		task.cancel(damageTasks[player])
		damageTasks[player] = nil
	end
	if rescuePrompts[player] then
		rescuePrompts[player]:Destroy()
		rescuePrompts[player] = nil
	end
end

function RescueManager.Reset()
	for _, player in Players:GetPlayers() do
		RescueManager.CleanUpPlayer(player)
		local char = player.Character
		if char then
			char:SetAttribute("IsCaptured", false)
			local root = char.PrimaryPart
			if root then
				root.Anchored = false
			end
		end
	end

	if activeCage and activeCage.Parent then
		activeCage:Destroy()
		activeCage = nil
	end
end

return RescueManager
