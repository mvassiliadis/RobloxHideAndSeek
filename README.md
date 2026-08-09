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
- With fewer than two connected players, the HUD displays **WAITING FOR PLAYERS** and `Need at least 2 players`, except when Studio solo practice is enabled.
- With at least two connected players, the HUD displays **ROUND STARTING** and the replicated five-second startup countdown.
- A player joining or leaving while waiting cancels and restarts the countdown so direct Studio test clients have time to connect.
- No world interaction, Lobby data, teleport data, or `SeekerSpot` proximity is required.
- When the countdown expires, the server shuffles and locks the connected roster, selects exactly one seeker and up to four hiders, and begins the synchronized role-selection reveal.
- If more than five players are connected, the remaining shuffled players become spectators around `WaitingSpawn`.

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
- The seeker waits on the capture-area edge behind `SeekerHoldingSpawn`, facing the post; hiders occupy unique, shuffled markers beneath `HiderSpawns`; spectators remain in distinct slots around `WaitingSpawn`.
- While Hiding, the server anchors the seeker's `HumanoidRootPart` at that edge position so temporary or open holding areas cannot be escaped. The root is unanchored before release, on reset, and when assignments are cleared.
- The seeker's 3D view fades to black while the HUD and countdown remain visible, and mouse camera movement is locked for the full Hiding phase.
- When the countdown finishes, the server releases the seeker in place at the post indicator's edge and changes the phase to `Seeking`.

### 4. Seeking

- The seeker gets a center-screen crosshair and can point at a visible hider and left-click to tag them. On touch devices, the seeker can either aim with the crosshair and press the on-screen **TAG** button or tap a visible hider directly.
- Every active hider receives a server-generated, invisible, non-colliding full-body tag volume, so limbs, gaps in an avatar rig, and cosmetic geometry do not reduce the reliable target silhouette. It is removed when the player stops being an active hider and is never baked into the map.
- The server first raycasts the exact submitted aim against that volume, then uses a configurable 1.5-stud-radius spherecast only when the center ray misses. A final thin line-of-sight check, 300-stud maximum range, and living-hider validation keep the forgiving tag from reaching through walls or around corners.
- The seeker can tag any number of currently active hiders before returning to the post. Tagged hiders remain active in the world until the tags are banked.
- Every active real hider can win by reaching `SeekerHoldingSpawn`, whether tagged or untagged. A hider who enters the 8-stud capture radius after being outside the 12-stud outer radius becomes a round winner, is promoted to spectator, and moves to a waiting-area slot.
- If the seeker reaches the post, every hider whose tag is still pending is eliminated at once. The same outside-then-enter rule prevents respawning at the post from resolving the race. In a same-server-frame race, the seeker defeats tagged hiders while an untagged hider still wins.
- During Seeking, the server raycasts around the post perimeter to generate a ground-flush, non-colliding red capture-area disc and segmented boundary. The indicator follows `SeekerHoldingSpawn` if the marker moves and is never baked into the Studio-authored map.
- Winning and eliminated real hiders become spectators and move to their waiting-area slots; eliminated practice mannequins are removed. Stationary practice mannequins cannot race to the post or become winners.
- A right-side **HIDER ROSTER** groups every round hider under **ACTIVE**, **TAGGED**, **WINNERS**, or **ELIMINATED**, with player avatars, names, counts, and practice-bot fallbacks.
- Resolving the final hider as a winner or elimination displays the completed roster for two seconds, then automatically resets the round and starts a new round when enough players remain.
- The HUD tells every hider that reaching the post wins, gives tagged hiders the urgent race warning, and shows the seeker how many pending tags will be banked together.
- A tagged real hider gets a bright red border around the entire screen and the warning `YOU'VE BEEN TAGGED. RUN TO THE POST BEFORE THE SEEKER TO WIN` until their tag status changes.
- When Seeking begins, mouse camera movement is restored immediately while the black camera layer fades away.
- The countdown is hidden.
- This phase has no time limit.
- Late joiners become spectators and are kept in distinct slots around `WaitingSpawn` rather than joining the active round.

### Reset behavior

- Any player can reset because all current users are treated as playtesters.
- Resets are sent to the server through `ResetRequested` and are debounced for one second.
- Reset increments `RoundNumber` and the controller generation, cancelling either startup or Hiding countdown work.
- It clears server role/spawn assignments, all pending tags, the hider roster, and every player's replicated `Role` attribute; resets both timers; spreads remaining characters around `WaitingSpawn`; and enters `WaitingToStart`.
- If at least two players remain—or one Studio player with practice enabled—reset automatically schedules a new round after the normal startup delay.
- If the active seeker leaves, or the last active hider leaves, the server performs the same reset. One hider leaving while another remains does not end the round; spectators leaving have no round effect.

## Player controls

### Desktop

- `WASD`: move.
- Mouse: look around in first person.
- Left mouse button while Seeking as the seeker: tag the visible hider under the crosshair.
- Hold `Left Alt`: temporarily unlock and show the cursor so UI buttons can be clicked.
- Release `Left Alt`: return to locked first-person mouse control.
- Hold `R` for one second: reset the round. The hold requirement reduces accidental resets.
- The **RESET ROUND** button is also available at the top right.
- The smaller **BACK TO LOBBY** button beneath reset returns only the clicking player to the Lobby.

### Touch and gamepad

- While Seeking on a touch device, press the on-screen **TAG** button to fire through the center crosshair.
- A short tap anywhere in the unobstructed game view tags along a ray through that exact screen point, so a seeker can directly tap a visible hider. Camera drags and touches consumed by UI or native movement controls do not fire.
- The reset button uses `GuiButton.Activated`, which is cross-platform.
- The desktop controls guide is hidden when a keyboard is not available.
- Explicit gamepad selection/navigation configuration has not yet been added or comprehensively tested.

### Studio solo practice

- In Roblox Studio only, a one-player session automatically starts a practice round when `StudioPracticeEnabled` is true.
- The real player is assigned seeker and two labeled, stationary practice hider mannequins spawn at shuffled markers beneath `HiderSpawns`.
- Practice rounds use a one-second role reveal and a three-second hiding countdown by default, after the normal five-second connection delay.
- Practice hiders use the same full-body tag volume, server casts, pending-tag, seeker-post return, and final-round-reset logic as real hiders.
- With two or more connected players, the normal player-only round starts and no practice mannequins are created.
- `RunService:IsStudio()` guards the entire feature, so practice hiders cannot appear in a published server even if the replicated configuration attribute remains enabled.

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
| `HiderRosterJson` | `[]` | Ordered JSON roster of real and practice hiders with `Active`, `Tagged`, `Winner`, or `Eliminated` status. Runtime-owned by the server. |
| `TagAssistRadius` | `1.5` | Radius in studs for the forgiving tag spherecast used after the exact center ray misses. Clamped from 0 (disabled) through 4. |
| `StudioPracticeEnabled` | `true` | Enables automatic one-player practice rounds in Studio only. |
| `StudioPracticeHiderCount` | `2` | Number of practice mannequins, clamped from 1 through 4. |
| `StudioPracticeHidingDuration` | `3` | Studio practice hiding countdown in seconds. Minimum effective value is 1. |
| `PracticeModeActive` | `false` | Whether the current active round is a Studio practice round. Runtime-owned by the server. |
| `RoundNumber` | `0` in Edit mode | Incremented whenever a round is initialized or reset. |
| `HidingDuration` | `30` | Hiding duration in seconds. Minimum effective value is 1. |

Other constants currently live in scripts:

- Minimum players: `2` in `RoundController`.
- Maximum hiders: `4`; maximum active round players: `5` in `RoundController`.
- Automatic-start delay: `5` seconds in `RoundController`.
- Role-selection reveal: `5` seconds in `RoundController`.
- Server reset debounce: `1` second in `RoundController`.
- Desktop `R` hold duration: `1` second in `RoundApp`.
- Maximum tag distance: `300` studs in `RoundController`.
- Seeker-post capture radius: `8` studs, after crossing a `12`-stud outer radius, for both sides of a tagged-hider race in `RoundController`.

## Studio hierarchy and ownership

```text
ReplicatedStorage
├── Packages (Wally-managed React dependencies)
└── RoundState (Folder)
    ├── attributes: Phase, TimeRemaining, StartTimeRemaining,
    │              ConnectedPlayers, RoleSelectionDuration,
    │              RoleSelectionEndTime, SelectionUserIds,
    │              SelectedSeekerUserId, HiderRosterJson,
    │              TagAssistRadius,
    │              StudioPracticeEnabled,
    │              StudioPracticeHiderCount,
    │              StudioPracticeHidingDuration, PracticeModeActive,
    │              RoundNumber, HidingDuration
    ├── ResetRequested (RemoteEvent)
    ├── TagRequested (RemoteEvent)
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

During Play, React creates the normal phase/role/timer HUD plus `SelectionOverlay`, its roulette candidate cards, the seeker crosshair, the four-section `HiderRosterPanel`, `ResetButton`, and `ControlsGuide` beneath `ReactRoot`.

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
- Give every connected player a stable waiting-area slot on a six-stud grid around `WaitingSpawn`, reclaiming the slot when they leave.
- Reset when the seeker or final hider leaves, while allowing rounds to continue after spectator departures or a non-final hider departure.
- Generate query-only full-body tag volumes and validate exact and forgiving seeker aim with final thin-ray line of sight, then track multiple pending tags and authoritatively resolve each race back to the holding post.
- Generate and maintain the Seeking-only visual indicator for the post's 8-stud capture area at runtime.
- Replicate the ordered hider roster and its Active, Tagged, Winner, and Eliminated transitions as JSON.
- Promote winning and eliminated hiders to spectators and reset automatically after the final hider is resolved.
- In Studio, create and clean up one-player practice rounds with configurable, raycastable hider mannequins.
- Replicate state through `RoundState` attributes.
- Accept playtester reset requests with server-side debounce.

The server script intentionally fails startup validation when required spawn containers/markers are absent or when fewer than four BasePart hider markers exist. It does not inspect or reference `SeekerSpot`.

### `StarterGui.RoundGui.RoundApp`

Responsibilities:

- Render all round phase states from replicated attributes.
- Show/hide the Hiding timer and distinguish waiting-for-players from automatic-start countdown state.
- Display the local player's replicated assignment as `You are the seeker`, `You are hiding`, or `You are spectating` throughout the active round.
- Show role-specific phase prompts for hiding, aiming/tagging, returning to the post, being tagged, and spectating.
- Render the seeker's center-screen crosshair and submit left-click, touch-button, or direct screen-tap aim rays during Seeking.
- Render the right-side hider roster with separate Active, Tagged, Winners, and Eliminated sections.
- Render an unmistakable full-screen red perimeter and expanded warning prompt for the locally tagged hider.
- Show a winning hider a green role banner and a clear round-win message while their name remains in the Winners section.
- Render the synchronized avatar roulette during `SelectingRoles`, with a server-clock-driven ease-out that lands on the authoritative seeker.
- Pulse the final five countdown values.
- Send reset requests from the reset button or held `R` key.
- Send individual return requests from the secondary **BACK TO LOBBY** button.
- Manage Alt-based desktop cursor interaction.
- Display the discreet bottom-left controls guide on keyboard devices.
- Apply the macOS first-person cursor startup/respawn refresh.
- Align the seeker's first-person camera directly with the center of `SeekerHoldingSpawn` when entering Hiding or Seeking and after respawn.
- Fade the seeker's world view to and from black and suppress mouse-look input during Hiding without covering the HUD.

Clients do not choose or submit roles, decide phase transitions, or directly mutate server state.

## Round spawn markers

The connected Match place now contains the required marker hierarchy. The markers created during the 2026-08-05 implementation pass use safe, non-overlapping **temporary** positions:

| Marker | Temporary position `(X, Y, Z)` |
| --- | --- |
| `WaitingSpawn` | `(0, 1, 0)` |
| `SeekerHoldingSpawn` | `(0, 1, -15)` |
| `Hider1` | `(-30, 1, 40)` |
| `Hider2` | `(-10, 1, 40)` |
| `Hider3` | `(10, 1, 40)` |
| `Hider4` | `(30, 1, 40)` |

- A map designer must deliberately reposition and orient all six markers for the final waiting area, seeker enclosure, and hiding map.
- Marker `CFrame` orientation controls the direction a respawned character faces. The seeker specifically uses the `SeekerHoldingSpawn` marker's backward (`+Z`) edge and therefore faces forward toward its center.
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

A one-client Play check on 2026-08-05 confirmed the pre-practice controller and HUD loaded without console errors. That check predates Studio solo practice and must be repeated after syncing this version. The available Studio bridge does not launch multi-client Server & Clients sessions, so the multiplayer matrix remains a manual Studio check.

For a fast solo check, use normal **Test** mode with one player. Confirm that the HUD announces a practice round, two labeled mannequins appear at hider markers, both can be tagged and banked at the seeker post, and the final mannequin resets the round. Practice mannequins are stationary, so the hider-win path requires a multi-client test.

Then use Studio's **Server & Clients** test mode with two through five clients. The five-second startup delay is specifically intended to absorb asynchronous test-client connections. Verify:

- One client starts a Studio-only practice round when practice is enabled; disabling `StudioPracticeEnabled` restores indefinite `WaitingToStart` behavior.
- Two through five clients produce exactly one `Seeker`, between one and four `Hider` attributes, no spectators, and unique hider marker assignments.
- A waiting roster change restarts the startup countdown; dropping below two cancels it.
- After startup, all clients show the same candidate icons for five seconds, slow onto the selected seeker, and receive no active role attribute until the reveal completes.
- The seeker begins eight studs behind `SeekerHoldingSpawn` on the indicator edge, with both character and first-person camera aimed directly at the post center, and is unanchored there when Seeking begins. Rotate the marker to choose the side where the seeker waits.
- During Hiding, the seeker's world view fades fully to black, the HUD remains readable, and mouse movement cannot rotate the camera; Seeking restores mouse-look and fades the world back in.
- A reset clears role attributes, spreads everyone around `WaitingSpawn`, and automatically schedules a fresh random selection when at least two players remain.
- Respawning returns a participant to the spawn appropriate for their current role and phase.
- A seeker departure or final-hider departure resets; one hider leaving while another remains continues; spectator departure does not affect the round.
- A seeker click, center-fire touch, or direct screen tap prioritizes a living hider on the submitted aim ray, then accepts a near miss within `TagAssistRadius`; walls, corners, and non-hider characters still block the final line-of-sight check.
- Head, torso, arms, legs, and the spaces between them are covered by the active hider's invisible tag volume; removing a hider's active role removes that volume.
- Multiple distinct hiders can be tagged before returning, while duplicate clicks on an already-tagged hider are ignored.
- A tagged hider sees the red screen border and full race-to-post warning immediately; other hiders and the seeker do not see that local alert.
- Any real hider who was outside the post's outer radius and enters the capture area moves to **WINNERS**, becomes a spectator at the waiting area, and sees the win message, even when they were never tagged.
- The seeker still eliminates every remaining tagged hider with one return, while hiders that already won remain winners and cannot be eliminated.
- The seeker and every hider must cross outside the post's outer radius before entering; character reset/respawn at the post cannot resolve the race.
- If a seeker and tagged hider enter during the same server frame, the seeker wins the tie and the hider is eliminated.
- The runtime post indicator appears only during Seeking, sits flush on the sampled ground, matches the horizontal 8-stud capture radius, and follows the marker after a `CFrame` change.
- One return promotes every tagged real hider to spectator and removes every tagged practice hider.
- All four roster sections and counts update together, and resolving the final hider resets after the two-second completion display.
- Late joiners during Hiding or Seeking receive `Spectator` and stay in separate slots around `WaitingSpawn`.
- No transition depends on touching, approaching, or retaining `SeekerSpot`.

For overflow testing above five players, verify that only five shuffled players are active and all remaining players are spectators. This exceeds the requested two-to-five-client baseline.

## Known missing gameplay

The project is an early playable hide-and-seek game. The following systems do not currently exist:

- A dedicated victory/results phase before the automatic round reset.
- A timed Seeking phase.
- Dedicated spectator camera/UI behavior beyond the replicated role and waiting-area spawn.
- Multiple maps or map rotation.
- Scores, rewards, persistence, badges, or data stores.
- Sound effects, music, or phase announcements.
- Production authorization rules for resetting; all players can currently reset.

## Recommended next development steps

1. Deliberately position and orient the temporary waiting, seeker, and hider markers in the final map layout.
2. Run two-to-five-client Server & Clients tests after syncing the Match project.
3. Add a victory/results presentation and optional Seeking duration.
4. Add dedicated spectator camera controls.
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
