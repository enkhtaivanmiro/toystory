--[[
	ToyStory - EventSetup (ModuleScript)
	Centralizes all RemoteEvent creation and server-side event handlers.
	Handles ToggleWings, ToggleFlashlight, CaptureToy, and SetFreezeState events.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Utils = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Utils"))

local EventSetup = {}

--- Initialize all RemoteEvents and connect their server handlers.
--- Requires references to the events folder, GameLoopManager, and RescueManager
--- to handle capture/mistake/stun logic.
function EventSetup.Init(eventsFolder: Folder, gameLoopManager: any, rescueManager: any)

	-- ========================================
	-- ToggleWings (Buzz only)
	-- ========================================
	local toggleWingsEvent = Utils.GetOrCreateRemoteEvent(eventsFolder, "ToggleWings")

	toggleWingsEvent.OnServerEvent:Connect(function(player)
		local char = player.Character
		if char and char:GetAttribute("CharacterName") == "Buzz" then
			local visuals = char:FindFirstChild("Visuals")
			local vTorso = visuals and (visuals:FindFirstChild("Chest") or visuals:FindFirstChild("Torso"))
			local wing = vTorso and vTorso:FindFirstChild("wing", true)

			if wing and wing:IsA("BasePart") then
				local current = char:GetAttribute("WingsOut") or false
				local newStatus = not current

				char:SetAttribute("WingsOut", newStatus)
				wing.Transparency = newStatus and 0 or 1

				-- Play wing pop-out/retract mechanical click sound
				Utils.PlayOneShot(wing, "rbxassetid://12222229", 0.65)
			end
		end
	end)

	-- ========================================
	-- ToggleFlashlight (Sid only)
	-- ========================================
	local toggleFlashlightEvent = Utils.GetOrCreateRemoteEvent(eventsFolder, "ToggleFlashlight")

	toggleFlashlightEvent.OnServerEvent:Connect(function(player)
		local char = player.Character
		if char and char:GetAttribute("CharacterName") == "Sid" then
			local head = char:FindFirstChild("Head")
			if head then
				local light = head:FindFirstChild("FlashlightLight")
				if light then
					light:Destroy()
				else
					light = Instance.new("SpotLight")
					light.Name = "FlashlightLight"
					light.Color = Color3.fromRGB(255, 255, 220)
					light.Brightness = 3.5
					light.Range = 70
					light.Angle = 45
					light.Face = Enum.NormalId.Front
					light.Shadows = true
					light.Parent = head
				end
			end
		end
	end)

	-- ========================================
	-- CaptureToy (Sid attacks a toy)
	-- ========================================
	local captureToyEvent = Utils.GetOrCreateRemoteEvent(eventsFolder, "CaptureToy")

	captureToyEvent.OnServerEvent:Connect(function(player, targetToy)
		local char = player.Character
		if not char or char:GetAttribute("CharacterName") ~= "Sid" then
			return
		end

		-- Validate target
		if not targetToy or not targetToy:IsA("Model") or not targetToy:GetAttribute("IsCustomCharacter") then
			return
		end

		local targetName = targetToy:GetAttribute("CharacterName")
		if targetName == "Sid" then
			return
		end

		-- If already captured, don't recapture
		if targetToy:GetAttribute("IsCaptured") == true then
			return
		end

		local isNPCToy = targetToy:GetAttribute("IsNPCToy") or false
		local isLayingDown = targetToy:GetAttribute("IsLayingDown") or false

		if isNPCToy then
			-- MISTAKE: Attacked an NPC toy!
			EventSetup._handleMistake(player, char, targetToy, eventsFolder, gameLoopManager, true)
		elseif isLayingDown then
			-- MISTAKE: Attacked a real player that was playing dead!
			EventSetup._handleMistake(player, char, targetToy, eventsFolder, gameLoopManager, false)
		else
			-- SUCCESS: Sid caught a toy player moving!
			print("[ToyStory EventSetup] Sid captured moving toy:", targetName)

			-- Play crunch capture sound
			local head = char:FindFirstChild("Head")
			if head then
				Utils.PlayOneShot(head, "rbxassetid://2801263", 1.0)
			end

			-- Send to cage / Capture
			rescueManager.Capture(targetToy, char)
		end
	end)

	-- ========================================
	-- SetFreezeState (Toy play-dead replication)
	-- ========================================
	local setFreezeStateEvent = Utils.GetOrCreateRemoteEvent(eventsFolder, "SetFreezeState")

	setFreezeStateEvent.OnServerEvent:Connect(function(player, isFrozen, targetC0)
		local char = player.Character
		if char and char:GetAttribute("IsCustomCharacter") then
			char:SetAttribute("IsLayingDown", isFrozen)
			local humanoid = char:FindFirstChildOfClass("Humanoid")
			if humanoid then
				if isFrozen then
					humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
				else
					humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
				end
			end

			-- Replicate Motor6D C0 to other players by modifying it on the server
			local root = char.PrimaryPart
			local rootJoint = root and root:FindFirstChild("RootJoint")
			if rootJoint and rootJoint:IsA("Motor6D") then
				if targetC0 then
					rootJoint.C0 = targetC0
					print("[ToyStory EventSetup] Replicated lay-down C0 for", player.Name)
				else
					warn("[ToyStory EventSetup] No targetC0 received for", player.Name)
				end
			else
				warn("[ToyStory EventSetup] RootJoint NOT found on server for", player.Name)
			end
		end
	end)

	-- Pre-create the StunHunter event so it's ready for use
	Utils.GetOrCreateRemoteEvent(eventsFolder, "StunHunter")

	print("[ToyStory EventSetup] All event handlers initialized!")
end

--- Handle a Sid mistake (hit NPC or frozen player).
--- Consolidates the duplicated mistake logic that was in two branches.
function EventSetup._handleMistake(
	player: Player,
	char: Model,
	targetToy: Model,
	eventsFolder: Folder,
	gameLoopManager: any,
	isNPCTarget: boolean
)
	local mistakes = player:GetAttribute("SidMistakes") or 0
	mistakes = mistakes + 1
	player:SetAttribute("SidMistakes", mistakes)

	local targetType = isNPCTarget and "NPC" or "frozen player"
	print("[ToyStory EventSetup] Sid made a mistake (hit " .. targetType .. ")! Total mistakes:", mistakes)

	-- Play buzzer sound
	local head = char:FindFirstChild("Head")
	if head then
		Utils.PlayOneShot(head, "rbxassetid://4798150495", 0.8)
	end

	-- If NPC, shatter it dramatically
	if isNPCTarget then
		for _, desc in targetToy:GetDescendants() do
			if desc:IsA("JointInstance") or desc:IsA("WeldConstraint") then
				desc:Destroy()
			end
		end

		local rng = Random.new()
		for _, desc in targetToy:GetDescendants() do
			if desc:IsA("BasePart") then
				desc.CanCollide = true
				desc.Anchored = false
				local impulse = Vector3.new(rng:NextNumber(-10, 10), rng:NextNumber(10, 20), rng:NextNumber(-10, 10))
				desc.AssemblyLinearVelocity = impulse
			end
		end

		game:GetService("Debris"):AddItem(targetToy, 5)
	end

	-- Stun Sid for 3 seconds
	local stunHunterEvent = Utils.GetOrCreateRemoteEvent(eventsFolder, "StunHunter")
	stunHunterEvent:FireClient(player, 3)

	local root = char:FindFirstChild("HumanoidRootPart")
	if root then
		root.Anchored = true
		task.delay(3, function()
			if char and char.Parent then
				root.Anchored = false
			end
		end)
	end

	-- Trigger distorted vision on 2nd mistake
	if mistakes == 2 then
		player:SetAttribute("SidDistorted", true)
	end

	-- Game over for Sid on 3rd mistake
	if mistakes >= 3 then
		gameLoopManager.EndGame("Toys")
	end
end

return EventSetup
