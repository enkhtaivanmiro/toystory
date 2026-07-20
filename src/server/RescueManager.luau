--[[
	ToyStory - RescueManager (ModuleScript)
	Handles carrying captured toys in Sid's hand,
	depositing them into the PrisonBox (hold E for 3s),
	and rescuing them from the PrisonBox (hold E for 5s by another toy).
]]

local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local PhysicsService = game:GetService("PhysicsService")
local RunService = game:GetService("RunService")

local RescueManager = {}

local captureConnections = {}
local damageTasks = {}
local rescuePrompts = {}

-- Tracking carried toys & welds
local carriedToys = {} -- Player -> Model
local carryingWelds = {} -- Player -> WeldConstraint (placeholder)
local carryingConnections = {} -- Player -> RBXScriptConnection (for manual CFrame carrying)

-- PrisonBox state
local prisonBox = nil -- Reference to the PrisonBox object in workspace
local prisonedToys = {} -- Array of { player: Player, character: Model }
local depositPrompt = nil -- ProximityPrompt for Sid to deposit
local rescuePrompt = nil -- ProximityPrompt for toys to rescue
local sidAttributeConnection = nil -- Connection listening for Sid's IsCarryingToy changes

--- Resets the IsCarryingToy attribute on all Sid characters.
local function resetSidCarrying()
	for _, p in ipairs(Players:GetPlayers()) do
		local c = p.Character
		if c and c:GetAttribute("CharacterName") == "Sid" then
			c:SetAttribute("IsCarryingToy", false)
		end
	end
end

--- Updates the rescue prompt visibility based on whether any toys are imprisoned.
local function updateRescuePromptState()
	if rescuePrompt then
		rescuePrompt.Enabled = (#prisonedToys > 0)
	end
end

--- Updates the deposit prompt visibility based on whether Sid is carrying a toy.
local function updateDepositPromptState()
	if not depositPrompt then return end

	local sidCarrying = false
	for _, p in ipairs(Players:GetPlayers()) do
		local c = p.Character
		if c and c:GetAttribute("CharacterName") == "Sid" and c:GetAttribute("IsCarryingToy") == true then
			sidCarrying = true
			break
		end
	end

	depositPrompt.Enabled = sidCarrying
end

--- Gets a safe position near the PrisonBox for depositing toys.
--- Offsets each toy slightly so multiple toys don't stack on top of each other.
local function getPrisonPosition(index: number): CFrame
	if not prisonBox then
		return CFrame.new(0, 3, 40)
	end

	local boxPart = nil
	if prisonBox:IsA("Model") then
		boxPart = prisonBox.PrimaryPart or prisonBox:FindFirstChildWhichIsA("BasePart")
	elseif prisonBox:IsA("BasePart") then
		boxPart = prisonBox
	end

	if boxPart then
		-- Place toys on top of the box, offset each one slightly so they don't overlap
		local boxCFrame = boxPart.CFrame
		local boxSize = boxPart.Size
		local xOffset = ((index - 1) % 3 - 1) * 3 -- -3, 0, 3 pattern
		local zOffset = math.floor((index - 1) / 3) * 3
		return boxCFrame * CFrame.new(xOffset, boxSize.Y / 2 + 2, zOffset)
	end

	return CFrame.new(0, 3, 40)
end

--- Gets a safe release position near the PrisonBox (outside it).
local function getReleasePosition(): CFrame
	if not prisonBox then
		return CFrame.new(0, 1, 28)
	end

	local boxPart = nil
	if prisonBox:IsA("Model") then
		boxPart = prisonBox.PrimaryPart or prisonBox:FindFirstChildWhichIsA("BasePart")
	elseif prisonBox:IsA("BasePart") then
		boxPart = prisonBox
	end

	if boxPart then
		-- Teleport 12 studs in front of the box
		return boxPart.CFrame * CFrame.new(0, 1, -12)
	end

	return CFrame.new(0, 1, 28)
end

--- Deposits a carried toy into the PrisonBox.
function RescueManager.DepositInPrisonBox(toyPlayer: Player)
	local char = toyPlayer.Character
	if not char then
		carriedToys[toyPlayer] = nil
		return
	end

	print("[ToyStory RescueManager] Toy deposited in PrisonBox:", toyPlayer.Name)

	-- Disconnect manual carrying Heartbeat loop
	local conn = carryingConnections[toyPlayer]
	if conn then
		conn:Disconnect()
		carryingConnections[toyPlayer] = nil
	end
	carryingWelds[toyPlayer] = nil
	carriedToys[toyPlayer] = nil
	char:SetAttribute("IsCarried", false)
	char:SetAttribute("IsPrisoned", true)

	-- Track in prisoned list
	table.insert(prisonedToys, { player = toyPlayer, character = char })

	-- Teleport inside/on top of PrisonBox
	local prisonIndex = #prisonedToys
	char:PivotTo(getPrisonPosition(prisonIndex))

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

	-- Reset Sid carrying attribute since toy was deposited
	resetSidCarrying()

	-- Update prompt states
	updateDepositPromptState()
	updateRescuePromptState()
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

			-- Anchor root part so it doesn't simulate physics or exert any force on Sid
			local root = toyCharacter.PrimaryPart
			if root then
				root.Anchored = true
			end

			-- Update the toy's position relative to Sid's hand every frame in Heartbeat.
			-- Since the toy is Anchored, it moves smoothly with Sid but cannot cause flinging!
			local heartbeatConn = RunService.Heartbeat:Connect(function()
				if not toyCharacter.Parent or not hunterCharacter.Parent then
					return
				end
				if toyCharacter:GetAttribute("IsCaptured") == true and toyCharacter:GetAttribute("IsCarried") == true then
					local rArm = hunterCharacter:FindFirstChild("Right Arm")
					if rArm then
						local sidScale = 31 / 5
						toyCharacter:PivotTo(rArm.CFrame * CFrame.new(0, -1.2 * sidScale, 0) * CFrame.Angles(math.rad(-90), 0, 0))
					end
				end
			end)

			carryingConnections[player] = heartbeatConn
			carryingWelds[player] = true -- placeholder flag for game state checks
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

			-- Make parts temporarily non-collidable and assign to CapturedToys collision group
			-- to prevent physical collisions with Sid or other Toys from flinging characters.
			-- Set Massless to true so their weight doesn't pull Sid down or glitch his movement.
			for _, part in toyCharacter:GetDescendants() do
				if part:IsA("BasePart") then
					part.CanCollide = false
					part.CollisionGroup = "CapturedToys"
					part.Massless = true
				end
			end

			-- Update deposit prompt so Sid can see it now
			updateDepositPromptState()
		end
	end

	-- Create Rescue ProximityPrompt on Torso (for direct rescue while being carried)
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

--- Releases a toy from the PrisonBox specifically.
function RescueManager.ReleaseFromPrisonBox(rescuingPlayer: Player)
	if #prisonedToys == 0 then return end

	-- Release the first imprisoned toy (FIFO order)
	local entry = table.remove(prisonedToys, 1)
	local toyPlayer = entry.player
	local char = entry.character

	if not char or not char.Parent then
		-- Character is gone, just update state
		updateRescuePromptState()
		return
	end

	print("[ToyStory RescueManager] Toy rescued from PrisonBox by", rescuingPlayer.Name, ":", toyPlayer.Name)

	char:SetAttribute("IsPrisoned", false)
	char:SetAttribute("IsCarried", false)

	-- Restore platformstand state
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.PlatformStand = false
	end

	-- Teleport outside PrisonBox
	char:PivotTo(getReleasePosition())

	-- Unanchor and restore network ownership to the client player
	local root = char.PrimaryPart
	if root then
		root.Anchored = false
		pcall(function()
			root:SetNetworkOwner(toyPlayer)
		end)
	end

	char:SetAttribute("IsCaptured", false)

	-- Restore standard collision rules and collision group
	for _, part in char:GetDescendants() do
		if part:IsA("BasePart") then
			part.CollisionGroup = "Toys"
			part.Massless = false
			local name = part.Name
			if name == "Torso" or name == "Left Leg" or name == "Right Leg" or name == "HumanoidRootPart" then
				part.CanCollide = true
			else
				part.CanCollide = false
			end
		end
	end

	-- Clean up rescue connection / prompts for this player
	RescueManager.CleanUpPlayer(toyPlayer)

	-- Play rescue sound
	local head = char:FindFirstChild("Head")
	if head then
		local Utils = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Utils"))
		Utils.PlayOneShot(head, "rbxassetid://9114226176", 0.8)
	end

	-- Update prompt states
	updateRescuePromptState()
end

function RescueManager.Release(player: Player)
	local char = player.Character
	if not char then return end

	print("[ToyStory RescueManager] Toy rescued:", player.Name)

	-- Remove from carried list if present
	carriedToys[player] = nil
	-- Disconnect manual carrying Heartbeat loop
	local conn = carryingConnections[player]
	if conn then
		conn:Disconnect()
		carryingConnections[player] = nil
	end
	carryingWelds[player] = nil

	char:SetAttribute("IsCarried", false)

	-- Remove from prisoned list if present
	for i, entry in ipairs(prisonedToys) do
		if entry.player == player then
			table.remove(prisonedToys, i)
			break
		end
	end
	char:SetAttribute("IsPrisoned", false)

	-- Restore platformstand state
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.PlatformStand = false
	end

	-- Teleport outside PrisonBox
	char:PivotTo(getReleasePosition())

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

	-- Restore standard captured collision rules and collision group
	for _, part in char:GetDescendants() do
		if part:IsA("BasePart") then
			part.CollisionGroup = "Toys"
			part.Massless = false
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

	-- Update prompt states
	updateDepositPromptState()
	updateRescuePromptState()
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

			-- Disconnect manual carrying Heartbeat loop
			local conn = carryingConnections[toyPlayer]
			if conn then
				conn:Disconnect()
				carryingConnections[toyPlayer] = nil
			end
			carryingWelds[toyPlayer] = nil

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

			-- Restore standard captured collision rules and collision group
			for _, part in char:GetDescendants() do
				if part:IsA("BasePart") then
					part.CollisionGroup = "Toys"
					part.Massless = false
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

			-- Update deposit prompt
			updateDepositPromptState()
		end
	end
end

--- Initializes the PrisonBox system. Finds the PrisonBox in workspace
--- and sets up deposit/rescue ProximityPrompts on it.
function RescueManager.InitPrisonBox()
	-- Clean up old prompts if re-initializing
	if depositPrompt then
		depositPrompt:Destroy()
		depositPrompt = nil
	end
	if rescuePrompt then
		rescuePrompt:Destroy()
		rescuePrompt = nil
	end
	if sidAttributeConnection then
		sidAttributeConnection:Disconnect()
		sidAttributeConnection = nil
	end

	-- Find the PrisonBox in workspace
	prisonBox = workspace:FindFirstChild("PrisonBox")
	if not prisonBox then
		warn("[ToyStory RescueManager] PrisonBox not found in workspace! Place a Part or Model named 'PrisonBox'.")
		return
	end

	-- Determine which part to attach prompts to
	local promptParent = nil
	if prisonBox:IsA("Model") then
		promptParent = prisonBox.PrimaryPart or prisonBox:FindFirstChildWhichIsA("BasePart")
	elseif prisonBox:IsA("BasePart") then
		promptParent = prisonBox
	end

	if not promptParent then
		warn("[ToyStory RescueManager] PrisonBox has no BasePart to attach prompts to!")
		return
	end

	-- === Deposit Prompt (Sid only, 3 second hold) ===
	depositPrompt = Instance.new("ProximityPrompt")
	depositPrompt.Name = "PrisonDepositPrompt"
	depositPrompt.ObjectText = "Prison Box"
	depositPrompt.ActionText = "Imprison Toy"
	depositPrompt.HoldDuration = 3.0
	depositPrompt.MaxActivationDistance = 12
	depositPrompt.RequiresLineOfSight = false
	depositPrompt.KeyboardKeyCode = Enum.KeyCode.E
	depositPrompt.Enabled = false -- Starts disabled, enabled when Sid is carrying
	depositPrompt.Parent = promptParent

	depositPrompt.Triggered:Connect(function(player)
		local char = player.Character
		if not char or char:GetAttribute("CharacterName") ~= "Sid" then
			return
		end
		if char:GetAttribute("IsCarryingToy") ~= true then
			return
		end

		-- Find the toy being carried by Sid
		local toyPlayer = nil
		for p, _ in pairs(carryingWelds) do
			toyPlayer = p
			break
		end

		if toyPlayer then
			RescueManager.DepositInPrisonBox(toyPlayer)
		end
	end)

	-- === Rescue Prompt (Toys only, 5 second hold) ===
	rescuePrompt = Instance.new("ProximityPrompt")
	rescuePrompt.Name = "PrisonRescuePrompt"
	rescuePrompt.ObjectText = "Prison Box"
	rescuePrompt.ActionText = "Free Teammate"
	rescuePrompt.HoldDuration = 5.0
	rescuePrompt.MaxActivationDistance = 12
	rescuePrompt.RequiresLineOfSight = false
	rescuePrompt.KeyboardKeyCode = Enum.KeyCode.E
	rescuePrompt.Enabled = false -- Starts disabled, enabled when toys are imprisoned
	rescuePrompt.Parent = promptParent

	rescuePrompt.Triggered:Connect(function(rescuingPlayer)
		local rescuerChar = rescuingPlayer.Character
		if not rescuerChar or not rescuerChar:GetAttribute("IsCustomCharacter") then
			return
		end

		local charName = rescuerChar:GetAttribute("CharacterName")
		local isCaptured = rescuerChar:GetAttribute("IsCaptured") or false

		-- Only non-Sid, non-captured toys can rescue
		if charName == "Sid" or isCaptured then
			return
		end

		RescueManager.ReleaseFromPrisonBox(rescuingPlayer)
	end)

	-- Listen for Sid's IsCarryingToy attribute changes to toggle deposit prompt
	-- We need to hook into CharacterAdded to catch when Sid spawns
	local function hookSidAttributeListener(player: Player)
		local char = player.Character
		if char and char:GetAttribute("CharacterName") == "Sid" then
			-- Listen for attribute changes on this Sid character
			local attrConn = char:GetAttributeChangedSignal("IsCarryingToy"):Connect(function()
				updateDepositPromptState()
			end)

			-- Clean up when character is removed
			char.AncestryChanged:Connect(function()
				if not char.Parent then
					attrConn:Disconnect()
				end
			end)
		end
	end

	for _, player in Players:GetPlayers() do
		hookSidAttributeListener(player)
		player.CharacterAdded:Connect(function()
			task.wait(1) -- Wait for attributes to be set
			hookSidAttributeListener(player)
		end)
	end

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			task.wait(1)
			hookSidAttributeListener(player)
		end)
	end)

	print("[ToyStory RescueManager] PrisonBox initialized with deposit (3s) and rescue (5s) prompts!")
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

	-- Clean up carried connection/toys
	carriedToys[player] = nil
	local conn = carryingConnections[player]
	if conn then
		conn:Disconnect()
		carryingConnections[player] = nil
	end
	carryingWelds[player] = nil
end

function RescueManager.Reset()
	for _, player in Players:GetPlayers() do
		RescueManager.CleanUpPlayer(player)
		local char = player.Character
		if char then
			char:SetAttribute("IsCaptured", false)
			char:SetAttribute("IsCarried", false)
			char:SetAttribute("IsPrisoned", false)
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
	carryingConnections = {}
	prisonedToys = {}

	-- Clean up PrisonBox prompts
	if depositPrompt then
		depositPrompt:Destroy()
		depositPrompt = nil
	end
	if rescuePrompt then
		rescuePrompt:Destroy()
		rescuePrompt = nil
	end
	if sidAttributeConnection then
		sidAttributeConnection:Disconnect()
		sidAttributeConnection = nil
	end
end

return RescueManager
