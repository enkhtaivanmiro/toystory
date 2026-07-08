--[[
	ToyStory - NpcSpawner (ModuleScript)
	Spawns static NPC toys across the map to act as camouflage.
	Applies randomized lifeless poses and registers them for Sid's mistake system.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CharacterConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CharacterConfig"))

local NpcSpawner = {}
local spawnedNPCs = {}

-- Spawning boundary box (adjusts dynamically by raycasting down to find walkable surfaces)
local SPAWN_BOUNDS_X = {-60, 60}
local SPAWN_BOUNDS_Z = {-60, 60}
local SPAWN_HEIGHT_START = 40

-- List of toy characters to use as NPCs
local TOY_CHARACTERS = {"Woody", "Buzz", "Slinky", "PotatoHead", "Rex"}

local function getModelExtents(model: Model)
	local minY = math.huge
	local maxY = -math.huge
	local minX = math.huge
	local maxX = -math.huge
	local minZ = math.huge
	local maxZ = -math.huge

	for _, desc in model:GetDescendants() do
		if desc:IsA("BasePart") then
			local pos = desc.CFrame.Position
			local half = desc.Size / 2
			minY = math.min(minY, pos.Y - half.Y)
			maxY = math.max(maxY, pos.Y + half.Y)
			minX = math.min(minX, pos.X - half.X)
			maxX = math.max(maxX, pos.X + half.X)
			minZ = math.min(minZ, pos.Z - half.Z)
			maxZ = math.max(maxZ, pos.Z + half.Z)
		end
	end

	return Vector3.new(maxX - minX, maxY - minY, maxZ - minZ)
end

function NpcSpawner.SpawnNPCs(buildCallback)
	NpcSpawner.ClearNPCs()

	local npcFolder = workspace:FindFirstChild("NPCs")
	if not npcFolder then
		npcFolder = Instance.new("Folder")
		npcFolder.Name = "NPCs"
		npcFolder.Parent = workspace
	end

	local rng = Random.new()
	local spawnCount = rng:NextInteger(15, 22)
	print("[ToyStory NpcSpawner] Spawning", spawnCount, "NPC toys...")

	for i = 1, spawnCount do
		local charName = TOY_CHARACTERS[rng:NextInteger(1, #TOY_CHARACTERS)]
		local config = CharacterConfig[charName]
		if not config then continue end

		-- Find template
		local charactersFolder = ReplicatedStorage:FindFirstChild("Characters")
		local template = charactersFolder and charactersFolder:FindFirstChild(charName)
		if not template and charName == "PotatoHead" then
			template = charactersFolder and charactersFolder:FindFirstChild("Model")
		end
		if not template then
			template = ReplicatedStorage:FindFirstChild(charName)
			if not template and charName == "PotatoHead" then
				template = ReplicatedStorage:FindFirstChild("Model")
			end
		end

		if not template then
			warn("[ToyStory NpcSpawner] Template not found for NPC:", charName)
			continue
		end

		-- Choose random coordinate
		local rx = rng:NextNumber(SPAWN_BOUNDS_X[1], SPAWN_BOUNDS_X[2])
		local rz = rng:NextNumber(SPAWN_BOUNDS_Z[1], SPAWN_BOUNDS_Z[2])
		
		-- Raycast down to find ground/shelf
		local rayOrigin = Vector3.new(rx, SPAWN_HEIGHT_START, rz)
		local rayDirection = Vector3.new(0, -60, 0)
		local raycastParams = RaycastParams.new()
		
		local result = workspace:Raycast(rayOrigin, rayDirection, raycastParams)
		if result then
			local spawnPos = result.Position
			local normal = result.Normal

			-- Build character
			local callback = buildCallback or NpcSpawner.BuildCallback
			if not callback then
				warn("[ToyStory NpcSpawner] No build callback defined!")
				continue
			end

			local npcModel = callback(template, charName, config.Height)
			if npcModel then
				npcModel.Name = charName .. "NPC"
				npcModel:SetAttribute("IsNPCToy", true)
				npcModel:SetAttribute("IsCustomCharacter", true)
				npcModel:SetAttribute("IsLayingDown", true)
				
				-- Hide overhead UI if humanoid has one
				local hum = npcModel:FindFirstChildOfClass("Humanoid")
				if hum then
					hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
					hum.HealthDisplayDistance = 0
					hum.NameDisplayDistance = 0
				end

				-- Position NPC
				local root = npcModel.PrimaryPart
				if root then
					-- Random rotation around Y
					local randomAngle = rng:NextNumber(0, math.pi * 2)
					local baseCFrame = CFrame.new(spawnPos) * CFrame.Angles(0, randomAngle, 0)
					
					npcModel:PivotTo(baseCFrame)

					-- Apply lifeless pose CFrame modification on RootJoint
					local rootJoint = root:FindFirstChild("RootJoint")
					if rootJoint and rootJoint:IsA("Motor6D") then
						local extents = getModelExtents(npcModel)
						local pivotToGround = root.Position.Y - (spawnPos.Y)
						
						local selectedPose = rng:NextInteger(1, 4)
						local layDownRotation = CFrame.new()
						local layDownOffsetHeight = 0

						if selectedPose == 1 then
							layDownRotation = CFrame.Angles(math.rad(90), 0, 0)
							layDownOffsetHeight = -(pivotToGround - (extents.Z / 2))
						elseif selectedPose == 2 then
							layDownRotation = CFrame.Angles(math.rad(-90), 0, 0)
							layDownOffsetHeight = -(pivotToGround - (extents.Z / 2))
						elseif selectedPose == 3 then
							layDownRotation = CFrame.Angles(0, 0, math.rad(90))
							layDownOffsetHeight = -(pivotToGround - (extents.X / 2))
						elseif selectedPose == 4 then
							layDownRotation = CFrame.Angles(0, 0, math.rad(-90))
							layDownOffsetHeight = -(pivotToGround - (extents.X / 2))
						end

						local layDownTranslation = CFrame.new(0, layDownOffsetHeight, 0)
						rootJoint.C0 = layDownTranslation * layDownRotation * rootJoint.C0
					end

					-- Anchor all parts to keep NPC fixed and stable
					for _, part in npcModel:GetDescendants() do
						if part:IsA("BasePart") then
							part.Anchored = true
							part.CanCollide = true
						end
					end
				end

				npcModel.Parent = npcFolder
				table.insert(spawnedNPCs, npcModel)
			end
		end
	end
end

function NpcSpawner.ClearNPCs()
	for _, npc in spawnedNPCs do
		if npc and npc.Parent then
			npc:Destroy()
		end
	end
	spawnedNPCs = {}

	local npcFolder = workspace:FindFirstChild("NPCs")
	if npcFolder then
		npcFolder:Destroy()
	end
end

return NpcSpawner
