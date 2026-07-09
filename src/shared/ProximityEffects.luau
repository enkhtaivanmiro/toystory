--[[
	ToyStory - ProximityEffects (ModuleScript)
	Handles toy-side proximity audio/visual effects that intensify
	as the Hunter (Sid) gets closer: heartbeat sound, footstep screen shake,
	landing noise alerts, and surface-based footstep volume.
]]

local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")

local ProximityEffects = {}

--- Initialize proximity effects for a toy character (non-Sid).
--- Starts background loops for heartbeat volume, screen shake, landing noise,
--- and dynamic surface-based footstep volume.
function ProximityEffects.Init(character: Model, rootPart: BasePart, humanoid: Humanoid, characterName: string)
	local camera = workspace.CurrentCamera

	-- ========================================
	-- Heartbeat Sound Loop
	-- ========================================
	local heartbeatSound = Instance.new("Sound")
	heartbeatSound.Name = "HeartbeatLoop"
	heartbeatSound.SoundId = "rbxassetid://9114227181" -- magical suspense/heartbeat vibe
	heartbeatSound.Volume = 0
	heartbeatSound.Looped = true
	heartbeatSound.Parent = rootPart
	heartbeatSound:Play()

	-- ========================================
	-- Landing Noise Detection
	-- ========================================
	humanoid.StateChanged:Connect(function(_oldState, newState)
		if newState == Enum.HumanoidStateType.Landed then
			-- Loud landing noise
			local landSound = Instance.new("Sound")
			landSound.SoundId = "rbxassetid://9114223126" -- deep thump landing sound
			landSound.Volume = 0.8
			landSound.Parent = rootPart
			landSound:Play()
			Debris:AddItem(landSound, 3)

			-- Temporarily alert the game of land noise
			character:SetAttribute("LandedNoise", true)
			task.delay(1.5, function()
				character:SetAttribute("LandedNoise", false)
			end)
		end
	end)

	-- ========================================
	-- Proximity Loop: Heartbeat Volume & Screen Shake
	-- ========================================
	task.spawn(function()
		while character and character.Parent do
			task.wait(0.1)

			-- Find the Hunter player (Sid)
			local hunterChar = nil
			for _, otherPlayer in Players:GetPlayers() do
				local otherChar = otherPlayer.Character
				if otherChar and otherChar:GetAttribute("CharacterName") == "Sid" then
					hunterChar = otherChar
					break
				end
			end

			if hunterChar and hunterChar:FindFirstChild("HumanoidRootPart") then
				local hunterRoot = hunterChar.HumanoidRootPart
				local hunterHum = hunterChar:FindFirstChildOfClass("Humanoid")

				local dist = (rootPart.Position - hunterRoot.Position).Magnitude

				-- 1. Heartbeat VFX/SFX volume scaling
				if dist < 80 then
					heartbeatSound.Volume = math.clamp((80 - dist) / 60 * 0.85, 0.1, 0.85)
					heartbeatSound.PlaybackSpeed = math.clamp(1.0 + (80 - dist) / 80 * 0.8, 1.0, 1.8)
				else
					heartbeatSound.Volume = 0
				end

				-- 2. Footstep Screen Shake (only when Sid is moving)
				if dist < 60 and hunterHum and hunterHum.MoveDirection.Magnitude > 0 then
					local shakeFactor = math.clamp((60 - dist) / 60, 0, 1)
					local intensity = shakeFactor * 0.3

					local shake = Vector3.new(
						math.random(-10, 10) * 0.01 * intensity,
						math.random(-10, 10) * 0.01 * intensity,
						0
					)
					camera.CFrame = camera.CFrame * CFrame.new(shake)
				end
			else
				heartbeatSound.Volume = 0
			end
		end
	end)

	-- ========================================
	-- Dynamic Surface Footstep Volume Loop
	-- ========================================
	ProximityEffects._initSurfaceFootsteps(character, rootPart, humanoid, characterName)
end

--- Adjusts footstep volume based on the ground material underfoot.
--- Separate function because it applies to ALL characters (including Sid).
function ProximityEffects._initSurfaceFootsteps(character: Model, rootPart: BasePart, humanoid: Humanoid, characterName: string)
	local torsoPart = character:FindFirstChild("Torso")

	task.spawn(function()
		local runningSound = (torsoPart and torsoPart:FindFirstChild("Running"))
			or (character:FindFirstChild("Head") and character.Head:FindFirstChild("Running"))

		-- Wait for the running sound to appear
		if not runningSound then
			if torsoPart then
				runningSound = torsoPart:WaitForChild("Running", 8)
			end
			if not runningSound then
				local head = character:WaitForChild("Head", 8)
				if head then
					runningSound = head:WaitForChild("Running", 8)
				end
			end
		end

		if runningSound and runningSound:IsA("Sound") then
			local baseMaxVolume = characterName == "Sid" and 3.0 or 0.15

			while character and character.Parent do
				task.wait(0.25)
				if humanoid.MoveDirection.Magnitude > 0.01 then
					-- Raycast down to find ground material
					local raycastParams = RaycastParams.new()
					raycastParams.FilterDescendantsInstances = { character }
					raycastParams.FilterType = Enum.RaycastFilterType.Exclude

					local result = workspace:Raycast(rootPart.Position, Vector3.new(0, -10, 0), raycastParams)
					if result then
						local mat = result.Material
						local multiplier = 1.0

						if mat == Enum.Material.Fabric or mat == Enum.Material.Sand or mat == Enum.Material.Grass then
							multiplier = 0.2 -- Carpet/Soft (very quiet)
						elseif mat == Enum.Material.Wood or mat == Enum.Material.WoodPlanks then
							multiplier = 0.65 -- Wood (moderate)
						elseif mat == Enum.Material.Concrete or mat == Enum.Material.Metal or mat == Enum.Material.DiamondPlate then
							multiplier = 1.0 -- Concrete/Metal (loud)
						elseif mat == Enum.Material.Plastic or mat == Enum.Material.SmoothPlastic then
							multiplier = 1.5 -- Plastic Blocks (extremely loud)
						end

						runningSound.Volume = baseMaxVolume * multiplier
					end
				end
			end
		end
	end)
end

--- Initialize footstep volume adjustment for Sid (louder, heavier).
--- Called separately since Sid doesn't get the proximity heartbeat/shake effects.
function ProximityEffects.InitFootstepVolume(character: Model, rootPart: BasePart, humanoid: Humanoid, characterName: string)
	-- Set Sid's base footstep volume
	local torsoPart = character:FindFirstChild("Torso")
	task.spawn(function()
		local runningSound = torsoPart and torsoPart:WaitForChild("Running", 8)
		if not runningSound then
			local head = character:WaitForChild("Head", 8)
			if head then
				runningSound = head:WaitForChild("Running", 8)
			end
		end
		if runningSound and runningSound:IsA("Sound") then
			if characterName == "Sid" then
				runningSound.Volume = 3.0
				runningSound.PlaybackSpeed = 0.8
			else
				runningSound.Volume = 0.15
			end
		end
	end)

	-- Surface-based volume loop
	ProximityEffects._initSurfaceFootsteps(character, rootPart, humanoid, characterName)
end

return ProximityEffects
