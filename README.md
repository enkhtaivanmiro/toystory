# 🧸 ToyStory - Roblox Game Design & Architecture

Welcome to the **ToyStory** game project! This is a modular, high-performance Roblox game built using **Rojo** and **Luau**. The game is a hide-and-seek survival match between one giant hunter (**Sid**) and multiple **Toys** (Woody, Buzz, Slinky, Mr. Potato Head, and Rex).

---

## 🎮 Game Rules & Round Flow

A single round is structured with strict phase transitions, objective trackers, and team win conditions:

1. **Preparation Phase (20 seconds)**
   - Sid is locked in place and blinded by a blackout screen (`TOYS ARE HIDING...`).
   - Toys have 20 seconds to run, find hiding spots, and locate Mrs. Potato Head's parts.
2. **Search Phase (5 minutes / 300 seconds)**
   - Sid is released and starts looking for moving toys.
   - Toys must complete their tasks while avoiding detection.
   - **Sid (Hunter) Wins** if:
     - All toys are captured and placed in the cage before the 5-minute timer runs out.
     - The 5-minute timer expires and the toys have not completed their task.
   - **Toys Win** if:
     - They find and assemble **all 3 missing parts** of Mrs. Potato Head.
3. **Ended Phase (15 seconds)**
   - Cooldown period. All players are locked, and the winner is displayed on the HUD.
   - A new game automatically prepares if there are 2 or more players present.

---

## 🛠️ Code Architecture

The codebase is split into decoupled, single-responsibility client, server, and shared modules to prevent circular dependencies and code duplication.

### 📂 File Structure & Responsibilities

| Path | Environment | Purpose |
|---|---|---|
| `src/server/init.server.luau` | Server | **Server Orchestrator**: Handles player connections, character swap lifecycle, and triggers sub-system initializations. |
| `src/server/CharacterRigger.luau` | Server | **Rigging Engine**: Converts static visual model templates into fully animated, scalable standard R6 playable characters. |
| `src/server/AutoGrouper.luau` | Server | **Spatial Segmenter**: Programmatically groups unstructured visual parts of complex models (Slinky, Mr. Potato Head, Sid) into standard R6 limb groups. |
| `src/server/EventSetup.luau` | Server | **Network Event Dispatcher**: Sets up and binds RemoteEvents for flashlight, wings, freezes, and capture mechanics. |
| `src/server/GameLoopManager.luau` | Server | **Match State Machine**: Handles match timer, phase switching, hunter locking, and checks win/loss conditions. |
| `src/server/NpcSpawner.luau` | Server | **Camouflage System**: Spawns static, lifeless NPC toys with randomized lay-down poses to confuse the hunter. |
| `src/server/ObjectiveManager.luau` | Server | **Task Controller**: Spawns Mrs. Potato Head parts, configures assembly prompts, and manages victory triggers. |
| `src/server/RescueManager.luau` | Server | **Capture & Carrying Handler**: Manages welding captured toys to Sid, cage deposits, health decay, and rescue promotions. |
| `src/shared/CharacterConfig.luau` | Shared | **Stat Database**: Contains custom height, speeds, lean angles, limb overlaps, and animation IDs for all 6 characters. |
| `src/shared/Utils.luau` | Shared | **Utility Box**: Shared algorithms for RemoteEvent instancing, one-shot audio, and 3D bounding box calculations. |
| `src/shared/CharacterAnimate.client.luau` | Client | **Local Anim Core**: Drives custom R6 animation state machines, sprinting, and forward lean interpolation. |
| `src/shared/FlightController.luau` | Client | **Buzz Flight Controller**: Manages active flying, gliding physics, landing detection, and fuel/cooldown HUD progression. |
| `src/shared/ProximityEffects.luau` | Client | **Sensory Immersion**: Drives heartbeat volume scaling, screen shake, land noise attributes, and surface-dependent footstep sound effects. |
| `src/shared/SidCombatController.luau` | Client | **Sid Attack System**: Handles click capture input raycasting, mistake penalties, and distortion vignetting. |
| `src/shared/LayDownController.luau` | Client | **Play Dead Controller**: Randomizes freeze poses and interpolates local RootJoint rotation. |
| `src/client/GameLoopUI.client.luau` | Client | **Universal UI HUD**: Renders the glassmorphic top header timer, phase status, victory cards, and team objective text. |
| `src/client/HunterController.client.luau` | Client | **Sid Action Controller**: Manages Sid's flashlight, blackout frame, and Q-Listen sonar radar. |

---

## 🕹️ Core Game Mechanics

### 1. Click Capture & Carrying System
When Sid (the giant hunter) clicks `Mouse 1` (handled in `SidCombatController.luau`):
- A client-side camera raycast shoots **`1000` studs** to guarantee targets register even when zoomed out.
- If it hits a part, the script climbs up the parent tree until it locates the top-level toy model.
- If the toy is close enough (**within 75 studs** of Sid's waist to account for his height), the server is notified via `CaptureToy`.
- If the toy is currently moving (not frozen/laying down):
  - The toy's parts are set to non-collidable (so they don't block Sid's movement).
  - The toy's humanoid is set to `PlatformStand = true` (disabling their local physics controls).
  - A `WeldConstraint` is created on the server to weld the toy's root part directly to Sid's **Right Arm**, making Sid carry them around in his hand.
  - A background loop checks Sid's position. When Sid walks **within 15 studs of the cage (`CAGE_POSITION`)**, the weld is destroyed, the toy is teleported inside, anchored, and default collision states are restored.
  - While carried or in the cage, a teammate can run up to the toy and trigger a **3-second Hold ProximityPrompt** to rescue them, releasing them immediately.

### 2. Mrs. Potato Head Assembly Objective
The Toys' primary objective is to find and assemble Mrs. Potato Head:
- **Assembly Target**: Spawns in the center of the playroom (`RC_CAR_POSITION`). Visually rendered as a potato-brown body part wearing a large red hat, with a ProximityPrompt labeled `Mrs. Potato Head`.
- **Collectible Parts**: Spawns **5 random components** across the floor. The parts are visually distinguished:
  - *Eyes* (Blue spheres)
  - *Ears* (Pink blocks)
  - *Lips* (Red cylinders)
  - All parts feature a PointLight glow making them easier to spot.
- **Carrying**: A toy player can pick up a part using a ProximityPrompt. The part is welded onto the player's back (`CarriedPart`) and blocks them from picking up another.
- **Assembly**: Depositing **3 parts** into Mrs. Potato Head immediately triggers the Toys' victory card and terminates the round.

### 3. Play-Dead Camouflage & Server Replication
To hide from Sid, toys can press **F** or **Mouse 1** to "play dead" and lay down:
- The character plays no animations and physics collisions are disabled to prevent fling glitches.
- A random pose is selected: *Face Down*, *Back Down*, *Left Side*, or *Right Side*.
- **Local Client**: The local client interpolates their own character's `RootJoint.C0` every frame on `RenderStepped` for a smooth transition.
- **Server Replication**: Roblox does not replicate joint `C0`/`C1` changes from client to server. To ensure other players see the toy laying down:
  - The client fires `SetFreezeState` passing their pose.
  - The server calculates the character's bounding dimensions and sets the character's `RootJoint.C0` to the target lay-down CFrame on the server.
  - This replicates the rotation to everyone else's screen.
  - If Sid attacks a player who is currently laying down, it registers as a **Mistake**, stunning Sid for 3 seconds and blurring his vision.

### 4. Sid's Q-Listen Ability
Pressing **Q** activates Sid's focus listening ability:
- Sid is anchored in place and a deep breathing sound plays.
- The screen gets covered by a heavy dark red vignette.
- For 3 seconds, a heartbeat loop connects. Any toy player within **90 studs** who is moving (or has landed heavily, triggering the `LandedNoise` attribute) will display a pulsing red circle `BillboardGui` directly over their model, showing their location through obstacles.
- After 3 seconds, Sid is unanchored and the ability goes on a **12-second recharge cooldown** (visualized on the HUD).

### 5. Proximity Auditory & Visual FX
To build tension, toy characters experience proximity-based feedback:
- **Heartbeat Loop**: If Sid is within 80 studs, a heartbeat loop plays. The volume and speed scale dynamically the closer Sid gets.
- **Footstep Screen Shake**: If Sid is within 60 studs and moving, the toy's camera shakes. The shake intensity scales dynamically.
- **Dynamic Surface Footsteps**: Footstep sounds scale depending on the ground material:
  - *Quiet (0.2x)*: Fabric, Sand, Grass (carpet/soft surfaces)
  - *Moderate (0.65x)*: Wood, WoodPlanks
  - *Loud (1.0x)*: Concrete, Metal, DiamondPlate
  - *Extremely Loud (1.5x)*: Plastic, SmoothPlastic

---

## 🚀 Building & Synchronizing

To build the Roblox place from the source code, open your terminal and run:

```bash
rojo build -o "ToyStory.rbxl"
```

Next, open the generated `ToyStory.rbxl` file in Roblox Studio and run the Rojo server to start live-syncing your code changes:

```bash
rojo serve
```