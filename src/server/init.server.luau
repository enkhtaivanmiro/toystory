--[[
	ToyStory - Server Entry Point
	Orchestrates initialization of all server subsystems.
	Handles character selection, spawning, and player lifecycle.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PhysicsService = game:GetService("PhysicsService")

-- Setup Collision Groups safely
pcall(function() PhysicsService:RegisterCollisionGroup("Hunters") end)
pcall(function() PhysicsService:RegisterCollisionGroup("Toys") end)
pcall(function() PhysicsService:RegisterCollisionGroup("CapturedToys") end)

pcall(function() PhysicsService:CollisionGroupSetCollidable("Hunters", "CapturedToys", false) end)
pcall(function() PhysicsService:CollisionGroupSetCollidable("Toys", "CapturedToys", false) end)
pcall(function() PhysicsService:CollisionGroupSetCollidable("CapturedToys", "CapturedToys", false) end)

-- Shared modules
local Utils = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Utils"))

-- Server modules
local CharacterRigger = require(script:WaitForChild("CharacterRigger"))
local GameLoopManager = require(script:WaitForChild("GameLoopManager"))
local NpcSpawner = require(script:WaitForChild("NpcSpawner"))
local ObjectiveManager = require(script:WaitForChild("ObjectiveManager"))
local RescueManager = require(script:WaitForChild("RescueManager"))
local EventSetup = require(script:WaitForChild("EventSetup"))

-- Initialize folders
local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
if not eventsFolder then
	eventsFolder = Instance.new("Folder")
	eventsFolder.Name = "Events"
	eventsFolder.Parent = ReplicatedStorage
end

local charactersFolder = ReplicatedStorage:FindFirstChild("Characters")
if not charactersFolder then
	charactersFolder = Instance.new("Folder")
	charactersFolder.Name = "Characters"
	charactersFolder.Parent = ReplicatedStorage
end

-- Initialize RemoteEvent for character selection
local selectCharacterEvent = Utils.GetOrCreateRemoteEvent(eventsFolder, "SelectCharacter")

-- Track player selections and swap locks
local playerSelections: { [Player]: string } = {}
local swapping: { [Player]: boolean } = {}

--- Find a character template model by name across known locations.
local function findTemplate(characterName: string): Model?
	-- 1. Characters folder
	local template = charactersFolder:FindFirstChild(characterName)
	if not template and characterName == "PotatoHead" then
		template = charactersFolder:FindFirstChild("Model")
	end

	-- 2. ReplicatedStorage directly
	if not template then
		template = ReplicatedStorage:FindFirstChild(characterName)
		if not template and characterName == "PotatoHead" then
			template = ReplicatedStorage:FindFirstChild("Model")
		end
	end

	-- 3. Workspace fallback
	if not template then
		template = workspace:FindFirstChild(characterName) or workspace:FindFirstChild(characterName:lower())
	end

	return template
end

--- Swap current character with a custom character.
local function swapCharacter(player: Player, currentCharacter: Model, characterName: string)
	if swapping[player] then
		return
	end
	swapping[player] = true

	local template = findTemplate(characterName)
	if not template then
		warn("[ToyStory Server] Template model not found for:", characterName)
		swapping[player] = nil
		return
	end

	-- Get spawn position
	local spawnCFrame = currentCharacter:GetPivot()

	-- Analyze the old character's height so the custom one matches it exactly
	local minY, maxY = Utils.GetModelBoundsY(currentCharacter)
	local defaultHeight = math.max(5, maxY - minY)

	-- Get Animate LocalScript
	local animateSource = ReplicatedStorage:FindFirstChild("Shared")
		and ReplicatedStorage.Shared:FindFirstChild("CharacterAnimate")

	-- Build new custom character model
	local customCharacter = CharacterRigger.Build(template, characterName, defaultHeight)
	if not customCharacter then
		swapping[player] = nil
		return
	end

	customCharacter.Name = player.Name

	-- Setup Animate script
	if animateSource then
		local animClone = animateSource:Clone()
		animClone.Name = "Animate"
		animClone.Disabled = true
		animClone.Parent = customCharacter
	end

	customCharacter:PivotTo(spawnCFrame)

	-- Destroy old character
	currentCharacter:Destroy()

	-- Parent and set character
	customCharacter.Parent = workspace
	player.Character = customCharacter

	-- Assign spawned parts to their respective collision groups
	local collisionGroupName = (characterName == "Sid") and "Hunters" or "Toys"
	for _, part in customCharacter:GetDescendants() do
		if part:IsA("BasePart") then
			part.CollisionGroup = collisionGroupName
		end
	end

	-- Enable Animate script
	task.defer(function()
		local animScript = customCharacter:FindFirstChild("Animate")
		if animScript then
			animScript.Disabled = false
		end
	end)

	swapping[player] = nil
	print("[ToyStory Server]", player.Name, "spawned as custom character:", characterName, "with height:", defaultHeight)
end

-- Listen to selection request
selectCharacterEvent.OnServerEvent:Connect(function(player, characterName)
	playerSelections[player] = characterName
	if player.Character then
		swapCharacter(player, player.Character, characterName)
	end
end)

-- Handle joins and respawns
local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character)
		task.wait(0.5)
		local selected = playerSelections[player]
		if selected and player.Character == character and not character:GetAttribute("IsCustomCharacter") then
			swapCharacter(player, character, selected)
		end
	end)
end

Players.PlayerRemoving:Connect(function(player)
	playerSelections[player] = nil
	swapping[player] = nil
end)

for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end
Players.PlayerAdded:Connect(onPlayerAdded)

-- Expose build callback for NPC spawner
NpcSpawner.BuildCallback = CharacterRigger.Build

-- Initialize event handlers
EventSetup.Init(eventsFolder, GameLoopManager, RescueManager)

-- Initialize game loop (connects all subsystems)
GameLoopManager.Init(NpcSpawner, ObjectiveManager, RescueManager)

print("[ToyStory Server] All systems initialized!")
