# Hide & Seek

Development handoff and current-state reference for the Roblox experience. This file is intended to give a new chat enough context to continue development safely without reconstructing the project from conversation history.

Last live audit: **2026-08-04** using the connected Roblox Studio MCP, with Studio in Edit mode.

## Important: source ownership

The experience now has separate Lobby and Match places and uses a hybrid Rojo workflow. Files in this repository are the source of truth for Match gameplay scripts, the round-state remote and attributes, the round HUD, and locked first-person camera configuration. The evolving 3D map, Lighting, Terrain, Lobby content, and other unlisted Studio instances remain authored in Roblox Studio.

- `match.project.json` targets the Match place and declares the React mount point, packages, and `ReplicatedStorage.RoundState` hierarchy.
- `lobby.project.json` targets the Lobby place and is intentionally minimal until lobby systems are implemented.
- Both project files deliberately set `$ignoreUnknownInstances` for Studio-owned services. Do not remove those safeguards unless the corresponding place content has first been exported into filesystem-owned models.
- `src/match/ServerScriptService/RoundController.server.luau` owns the server round controller.
- `src/match/StarterGui/RoundApp.luau` owns the React-Lua HUD component and client behavior.
- `src/match/StarterGui/RoundUI.client.luau` mounts the React tree.
- Add future Lobby-owned scripts beneath `src/lobby/` and map them explicitly in `lobby.project.json`.
- Studio changes still need to be saved or published by the developer.
- Before modifying either place through MCP, list connected Studio instances and confirm the active place by both name and Place ID.

## Rojo development

This repository pins Rojo 7.6.1 and Wally 0.3.2 with [Rokit](https://github.com/rojo-rbx/rokit). Wally locks React-Lua and ReactRoblox at 17.2.1. After installing Rokit and the matching Rojo 7 Studio plugin:

```sh
rokit install
wally install
rojo serve match.project.json
```

Open the corresponding place in Studio, then serve exactly one matching project file:

```sh
# Studio has Match (88216950471180) open
rojo serve match.project.json

# Studio has Lobby (98577386131530) open
rojo serve lobby.project.json
```

In Studio, open the Rojo plugin, connect to `localhost:34872`, inspect the proposed changes, and sync. Each project is restricted to its own place ID, reducing the chance of connecting it to the wrong place. Both places do not need to be open simultaneously. If they are, run the two Rojo servers on different ports.

Useful validation/build commands:

```sh
rojo sourcemap match.project.json --output match-sourcemap.json
rojo build match.project.json --output match.rbxlx
rojo sourcemap lobby.project.json --output lobby-sourcemap.json
rojo build lobby.project.json --output lobby.rbxlx
```

The built place contains the filesystem-owned systems only; use live sync against the existing Studio place for normal development because the map is intentionally Studio-owned.

## Experience identity

| Field | Value |
| --- | --- |
| Experience | `Hide & Seek` |
| Lobby place ID | `98577386131530` |
| Match place ID | `88216950471180` |
| Universe/Game ID | `10628256098` |
| Current development stage | Early playable prototype |
| Camera | Locked first person for all players |

## Current gameplay

The game has a server-authoritative round state machine with three sequential phases:

```text
WaitingToStart -> Hiding -> Seeking
       ^                        |
       +------ round reset -----+
```

### 1. WaitingToStart

- This is the first phase of every initial or reset round.
- The timer is hidden.
- The HUD displays **WAITING TO START** and `Approach SeekerSpot to begin`.
- Hiding starts when any player's character touches `SeekerSpot` or their `HumanoidRootPart` comes within the configured activation distance.
- Proximity is measured from the closest point on the oriented `SeekerSpot` bounding box, not only from its center.
- The server checks proximity every `0.15` seconds.

### 2. Hiding

- Default duration: **30 seconds**.
- A large synchronized countdown appears at the top center of the screen.
- The last five seconds turn red and pulse.
- When the countdown finishes, the server changes the phase to `Seeking`.

### 3. Seeking

- The HUD displays **SEEKING**.
- The countdown is hidden.
- This phase currently lasts indefinitely.
- The only way to leave Seeking is to reset the round.

### Reset behavior

- Any player can reset because all current users are treated as playtesters.
- Resets are sent to the server through `ResetRequested` and are debounced for one second.
- Reset increments `RoundNumber`, cancels an active countdown, clears the timer, and returns to `WaitingToStart`.
- If a player is still standing inside the SeekerSpot trigger area after a reset, the proximity check may immediately start Hiding again. Move players away first if a persistent waiting state is desired.

## Player controls

### Desktop

- `WASD`: move.
- Mouse: look around in first person.
- Hold `Left Alt`: temporarily unlock and show the cursor so UI buttons can be clicked.
- Release `Left Alt`: return to locked first-person mouse control.
- Hold `R` for one second: reset the round. The hold requirement reduces accidental resets.
- The **RESET ROUND** button is also available at the top right.

### Touch and gamepad

- The reset button uses `GuiButton.Activated`, which is cross-platform.
- The desktop controls guide is hidden when a keyboard is not available.
- Explicit gamepad selection/navigation configuration has not yet been added or comprehensively tested.

### macOS cursor handling

Roblox Studio on macOS was leaving the native cursor visible and centered when first-person mode initialized. `RoundApp` contains a startup/respawn workaround:

1. Wait `0.2` seconds for character and camera scripts to initialize.
2. Briefly cycle the button's `Modal`, `MouseIconEnabled`, and `MouseBehavior` states.
3. Finish with the cursor hidden and `MouseBehavior.LockCenter`.

The final `Modal = false` assignment is applied directly as well as through React state. This is intentional: at startup the React cursor state is already `false`, so React may skip a no-op state update and otherwise leave the temporary modal state enabled, blocking mouse-look until Alt is pressed once.

The same refresh runs after `CharacterAdded`. MCP verification confirmed the final Roblox properties, but user confirmation after the latest macOS-specific refresh is not recorded in this file.

## Configurable values

Select `ReplicatedStorage.RoundState` in Studio and edit its attributes:

| Attribute | Current value | Purpose |
| --- | ---: | --- |
| `Phase` | `WaitingToStart` | Replicated current phase. Runtime-owned by the server. |
| `TimeRemaining` | `0` | Replicated Hiding countdown. Runtime-owned by the server. |
| `RoundNumber` | `0` in Edit mode | Incremented whenever a round is initialized or reset. |
| `HidingDuration` | `30` | Hiding duration in seconds. Minimum effective value is 1. |
| `ActivationDistance` | `4` | Extra trigger distance in studs outside SeekerSpot's bounds. Minimum is 0. |

Other constants currently live in scripts:

- Server reset debounce: `1` second in `RoundController`.
- Proximity polling interval: `0.15` seconds in `RoundController`.
- Desktop `R` hold duration: `1` second in `RoundApp`.

## Studio hierarchy and ownership

```text
ReplicatedStorage
├── Packages (Wally-managed React dependencies)
└── RoundState (Folder)
    ├── attributes: Phase, TimeRemaining, RoundNumber,
    │              HidingDuration, ActivationDistance
    └── ResetRequested (RemoteEvent)

ServerScriptService
└── RoundController (Script)

StarterPlayer
└── CameraMode = LockFirstPerson

StarterGui
└── RoundGui (ScreenGui; ResetOnSpawn = false)
    ├── ReactRoot (Frame; runtime mount point)
    ├── RoundApp (ModuleScript)
    └── RoundUI (LocalScript bootstrap)

During Play, React creates `PhaseLabel`, `TimerLabel`, `StatusLabel`, `ResetButton`, and `ControlsGuide` beneath `ReactRoot`.

Workspace
├── Terrain
├── SpawnLocation
├── Baseplate
├── Camera
└── Obstacles
    ├── SeekerSpot
    ├── SeekerSpotTriggerDecal
    │   └── TriggerAreaDecal (SurfaceGui)
    │       └── AreaDisc (Frame with UICorner and UIStroke)
    └── many prototype obstacle Parts
```

### `ServerScriptService.RoundController`

Responsibilities:

- Own all authoritative phase transitions.
- Locate a descendant of Workspace named exactly `SeekerSpot` and assert that it is a `BasePart`.
- Detect both physical touches and nearby player roots.
- Run and cancel the Hiding countdown using a generation token.
- Replicate state through `RoundState` attributes.
- Accept playtester reset requests with server-side debounce.
- Resize and reposition the ground trigger marker from the SeekerSpot bounds and `ActivationDistance`.

The server script will intentionally fail its startup assertion if `SeekerSpot` is removed, renamed, or changed to a non-BasePart object.

### `StarterGui.RoundGui.RoundApp`

Responsibilities:

- Render all three phase states from replicated attributes.
- Show/hide the timer and waiting instruction.
- Pulse the final five countdown values.
- Send reset requests from the reset button or held `R` key.
- Manage Alt-based desktop cursor interaction.
- Display the discreet bottom-left controls guide on keyboard devices.
- Apply the macOS first-person cursor startup/respawn refresh.

Clients do not decide phase transitions or directly reset server state.

## SeekerSpot and trigger marker

Current SeekerSpot details:

| Property | Value |
| --- | --- |
| Path | `Workspace.Obstacles.SeekerSpot` |
| Class | `Part` |
| Shape/color | Bright-red vertical cylinder |
| Position | Approximately `(0.5, 5, -27.547)` |
| Size | `(10, 7, 9)` |
| Anchored | `true` |
| CanCollide / CanTouch / CanQuery | `true / true / true` |

The visible start boundary is an asset-free, decal-style ground marker:

- Path: `Workspace.Obstacles.SeekerSpotTriggerDecal`.
- Current size: `17 x 0.05 x 17` studs for the current SeekerSpot and four-stud activation distance.
- Invisible, anchored support part with `CanCollide`, `CanTouch`, and `CanQuery` disabled.
- A top-facing `SurfaceGui` draws a translucent amber disc and bright circular perimeter.
- The marker has no external image/asset dependency.
- `RoundController` recalculates it at server startup and whenever `ActivationDistance` changes.
- Moving or resizing SeekerSpot in Edit mode may leave the Edit-mode marker temporarily stale; starting Play causes the server to realign it.

## World and visual state

As of the last audit:

- `Workspace.Obstacles` had **44 direct children** and is actively evolving.
- Many map parts still use the generic name `Part`; do not rely on those names being unique.
- Baseplate: approximately `2048 x 16 x 2048`, centered at `(0, -8, 0)`.
- SpawnLocation: approximately `12 x 1 x 12`, centered at `(0, 0.5, 0)`.
- Workspace streaming is enabled.
- Gravity is the Roblox default, approximately `196.2` studs/s².
- Lighting contains `Sky`, `SunRays`, `Atmosphere`, `Bloom`, and `DepthOfField` effects.
- No game sounds were present in the latest audit.

Because the developer is modifying the map directly in Studio, refresh the hierarchy before making assumptions about obstacle counts or positions.

## Verified behavior

The following was tested through Roblox Studio Play mode:

- Player spawns successfully in locked first person.
- Waiting remains active while the player is away from SeekerSpot.
- Moving a player within the activation area changes Waiting to Hiding.
- The Hiding countdown replicates to the HUD.
- A temporary runtime-only three-second duration transitioned correctly to Seeking.
- Reset returned the game to Waiting when the player was moved away from SeekerSpot.
- The reset button was activated in a prior UI test and reached the server.
- Saved `HidingDuration` remained 30 after temporary runtime tests.
- The trigger marker rendered correctly during Play mode and matched the configured area.
- No game-script runtime errors were present in the latest checks.

Temporary Play-mode test values do not persist back into Edit mode.

## Known missing gameplay

The project has a round shell, not yet a complete hide-and-seek game. The following systems do not currently exist:

- Seeker selection or role assignment.
- Hider/seeker teams.
- Freezing, teleporting, hiding, or revealing players by phase.
- Tag/catch mechanics.
- Hider elimination or spectator mode.
- Win conditions and automatic end-of-round behavior.
- A timed Seeking phase.
- Minimum-player checks or a lobby population requirement.
- Multiple maps or map rotation.
- Scores, rewards, persistence, badges, or data stores.
- Sound effects, music, or phase announcements.
- Production authorization rules for resetting; all players can currently reset.

## Recommended next development steps

1. Decide how the seeker is selected when a player activates SeekerSpot.
2. Assign explicit seeker/hider roles on the server.
3. Add phase-specific spawning or movement rules.
4. Implement server-authoritative tagging and elimination.
5. Add a Seeking duration and win conditions.
6. Restrict reset access before inviting non-playtesters.
7. Rename generic obstacle parts or group them into maintainable models.
8. Add audio and clearer feedback for phase transitions.
9. Gradually rename generic obstacle parts and export stable map sections into Rojo-owned `.rbxm`/`.rbxmx` models when they stop changing rapidly.

## Workflow for a new chat

1. Read this README.
2. Use Roblox Studio MCP to list connected Studio instances.
3. Confirm the intended Lobby or Match place is active and in Edit mode before modifications.
4. Read the filesystem-owned `RoundController.server.luau`, `RoundApp.luau`, and `RoundUI.client.luau`; do not treat Studio copies of Rojo-managed scripts as authoritative.
5. Refresh `Workspace`, `ReplicatedStorage.RoundState`, and the target object before editing.
6. Preserve map changes and avoid recreating named systems unless explicitly needed.
7. Test meaningful state transitions in Play mode.
8. Stop Play mode and return Studio to Edit mode after verification.
9. Update this README when architecture, controls, phase rules, or important paths change.
