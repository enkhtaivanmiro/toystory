--[[
	ToyStory - SidCombatController (ModuleScript)
	Handles all Sid-specific client mechanics: attack/capture click input,
	mistake counter GUI, stun effect handler, and distorted vision penalty.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local eventsFolder = ReplicatedStorage:WaitForChild("Events")
local localPlayer = Players.LocalPlayer

local SidCombatController = {}

--- Initialize all Sid combat systems.
function SidCombatController.Init(
	character: Model,
	rootPart: BasePart,
	humanoid: Humanoid,
	playerGui: PlayerGui,
	tracks: { [string]: AnimationTrack },
	animWeight: number,
	getCurrentTrack: () -> (AnimationTrack?, string),
	setCurrentTrack: (track: AnimationTrack?, name: string) -> (),
	updateMovementState: (speed: number) -> ()
)
	local camera = workspace.CurrentCamera
	local mouse = localPlayer:GetMouse()

	-- ========================================
	-- Mistakes GUI
	-- ========================================
	local mistakesGui = Instance.new("ScreenGui")
	mistakesGui.Name = "SidMistakesGui"
	mistakesGui.ResetOnSpawn = true

	local label = Instance.new("TextLabel")
	label.Name = "MistakesLabel"
	label.Size = UDim2.new(0, 300, 0, 50)
	label.Position = UDim2.new(0.5, -150, 0.05, 0)
	label.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
	label.BackgroundTransparency = 0.3
	label.TextColor3 = Color3.fromRGB(255, 75, 75)
	label.Font = Enum.Font.FredokaOne
	label.TextSize = 22
	label.Text = "MISTAKES: 0 / 3"
	label.Parent = mistakesGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = label

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 75, 75)
	stroke.Thickness = 1.5
	stroke.Parent = label

	mistakesGui.Parent = playerGui

	-- Listen for mistake updates from server
	localPlayer:GetAttributeChangedSignal("SidMistakes"):Connect(function()
		local mistakes = localPlayer:GetAttribute("SidMistakes") or 0
		label.Text = string.format("MISTAKES: %d / 3", mistakes)
		if mistakes >= 3 then
			label.TextColor3 = Color3.fromRGB(255, 0, 0)
			label.Text = "GAME OVER - TOO MANY MISTAKES!"
		end
	end)

	-- ========================================
	-- Attack Animation
	-- ========================================
	local lastAttackTime = 0

	local function playAttackAnimation()
		local track = tracks["attack"]
		if track then
			local currentTrack, _ = getCurrentTrack()
			if currentTrack then
				currentTrack:Stop(0.1)
			end

			setCurrentTrack(track, "attack")
			track:Play(0.1, animWeight)

			-- Once attack finishes, resume idle/walk animation state
			task.delay(track.Length > 0 and track.Length or 0.6, function()
				local _, currentName = getCurrentTrack()
				if currentName == "attack" then
					setCurrentTrack(nil, "")
					local speed = rootPart and rootPart.AssemblyLinearVelocity.Magnitude or 0
					updateMovementState(speed)
				end
			end)
		end
	end

	-- ========================================
	-- Attack/Capture Click Input
	-- ========================================
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end

		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			local now = os.clock()
			if now - lastAttackTime < 0.8 then
				return
			end -- Attack cooldown
			lastAttackTime = now

			-- Play attack animation locally
			playAttackAnimation()

			-- Raycast from mouse to find clicked character
			local ray = camera:ScreenPointToRay(mouse.X, mouse.Y)
			local raycastParams = RaycastParams.new()
			raycastParams.FilterDescendantsInstances = { character }
			raycastParams.FilterType = Enum.RaycastFilterType.Exclude

			local result = workspace:Raycast(ray.Origin, ray.Direction * 150, raycastParams)
			if result and result.Instance then
				-- Find character model
				local targetModel = result.Instance:FindFirstAncestorOfClass("Model")
				if targetModel and targetModel:GetAttribute("IsCustomCharacter") then
					local targetName = targetModel:GetAttribute("CharacterName")
					if targetName and targetName ~= "Sid" then
						-- Range check: Sid must be close enough (50 studs)
						local dist = (rootPart.Position - result.Position).Magnitude
						if dist <= 50 then
							-- Request capture
							local captureToyEvent = eventsFolder:FindFirstChild("CaptureToy")
							if captureToyEvent then
								captureToyEvent:FireServer(targetModel)
							end
						end
					end
				end
			end
		end
	end)

	-- ========================================
	-- Stun Effect Handler
	-- ========================================
	local stunEvent = eventsFolder:WaitForChild("StunHunter", 8)
	if stunEvent then
		stunEvent.OnClientEvent:Connect(function(duration)
			local stunGui = Instance.new("ScreenGui")
			stunGui.Name = "StunGui"

			local text = Instance.new("TextLabel")
			text.Size = UDim2.new(0, 450, 0, 80)
			text.Position = UDim2.new(0.5, -225, 0.4, -40)
			text.BackgroundColor3 = Color3.fromRGB(10, 10, 15)
			text.BackgroundTransparency = 0.2
			text.TextColor3 = Color3.fromRGB(231, 76, 60)
			text.Font = Enum.Font.FredokaOne
			text.TextSize = 32
			text.Text = "STUNNED (MISTAKE PENALTY)!"
			text.Parent = stunGui

			local stunCorner = Instance.new("UICorner")
			stunCorner.CornerRadius = UDim.new(0, 12)
			stunCorner.Parent = text

			local stunStroke = Instance.new("UIStroke")
			stunStroke.Color = Color3.fromRGB(231, 76, 60)
			stunStroke.Thickness = 2
			stunStroke.Parent = text

			stunGui.Parent = playerGui

			-- Camera shake during stun
			local start = os.clock()
			local connection
			connection = RunService.RenderStepped:Connect(function()
				local elapsed = os.clock() - start
				if elapsed >= duration then
					connection:Disconnect()
					stunGui:Destroy()
				else
					local shake = Vector3.new(
						math.random(-10, 10) * 0.06,
						math.random(-10, 10) * 0.06,
						0
					)
					camera.CFrame = camera.CFrame * CFrame.new(shake)
				end
			end)
		end)
	end

	-- ========================================
	-- Distorted Vision (2nd mistake penalty)
	-- ========================================
	local lighting = game:GetService("Lighting")
	local blurEffect: BlurEffect? = nil
	local ccEffect: ColorCorrectionEffect? = nil

	localPlayer:GetAttributeChangedSignal("SidDistorted"):Connect(function()
		local distorted = localPlayer:GetAttribute("SidDistorted") or false
		if distorted then
			-- Apply heavy screen blur & color distortion
			if not blurEffect then
				blurEffect = Instance.new("BlurEffect")
				blurEffect.Size = 24
				blurEffect.Parent = camera
			end
			if not ccEffect then
				ccEffect = Instance.new("ColorCorrectionEffect")
				ccEffect.Saturation = -0.7
				ccEffect.Contrast = 0.5
				ccEffect.Parent = lighting
			end
		else
			-- Clean up effects
			if blurEffect then
				blurEffect:Destroy()
				blurEffect = nil
			end
			if ccEffect then
				ccEffect:Destroy()
				ccEffect = nil
			end
		end
	end)
end

return SidCombatController
