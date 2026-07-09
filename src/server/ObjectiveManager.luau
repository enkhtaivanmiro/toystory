--[[
	ToyStory - ObjectiveManager (ModuleScript)
	Spawns Mrs. Potato Head's parts, welds them to toys when collected,
	configures Mrs. Potato Head assembly base, and handles toy victory.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local ObjectiveManager = {}

local batteriesVal = ReplicatedStorage:WaitForChild("GameState"):WaitForChild("TimeRemaining").Parent:WaitForChild("BatteriesCollected")

local spawnedBatteries = {}
local activeRcCar = nil
local activeEscapeZone = nil
local escapeTouchedConnection = nil

local RC_CAR_POSITION = Vector3.new(0, 1.2, 0)
local ESCAPE_ZONE_POSITION = Vector3.new(0, 1, -55) -- Escape boundary

-- Spawning boundary box (raycasts down to find surfaces)
local SPAWN_BOUNDS_X = {-50, 50}
local SPAWN_BOUNDS_Z = {-50, 50}
local SPAWN_HEIGHT_START = 35

-- Helper to spawn visual Potato Head Part programmatically
local function createPotatoHeadPart(position: Vector3, partIndex: number): Part
	local part = Instance.new("Part")
	part.Name = "PotatoHeadPart"
	part.Size = Vector3.new(1, 1, 1)
	part.Position = position + Vector3.new(0, 0.5, 0)
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = false
	part.CanCollide = true

	-- Determine style based on index (so they collect different parts)
	if partIndex == 1 or partIndex == 4 then
		part.Color = Color3.fromRGB(52, 152, 219) -- Blue (Eye)
		part.Shape = Enum.PartType.Ball
		part.Size = Vector3.new(0.8, 0.8, 0.8)
	elseif partIndex == 2 or partIndex == 5 then
		part.Color = Color3.fromRGB(244, 143, 177) -- Pink (Ear)
		part.Size = Vector3.new(0.6, 1.2, 0.4)
	else
		part.Color = Color3.fromRGB(231, 76, 60) -- Red (Lips)
		part.Size = Vector3.new(1.2, 0.5, 0.5)
	end

	-- Glow effect so they are easy to spot
	local attachment = Instance.new("Attachment")
	attachment.Parent = part

	local light = Instance.new("PointLight")
	light.Color = part.Color
	light.Brightness = 2.0
	light.Range = 8
	light.Parent = attachment

	return part
end

-- Helper to spawn visual Mrs. Potato Head base model programmatically
local function createMrsPotatoHeadPart()
	if activeRcCar and activeRcCar.Parent then
		return activeRcCar
	end

	local model = Instance.new("Model")
	model.Name = "MrsPotatoHead"

	-- Potato body
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(3, 4, 3)
	body.Position = RC_CAR_POSITION
	body.Anchored = true
	body.Material = Enum.Material.SmoothPlastic
	body.Color = Color3.fromRGB(180, 130, 90) -- Potato brown
	body.Parent = model

	-- Red hat
	local hat = Instance.new("Part")
	hat.Name = "Hat"
	hat.Size = Vector3.new(3.2, 0.6, 3.2)
	hat.Position = RC_CAR_POSITION + Vector3.new(0, 2.1, 0)
	hat.Anchored = true
	hat.Material = Enum.Material.Plastic
	hat.Color = Color3.fromRGB(231, 76, 60) -- Red
	hat.Parent = model

	model.Parent = workspace
	activeRcCar = model
	return model
end

function ObjectiveManager.InitializeObjectives()
	ObjectiveManager.ClearObjectives()
	batteriesVal.Value = 0

	-- Create Mrs. Potato Head Base
	local assemblyBase = createMrsPotatoHeadPart()
	local body = assemblyBase:FindFirstChild("Body")
	if body then
		-- Prompt to assemble parts
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "PotatoPrompt"
		prompt.ObjectText = "Mrs. Potato Head"
		prompt.ActionText = "Assemble Part"
		prompt.HoldDuration = 1.5
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Parent = body

		prompt.Triggered:Connect(function(player)
			local char = player.Character
			if char and char:GetAttribute("CarryingPart") == true then
				-- Find part welded to player and destroy it
				local carriedPart = char:FindFirstChild("CarriedPart")
				if carriedPart then
					carriedPart:Destroy()
				end

				char:SetAttribute("CarryingPart", false)
				batteriesVal.Value = batteriesVal.Value + 1
				print("[ToyStory Objectives] Part assembled by", player.Name, "- Total:", batteriesVal.Value)

				-- Play insertion sound
				local Utils = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Utils"))
				Utils.PlayOneShot(body, "rbxassetid://9114226176", 0.8)

				-- Check if completed
				if batteriesVal.Value >= 3 then
					local GameLoopManager = require(script.Parent.GameLoopManager)
					GameLoopManager.EndGame("Toys")
				end
			end
		end)
	end

	-- Spawn 5 Potato Head Parts
	local rng = Random.new()
	local spawnedCount = 0

	for i = 1, 15 do
		if spawnedCount >= 5 then break end

		local rx = rng:NextNumber(SPAWN_BOUNDS_X[1], SPAWN_BOUNDS_X[2])
		local rz = rng:NextNumber(SPAWN_BOUNDS_Z[1], SPAWN_BOUNDS_Z[2])

		local rayOrigin = Vector3.new(rx, SPAWN_HEIGHT_START, rz)
		local rayDirection = Vector3.new(0, -50, 0)
		local raycastParams = RaycastParams.new()

		local result = workspace:Raycast(rayOrigin, rayDirection, raycastParams)
		if result and result.Instance and not result.Instance:FindFirstAncestor("MrsPotatoHead") then
			local hitPos = result.Position
			local part = createPotatoHeadPart(hitPos, spawnedCount + 1)
			part.Parent = workspace
			table.insert(spawnedBatteries, part)
			spawnedCount = spawnedCount + 1

			-- Setup Pick Up Prompt
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "PickPrompt"
			prompt.ObjectText = "Mrs. Potato Head's Part"
			prompt.ActionText = "Pick Up"
			prompt.HoldDuration = 0.5
			prompt.MaxActivationDistance = 8
			prompt.RequiresLineOfSight = false
			prompt.Parent = part

			prompt.Triggered:Connect(function(player)
				local char = player.Character
				if char and char:GetAttribute("IsCustomCharacter") then
					local name = char:GetAttribute("CharacterName")
					local isCaptured = char:GetAttribute("IsCaptured") or false
					if name ~= "Sid" and not isCaptured and not char:GetAttribute("CarryingPart") then
						-- Pick up part
						char:SetAttribute("CarryingPart", true)
						prompt:Destroy()
						
						-- Weld part to back of player
						part.CanCollide = false
						part.Anchored = false
						part.Name = "CarriedPart"
						
						local torso = char:FindFirstChild("Torso")
						if torso then
							part.CFrame = torso.CFrame * CFrame.new(0, 0, 1.1) * CFrame.Angles(math.rad(90), 0, 0)
							
							local weld = Instance.new("WeldConstraint")
							weld.Part0 = torso
							weld.Part1 = part
							weld.Parent = part
							
							part.Parent = char
						else
							part:Destroy()
						end

						-- Play pick up sound
						local head = char:FindFirstChild("Head")
						if head then
							local Utils = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Utils"))
							Utils.PlayOneShot(head, "rbxassetid://9114223126", 0.6)
						end
					end
				end
			end)
		end
	end
	
	print("[ToyStory Objectives] Spawned", spawnedCount, "Mrs. Potato Head parts across the room.")
end

function ObjectiveManager.OpenEscapeZone()
	if activeEscapeZone and activeEscapeZone.Parent then
		return
	end

	print("[ToyStory Objectives] Escape zone opened! Toys must escape!")

	-- Spawn Escape Ring visual
	local escapeZone = Instance.new("Part")
	escapeZone.Name = "EscapeZone"
	escapeZone.Shape = Enum.PartType.Cylinder
	escapeZone.Size = Vector3.new(2, 16, 16)
	escapeZone.Position = ESCAPE_ZONE_POSITION
	escapeZone.Rotation = Vector3.new(0, 0, 90)
	escapeZone.Anchored = true
	escapeZone.CanCollide = false
	escapeZone.Material = Enum.Material.Neon
	escapeZone.Color = Color3.fromRGB(52, 152, 219) -- Sky blue glow
	escapeZone.Transparency = 0.5
	escapeZone.Parent = workspace

	activeEscapeZone = escapeZone

	-- Setup touched trigger
	escapeTouchedConnection = escapeZone.Touched:Connect(function(hit)
		local char = hit:FindFirstAncestorOfClass("Model")
		if char and char:GetAttribute("IsCustomCharacter") then
			local player = Players:GetPlayerFromCharacter(char)
			local name = char:GetAttribute("CharacterName")
			local isCaptured = char:GetAttribute("IsCaptured") or false

			if player and name ~= "Sid" and not isCaptured then
				-- Play escape chime
				local head = char:FindFirstChild("Head")
				if head then
					local Utils = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Utils"))
					Utils.PlayOneShot(head, "rbxassetid://9114227181", 1.0)
				end

				print("[ToyStory Objectives]", player.Name, "successfully escaped!")
				
				-- Destroy character (escaped!)
				player.Character = nil
				char:Destroy()

				-- Increment escaped count
				local GameLoopManager = require(script.Parent.GameLoopManager)
				GameLoopManager.ToysEscapedCount = GameLoopManager.ToysEscapedCount + 1
				
				-- If no toys left in play area, end match immediately
				task.wait(1)
				local aliveToys = 0
				for _, p in Players:GetPlayers() do
					local c = p.Character
					if c and c:GetAttribute("IsCustomCharacter") then
						local n = c:GetAttribute("CharacterName")
						local cap = c:GetAttribute("IsCaptured") or false
						if n ~= "Sid" and not cap then
							aliveToys = aliveToys + 1
						end
					end
				end

				if aliveToys == 0 then
					GameLoopManager.EndGame("Toys")
				end
			end
		end
	end)
end

function ObjectiveManager.ClearObjectives()
	for _, bat in spawnedBatteries do
		if bat and bat.Parent then
			bat:Destroy()
		end
	end
	spawnedBatteries = {}

	if activeRcCar and activeRcCar.Parent then
		activeRcCar:Destroy()
		activeRcCar = nil
	end

	if activeEscapeZone and activeEscapeZone.Parent then
		activeEscapeZone:Destroy()
		activeEscapeZone = nil
	end

	if escapeTouchedConnection then
		escapeTouchedConnection:Disconnect()
		escapeTouchedConnection = nil
	end

	-- Clean up any carried part leftover on players
	for _, player in Players:GetPlayers() do
		local char = player.Character
		if char then
			char:SetAttribute("CarryingPart", false)
			local carried = char:FindFirstChild("CarriedPart")
			if carried then
				carried:Destroy()
			end
		end
	end
end

return ObjectiveManager
