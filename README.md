# Hide & Seek

Development handoff and current-state reference for the Roblox experience. This file is intended to give a new chat enough context to continue development safely without reconstructing the project from conversation history.

Last live audit: **2026-08-05** using the connected Roblox Studio MCP, with the Match place confirmed in Edit mode.

## Important: source ownership

The experience now has separate Lobby and Match places and uses a hybrid Rojo workflow. Files in this repository are the source of truth for Match gameplay scripts, the round-state remote and attributes, the round HUD, and locked first-person camera configuration. The evolving 3D map, Lighting, Terrain, Lobby content, and other unlisted Studio instances remain authored in Roblox Studio.

- `match.project.json` targets the Match place and declares the React mount point, packages, and `ReplicatedStorage.RoundState` hierarchy.
- `lobby.project.json` targets the Lobby place and owns the temporary playtest teleport button, request remote, and server handler.
- Both project files deliberately set `$ignoreUnknownInstances` for Studio-owned services. Do not remove those safeguards unless the corresponding place content has first been exported into filesystem-owned models.
- `src/match/ServerScriptService/RoundController.server.luau` owns the server round controller.
- `src/match/StarterGui/RoundApp.luau` owns the React-Lua HUD component and client behavior.
- `src/match/StarterGui/RoundUI.client.luau` mounts the React tree.
- `src/match/ServerScriptService/ReturnToLobby.server.luau` handles individual requests to return from Match to Lobby.
- `src/lobby/ServerScriptService/TestTeleport.server.luau` teleports the current Lobby roster to the Match place when requested.
- `src/lobby/StarterGui/TestTeleport.client.luau` creates the temporary bottom-center teleport button.
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

The game has a server-authoritative round state machine with four sequential phases:

```text
WaitingToStart -> SelectingRoles -> Hiding -> Seeking
       ^                                      |
       +------------ round reset -------------+
```

### 1. WaitingToStart

- This is the first phase of every initial or reset round.
- The timer is hidden.
- With fewer than two connected players, the HUD displays **WAITING FOR PLAYERS** and `Need at least 2 players`.
- With at least two connected players, the HUD displays **ROUND STARTING** and the replicated five-second startup countdown.
- A player joining or leaving while waiting cancels and restarts the countdown so direct Studio test clients have time to connect.
- No world interaction, Lobby data, teleport data, or `SeekerSpot` proximity is required.
- When the countdown expires, the server shuffles and locks the connected roster, selects exactly one seeker and up to four hiders, and begins the synchronized role-selection reveal.
- If more than five players are connected, the remaining shuffled players become spectators at `WaitingSpawn`.

### 2. SelectingRoles

- The server chooses the authoritative seeker and role/spawn assignments before the animation, but does not replicate active-player `Role` attributes or move characters yet.
- Every client receives the same shuffled candidate UserIds, selected seeker UserId, five-second duration, and server-clock end time.
- The HUD replaces the normal phase display with an avatar-headshot roulette. Its highlight cycles rapidly, decelerates with quadratic ease-out, and lands on the server-selected seeker.
- Player icons are loaded through Roblox avatar-thumbnail URLs; compact cards are used on touch devices.
- Studio Server & Clients test players use synthetic negative UserIds with no Roblox avatar thumbnail. Their cards fall back to readable `P1`, `P2`, and similar badges; real players still show account headshots when thumbnails load.
- When the five-second reveal ends, the server publishes roles, moves players to their assigned spawns, locks the seeker at the holding marker, and enters Hiding.
- Reset, a seeker departure, or the final hider departing cancels the pending reveal through the same generation token used by other round work.

### 3. Hiding

- Default duration: **30 seconds**.
- A large synchronized countdown appears at the top center of the screen.
- The last five seconds turn red and pulse.
- The seeker waits at `SeekerHoldingSpawn`; hiders occupy unique, shuffled markers beneath `HiderSpawns`; spectators remain at `WaitingSpawn`.
- While Hiding, the server anchors the seeker's `HumanoidRootPart` at the holding marker so temporary or open holding areas cannot be escaped. The root is unanchored before release, on reset, and when assignments are cleared.
- When the countdown finishes, the server moves the seeker to `SeekerReleaseSpawn` and changes the phase to `Seeking`.

### 4. Seeking

- The HUD displays **SEEKING**.
- The countdown is hidden.
- This phase currently lasts indefinitely.
- The only way to leave Seeking is to reset the round.
- Late joiners become spectators and are kept at `WaitingSpawn` rather than joining the active round.

### Reset behavior

- Any player can reset because all current users are treated as playtesters.
- Resets are sent to the server through `ResetRequested` and are debounced for one second.
- Reset increments `RoundNumber` and the controller generation, cancelling either startup or Hiding countdown work.
- It clears server role/spawn assignments and every player's replicated `Role` attribute, resets both timers, returns remaining characters to `WaitingSpawn`, and enters `WaitingToStart`.
- If at least two players remain, reset automatically schedules a completely new random role selection after the normal startup delay.
- If the active seeker leaves, or the last active hider leaves, the server performs the same reset. One hider leaving while another remains does not end the round; spectators leaving have no round effect.

## Player controls

### Desktop

- `WASD`: move.
- Mouse: look around in first person.
- Hold `Left Alt`: temporarily unlock and show the cursor so UI buttons can be clicked.
- Release `Left Alt`: return to locked first-person mouse control.
- Hold `R` for one second: reset the round. The hold requirement reduces accidental resets.
- The **RESET ROUND** button is also available at the top right.
- The smaller **BACK TO LOBBY** button beneath reset returns only the clicking player to the Lobby.

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
| `StartTimeRemaining` | `0` | Replicated automatic-start countdown. Runtime-owned by the server. |
| `ConnectedPlayers` | `0` | Replicated connected-player count for waiting HUD feedback. Runtime-owned by the server. |
| `RoleSelectionDuration` | `5` | Replicated roulette duration in seconds. Runtime-owned by the server constant. |
| `RoleSelectionEndTime` | `0` | Server-clock deadline used to synchronize roulette animation. Runtime-owned by the server. |
| `SelectionUserIds` | empty | Comma-separated candidate UserIds in shuffled display order. Runtime-owned by the server. |
| `SelectedSeekerUserId` | `0` | Server-selected roulette target. Runtime-owned by the server. |
| `RoundNumber` | `0` in Edit mode | Incremented whenever a round is initialized or reset. |
| `HidingDuration` | `30` | Hiding duration in seconds. Minimum effective value is 1. |

Other constants currently live in scripts:

- Minimum players: `2` in `RoundController`.
- Maximum hiders: `4`; maximum active round players: `5` in `RoundController`.
- Automatic-start delay: `5` seconds in `RoundController`.
- Role-selection reveal: `5` seconds in `RoundController`.
- Server reset debounce: `1` second in `RoundController`.
- Desktop `R` hold duration: `1` second in `RoundApp`.

## Studio hierarchy and ownership

```text
ReplicatedStorage
├── Packages (Wally-managed React dependencies)
└── RoundState (Folder)
    ├── attributes: Phase, TimeRemaining, StartTimeRemaining,
    │              ConnectedPlayers, RoleSelectionDuration,
    │              RoleSelectionEndTime, SelectionUserIds,
    │              SelectedSeekerUserId, RoundNumber, HidingDuration
    ├── ResetRequested (RemoteEvent)
    └── ReturnToLobbyRequested (RemoteEvent)

ServerScriptService
├── RoundController (Script)
└── ReturnToLobby (Script)

StarterPlayer
└── CameraMode = LockFirstPerson

StarterGui
└── RoundGui (ScreenGui; ResetOnSpawn = false)
    ├── ReactRoot (Frame; runtime mount point)
    ├── RoundApp (ModuleScript)
    └── RoundUI (LocalScript bootstrap)

During Play, React creates the normal phase/role/timer HUD plus `SelectionOverlay`, its roulette candidate cards, `ResetButton`, and `ControlsGuide` beneath `ReactRoot`.

Workspace
├── Terrain
├── SpawnLocation
├── Baseplate
├── Camera
├── Obstacles
│   ├── SeekerSpot (retained map object; no startup behavior)
│   └── many prototype obstacle Parts
└── RoundSpawns (Folder or Model)
    ├── WaitingSpawn (BasePart)
    ├── SeekerHoldingSpawn (BasePart)
    ├── SeekerReleaseSpawn (BasePart)
    └── HiderSpawns (Folder or Model)
        ├── Hider1 (BasePart)
        ├── Hider2 (BasePart)
        ├── Hider3 (BasePart)
        └── Hider4 (BasePart)
```

### `ServerScriptService.RoundController`

Responsibilities:

- Own all authoritative phase transitions.
- Validate the Studio-owned `RoundSpawns` hierarchy and normalize markers to anchored, invisible, non-collidable, non-touchable, non-queryable parts.
- Run and cancel automatic-start, role-selection, and Hiding countdown work using one generation token.
- Shuffle the roster with one server-created `Random`, assign one seeker, up to four hiders, and any overflow spectators, and replicate each role through the player's `Role` attribute.
- Keep authoritative role and hider-spawn assignments on the server, including unique shuffled hider markers.
- Reposition characters on assignment and respawn using each marker's full `CFrame` plus a small vertical offset.
- Reset when the seeker or final hider leaves, while allowing rounds to continue after spectator departures or a non-final hider departure.
- Replicate state through `RoundState` attributes.
- Accept playtester reset requests with server-side debounce.

The server script intentionally fails startup validation when required spawn containers/markers are absent or when fewer than four BasePart hider markers exist. It does not inspect or reference `SeekerSpot`.

### `StarterGui.RoundGui.RoundApp`

Responsibilities:

- Render all three phase states from replicated attributes.
- Show/hide the Hiding timer and distinguish waiting-for-players from automatic-start countdown state.
- Display the local player's replicated assignment as `You are the seeker`, `You are hiding`, or `You are spectating` throughout the active round.
- Show role-specific phase prompts: seekers see `WAIT FOR PLAYERS TO HIDE` then `FIND THEM!`; hiders see `GO HIDE!` then `STAY OUT OF SIGHT OF THE SEEKER`.
- Render the synchronized avatar roulette during `SelectingRoles`, with a server-clock-driven ease-out that lands on the authoritative seeker.
- Pulse the final five countdown values.
- Send reset requests from the reset button or held `R` key.
- Send individual return requests from the secondary **BACK TO LOBBY** button.
- Manage Alt-based desktop cursor interaction.
- Display the discreet bottom-left controls guide on keyboard devices.
- Apply the macOS first-person cursor startup/respawn refresh.

Clients do not choose or submit roles, decide phase transitions, or directly mutate server state.

## Round spawn markers

The connected Match place now contains the required marker hierarchy. The markers created during the 2026-08-05 implementation pass use safe, non-overlapping **temporary** positions:

| Marker | Temporary position `(X, Y, Z)` |
| --- | --- |
| `WaitingSpawn` | `(0, 1, 0)` |
| `SeekerHoldingSpawn` | `(0, 1, -15)` |
| `SeekerReleaseSpawn` | `(0, 1, 15)` |
| `Hider1` | `(-30, 1, 40)` |
| `Hider2` | `(-10, 1, 40)` |
| `Hider3` | `(10, 1, 40)` |
| `Hider4` | `(30, 1, 40)` |

- A map designer must deliberately reposition and orient all seven markers for the final waiting area, seeker enclosure/release point, and hiding map.
- Marker `CFrame` orientation controls the direction a respawned character faces.
- Every marker is currently a `4 x 1 x 4` anchored Part with transparency `1` and collision, touch, and query disabled.
- `Workspace.Obstacles.SeekerSpotTriggerDecal` was removed from the connected Match place because it served only the obsolete activation boundary.
- `Workspace.Obstacles.SeekerSpot` was retained as a visible map object because inspection did not prove it had no remaining map purpose. The controller no longer references it.
- Studio-owned changes must be saved or published from Studio; Rojo builds do not contain these map markers.

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

## Validation and direct Studio testing

Filesystem validation for this implementation includes both `rojo sourcemap match.project.json` and `rojo build match.project.json`. Because the spawn hierarchy is Studio-owned, normal testing must use Rojo live sync against the existing Match place rather than treating the filesystem-only build as a complete map.

A one-client Play check on 2026-08-05 confirmed that the updated controller and HUD load without console errors, remain in `WaitingToStart`, keep `Role` clear, place the character at `WaitingSpawn`, replicate `ConnectedPlayers = 1`, and display **WAITING FOR PLAYERS** / `Need at least 2 players`. The available Studio bridge does not launch multi-client Server & Clients sessions, so the following multiplayer matrix remains a manual Studio check.

Use Studio's **Server & Clients** test mode with two through five clients. The five-second startup delay is specifically intended to absorb asynchronous test-client connections. Verify:

- One client remains in `WaitingToStart` indefinitely and every waiting character uses `WaitingSpawn`.
- Two through five clients produce exactly one `Seeker`, between one and four `Hider` attributes, no spectators, and unique hider marker assignments.
- A waiting roster change restarts the startup countdown; dropping below two cancels it.
- After startup, all clients show the same candidate icons for five seconds, slow onto the selected seeker, and receive no active role attribute until the reveal completes.
- The seeker begins at `SeekerHoldingSpawn` and moves to `SeekerReleaseSpawn` before Seeking begins.
- A reset clears role attributes, moves everyone to `WaitingSpawn`, and automatically schedules a fresh random selection when at least two players remain.
- Respawning returns a participant to the spawn appropriate for their current role and phase.
- A seeker departure or final-hider departure resets; one hider leaving while another remains continues; spectator departure does not affect the round.
- Late joiners during Hiding or Seeking receive `Spectator` and stay at `WaitingSpawn`.
- No transition depends on touching, approaching, or retaining `SeekerSpot`.

For overflow testing above five players, verify that only five shuffled players are active and all remaining players are spectators. This exceeds the requested two-to-five-client baseline.

## Known missing gameplay

The project has a round shell, not yet a complete hide-and-seek game. The following systems do not currently exist:

- Tag/catch mechanics.
- Hider elimination and promotion to spectator after being caught.
- Win conditions and automatic end-of-round behavior.
- A timed Seeking phase.
- Dedicated spectator camera/UI behavior beyond the replicated role and waiting-area spawn.
- Multiple maps or map rotation.
- Scores, rewards, persistence, badges, or data stores.
- Sound effects, music, or phase announcements.
- Production authorization rules for resetting; all players can currently reset.

## Recommended next development steps

1. Deliberately position and orient the temporary waiting, seeker, and hider markers in the final map layout.
2. Run two-to-five-client Server & Clients tests after syncing the Match project.
3. Implement server-authoritative tagging and elimination.
4. Add a Seeking duration and win conditions.
5. Restrict reset access before inviting non-playtesters.
6. Rename generic obstacle parts or group them into maintainable models.
7. Add audio and clearer feedback for phase transitions.
8. Gradually rename generic obstacle parts and export stable map sections into Rojo-owned `.rbxm`/`.rbxmx` models when they stop changing rapidly.

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
