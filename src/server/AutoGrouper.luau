--[[
	ToyStory - AutoGrouper (ModuleScript)
	Programmatically groups unstructured visual parts into standard R6 body groups
	(Head, Chest, Left Arm, Right Arm, Left Leg, Right Leg) for characters whose
	templates don't arrive pre-grouped: Slinky, Mr. Potato Head, and Sid.
]]

local AutoGrouper = {}

-- Standard R6 visual group names
local R6_GROUP_NAMES = { "Chest", "Head", "Left Arm", "Right Arm", "Left Leg", "Right Leg" }

--- Finds or creates a named Model child inside a parent model.
--- Shared helper that was previously copy-pasted inside each auto-group function.
local function getOrCreateGroup(parent: Model, name: string): Model
	local group = parent:FindFirstChild(name)
	if not group then
		group = Instance.new("Model")
		group.Name = name
		group.Parent = parent
	end
	return group
end

--- Destroys empty non-R6 Model children to clean up after grouping.
--- Shared helper that was previously duplicated 3 times.
local function cleanUpEmptyModels(parent: Model)
	local r6Set = {}
	for _, name in R6_GROUP_NAMES do
		r6Set[name] = true
	end

	for _, child in parent:GetChildren() do
		if child:IsA("Model") and not r6Set[child.Name] then
			if #child:GetChildren() == 0 then
				child:Destroy()
			end
		end
	end
end

--- Auto-groups Slinky's unstructured detailed parts into proper R6 visual models.
--- Uses spatial heuristics: head anchor from facial features, body center for
--- leg/torso classification, and Z-axis relative position for front/back legs.
function AutoGrouper.GroupSlinky(visualTemplate: Model)
	local chestGroup = getOrCreateGroup(visualTemplate, "Chest")
	local headGroup = getOrCreateGroup(visualTemplate, "Head")
	local leftArmGroup = getOrCreateGroup(visualTemplate, "Left Arm")
	local rightArmGroup = getOrCreateGroup(visualTemplate, "Right Arm")
	local leftLegGroup = getOrCreateGroup(visualTemplate, "Left Leg")
	local rightLegGroup = getOrCreateGroup(visualTemplate, "Right Leg")

	local allParts = {}
	local dogEars = visualTemplate:FindFirstChild("Dog Ears")
	local leftEye = visualTemplate:FindFirstChild("Left eye")
	local headAnchor = nil

	if dogEars and dogEars:IsA("BasePart") then
		headAnchor = dogEars.Position
	elseif leftEye then
		if leftEye:IsA("BasePart") then
			headAnchor = leftEye.Position
		elseif leftEye:IsA("Model") then
			headAnchor = leftEye:GetPivot().Position
		end
	end

	-- Retrieve all BaseParts in the model (direct or nested inside other models)
	local children = visualTemplate:GetChildren()
	for _, child in children do
		if child:IsA("BasePart") and child.Name ~= "HumanoidRootPart" then
			table.insert(allParts, child)
		elseif
			child:IsA("Model")
			and child.Name ~= "Chest"
			and child.Name ~= "Head"
			and child.Name ~= "Left Arm"
			and child.Name ~= "Right Arm"
			and child.Name ~= "Left Leg"
			and child.Name ~= "Right Leg"
		then
			for _, subChild in child:GetDescendants() do
				if subChild:IsA("BasePart") then
					table.insert(allParts, subChild)
				end
			end
		end
	end

	if #allParts == 0 then
		return
	end

	-- Find default head anchor if not found via names
	if not headAnchor then
		local highestY = -math.huge
		for _, part in allParts do
			if part.Position.Y > highestY then
				highestY = part.Position.Y
				headAnchor = part.Position
			end
		end
	end

	-- PHASE 1: Separate the Head parts (using a tight 2.2-stud radius around the head anchor)
	local headRadius = 2.2
	local bodyParts = {}

	for _, part in allParts do
		local dist = (part.Position - headAnchor).Magnitude
		if
			dist < headRadius
			or part.Name == "Dog Ears"
			or part.Name == "Left eye"
			or part.Parent.Name == "Left eye"
		then
			part.Parent = headGroup
		else
			table.insert(bodyParts, part)
		end
	end

	-- PHASE 2: Find bounds of the REMAINING body parts (keeps the head out of body bounds math)
	local minY = math.huge
	local maxY = -math.huge
	local minZ = math.huge
	local maxZ = -math.huge
	local sumPos = Vector3.new(0, 0, 0)

	for _, part in bodyParts do
		local pos = part.Position
		minY = math.min(minY, pos.Y)
		maxY = math.max(maxY, pos.Y)
		minZ = math.min(minZ, pos.Z)
		maxZ = math.max(maxZ, pos.Z)
		sumPos = sumPos + pos
	end

	local bodyCenter = sumPos / #bodyParts
	local bodyLength = maxZ - minZ

	-- Thresholds (for a 5-stud tall scaled Slinky)
	local legYCutoff = minY + 1.8 -- legs are in the lower 1.8 studs
	local isHeadFrontZPositive = headAnchor.Z > bodyCenter.Z

	-- PHASE 3: Classify remaining body parts into Legs vs Torso/Coils
	for _, part in bodyParts do
		local pos = part.Position

		-- Leg check: must be low enough, and must NOT be in the middle 50% of the body (coils zone)
		local relativeZ = (pos.Z - minZ) / bodyLength
		local isMiddleCoils = (relativeZ > 0.25 and relativeZ < 0.75)

		if pos.Y < legYCutoff and not isMiddleCoils then
			-- Classify as one of the 4 legs
			local isLeft = pos.X > bodyCenter.X
			local isFront = false
			if isHeadFrontZPositive then
				isFront = pos.Z > bodyCenter.Z
			else
				isFront = pos.Z <= bodyCenter.Z
			end

			if isFront then
				if isLeft then
					part.Parent = leftArmGroup
				else
					part.Parent = rightArmGroup
				end
			else
				if isLeft then
					part.Parent = leftLegGroup
				else
					part.Parent = rightLegGroup
				end
			end
		else
			-- Torso/Spring coils/Back-body/Tail -> Chest
			part.Parent = chestGroup
		end
	end

	cleanUpEmptyModels(visualTemplate)
end

--- Auto-groups Mr. Potato Head's loose parts programmatically into standard R6 visual groups.
--- Uses name-based classification first (foot, leg, arm, eye, hat, etc.), then falls back
--- to spatial heuristics relative to the main body part.
function AutoGrouper.GroupPotatoHead(visualTemplate: Model)
	local chestGroup = getOrCreateGroup(visualTemplate, "Chest")
	local headGroup = getOrCreateGroup(visualTemplate, "Head")
	local leftArmGroup = getOrCreateGroup(visualTemplate, "Left Arm")
	local rightArmGroup = getOrCreateGroup(visualTemplate, "Right Arm")
	local leftLegGroup = getOrCreateGroup(visualTemplate, "Left Leg")
	local rightLegGroup = getOrCreateGroup(visualTemplate, "Right Leg")

	-- Pre-pass: extract nested model wrappers (e.g., "Model > Left Arm" → move "Left Arm" to top level)
	for _, child in visualTemplate:GetChildren() do
		if child:IsA("Model") and child.Name == "Model" then
			for _, sub in child:GetChildren() do
				sub.Parent = visualTemplate
			end
			child:Destroy()
		end
	end

	local children = visualTemplate:GetChildren()

	-- Locate the main potato body
	local bodyPart = visualTemplate:FindFirstChild("Body")
	if not bodyPart then
		local biggestSize = 0
		for _, child in children do
			if child:IsA("BasePart") and child.Name ~= "HumanoidRootPart" then
				local sz = child.Size.X * child.Size.Y * child.Size.Z
				if sz > biggestSize then
					biggestSize = sz
					bodyPart = child
				end
			end
		end
	end

	local bodyCenter = bodyPart and bodyPart.Position or Vector3.new(0, 0, 0)
	local bodySize = bodyPart and bodyPart.Size or Vector3.new(3, 3, 3)

	for _, child in children do
		if
			child.Name == "Chest"
			or child.Name == "Head"
			or child.Name == "Left Arm"
			or child.Name == "Right Arm"
			or child.Name == "Left Leg"
			or child.Name == "Right Leg"
		then
			continue
		end

		local name = child.Name:lower()

		if name:find("foot") or name:find("leg") or name:find("boot") or name:find("shoe") then
			if name:find("left") then
				child.Parent = leftLegGroup
			elseif name:find("right") then
				child.Parent = rightLegGroup
			else
				if child:GetPivot().Position.X > bodyCenter.X then
					child.Parent = leftLegGroup
				else
					child.Parent = rightLegGroup
				end
			end
		elseif name:find("arm") or name:find("hand") or name:find("glove") then
			if name:find("left") then
				child.Parent = leftArmGroup
			elseif name:find("right") then
				child.Parent = rightArmGroup
			else
				if child:GetPivot().Position.X > bodyCenter.X then
					child.Parent = leftArmGroup
				else
					child.Parent = rightArmGroup
				end
			end
		elseif
			name:find("eye")
			or name:find("ear")
			or name:find("nose")
			or name:find("mustache")
			or name:find("mouth")
			or name:find("tongue")
			or name:find("hat")
			or name:find("bowler")
		then
			child.Parent = headGroup
		elseif child == bodyPart or name:find("body") or name:find("torso") or name:find("chest") then
			child.Parent = chestGroup
		else
			-- Spatial fallback for unnamed parts (like Model or Part)
			local pos = child:GetPivot().Position
			local yDiff = pos.Y - bodyCenter.Y

			if pos.Y < bodyCenter.Y - bodySize.Y * 0.4 then
				if pos.X > bodyCenter.X then
					child.Parent = leftLegGroup
				else
					child.Parent = rightLegGroup
				end
			elseif pos.X > bodyCenter.X + bodySize.X * 0.4 then
				child.Parent = leftArmGroup
			elseif pos.X < bodyCenter.X - bodySize.X * 0.4 then
				child.Parent = rightArmGroup
			elseif yDiff > -bodySize.Y * 0.2 then
				child.Parent = headGroup
			else
				child.Parent = chestGroup
			end
		end
	end

	cleanUpEmptyModels(visualTemplate)
end

--- Auto-groups Sid's parts programmatically into standard R6 visual groups.
--- Uses volume-based torso identification, then positional classification
--- relative to the torso center.
function AutoGrouper.GroupSid(visualTemplate: Model)
	local chestGroup = getOrCreateGroup(visualTemplate, "Chest")
	local headGroup = getOrCreateGroup(visualTemplate, "Head")
	local leftArmGroup = getOrCreateGroup(visualTemplate, "Left Arm")
	local rightArmGroup = getOrCreateGroup(visualTemplate, "Right Arm")
	local leftLegGroup = getOrCreateGroup(visualTemplate, "Left Leg")
	local rightLegGroup = getOrCreateGroup(visualTemplate, "Right Leg")

	-- Collect all BaseParts (including nested ones under other models)
	local allParts = {}
	for _, desc in visualTemplate:GetDescendants() do
		if desc:IsA("BasePart") and desc.Name ~= "HumanoidRootPart" then
			table.insert(allParts, desc)
		end
	end

	-- Identify the main Torso part by volume (it's the largest part by far)
	local torsoPart = nil
	local biggestVolume = 0
	for _, part in allParts do
		if part.Name == "Part" then
			local vol = part.Size.X * part.Size.Y * part.Size.Z
			if vol > biggestVolume then
				biggestVolume = vol
				torsoPart = part
			end
		end
	end

	if not torsoPart then
		warn("[ToyStory AutoGrouper] Torso part not found for Sid!")
		return
	end

	local torsoCenter = torsoPart.Position

	for _, part in allParts do
		if part.Name == "Head" then
			part.Parent = headGroup
		elseif part == torsoPart then
			part.Parent = chestGroup
		else
			-- Classify based on position relative to torsoCenter
			local pos = part.Position
			local diffX = pos.X - torsoCenter.X
			local diffY = pos.Y - torsoCenter.Y

			if diffY < -6 then
				-- Leg zone
				if diffX < 0 then
					part.Parent = leftLegGroup
				else
					part.Parent = rightLegGroup
				end
			else
				-- Arm/Shoulder zone
				if diffX < 0 then
					part.Parent = leftArmGroup
				else
					part.Parent = rightArmGroup
				end
			end
		end
	end

	cleanUpEmptyModels(visualTemplate)
end

--- Routes to the correct auto-grouping function based on character name.
--- Returns false if no auto-grouping was needed for this character.
function AutoGrouper.AutoGroup(visualTemplate: Model, characterName: string): boolean
	if characterName == "Slinky" then
		AutoGrouper.GroupSlinky(visualTemplate)
		return true
	elseif characterName == "PotatoHead" then
		AutoGrouper.GroupPotatoHead(visualTemplate)
		return true
	elseif characterName == "Sid" then
		AutoGrouper.GroupSid(visualTemplate)
		return true
	end
	return false
end

return AutoGrouper
