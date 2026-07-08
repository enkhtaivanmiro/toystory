--[[
	ToyStory - Character Configuration
	Defines configurations, stats, lean angles, and animation IDs for all playable characters.
]]

export type CharacterStats = {
	Height: number,
	WalkSpeed: number,
	RunSpeed: number,
	LeanAngle: number, -- in radians (negative = lean forward)
	Overlap: number, -- target overlap for joints (deeper overlap prevents gaps on thin limbs)
	AnimWeight: number, -- standard animation weight (lower weight reduces swing rotation)
	WingScale: number?, -- optional scale multiplier for special accessories like wings
	Animations: {
		idle: string,
		walk: string,
		run: string,
		jump: string,
		fall: string,
		climb: string,
	},
}

local CharacterConfig: { [string]: CharacterStats } = {
	Buzz = {
		Height = 7,
		WalkSpeed = 8,
		RunSpeed = 22,
		LeanAngle = math.rad(-15),
		Overlap = 0.35, -- standard overlap
		AnimWeight = 0.9, -- full normal swings
		WingScale = 3.0, -- scales the wing mesh size to be 3x larger to match chest ratio
		Animations = {
			idle = "rbxassetid://180435571",
			walk = "rbxassetid://180426354",
			run = "rbxassetid://180426354", -- custom speed scaling handles run
			jump = "rbxassetid://125750702",
			fall = "rbxassetid://180436148",
			climb = "rbxassetid://180436334",
		},
	},
	Woody = {
		Height = 7,
		WalkSpeed = 10,
		RunSpeed = 26,
		LeanAngle = math.rad(-15),
		Overlap = 0.05, -- very small overlap to keep the pivot at the exact boundary and prevent thin limbs from separating
		AnimWeight = 0.6, -- lower swing weight to keep Woody's lanky limbs connected
		Animations = {
			idle = "rbxassetid://180435571",
			walk = "rbxassetid://180426354",
			run = "rbxassetid://180426354",
			jump = "rbxassetid://125750702",
			fall = "rbxassetid://180436148",
			climb = "rbxassetid://180436334",
		},
	},
	Slinky = {
		Height = 5,
		WalkSpeed = 10,
		RunSpeed = 24,
		LeanAngle = math.rad(-5),
		Overlap = 0.25,
		AnimWeight = 0.85,
		Animations = {
			idle = "rbxassetid://180435571",
			walk = "rbxassetid://180426354",
			run = "rbxassetid://180426354",
			jump = "rbxassetid://125750702",
			fall = "rbxassetid://180436148",
			climb = "rbxassetid://180436334",
		},
	},
	PotatoHead = {
		Height = 5.5,
		WalkSpeed = 8,
		RunSpeed = 20,
		LeanAngle = math.rad(-10),
		Overlap = 0.15,
		AnimWeight = 0.75,
		Animations = {
			idle = "rbxassetid://180435571",
			walk = "rbxassetid://180426354",
			run = "rbxassetid://180426354",
			jump = "rbxassetid://125750702",
			fall = "rbxassetid://180436148",
			climb = "rbxassetid://180436334",
		},
	},
	Rex = {
		Height = 6,
		WalkSpeed = 9,
		RunSpeed = 22,
		LeanAngle = math.rad(-8),
		Overlap = 0.25,
		AnimWeight = 0.8,
		Animations = {
			idle = "rbxassetid://180435571",
			walk = "rbxassetid://180426354",
			run = "rbxassetid://180426354",
			jump = "rbxassetid://125750702",
			fall = "rbxassetid://180436148",
			climb = "rbxassetid://180436334",
		},
	},
	Sid = {
		Height = 31, -- Sid is giant compared to the toys
		WalkSpeed = 16,
		RunSpeed = 28,
		LeanAngle = math.rad(-5),
		Overlap = 0.15,
		AnimWeight = 0.8,
		Animations = {
			idle = "rbxassetid://180435571",
			walk = "rbxassetid://180426354",
			run = "rbxassetid://180426354",
			jump = "rbxassetid://125750702",
			fall = "rbxassetid://180436148",
			climb = "rbxassetid://180436334",
			attack = "rbxassetid://182393478",
		},
	},
}

return CharacterConfig
