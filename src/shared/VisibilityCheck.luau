--[[
	ToyStory - VisibilityCheck (ModuleScript)
	Handles visibility checking logic between the hunter (Sid) and toys.
	Uses distance checks, field-of-view cone checks, and multi-point raycasting.
]]

local Players = game:GetService("Players")

local VisibilityCheck = {}

-- Constants for vision parameters
local FOV_ANGLE_DEG = 120 -- Field of view angle (cone) of Sid
local MAX_DISTANCE = 160 -- Max distance Sid can see toys
local MIN_VISIBLE_RATIO = 0.5 -- Most points must be visible to be detected (>= 50%)

--- Checks if a specific Sid character has line of sight to a toy character
function VisibilityCheck.CanSidSeeToy(sidChar: Model, toyChar: Model): boolean
	local sidHead = sidChar:FindFirstChild("Head") or sidChar.PrimaryPart
	local toyTorso = toyChar:FindFirstChild("Torso") or toyChar.PrimaryPart
	if not sidHead or not toyTorso then
		return false
	end

	local sidPos = sidHead.Position
	local sidLook = sidHead.CFrame.LookVector

	-- 1. Cheap Distance check (optimization)
	local toyPos = toyTorso.Position
	local toToy = toyPos - sidPos
	local distance = toToy.Magnitude
	if distance > MAX_DISTANCE then
		return false
	end

	-- 2. Cheap Field-of-view check (optimization)
	local dirToToy = toToy.Unit
	local dotProduct = sidLook:Dot(dirToToy)
	local threshold = math.cos(math.rad(FOV_ANGLE_DEG / 2))
	if dotProduct < threshold then
		return false
	end

	-- 3. Raycast check on multiple points of the toy for fairness
	-- We define 5 test points on the toy character:
	-- - Torso center
	-- - Head (if exists, else slightly above torso)
	-- - Left offset (relative to torso facing)
	-- - Right offset (relative to torso facing)
	-- - Bottom/Low offset (near feet)
	local testPositions = {}
	
	-- Center (Torso)
	table.insert(testPositions, toyPos)
	
	-- Top (Head)
	local head = toyChar:FindFirstChild("Head")
	if head then
		table.insert(testPositions, head.Position)
	else
		table.insert(testPositions, toyPos + Vector3.new(0, 1.5, 0))
	end
	
	-- Sides and Bottom (using Torso CFrame for relative offsets)
	local torsoCFrame = toyTorso.CFrame
	table.insert(testPositions, (torsoCFrame * CFrame.new(-1.2, 0, 0)).Position) -- Left
	table.insert(testPositions, (torsoCFrame * CFrame.new(1.2, 0, 0)).Position)  -- Right
	table.insert(testPositions, (torsoCFrame * CFrame.new(0, -1.5, 0)).Position) -- Bottom

	-- Setup raycast parameters (ignore Sid and the target toy)
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { sidChar, toyChar }
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true

	local visibleCount = 0
	for _, targetPos in ipairs(testPositions) do
		local direction = targetPos - sidPos
		local result = workspace:Raycast(sidPos, direction, params)
		
		-- If the ray hit nothing, the path is clear to that point
		if not result then
			visibleCount = visibleCount + 1
		end
	end

	-- If most points are visible, Sid can see the toy
	local requiredVisible = math.ceil(#testPositions * MIN_VISIBLE_RATIO)
	return visibleCount >= requiredVisible
end

--- Checks if any active Sid in the game can see a specific toy character
function VisibilityCheck.CanAnySidSeeToy(toyChar: Model): boolean
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		if char and char:GetAttribute("CharacterName") == "Sid" then
			if VisibilityCheck.CanSidSeeToy(char, toyChar) then
				return true
			end
		end
	end
	return false
end

return VisibilityCheck
