--[[
	ToyStory - Game Manager Server Script
	Orchestrates round state machine, spawns objectives, lobby, cages, and closets dynamically.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

-- Initialize folders
local eventsFolder = ReplicatedStorage:WaitForChild("Events")

-- Game Settings
local ROUND_DURATION = 180 -- seconds
local HIDING_DURATION = 20 -- seconds
local INTERMISSION_DURATION = 15 -- seconds

-- State Variables
local gameState = "Intermission" -- "Intermission", "Hiding", "Hunt", "Escape", "RoundOver"
local roundTimer = 0
local batteryCount = 0
local requiredBatteries = 3

-- Dynamic World References
local lobbyPlatform = nil
local rescueCage = nil
local hunterCloset = nil
local closetBarrier = nil
local escapeZone = nil
local radioGenerator = nil
local activeBatteries = {}

-- remote values
local function getOrCreateValue(parent, name, className)
	local val = parent:FindFirstChild(name)
	if not val then
		val = Instance.new(className)
		val.Name = name
		val.Parent = parent
	end
	return val
end

local gameStateVal = getOrCreateValue(ReplicatedStorage, "GameState", "StringValue")
local gameTimerVal = getOrCreateValue(ReplicatedStorage, "GameTimer", "IntValue")
local batteriesCollectedVal = getOrCreateValue(ReplicatedStorage, "BatteriesCollected", "IntValue")

-- Setup Game Events
local function createRemoteEvent(name)
	local ev = eventsFolder:FindFirstChild(name)
	if not ev then
		ev = Instance.new("RemoteEvent")
		ev.Name = name
		ev.Parent = eventsFolder
	end
	return ev
end

local updateMessageEvent = createRemoteEvent("UpdateSystemMessage")

local function broadcastMessage(text, color)
	updateMessageEvent:FireAllClients(text, color or Color3.fromRGB(255, 255, 255))
	print("[ToyStory Game Manager]", text)
end

-- ========================================
-- DYNAMIC MAP CONSTRUCTION
-- ========================================
local function createDynamicMap()
	broadcastMessage("Constructing play area...", Color3.fromRGB(255, 200, 50))

	-- 1. Lobby Platform (High altitude safe zone)
	lobbyPlatform = Instance.new("Part")
	lobbyPlatform.Name = "GameLobbyPlatform"
	lobbyPlatform.Size = Vector3.new(50, 2, 50)
	lobbyPlatform.Position = Vector3.new(0, 100, 0)
	lobbyPlatform.Material = Enum.Material.Concrete
	lobbyPlatform.Color = Color3.fromRGB(50, 50, 60)
	lobbyPlatform.Anchored = true
	lobbyPlatform.Parent = workspace

	-- SpawnLocation in Lobby
	local spawnLocation = Instance.new("SpawnLocation")
	spawnLocation.Name = "LobbySpawn"
	spawnLocation.Size = Vector3.new(6, 1, 6)
	spawnLocation.Position = Vector3.new(0, 101, 0)
	spawnLocation.Duration = 0
	spawnLocation.Enabled = true
	spawnLocation.Parent = lobbyPlatform

	-- 2. Hunter Closet (Closet where Sid spawns and gets locked during hiding)
	hunterCloset = Instance.new("Part")
	hunterCloset.Name = "HunterCloset"
	hunterCloset.Size = Vector3.new(20, 40, 20)
	hunterCloset.Position = Vector3.new(80, 20, 80)
	hunterCloset.Material = Enum.Material.WoodPlanks
	hunterCloset.Color = Color3.fromRGB(80, 50, 30)
	hunterCloset.Transparency = 0.5
	hunterCloset.CanCollide = false
	hunterCloset.Anchored = true
	hunterCloset.Parent = workspace

	-- Closet SpawnLocation
	local closetSpawn = Instance.new("SpawnLocation")
	closetSpawn.Name = "ClosetSpawn"
	closetSpawn.Size = Vector3.new(6, 1, 6)
	closetSpawn.Position = Vector3.new(80, 2, 80)
	closetSpawn.Duration = 0
	closetSpawn.Enabled = false
	closetSpawn.Parent = workspace

	-- Closet Door/Barrier (blocks hunter)
	closetBarrier = Instance.new("Part")
	closetBarrier.Name = "ClosetBarrier"
	closetBarrier.Size = Vector3.new(22, 40, 1)
	closetBarrier.Position = Vector3.new(80, 20, 70)
	closetBarrier.Material = Enum.Material.ForceField
	closetBarrier.Color = Color3.fromRGB(255, 50, 50)
	closetBarrier.Anchored = true
	closetBarrier.CanCollide = true
	closetBarrier.Parent = workspace

	-- 3. Rescue Cage (locked toys are sent here)
	rescueCage = Instance.new("Part")
	rescueCage.Name = "RescueCage"
	rescueCage.Size = Vector3.new(16, 12, 16)
	rescueCage.Position = Vector3.new(0, 6, 40)
	rescueCage.Material = Enum.Material.Metal
	rescueCage.Color = Color3.fromRGB(40, 40, 40)
	rescueCage.Transparency = 0.7
	rescueCage.CanCollide = true
	rescueCage.Anchored = true
	rescueCage.Parent = workspace

	-- Rescue Trigger Prompt
	local rescuePrompt = Instance.new("ProximityPrompt")
	rescuePrompt.Name = "RescuePrompt"
	rescuePrompt.ObjectText = "Rescue Captured Toys"
	rescuePrompt.ActionText = "Hold to Rescue"
	rescuePrompt.HoldDuration = 4.0
	rescuePrompt.Range = 10
	rescuePrompt.RequiresLineOfSight = false
	rescuePrompt.Parent = rescueCage

	rescuePrompt.Triggered:Connect(function(player)
		-- Free all players inside the cage
		local rescuedCount = 0
		for _, target in Players:GetPlayers() do
			local char = target.Character
			if char and char:GetAttribute("IsCustomCharacter") and char:GetAttribute("CharacterName") ~= "Sid" then
				local dist = (char:GetPivot().Position - rescueCage.Position).Magnitude
				if dist < 15 then
					-- Teleport out of cage
					char:PivotTo(CFrame.new(0, 3, 20))
					char:SetAttribute("Captured", false)
					
					-- Restore speed and jump power from config
					local targetName = char:GetAttribute("CharacterName")
					local targetConfig = CharacterConfig[targetName]
					local hum = char:FindFirstChildOfClass("Humanoid")
					if hum then
						hum.WalkSpeed = targetConfig and targetConfig.WalkSpeed or 8
						hum.JumpPower = 50
					end

					rescuedCount = rescuedCount + 1
				end
			end
		end
		if rescuedCount > 0 then
			broadcastMessage(player.Name .. " rescued " .. rescuedCount .. " toys from the cage!", Color3.fromRGB(50, 255, 100))
		end
	end)

	-- Connect BindableEvent for ending round from other scripts
	local endRoundBindable = eventsFolder:FindFirstChild("EndRoundBindable")
	if not endRoundBindable then
		endRoundBindable = Instance.new("BindableEvent")
		endRoundBindable.Name = "EndRoundBindable"
		endRoundBindable.Parent = eventsFolder
	end
	endRoundBindable.Event:Connect(endRound)

	-- 4. Radio Generator (Objective Hub)
	radioGenerator = Instance.new("Part")
	radioGenerator.Name = "RadioGenerator"
	radioGenerator.Size = Vector3.new(8, 8, 8)
	radioGenerator.Position = Vector3.new(0, 4, -40)
	radioGenerator.Material = Enum.Material.Rust
	radioGenerator.Color = Color3.fromRGB(150, 75, 50)
	radioGenerator.Anchored = true
	radioGenerator.Parent = workspace

	local genPrompt = Instance.new("ProximityPrompt")
	genPrompt.Name = "GeneratorPrompt"
	genPrompt.ObjectText = "Radio Transmitter"
	genPrompt.ActionText = "Insert Battery"
	genPrompt.HoldDuration = 1.0
	genPrompt.Range = 8
	genPrompt.Parent = radioGenerator

	genPrompt.Triggered:Connect(function(player)
		local carried = player:GetAttribute("CarryingBattery") or false
		if carried then
			player:SetAttribute("CarryingBattery", false)
			batteryCount = batteryCount + 1
			batteriesCollectedVal.Value = batteryCount
			broadcastMessage(player.Name .. " deposited a battery! (" .. batteryCount .. "/" .. requiredBatteries .. ")", Color3.fromRGB(100, 200, 255))
			
			-- Play spark sound
			local sound = Instance.new("Sound")
			sound.SoundId = "rbxassetid://130113322"
			sound.Volume = 0.75
			sound.Parent = radioGenerator
			sound:Play()
			Debris:AddItem(sound, 3)

			-- Check if escape unlocked
			if batteryCount >= requiredBatteries then
				unlockEscape()
			end
		else
			-- Notify player they need a battery
			local notify = eventsFolder:FindFirstChild("UpdateSystemMessage")
			if notify then
				notify:FireClient(player, "You must find a Battery first!", Color3.fromRGB(255, 100, 100))
			end
		end
	end)

	-- 5. Escape Zone (Initially locked / invisible)
	escapeZone = Instance.new("Part")
	escapeZone.Name = "EscapeZone"
	escapeZone.Shape = Enum.PartType.Cylinder
	escapeZone.Size = Vector3.new(1, 15, 15)
	escapeZone.Position = Vector3.new(0, 0.5, -60)
	escapeZone.Orientation = Vector3.new(0, 0, 90)
	escapeZone.Material = Enum.Material.Neon
	escapeZone.Color = Color3.fromRGB(0, 255, 0)
	escapeZone.Transparency = 0.8
	escapeZone.CanCollide = false
	escapeZone.Anchored = true
	escapeZone.Parent = workspace

	local escapePrompt = Instance.new("ProximityPrompt")
	escapePrompt.Name = "EscapePrompt"
	escapePrompt.ObjectText = "Escape Vehicle"
	escapePrompt.ActionText = "Escape!"
	escapePrompt.HoldDuration = 1.0
	escapePrompt.Range = 10
	escapePrompt.Enabled = false
	escapePrompt.Parent = escapeZone

	escapePrompt.Triggered:Connect(function(player)
		if gameState == "Escape" then
			local char = player.Character
			if char and char:GetAttribute("IsCustomCharacter") and char:GetAttribute("CharacterName") ~= "Sid" then
				-- Teleport to lobby (escaped!)
				player:SetAttribute("Escaped", true)
				char:PivotTo(CFrame.new(0, 102, 0))
				broadcastMessage(player.Name .. " escaped successfully!", Color3.fromRGB(0, 255, 100))
				checkWinConditions()
			end
		end
	end)
end

-- Spawn Battery Objectives
local function spawnBatteries()
	-- Clear old
	for _, bat in activeBatteries do
		if bat then bat:Destroy() end
	end
	activeBatteries = {}
	batteryCount = 0
	batteriesCollectedVal.Value = 0

	local spawns = {
		Vector3.new(-40, 2, 20),
		Vector3.new(40, 2, -20),
		Vector3.new(-25, 2, -30),
		Vector3.new(30, 2, 40),
		Vector3.new(10, 2, -10)
	}

	-- Shuffle spawns
	local rng = Random.new()
	for i = #spawns, 2, -1 do
		local j = rng:NextInteger(1, i)
		spawns[i], spawns[j] = spawns[j], spawns[i]
	end

	-- Create 3 batteries
	for i = 1, requiredBatteries do
		local pos = spawns[i]
		local bat = Instance.new("Part")
		bat.Name = "BatteryObjective_" .. i
		bat.Size = Vector3.new(2, 4, 2)
		bat.Position = pos
		bat.Material = Enum.Material.Neon
		bat.Color = Color3.fromRGB(0, 200, 255)
		bat.Anchored = true
		bat.Parent = workspace

		-- Spark light
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(0, 200, 255)
		light.Range = 12
		light.Parent = bat

		local prompt = Instance.new("ProximityPrompt")
		prompt.ObjectText = "Power Battery"
		prompt.ActionText = "Pick Up"
		prompt.HoldDuration = 1.0
		prompt.Range = 6
		prompt.Parent = bat

		prompt.Triggered:Connect(function(player)
			if player:GetAttribute("CarryingBattery") then
				return
			end
			player:SetAttribute("CarryingBattery", true)
			bat:Destroy()
			broadcastMessage(player.Name .. " picked up a battery!", Color3.fromRGB(0, 255, 255))
		end)

		table.insert(activeBatteries, bat)
	end
end

function unlockEscape()
	gameState = "Escape"
	gameStateVal.Value = "Escape"
	local prompt = escapeZone:FindFirstChild("EscapePrompt")
	if prompt then
		prompt.Enabled = true
	end
	broadcastMessage("THE ESCAPE ROUTE IS UNLOCKED! Run to the glowing green helicopter zone!", Color3.fromRGB(0, 255, 0))
	
	-- Play sirens
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://9125696011"
	sound.Volume = 0.5
	sound.Looped = true
	sound.Parent = escapeZone
	sound:Play()
end

-- ========================================
-- GAME CYCLE & STATES
-- ========================================
local function cleanupRound()
	for _, bat in activeBatteries do
		if bat then bat:Destroy() end
	end
	activeBatteries = {}

	for _, player in Players:GetPlayers() do
		player:SetAttribute("CarryingBattery", false)
		player:SetAttribute("Escaped", false)
		player:SetAttribute("SidMistakes", 0)
	end

	local prompt = escapeZone:FindFirstChild("EscapePrompt")
	if prompt then prompt.Enabled = false end

	local siren = escapeZone:FindFirstChildOfClass("Sound")
	if siren then siren:Destroy() end

	closetBarrier.CanCollide = true
	closetBarrier.Transparency = 0
end

local function teleportAllToLobby()
	for _, player in Players:GetPlayers() do
		local char = player.Character
		if char then
			char:PivotTo(CFrame.new(0, 102, 0))
		end
	end
end

function checkWinConditions()
	if gameState ~= "Hunt" and gameState ~= "Escape" then return end

	local toysLeft = 0
	local toysEscaped = 0

	for _, player in Players:GetPlayers() do
		local char = player.Character
		if char and char:GetAttribute("IsCustomCharacter") then
			local name = char:GetAttribute("CharacterName")
			if name ~= "Sid" then
				if player:GetAttribute("Escaped") then
					toysEscaped = toysEscaped + 1
				else
					toysLeft = toysLeft + 1
				end
			end
		end
	end

	-- If all toys escaped
	if toysLeft == 0 and toysEscaped > 0 then
		endRound("ToysWin", "All toys escaped! Toys Victory!")
		return
	end

	-- If no toys left (all captured / broken)
	local cagedToys = 0
	for _, player in Players:GetPlayers() do
		local char = player.Character
		if char and char:GetAttribute("IsCustomCharacter") and char:GetAttribute("CharacterName") ~= "Sid" then
			local dist = (char:GetPivot().Position - rescueCage.Position).Magnitude
			if dist < 15 then
				cagedToys = cagedToys + 1
			end
		end
	end

	if cagedToys > 0 and cagedToys == (toysLeft + cagedToys) then
		endRound("SidWins", "Sid captured all toys! Hunter Victory!")
	end
end

function endRound(winner, reason)
	gameState = "RoundOver"
	gameStateVal.Value = "RoundOver"
	broadcastMessage(reason, Color3.fromRGB(255, 50, 50))

	-- Play win sound
	local sound = Instance.new("Sound")
	sound.SoundId = winner == "ToysWin" and "rbxassetid://9120150937" or "rbxassetid://9125696011"
	sound.Volume = 0.8
	sound.Parent = workspace
	sound:Play()
	Debris:AddItem(sound, 5)

	task.wait(10)
	teleportAllToLobby()
	cleanupRound()
	gameState = "Intermission"
	gameStateVal.Value = "Intermission"
end

-- Main Loop Thread
task.spawn(function()
	createDynamicMap()

	-- Get character select remote
	local selectCharacterEvent = eventsFolder:WaitForChild("SelectCharacter")

	while true do
		task.wait(1)

		if gameState == "Intermission" then
			roundTimer = INTERMISSION_DURATION
			while roundTimer > 0 and gameState == "Intermission" do
				gameTimerVal.Value = roundTimer
				roundTimer = roundTimer - 1
				task.wait(1)
			end

			-- Start Hiding Phase
			gameState = "Hiding"
			gameStateVal.Value = "Hiding"
			roundTimer = HIDING_DURATION
			spawnBatteries()
			broadcastMessage("HIDING PHASE STARTED! Toys, go hide and find batteries. Sid is locked in the closet!", Color3.fromRGB(50, 150, 255))

			-- Spawn players in play area
			local activePlayers = Players:GetPlayers()
			if #activePlayers > 0 then
				local sidPlayer = activePlayers[math.random(1, #activePlayers)]
				
				-- Assign characters
				for _, player in activePlayers do
					local charName = "Woody"
					if player == sidPlayer then
						charName = "Sid"
					else
						-- Distribute toy types
						local toyTypes = {"Woody", "Buzz", "Slinky", "PotatoHead", "Rex"}
						charName = toyTypes[math.random(1, #toyTypes)]
					end

					-- Set Selection and trigger swap character
					selectCharacterEvent:FireClient(player, charName) -- Sync client selection UI
					
					task.wait(0.2)
					local newChar = player.Character
					if newChar then
						if charName == "Sid" then
							newChar:PivotTo(CFrame.new(80, 3, 80))
							local hum = newChar:FindFirstChildOfClass("Humanoid")
							if hum then
								hum.WalkSpeed = 0
							end
						else
							newChar:PivotTo(CFrame.new(math.random(-30, 30), 3, math.random(-30, 30)))
						end
					end
				end
			end

		elseif gameState == "Hiding" then
			while roundTimer > 0 and gameState == "Hiding" do
				gameTimerVal.Value = roundTimer
				roundTimer = roundTimer - 1
				task.wait(1)
			end

			-- Start Hunt Phase
			gameState = "Hunt"
			gameStateVal.Value = "Hunt"
			roundTimer = ROUND_DURATION
			broadcastMessage("SID HAS BEEN RELEASED! HIDE AND DON'T MOVE!", Color3.fromRGB(255, 50, 50))

			-- Open closet door
			closetBarrier.CanCollide = false
			closetBarrier.Transparency = 1

			-- Unlock Sid's movement
			for _, player in Players:GetPlayers() do
				local char = player.Character
				if char and char:GetAttribute("CharacterName") == "Sid" then
					local hum = char:FindFirstChildOfClass("Humanoid")
					if hum then
						hum.WalkSpeed = 16
					end
				end
			end

		elseif gameState == "Hunt" or gameState == "Escape" then
			if roundTimer > 0 then
				gameTimerVal.Value = roundTimer
				roundTimer = roundTimer - 1
				checkWinConditions()
			else
				-- Time ran out: Toys win by survival!
				endRound("ToysWin", "Time is up! Toys survived and won the round!")
			end
		end
	end
end)
