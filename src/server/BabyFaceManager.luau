--[[
	ToyStory - BabyFaceManager (ModuleScript)
	Handles AI for the BabyFace NPC placed in workspace.
	- Detects if model has a Humanoid (uses MoveTo) or is a plain Model (uses CFrame at fixed Y).
	- Roams randomly, chases nearby toys, freezes them for 10 seconds on touch.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Utils = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Utils"))

local BabyFaceManager = {}

-- State
local activeBabyFace = nil
local aiTask = nil
local isStunnedCooldown = {} -- Player -> os.clock() when stunned
local originalCFrame = nil
local fixedY = nil -- Y level to lock to when non-humanoid

-- Configuration
local DETECTION_RANGE = 45   -- studs: spots toy within this range
local LOSE_RANGE = 60        -- studs: drops chase if toy goes this far
local CAPTURE_RANGE = 5.5    -- studs: triggers stun when this close
local WALK_SPEED = 11        -- studs/sec for non-humanoid CFrame movement
local STUN_DURATION = 10     -- seconds toy is frozen
local COOLDOWN_DURATION = 8  -- seconds before same toy can be caught again

-- Roam only within this many studs of the original placed position (keeps BabyFace inside the house)
local ROAM_RADIUS = 18

-- ──────────────────────────────────────────────────────────
-- Helpers
-- ──────────────────────────────────────────────────────────

local function getPhase()
	local gs = ReplicatedStorage:FindFirstChild("GameState")
	local mp = gs and gs:FindFirstChild("MatchPhase")
	return mp and mp.Value or "Lobby"
end

local function findNearestToy(fromPos: Vector3)
	local best, bestChar, bestDist = nil, nil, DETECTION_RANGE

	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		if not char then continue end
		if not char:GetAttribute("IsCustomCharacter") then continue end
		if char:GetAttribute("CharacterName") == "Sid" then continue end
		if char:GetAttribute("IsCaptured") then continue end
		if char:GetAttribute("IsLayingDown") then continue end

		local cooldown = isStunnedCooldown[player] or 0
		if os.clock() - cooldown <= COOLDOWN_DURATION then continue end

		local root = char.PrimaryPart
		if not root then continue end

		local dist = (Vector3.new(fromPos.X, 0, fromPos.Z) - Vector3.new(root.Position.X, 0, root.Position.Z)).Magnitude
		if dist < bestDist then
			bestDist = dist
			best = player
			bestChar = char
		end
	end

	return best, bestChar, bestDist
end

local function isTargetValid(fromPos: Vector3, targetChar: Model): boolean
	if not targetChar or not targetChar.Parent then return false end
	if targetChar:GetAttribute("IsCaptured") then return false end
	if targetChar:GetAttribute("IsLayingDown") then return false end
	local root = targetChar.PrimaryPart
	if not root then return false end
	local dist = (Vector3.new(fromPos.X, 0, fromPos.Z) - Vector3.new(root.Position.X, 0, root.Position.Z)).Magnitude
	return dist <= LOSE_RANGE
end

-- Pick a random XZ point within ROAM_RADIUS studs of the original placement
local function randomWaypointXZ(): (number, number)
	if not originalCFrame then
		return 0, 0
	end
	local rng = Random.new()
	local angle = rng:NextNumber(0, math.pi * 2)
	local radius = rng:NextNumber(ROAM_RADIUS * 0.3, ROAM_RADIUS)
	local ox = originalCFrame.Position.X
	local oz = originalCFrame.Position.Z
	return ox + math.cos(angle) * radius, oz + math.sin(angle) * radius
end

-- Move the model horizontally. If non-humanoid, lock Y to fixedY.
local function moveTo(targetPos: Vector3)
	if not activeBabyFace or not activeBabyFace.Parent then return end

	local humanoid = activeBabyFace:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:MoveTo(targetPos)
		return
	end

	-- Non-humanoid: CFrame slide at fixed Y level
	local pivot = activeBabyFace:GetPivot()
	local curPos = pivot.Position

	-- Horizontal direction only
	local dx = targetPos.X - curPos.X
	local dz = targetPos.Z - curPos.Z
	local dist = math.sqrt(dx*dx + dz*dz)

	if dist < 0.2 then return end

	local step = math.min(dist, WALK_SPEED * 0.25)
	local nx = curPos.X + (dx/dist) * step
	local nz = curPos.Z + (dz/dist) * step
	local ny = fixedY or curPos.Y  -- Never change Y

	-- Build new CFrame: position + face direction of travel (Y-axis rotation only)
	local newCF = CFrame.new(nx, ny, nz) * CFrame.Angles(0, math.atan2(-dx, -dz), 0)
	activeBabyFace:PivotTo(newCF)
end

-- ──────────────────────────────────────────────────────────
-- Public API
-- ──────────────────────────────────────────────────────────

function BabyFaceManager.Spawn()
	BabyFaceManager.CleanUp()

	local babyFace = workspace:FindFirstChild("BabyFace") or workspace:FindFirstChild("babyface")
	if not babyFace then
		warn("[ToyStory BabyFaceManager] 'BabyFace' model not found in Workspace!")
		return
	end

	activeBabyFace = babyFace

	if not originalCFrame then
		originalCFrame = babyFace:GetPivot()
	end

	-- Determine root part
	local root = babyFace.PrimaryPart or babyFace:FindFirstChild("HumanoidRootPart") or babyFace:FindFirstChildWhichIsA("BasePart")
	if not root then
		warn("[ToyStory BabyFaceManager] BabyFace has no root part!")
		return
	end
	if not babyFace.PrimaryPart then
		babyFace.PrimaryPart = root
	end

	local humanoid = babyFace:FindFirstChildOfClass("Humanoid")
	local hasHumanoid = humanoid ~= nil

	-- Record the fixed Y height so non-humanoid movement never changes altitude
	fixedY = originalCFrame.Position.Y

	-- Configure physics
	for _, part in ipairs(babyFace:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CollisionGroup = "Hunters"
			if hasHumanoid then
				part.Anchored = false
				part.CanCollide = (part == root)
			else
				part.Anchored = true  -- gravity is irrelevant; we move via CFrame
				part.CanCollide = false
			end
		end
	end

	-- Reset to editor position
	babyFace:PivotTo(originalCFrame)

	if hasHumanoid then
		humanoid.WalkSpeed = WALK_SPEED
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		if humanoid.HipHeight == 0 then
			humanoid.HipHeight = 2.5
		end
	end

	local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
	local stunToyEvent = eventsFolder and Utils.GetOrCreateRemoteEvent(eventsFolder, "StunToy")

	-- AI loop
	aiTask = task.spawn(function()
		local state = "Roam"
		local targetPlayer, targetChar = nil, nil
		local waypointX, waypointZ = randomWaypointXZ()
		local lastMoveRequest = 0

		while activeBabyFace and activeBabyFace.Parent do
			task.wait(0.25)
			if not root or not root.Parent then break end

			local phase = getPhase()
			local curPos = root.Position

			-- Freeze during non-active phases
			if phase ~= "Search" and phase ~= "Escape" then
				state = "Roam"
				targetPlayer = nil
				targetChar = nil
				if hasHumanoid and humanoid then
					humanoid:Move(Vector3.new(0, 0, 0))
				end
				continue
			end

			-- Always scan for toys (update target even in roam)
			-- Skip if currently in post-capture cooldown
			if state == "Stunned" then
				continue
			end
			local p, c, dist = findNearestToy(curPos)
			if p and c then
				if state == "Roam" then
					print("[ToyStory BabyFace] Spotted:", p.Name, "dist:", math.floor(dist))
					local head = babyFace:FindFirstChild("Head") or root
					Utils.PlayOneShot(head, "rbxassetid://9114227181", 0.7)
				end
				state = "Chase"
				targetPlayer = p
				targetChar = c
			elseif state == "Chase" and not isTargetValid(curPos, targetChar) then
				print("[ToyStory BabyFace] Lost target, resuming roam.")
				state = "Roam"
				targetPlayer = nil
				targetChar = nil
			end

			if state == "Chase" and targetChar then
				local tRoot = targetChar.PrimaryPart
				if tRoot then
					moveTo(tRoot.Position)

					-- Check capture (horizontal distance only)
					local hdist = (Vector3.new(curPos.X, 0, curPos.Z) - Vector3.new(tRoot.Position.X, 0, tRoot.Position.Z)).Magnitude
					if hdist <= CAPTURE_RANGE then
						local p2 = targetPlayer
						local c2 = targetChar
						local stunStartCF = activeBabyFace:GetPivot()

						isStunnedCooldown[p2] = os.clock()
						print("[ToyStory BabyFace] Stunned:", p2.Name)

						-- Freeze BabyFace at current spot briefly
						state = "Stunned"
						targetPlayer = nil
						targetChar = nil

						local pRoot = c2.PrimaryPart
						if pRoot then
							pRoot.Anchored = true

							-- Add a countdown BillboardGui above the toy's head
							local pHead = c2:FindFirstChild("Head") or pRoot
							Utils.PlayOneShot(pHead, "rbxassetid://4798150495", 0.9)

							-- Build billboard visible to all players
							local existingBill = pHead:FindFirstChild("StunLabel")
							if existingBill then existingBill:Destroy() end

							local bill = Instance.new("BillboardGui")
							bill.Name = "StunLabel"
							bill.Size = UDim2.fromOffset(200, 50)
							bill.StudsOffset = Vector3.new(0, 3, 0)
							bill.AlwaysOnTop = true
							bill.Parent = pHead

							local tl = Instance.new("TextLabel")
							tl.Size = UDim2.fromScale(1, 1)
							tl.BackgroundTransparency = 1
							tl.TextColor3 = Color3.fromRGB(231, 76, 60)
							tl.TextStrokeTransparency = 0
							tl.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
							tl.Font = Enum.Font.FredokaOne
							tl.TextSize = 22
							tl.Text = "FROZEN! 10s"
							tl.Parent = bill

							-- Update countdown label every second
							task.spawn(function()
								for i = STUN_DURATION, 1, -1 do
									if not bill.Parent then break end
									tl.Text = string.format("FROZEN! %ds", i)
									task.wait(1)
								end
								if bill.Parent then bill:Destroy() end
							end)

							if stunToyEvent then
								stunToyEvent:FireClient(p2, STUN_DURATION)
							end

							task.delay(STUN_DURATION, function()
								if c2 and c2.Parent and pRoot then
									pRoot.Anchored = false
								end
							end)
						end

						-- Return BabyFace to its original position after a brief pause, then resume roam from there
						task.delay(1.5, function()
							if activeBabyFace and activeBabyFace.Parent and originalCFrame then
								activeBabyFace:PivotTo(originalCFrame)
								waypointX, waypointZ = randomWaypointXZ()
								lastMoveRequest = os.clock()
								state = "Roam"
							end
						end)
					end
				end

			else -- Roam
				local wx, wz = waypointX, waypointZ
				local hdist = math.sqrt((curPos.X - wx)^2 + (curPos.Z - wz)^2)
				if hdist < 6 or os.clock() - lastMoveRequest > 12 then
					waypointX, waypointZ = randomWaypointXZ()
					lastMoveRequest = os.clock()
				end
				moveTo(Vector3.new(waypointX, fixedY or curPos.Y, waypointZ))
			end
		end
	end)

	print("[ToyStory BabyFaceManager] BabyFace AI started! Humanoid:", hasHumanoid)
end

function BabyFaceManager.CleanUp()
	if aiTask then
		task.cancel(aiTask)
		aiTask = nil
	end

	if activeBabyFace and activeBabyFace.Parent then
		local humanoid = activeBabyFace:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid:Move(Vector3.new(0, 0, 0))
		end
		if originalCFrame then
			activeBabyFace:PivotTo(originalCFrame)
		end
		for _, part in ipairs(activeBabyFace:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Anchored = true
			end
		end
		activeBabyFace = nil
	end

	isStunnedCooldown = {}
end

return BabyFaceManager
