--[[
	ToyStory - ObjectiveManager (ModuleScript)
	Uses 9 pre-placed "Battery" objects in workspace.
	Each round, randomly picks 5 to activate.
	Toys collect batteries via ProximityPrompt to win.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Utils = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Utils"))

local ObjectiveManager = {}

local batteriesVal = ReplicatedStorage:WaitForChild("GameState"):WaitForChild("TimeRemaining").Parent:WaitForChild("BatteriesCollected")

local BATTERIES_NEEDED = 5
local TOTAL_SPAWN_POINTS = 9

-- All Battery objects found in workspace (stored at init)
local allBatteryObjects = {} -- Array of Battery Parts/Models
local activeBatteries = {} -- Array of currently active Battery objects this round
local batteryPrompts = {} -- Battery -> ProximityPrompt
local batteryConnections = {} -- Battery -> RBXScriptConnection

local activeEscapeZone = nil
local escapeTouchedConnection = nil
local ESCAPE_ZONE_POSITION = Vector3.new(0, 1, -55) -- Escape boundary

--- Finds all Battery objects in workspace and caches them.
local function discoverBatteries()
	allBatteryObjects = {}
	for _, obj in workspace:GetChildren() do
		if obj.Name == "Battery" then
			table.insert(allBatteryObjects, obj)
		end
	end

	-- Also search recursively one level deeper (in case batteries are inside folders/models)
	for _, folder in workspace:GetChildren() do
		if folder:IsA("Folder") or folder:IsA("Model") then
			for _, obj in folder:GetChildren() do
				if obj.Name == "Battery" then
					table.insert(allBatteryObjects, obj)
				end
			end
		end
	end

	-- Deduplicate (in case a Battery was found at both levels)
	local seen = {}
	local unique = {}
	for _, obj in allBatteryObjects do
		if not seen[obj] then
			seen[obj] = true
			table.insert(unique, obj)
		end
	end
	allBatteryObjects = unique

	print("[ToyStory Objectives] Discovered", #allBatteryObjects, "Battery objects in workspace.")
end

--- Hides a battery (makes it invisible and non-interactable).
local function hideBattery(battery)
	if battery:IsA("BasePart") then
		battery.Transparency = 1
		battery.CanCollide = false
		-- Hide any children (lights, particles, etc.)
		for _, desc in battery:GetDescendants() do
			if desc:IsA("BasePart") then
				desc.Transparency = 1
				desc.CanCollide = false
			elseif desc:IsA("PointLight") or desc:IsA("SpotLight") or desc:IsA("SurfaceLight") then
				desc.Enabled = false
			elseif desc:IsA("ParticleEmitter") or desc:IsA("BillboardGui") then
				desc.Enabled = false
			elseif desc:IsA("Decal") or desc:IsA("Texture") then
				desc.Transparency = 1
			end
		end
	elseif battery:IsA("Model") then
		for _, desc in battery:GetDescendants() do
			if desc:IsA("BasePart") then
				desc.Transparency = 1
				desc.CanCollide = false
			elseif desc:IsA("PointLight") or desc:IsA("SpotLight") or desc:IsA("SurfaceLight") then
				desc.Enabled = false
			elseif desc:IsA("ParticleEmitter") or desc:IsA("BillboardGui") then
				desc.Enabled = false
			elseif desc:IsA("Decal") or desc:IsA("Texture") then
				desc.Transparency = 1
			end
		end
	end
end

--- Shows a battery (restores visibility).
local function showBattery(battery)
	if battery:IsA("BasePart") then
		battery.Transparency = 0
		battery.CanCollide = true
		for _, desc in battery:GetDescendants() do
			if desc:IsA("BasePart") then
				desc.Transparency = 0
				desc.CanCollide = true
			elseif desc:IsA("PointLight") or desc:IsA("SpotLight") or desc:IsA("SurfaceLight") then
				desc.Enabled = true
			elseif desc:IsA("ParticleEmitter") or desc:IsA("BillboardGui") then
				desc.Enabled = true
			elseif desc:IsA("Decal") or desc:IsA("Texture") then
				desc.Transparency = 0
			end
		end
	elseif battery:IsA("Model") then
		for _, desc in battery:GetDescendants() do
			if desc:IsA("BasePart") then
				desc.Transparency = 0
				desc.CanCollide = true
			elseif desc:IsA("PointLight") or desc:IsA("SpotLight") or desc:IsA("SurfaceLight") then
				desc.Enabled = true
			elseif desc:IsA("ParticleEmitter") or desc:IsA("BillboardGui") then
				desc.Enabled = true
			elseif desc:IsA("Decal") or desc:IsA("Texture") then
				desc.Transparency = 0
			end
		end
	end
end

--- Gets the part to attach a ProximityPrompt to.
local function getPromptParent(battery): BasePart?
	if battery:IsA("BasePart") then
		return battery
	elseif battery:IsA("Model") then
		return battery.PrimaryPart or battery:FindFirstChildWhichIsA("BasePart")
	end
	return nil
end

--- Shuffle an array in-place (Fisher-Yates).
local function shuffle(arr)
	local rng = Random.new()
	for i = #arr, 2, -1 do
		local j = rng:NextInteger(1, i)
		arr[i], arr[j] = arr[j], arr[i]
	end
end

function ObjectiveManager.InitializeObjectives()
	ObjectiveManager.ClearObjectives()
	batteriesVal.Value = 0

	-- Discover all Battery objects in workspace
	discoverBatteries()

	if #allBatteryObjects < BATTERIES_NEEDED then
		warn("[ToyStory Objectives] Not enough Battery objects in workspace! Found:", #allBatteryObjects, "Need:", BATTERIES_NEEDED)
	end

	-- Hide all batteries first
	for _, battery in allBatteryObjects do
		hideBattery(battery)
	end

	-- Randomly pick 5 batteries to activate
	local indices = {}
	for i = 1, #allBatteryObjects do
		table.insert(indices, i)
	end
	shuffle(indices)

	local countToActivate = math.min(BATTERIES_NEEDED, #allBatteryObjects)
	activeBatteries = {}

	for i = 1, countToActivate do
		local battery = allBatteryObjects[indices[i]]
		table.insert(activeBatteries, battery)

		-- Show this battery
		showBattery(battery)

		-- Create ProximityPrompt for collecting
		local promptParent = getPromptParent(battery)
		if promptParent then
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "BatteryPrompt"
			prompt.ObjectText = "Battery"
			prompt.ActionText = "Collect"
			prompt.HoldDuration = 0.5
			prompt.MaxActivationDistance = 8
			prompt.RequiresLineOfSight = false
			prompt.Parent = promptParent

			batteryPrompts[battery] = prompt

			local conn = prompt.Triggered:Connect(function(player)
				local char = player.Character
				if not char or not char:GetAttribute("IsCustomCharacter") then
					return
				end

				local charName = char:GetAttribute("CharacterName")
				local isCaptured = char:GetAttribute("IsCaptured") or false

				-- Only non-Sid, non-captured toys can collect batteries
				if charName == "Sid" or isCaptured then
					return
				end

				-- Collect this battery
				prompt:Destroy()
				batteryPrompts[battery] = nil

				if batteryConnections[battery] then
					batteryConnections[battery]:Disconnect()
					batteryConnections[battery] = nil
				end

				-- Hide the battery
				hideBattery(battery)

				-- Increment counter
				batteriesVal.Value = batteriesVal.Value + 1
				print("[ToyStory Objectives] Battery collected by", player.Name, "- Total:", batteriesVal.Value, "/", BATTERIES_NEEDED)

				-- Play collect sound
				local head = char:FindFirstChild("Head")
				if head then
					Utils.PlayOneShot(head, "rbxassetid://9114223126", 0.6)
				end

				-- Check if enough batteries collected
				if batteriesVal.Value >= BATTERIES_NEEDED then
					local GameLoopManager = require(script.Parent.GameLoopManager)
					GameLoopManager.EndGame("Toys")
				end
			end)

			batteryConnections[battery] = conn
		end
	end

	print("[ToyStory Objectives] Activated", countToActivate, "of", #allBatteryObjects, "batteries for this round.")
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
	-- Clean up prompts and connections
	for battery, prompt in pairs(batteryPrompts) do
		if prompt and prompt.Parent then
			prompt:Destroy()
		end
	end
	batteryPrompts = {}

	for battery, conn in pairs(batteryConnections) do
		if conn then
			conn:Disconnect()
		end
	end
	batteryConnections = {}

	-- Hide all batteries at end of round (they'll be re-shown at next InitializeObjectives)
	for _, battery in allBatteryObjects do
		hideBattery(battery)
	end

	activeBatteries = {}

	if activeEscapeZone and activeEscapeZone.Parent then
		activeEscapeZone:Destroy()
		activeEscapeZone = nil
	end

	if escapeTouchedConnection then
		escapeTouchedConnection:Disconnect()
		escapeTouchedConnection = nil
	end
end

return ObjectiveManager
