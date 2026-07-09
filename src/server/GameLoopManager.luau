--[[
	ToyStory - GameLoopManager (ModuleScript)
	Manages the server-side match phases, timer, hunter lock/release,
	and win/loss condition evaluation.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Utils = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Utils"))

local GameLoopManager = {}

-- State variables
GameLoopManager.Phase = "Ended" -- "Prep", "Search", "Escape", "Ended"
GameLoopManager.TimeRemaining = 0
GameLoopManager.ToysEscapedCount = 0

-- Folder for replicating state to clients
local gameStateFolder = ReplicatedStorage:FindFirstChild("GameState")
if not gameStateFolder then
	gameStateFolder = Instance.new("Folder")
	gameStateFolder.Name = "GameState"
	gameStateFolder.Parent = ReplicatedStorage
end

local phaseVal = gameStateFolder:FindFirstChild("MatchPhase") or Instance.new("StringValue")
phaseVal.Name = "MatchPhase"
phaseVal.Value = "Ended"
phaseVal.Parent = gameStateFolder

local timerVal = gameStateFolder:FindFirstChild("TimeRemaining") or Instance.new("IntValue")
timerVal.Name = "TimeRemaining"
timerVal.Value = 0
timerVal.Parent = gameStateFolder

local batteriesVal = gameStateFolder:FindFirstChild("BatteriesCollected") or Instance.new("IntValue")
batteriesVal.Name = "BatteriesCollected"
batteriesVal.Value = 0
batteriesVal.Parent = gameStateFolder

-- RemoteEvents for UI overlay triggers
local eventsFolder = ReplicatedStorage:WaitForChild("Events")
local gameEndedEvent = Utils.GetOrCreateRemoteEvent(eventsFolder, "GameEnded")

-- Require dependencies (loaded lazily to prevent circular dependencies)
local NpcSpawner
local ObjectiveManager
local RescueManager

local function getAliveToyCount(): number
	local count = 0
	for _, player in Players:GetPlayers() do
		local char = player.Character
		if char and char:GetAttribute("IsCustomCharacter") then
			local name = char:GetAttribute("CharacterName")
			if name ~= "Sid" then
				local isCaptured = char:GetAttribute("IsCaptured") or false
				local humanoid = char:FindFirstChildOfClass("Humanoid")
				if humanoid and humanoid.Health > 0 and not isCaptured then
					count = count + 1
				end
			end
		end
	end
	return count
end

local function getHunterPlayer(): Player?
	for _, player in Players:GetPlayers() do
		local char = player.Character
		if char and char:GetAttribute("CharacterName") == "Sid" then
			return player
		end
	end
	return nil
end

local function lockHunter(lock: boolean)
	local hunterPlayer = getHunterPlayer()
	if not hunterPlayer or not hunterPlayer.Character then
		return
	end

	local char = hunterPlayer.Character
	local root = char:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		root.Anchored = lock
	end

	-- Notify the Hunter client (for black screen or lock message)
	local lockHunterEvent = Utils.GetOrCreateRemoteEvent(eventsFolder, "LockHunter")
	lockHunterEvent:FireClient(hunterPlayer, lock)
end

function GameLoopManager.SetPhase(newPhase: string)
	GameLoopManager.Phase = newPhase
	phaseVal.Value = newPhase
	print("[ToyStory GameLoop] Phase changed to:", newPhase)

	if newPhase == "Prep" then
		-- Lock the Hunter
		lockHunter(true)
		-- Spawn NPCs
		if NpcSpawner then
			NpcSpawner.SpawnNPCs()
		end
		-- Setup Objectives
		if ObjectiveManager then
			ObjectiveManager.InitializeObjectives()
		end
		-- Reset cage/captures
		if RescueManager then
			RescueManager.Reset()
		end
		-- Reset mistake counter on Hunter player
		local hunter = getHunterPlayer()
		if hunter then
			hunter:SetAttribute("SidMistakes", 0)
			hunter:SetAttribute("SidDistorted", false)
		end
		-- Set timer to 20 seconds
		GameLoopManager.TimeRemaining = 20
	elseif newPhase == "Search" then
		-- Release Hunter
		lockHunter(false)
		-- Set timer to 300 seconds (5 mins)
		GameLoopManager.TimeRemaining = 300
	elseif newPhase == "Escape" then
		-- Trigger Escape zone opening
		if ObjectiveManager then
			ObjectiveManager.OpenEscapeZone()
		end
		-- Add 60 seconds final escape time
		GameLoopManager.TimeRemaining = 60
	elseif newPhase == "Ended" then
		-- Lock Hunter
		lockHunter(true)
		-- Clean up NPCs
		if NpcSpawner then
			NpcSpawner.ClearNPCs()
		end
		-- Clean up objectives
		if ObjectiveManager then
			ObjectiveManager.ClearObjectives()
		end
		-- Set timer to 15 seconds cooldown
		GameLoopManager.TimeRemaining = 15
	end
end

function GameLoopManager.EndGame(winner: string)
	GameLoopManager.SetPhase("Ended")
	
	-- Send GameEnded event to all players
	gameEndedEvent:FireAllClients(winner)
	print("[ToyStory GameLoop] Game ended! Winner:", winner)
end

function GameLoopManager.Update()
	if GameLoopManager.Phase == "Ended" then
		if GameLoopManager.TimeRemaining <= 0 then
			-- Start a new game if players are present
			if #Players:GetPlayers() >= 1 then
				GameLoopManager.SetPhase("Prep")
			else
				GameLoopManager.TimeRemaining = 10 -- keep waiting
			end
		end
		return
	end

	-- Check Victory/Defeat Conditions
	local hunter = getHunterPlayer()
	if hunter then
		local mistakes = hunter:GetAttribute("SidMistakes") or 0
		if mistakes >= 3 then
			GameLoopManager.EndGame("Toys")
			return
		end
	end

	-- Check if all toys are captured/eliminated
	local aliveToys = getAliveToyCount()
	if aliveToys == 0 and GameLoopManager.Phase ~= "Prep" then
		GameLoopManager.EndGame("Hunter")
		return
	end

	-- Timer count down
	if GameLoopManager.TimeRemaining > 0 then
		GameLoopManager.TimeRemaining = GameLoopManager.TimeRemaining - 1
		timerVal.Value = GameLoopManager.TimeRemaining
	else
		-- Timer ran out!
		if GameLoopManager.Phase == "Prep" then
			GameLoopManager.SetPhase("Search")
		elseif GameLoopManager.Phase == "Search" or GameLoopManager.Phase == "Escape" then
			-- Hunter wins if time runs out and toys didn't escape
			GameLoopManager.EndGame("Hunter")
		end
	end
end

function GameLoopManager.Init(spawnerModule, objModule, rescueModule)
	NpcSpawner = spawnerModule
	ObjectiveManager = objModule
	RescueManager = rescueModule

	-- Run update loop every 1 second
	task.spawn(function()
		while true do
			task.wait(1)
			pcall(function()
				GameLoopManager.Update()
			end)
		end
	end)

	-- Handle player joins/leaves mid-match
	Players.PlayerAdded:Connect(function(player)
		-- If game is in progress, make sure Hunter locking applies if they spawn as Sid
		task.wait(2)
		if GameLoopManager.Phase == "Prep" then
			lockHunter(true)
		end
	end)

	-- Start initial wait timer
	GameLoopManager.TimeRemaining = 15
	GameLoopManager.SetPhase("Ended")
	
	print("[ToyStory GameLoop] GameLoopManager Initialized!")
end

return GameLoopManager
