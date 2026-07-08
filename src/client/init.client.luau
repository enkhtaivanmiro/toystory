--[[
	ToyStory - Client Camera Script
	Handles camera setup for any custom avatar character selection.
]]

local Players = game:GetService("Players")
local player = Players.LocalPlayer

--- Set up the camera to properly follow the character
local function setupCamera(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 30)
	local rootPart = character:WaitForChild("HumanoidRootPart", 30)

	if not humanoid or not rootPart then
		return
	end

	local camera = workspace.CurrentCamera
	camera.CameraSubject = humanoid
	camera.CameraType = Enum.CameraType.Custom

	print("[ToyStory Client] Camera set up for character:", character.Name)
end

-- Listen for character changes
player.CharacterAdded:Connect(function(character)
	-- Wait a moment - if this is the default character, it will be destroyed soon
	task.wait(1)
	if player.Character == character then
		setupCamera(character)
	end
end)

-- Handle existing character
if player.Character then
	task.spawn(function()
		task.wait(1)
		if player.Character then
			setupCamera(player.Character)
		end
	end)
end

print("[ToyStory Client] Client camera system loaded!")
