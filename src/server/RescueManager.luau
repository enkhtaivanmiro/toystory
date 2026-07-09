--[[
	ToyStory - RescueManager (ModuleScript)
	Handles cage generation, carrying captured toys in Sid's hand,
	teleporting captured toys, health decay, and rescue ProximityPrompts.
]]

local Players = game:GetService("Players")
local Debris = game:GetService("Debris")

local RescueManager = {}
local activeCage = nil
local CAGE_POSITION = Vector3.new(0, 3, 40) -- Default location

local captureConnections = {}
local damageTasks = {}
local rescuePrompts = {}

-- Tracking carried toys & welds
local carriedToys = {} -- Player -> Model
local carryingWelds = {} -- Player -> WeldConstraint
local checkLoopActive = false

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

--- Deposits a carried toy into the cage.
local function resetSidCarrying()
	for _, p in ipairs(Players:GetPlayers()) do
		local c = p.Character
		if c and c:GetAttribute("CharacterName") == "Sid" then
			c:SetAttribute("IsCarryingToy", false)
		end
	end
end

function RescueManager.DepositInCage(player: Player)
	local char = player.Character
	if not char then
		carriedToys[player] = nil
		return
	end

	print("[ToyStory RescueManager] Toy deposited in cage:", player.Name)

	-- Remove carrying weld
	local weld = carryingWelds[player]
	if weld then
		weld:Destroy()
		carryingWelds[player] = nil
	end

	carriedToys[player] = nil
	char:SetAttribute("IsCarried", false)

	-- Teleport inside cage
	createVisualCage()
	char:PivotTo(CFrame.new(CAGE_POSITION + Vector3.new(0, 1, 0)))

	-- Anchor root
	local root = char.PrimaryPart
	if root then
		root.Anchored = true
	end

	-- Restore platformstand state
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.PlatformStand = false
	end

	-- Restore standard captured collision rules (standard R6 is Torso, Left Leg, Right Leg, HumanoidRootPart collidable)
	for _, part in char:GetDescendants() do
		if part:IsA("BasePart") then
			local name = part.Name
			if name == "Torso" or name == "Left Leg" or name == "Right Leg" or name == "HumanoidRootPart" then
				part.CanCollide = true
			else
				part.CanCollide = false
			end
		end
	end

	-- Reset Sid carrying attribute since toy was deposited
	resetSidCarrying()
end

--- Starts the background loop that checks distance of carried toys to the cage.
local function startCheckLoop()
	if checkLoopActive then return end
	checkLoopActive = true

	task.spawn(function()
		while next(carriedToys) ~= nil do
			task.wait(0.2)
			local toDeposit = {}
			for p, char in pairs(carriedToys) do
				if char and char.Parent then
					local root = char.PrimaryPart
					if root then
						-- Check distance to CAGE_POSITION
						local dist = (root.Position - CAGE_POSITION).Magnitude
						if dist <= 15 then
							table.insert(toDeposit, p)
						end
					end
				else
					carriedToys[p] = nil
				end
			end

			-- Perform deposits outside the iteration loop to prevent dictionary mutation errors
			for _, p in toDeposit do
				RescueManager.DepositInCage(p)
			end
		end
		checkLoopActive = false
	end)
end

function RescueManager.Capture(toyCharacter: Model, hunterCharacter: Model?)
	local player = Players:GetPlayerFromCharacter(toyCharacter)
	if not player then return end

	toyCharacter:SetAttribute("IsCaptured", true)
	print("[ToyStory RescueManager] Toy captured:", player.Name)

	-- Setup carrying if Sid (hunterCharacter) is provided
	if hunterCharacter then
		local rightArm = hunterCharacter:FindFirstChild("Right Arm")
		if rightArm and rightArm:IsA("BasePart") then
			-- Flag Sid as carrying a toy
			hunterCharacter:SetAttribute("IsCarryingToy", true)

			-- Unanchor root and hand over network ownership to the server (nil)
			-- This stops the toy player's client from simulating physics and fighting the weld
			local root = toyCharacter.PrimaryPart
			if root then
				root.Anchored = false
				pcall(function()
					root:SetNetworkOwner(nil)
				end)
			end

			-- Weld toy's primary part to Sid's Right Arm
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = rightArm
			weld.Part1 = root or toyCharacter:FindFirstChild("Torso")
			weld.Name = "CarryingWeld"
			weld.Parent = rightArm

			carryingWelds[player] = weld
			toyCharacter:SetAttribute("IsCarried", true)
			carriedToys[player] = toyCharacter

			-- Position nicely relative to Sid's hand (Sid is scale ~6.2)
			local sidScale = 31 / 5
			toyCharacter:PivotTo(rightArm.CFrame * CFrame.new(0, -1.2 * sidScale, 0) * CFrame.Angles(math.rad(-90), 0, 0))

			-- Platform stand so they don't fight physics
			local humanoid = toyCharacter:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.PlatformStand = true
			end

			-- Make parts temporarily non-collidable so they don't glitch Sid's movement
			for _, part in toyCharacter:GetDescendants() do
				if part:IsA("BasePart") then
					part.CanCollide = false
				end
			end

			startCheckLoop()
		else
			-- Fallback: Teleport directly inside cage
			createVisualCage()
			toyCharacter:PivotTo(CFrame.new(CAGE_POSITION + Vector3.new(0, 1, 0)))
			local root = toyCharacter.PrimaryPart
			if root then
				root.Anchored = true
			end
		end
	else
		-- Teleport directly inside cage
		createVisualCage()
		toyCharacter:PivotTo(CFrame.new(CAGE_POSITION + Vector3.new(0, 1, 0)))
		local root = toyCharacter.PrimaryPart
		if root then
			root.Anchored = true
		end
	end

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

	-- Ensure health is full while captured (no damage decay)
	local humanoid = toyCharacter:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Health = 100
	end
end

function RescueManager.Release(player: Player)
	local char = player.Character
	if not char then return end

	print("[ToyStory RescueManager] Toy rescued:", player.Name)

	-- Remove from carried list if present
	carriedToys[player] = nil
	local weld = carryingWelds[player]
	if weld then
		weld:Destroy()
		carryingWelds[player] = nil
	end

	char:SetAttribute("IsCarried", false)

	-- Restore platformstand state
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.PlatformStand = false
	end

	-- Teleport outside cage
	char:PivotTo(CFrame.new(CAGE_POSITION + Vector3.new(0, 1, -12)))

	-- Unanchor and restore network ownership to the client player
	local root = char.PrimaryPart
	if root then
		root.Anchored = false
		pcall(function()
			root:SetNetworkOwner(player)
		end)
	end

	char:SetAttribute("IsCaptured", false)

	-- Reset Sid carrying attribute in case they were rescued from hand
	resetSidCarrying()

	-- Restore standard captured collision rules
	for _, part in char:GetDescendants() do
		if part:IsA("BasePart") then
			local name = part.Name
			if name == "Torso" or name == "Left Leg" or name == "Right Leg" or name == "HumanoidRootPart" then
				part.CanCollide = true
			else
				part.CanCollide = false
			end
		end
	end

	-- Clean up rescue connection / prompts
	RescueManager.CleanUpPlayer(player)

	-- Play rescue sound
	local head = char:FindFirstChild("Head")
	if head then
		local Utils = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Utils"))
		Utils.PlayOneShot(head, "rbxassetid://9114226176", 0.8)
	end
end

function RescueManager.DropCarriedToy(hunterPlayer: Player)
	local toyPlayer = nil
	for p, _ in pairs(carryingWelds) do
		toyPlayer = p
		break
	end

	if toyPlayer then
		local char = toyPlayer.Character
		if char then
			print("[ToyStory RescueManager] Toy dropped by Sid:", toyPlayer.Name)

			-- Destroy carrying weld
			local weld = carryingWelds[toyPlayer]
			if weld then
				weld:Destroy()
				carryingWelds[toyPlayer] = nil
			end

			carriedToys[toyPlayer] = nil
			char:SetAttribute("IsCarried", false)

			-- Restore platformstand state
			local humanoid = char:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.PlatformStand = false
			end

			-- Drop right in front of Sid
			local sidChar = hunterPlayer.Character
			if sidChar then
				local root = sidChar.PrimaryPart
				if root then
					char:PivotTo(root.CFrame * CFrame.new(0, 0, -10)) -- 10 studs in front of Sid
				end
			end

			-- Restore network ownership to player
			local root = char.PrimaryPart
			if root then
				root.Anchored = false
				pcall(function()
					root:SetNetworkOwner(toyPlayer)
				end)
			end

			char:SetAttribute("IsCaptured", false)

			-- Restore standard captured collision rules
			for _, part in char:GetDescendants() do
				if part:IsA("BasePart") then
					local name = part.Name
					if name == "Torso" or name == "Left Leg" or name == "Right Leg" or name == "HumanoidRootPart" then
						part.CanCollide = true
					else
						part.CanCollide = false
					end
				end
			end

			-- Clean up rescue connection / prompts
			RescueManager.CleanUpPlayer(toyPlayer)

			-- Reset Sid carrying attribute
			resetSidCarrying()
		end
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

	-- Clean up carried welds/toys
	carriedToys[player] = nil
	if carryingWelds[player] then
		carryingWelds[player]:Destroy()
		carryingWelds[player] = nil
	end
end

function RescueManager.Reset()
	for _, player in Players:GetPlayers() do
		RescueManager.CleanUpPlayer(player)
		local char = player.Character
		if char then
			char:SetAttribute("IsCaptured", false)
			char:SetAttribute("IsCarried", false)
			local root = char.PrimaryPart
			if root then
				root.Anchored = false
			end
			local humanoid = char:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.PlatformStand = false
			end
		end
	end

	carriedToys = {}
	carryingWelds = {}

	if activeCage and activeCage.Parent then
		activeCage:Destroy()
		activeCage = nil
	end
end

return RescueManager
