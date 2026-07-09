--[[
	ToyStory - ObjectiveManager (ModuleScript)
	Spawns battery objects, welds them to toys, configures the RC Car objective,
	opens the Escape Zone, and handles toy escape events.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local Utils = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Utils"))

local ObjectiveManager = {}

local batteriesVal = ReplicatedStorage:WaitForChild("GameState"):WaitForChild("BatteriesCollected")

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

-- Helper to spawn visual Battery programmatically
local function createBatteryPart(position: Vector3): Part
	local battery = Instance.new("Part")
	battery.Name = "Battery"
	battery.Size = Vector3.new(0.6, 1.2, 0.6)
	battery.Position = position + Vector3.new(0, 0.6, 0)
	battery.Material = Enum.Material.Metal
	battery.Color = Color3.fromRGB(241, 196, 15) -- Yellow gold
	battery.Anchored = false
	battery.CanCollide = true

	-- Black tip cap
	local cap = Instance.new("Part")
	cap.Name = "Cap"
	cap.Size = Vector3.new(0.4, 0.2, 0.4)
	cap.Position = battery.Position + Vector3.new(0, 0.6, 0)
	cap.Material = Enum.Material.Plastic
	cap.Color = Color3.fromRGB(30, 30, 30)
	cap.Anchored = false
	cap.CanCollide = false
	cap.Parent = battery

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = battery
	weld.Part1 = cap
	weld.Parent = battery

	-- Glow effect
	local attachment = Instance.new("Attachment")
	attachment.Parent = battery

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(241, 196, 15)
	light.Brightness = 2.0
	light.Range = 8
	light.Parent = attachment

	return battery
end

-- Helper to spawn visual RC Car programmatically
local function createRcCarPart()
	if activeRcCar and activeRcCar.Parent then
		return activeRcCar
	end

	local carModel = Instance.new("Model")
	carModel.Name = "RcCar"

	-- Main Body
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(4, 1.5, 6)
	body.Position = RC_CAR_POSITION
	body.Anchored = true
	body.Material = Enum.Material.Plastic
	body.Color = Color3.fromRGB(46, 204, 113) -- Green
	body.Parent = carModel

	-- Wheels
	local wheelParams = {
		Vector3.new(2.1, -0.4, 2),
		Vector3.new(-2.1, -0.4, 2),
		Vector3.new(2.1, -0.4, -2),
		Vector3.new(-2.1, -0.4, -2),
	}

	for _, offset in wheelParams do
		local wheel = Instance.new("Part")
		wheel.Name = "Wheel"
		wheel.Size = Vector3.new(0.8, 1.4, 1.4)
		wheel.Position = RC_CAR_POSITION + offset
		wheel.Rotation = Vector3.new(0, 0, 90)
		wheel.Anchored = true
		wheel.Material = Enum.Material.SmoothPlastic
		wheel.Color = Color3.fromRGB(20, 20, 20)
		wheel.Parent = carModel
	end

	carModel.Parent = workspace
	activeRcCar = carModel
	return carModel
end

function ObjectiveManager.InitializeObjectives()
	ObjectiveManager.ClearObjectives()
	batteriesVal.Value = 0

	-- Create RC Car
	local car = createRcCarPart()
	local body = car:FindFirstChild("Body")
	if body then
		-- Prompt to insert batteries
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "RcPrompt"
		prompt.ObjectText = "RC Escape Car"
		prompt.ActionText = "Insert Battery"
		prompt.HoldDuration = 1.5
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Parent = body

		prompt.Triggered:Connect(function(player)
			local char = player.Character
			if char and char:GetAttribute("CarryingBattery") == true then
				-- Find battery welded to player and destroy it
				local carriedBattery = char:FindFirstChild("CarriedBattery")
				if carriedBattery then
					carriedBattery:Destroy()
				end

				char:SetAttribute("CarryingBattery", false)
				batteriesVal.Value = batteriesVal.Value + 1
				print("[ToyStory Objectives] Battery inserted by", player.Name, "- Total:", batteriesVal.Value)

				-- Play mechanical insertion sound
				Utils.PlayOneShot(body, "rbxassetid://9114226176", 0.8)

				-- Check if completed
				if batteriesVal.Value >= 3 then
					-- Start escape phase via loop manager
					local GameLoopManager = require(script.Parent.GameLoopManager)
					GameLoopManager.SetPhase("Escape")
				end
			end
		end)
	end

	-- Spawn 5 Batteries
	local rng = Random.new()
	local spawnedCount = 0

	for i = 1, 10 do
		if spawnedCount >= 5 then break end

		local rx = rng:NextNumber(SPAWN_BOUNDS_X[1], SPAWN_BOUNDS_X[2])
		local rz = rng:NextNumber(SPAWN_BOUNDS_Z[1], SPAWN_BOUNDS_Z[2])

		local rayOrigin = Vector3.new(rx, SPAWN_HEIGHT_START, rz)
		local rayDirection = Vector3.new(0, -50, 0)
		local raycastParams = RaycastParams.new()

		local result = workspace:Raycast(rayOrigin, rayDirection, raycastParams)
		if result and result.Instance and not result.Instance:FindFirstAncestor("RcCar") then
			local hitPos = result.Position
			local battery = createBatteryPart(hitPos)
			battery.Parent = workspace
			table.insert(spawnedBatteries, battery)
			spawnedCount = spawnedCount + 1

			-- Setup Pick Up Prompt
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "PickPrompt"
			prompt.ObjectText = "Battery"
			prompt.ActionText = "Pick Up"
			prompt.HoldDuration = 0.5
			prompt.MaxActivationDistance = 8
			prompt.RequiresLineOfSight = false
			prompt.Parent = battery

			prompt.Triggered:Connect(function(player)
				local char = player.Character
				if char and char:GetAttribute("IsCustomCharacter") then
					local name = char:GetAttribute("CharacterName")
					local isCaptured = char:GetAttribute("IsCaptured") or false
					if name ~= "Sid" and not isCaptured and not char:GetAttribute("CarryingBattery") then
						-- Pick up battery
						char:SetAttribute("CarryingBattery", true)
						prompt:Destroy()
						
						-- Weld battery to back of player
						battery.CanCollide = false
						battery.Anchored = false
						battery.Name = "CarriedBattery"
						
						local torso = char:FindFirstChild("Torso")
						if torso then
							battery.CFrame = torso.CFrame * CFrame.new(0, 0, 1.1) * CFrame.Angles(math.rad(90), 0, 0)
							
							local weld = Instance.new("WeldConstraint")
							weld.Part0 = torso
							weld.Part1 = battery
							weld.Parent = battery
							
							battery.Parent = char
						else
							battery:Destroy()
						end

						-- Play pick up sound
						local head = char:FindFirstChild("Head")
						if head then
							Utils.PlayOneShot(head, "rbxassetid://9114223126", 0.6)
						end
					end
				end
			end)
		end
	end
	
	print("[ToyStory Objectives] Spawned", spawnedCount, "batteries across the room.")
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

	-- Clean up any carried battery leftover on players
	for _, player in Players:GetPlayers() do
		local char = player.Character
		if char then
			char:SetAttribute("CarryingBattery", false)
			local carried = char:FindFirstChild("CarriedBattery")
			if carried then
				carried:Destroy()
			end
		end
	end
end

return ObjectiveManager
