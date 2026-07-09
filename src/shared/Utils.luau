--[[
	ToyStory - Shared Utilities Module
	Provides common helper functions used across multiple server and client modules.
	Eliminates duplication of RemoteEvent creation, one-shot sound playback,
	and model bounds calculations.
]]

local Debris = game:GetService("Debris")

local Utils = {}

--- Finds or creates a RemoteEvent inside a given folder.
--- Deduplicates the find-or-create pattern used throughout the codebase.
function Utils.GetOrCreateRemoteEvent(folder: Folder, name: string): RemoteEvent
	local event = folder:FindFirstChild(name)
	if not event then
		event = Instance.new("RemoteEvent")
		event.Name = name
		event.Parent = folder
	end
	return event :: RemoteEvent
end

--- Plays a one-shot sound on a given parent part, auto-destroying after playback.
--- Deduplicates the repeated pattern of creating, playing, and debris-cleaning a Sound.
function Utils.PlayOneShot(parent: Instance, soundId: string, volume: number?, playbackSpeed: number?)
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume or 0.8
	if playbackSpeed then
		sound.PlaybackSpeed = playbackSpeed
	end
	sound.Parent = parent
	sound:Play()
	Debris:AddItem(sound, 3)
end

--- Calculates the full 3D extents (width, height, depth) of a model by scanning all BaseParts.
--- Used by NpcSpawner for pose positioning and CharacterAnimate for lay-down offsets.
function Utils.GetModelExtents(model: Model): Vector3
	local minX, minY, minZ = math.huge, math.huge, math.huge
	local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge

	for _, desc in model:GetDescendants() do
		if desc:IsA("BasePart") then
			local pos = desc.CFrame.Position
			local half = desc.Size / 2
			minX = math.min(minX, pos.X - half.X)
			maxX = math.max(maxX, pos.X + half.X)
			minY = math.min(minY, pos.Y - half.Y)
			maxY = math.max(maxY, pos.Y + half.Y)
			minZ = math.min(minZ, pos.Z - half.Z)
			maxZ = math.max(maxZ, pos.Z + half.Z)
		end
	end

	return Vector3.new(maxX - minX, maxY - minY, maxZ - minZ)
end

--- Calculates the bounding box height (minY, maxY) of a model.
--- Used by CharacterRigger for scaling characters to target height.
function Utils.GetModelBoundsY(model: Model): (number, number)
	local minY = math.huge
	local maxY = -math.huge

	for _, desc in model:GetDescendants() do
		if desc:IsA("BasePart") then
			local pos = desc.CFrame.Position
			local halfY = desc.Size.Y / 2
			minY = math.min(minY, pos.Y - halfY)
			maxY = math.max(maxY, pos.Y + halfY)
		end
	end

	return minY, maxY
end

return Utils
