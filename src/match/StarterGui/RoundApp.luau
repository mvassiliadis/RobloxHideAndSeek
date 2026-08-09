--!strict

local Players = game:GetService("Players")
local ContextActionService = game:GetService("ContextActionService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(packages:WaitForChild("React"))

local roundState = ReplicatedStorage:WaitForChild("RoundState")
local resetRequested = roundState:WaitForChild("ResetRequested") :: RemoteEvent
local tagRequested = roundState:WaitForChild("TagRequested") :: RemoteEvent
local returnToLobbyRequested = roundState:WaitForChild("ReturnToLobbyRequested") :: RemoteEvent
local localPlayer = Players.LocalPlayer

local e = React.createElement

local WAITING_COLOR = Color3.fromRGB(255, 210, 105)
local HIDING_COLOR = Color3.fromRGB(104, 213, 255)
local SEEKING_COLOR = Color3.fromRGB(255, 92, 92)
local NORMAL_TIMER_COLOR = Color3.fromRGB(255, 255, 255)
local WARNING_TIMER_COLOR = Color3.fromRGB(255, 105, 105)
local DEFAULT_GUIDE_COLOR = Color3.fromRGB(222, 230, 241)
local CURSOR_GUIDE_COLOR = Color3.fromRGB(255, 220, 130)
local SELECTION_ACCENT_COLOR = Color3.fromRGB(255, 196, 74)
local SELECTION_DIM_COLOR = Color3.fromRGB(82, 91, 110)
local ACTIVE_HIDER_COLOR = Color3.fromRGB(92, 190, 255)
local TAGGED_HIDER_COLOR = Color3.fromRGB(255, 178, 75)
local WINNER_HIDER_COLOR = Color3.fromRGB(105, 225, 140)
local ELIMINATED_HIDER_COLOR = Color3.fromRGB(143, 152, 168)
local TAGGED_ALERT_COLOR = Color3.fromRGB(255, 45, 45)

local DEFAULT_GUIDE_TEXT = "WASD  MOVE   •   MOUSE  LOOK\nHOLD ALT  CURSOR   •   HOLD R  RESET"
local CURSOR_GUIDE_TEXT = "CURSOR ACTIVE\nRELEASE ALT TO LOOK"
local R_HOLD_SECONDS = 1
local SEEKER_CAMERA_LOCK_ACTION = "LockSeekerHidingCamera"
local SEEKER_CAMERA_LOCK_PRIORITY = Enum.ContextActionPriority.High.Value + 100
local BLACKOUT_FADE_IN_DURATION = 0.65
local BLACKOUT_FADE_OUT_DURATION = 0.8

type HiderStatus = "Active" | "Tagged" | "Winner" | "Eliminated"
type HiderRosterItem = {
	id: string,
	userId: number,
	name: string,
	status: HiderStatus,
	isPractice: boolean,
}

local GOTHAM_BOLD = Font.new(
	"rbxasset://fonts/families/GothamSSm.json",
	Enum.FontWeight.Bold,
	Enum.FontStyle.Normal
)
local GOTHAM_HEAVY = Font.new(
	"rbxasset://fonts/families/GothamSSm.json",
	Enum.FontWeight.Heavy,
	Enum.FontStyle.Normal
)
local GOTHAM_MEDIUM = Font.new(
	"rbxasset://fonts/families/GothamSSm.json",
	Enum.FontWeight.Medium,
	Enum.FontStyle.Normal
)

local function parseUserIds(serializedUserIds: unknown): { number }
	local userIds: { number } = {}
	if typeof(serializedUserIds) ~= "string" then
		return userIds
	end

	for serializedUserId in string.gmatch(serializedUserIds, "[^,]+") do
		local userId = tonumber(serializedUserId)
		if userId then
			table.insert(userIds, userId)
		end
	end

	return userIds
end

local function parseHiderRoster(serializedRoster: unknown): { HiderRosterItem }
	if typeof(serializedRoster) ~= "string" or serializedRoster == "" then
		return {}
	end

	local success, decoded = pcall(function(): any
		return HttpService:JSONDecode(serializedRoster)
	end)
	if not success or typeof(decoded) ~= "table" then
		return {}
	end

	local roster: { HiderRosterItem } = {}
	for _, rawEntry in decoded :: { any } do
		if typeof(rawEntry) == "table"
			and typeof(rawEntry.id) == "string"
			and typeof(rawEntry.userId) == "number"
			and typeof(rawEntry.name) == "string"
			and (rawEntry.status == "Active"
				or rawEntry.status == "Tagged"
				or rawEntry.status == "Winner"
				or rawEntry.status == "Eliminated")
		then
			table.insert(roster, {
				id = rawEntry.id,
				userId = rawEntry.userId,
				name = rawEntry.name,
				status = rawEntry.status,
				isPractice = rawEntry.isPractice == true,
			})
		end
	end

	return roster
end

local function sinkSeekerCameraInput(
	_actionName: string,
	_inputState: Enum.UserInputState,
	_inputObject: InputObject
): Enum.ContextActionResult
	return Enum.ContextActionResult.Sink
end

local function RoundApp()
	local phase, setPhase = React.useState(roundState:GetAttribute("Phase"))
	local timeRemaining, setTimeRemaining = React.useState(roundState:GetAttribute("TimeRemaining"))
	local connectedPlayers, setConnectedPlayers = React.useState(roundState:GetAttribute("ConnectedPlayers"))
	local startTimeRemaining, setStartTimeRemaining = React.useState(roundState:GetAttribute("StartTimeRemaining"))
	local selectionUserIds, setSelectionUserIds = React.useState(roundState:GetAttribute("SelectionUserIds"))
	local selectedSeekerUserId, setSelectedSeekerUserId = React.useState(roundState:GetAttribute("SelectedSeekerUserId"))
	local roleSelectionDuration, setRoleSelectionDuration = React.useState(roundState:GetAttribute("RoleSelectionDuration"))
	local roleSelectionEndTime, setRoleSelectionEndTime = React.useState(roundState:GetAttribute("RoleSelectionEndTime"))
	local hiderRosterJson, setHiderRosterJson = React.useState(roundState:GetAttribute("HiderRosterJson"))
	local practiceModeActive, setPracticeModeActive = React.useState(roundState:GetAttribute("PracticeModeActive"))
	local selectionIndex, setSelectionIndex = React.useState(1)
	local role, setRole = React.useState(localPlayer:GetAttribute("Role"))
	local buttonText, setButtonText = React.useState("RESET ROUND")
	local lobbyButtonText, setLobbyButtonText = React.useState("BACK TO LOBBY")
	local cursorActive, setCursorActive = React.useState(false)

	local mountedRef = React.useRef(false)
	local resetPendingRef = React.useRef(false)
	local returnPendingRef = React.useRef(false)
	local rHeldRef = React.useRef(false)
	local rHoldGenerationRef = React.useRef(0)
	local altHeldRef = React.useRef(false)
	local cameraSnapGenerationRef = React.useRef(0)
	local resetButtonRef = React.useRef(nil)
	local tagButtonRef = React.useRef(nil)
	local pulseScaleRef = React.useRef(nil)
	local blackoutRef = React.useRef(nil)
	local blackoutTweenRef = React.useRef(nil)

	local function setCursorMode(enabled: boolean)
		if not UserInputService.KeyboardEnabled then
			return
		end

		setCursorActive(enabled)

		-- Keep the actual Modal property in sync immediately. React can skip the
		-- update when cursorActive already equals enabled, which otherwise leaves
		-- the startup refresh's temporary Modal = true in place until Alt is used.
		local resetButton = resetButtonRef.current
		if resetButton then
			(resetButton :: TextButton).Modal = enabled
		end

		UserInputService.MouseIconEnabled = enabled
		UserInputService.MouseBehavior = if enabled
			then Enum.MouseBehavior.Default
			else Enum.MouseBehavior.LockCenter
	end

	local function refreshLockedCursor()
		if not UserInputService.KeyboardEnabled then
			return
		end

		task.spawn(function()
			-- Let Roblox's character and camera scripts finish initializing first.
			task.wait(0.2)

			if not mountedRef.current or altHeldRef.current then
				return
			end

			-- Cycling these values refreshes the native macOS cursor state.
			local resetButton = resetButtonRef.current
			if resetButton then
				(resetButton :: TextButton).Modal = true
			end
			UserInputService.MouseIconEnabled = true
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			RunService.RenderStepped:Wait()

			if mountedRef.current and not altHeldRef.current then
				setCursorMode(false)
			end
		end)
	end

	local function snapSeekerCameraToPost()
		cameraSnapGenerationRef.current += 1
		local thisGeneration = cameraSnapGenerationRef.current

		task.spawn(function()
			local character = localPlayer.Character
			if not character then
				return
			end

			local head = character:WaitForChild("Head", 2)
			if not head or not head:IsA("BasePart") then
				return
			end

			-- Wait for the assigned-spawn pivot and Roblox's camera script.
			task.wait(0.1)
			for _ = 1, 3 do
				RunService.RenderStepped:Wait()
				local currentPhase = roundState:GetAttribute("Phase")
				if not mountedRef.current
					or thisGeneration ~= cameraSnapGenerationRef.current
					or localPlayer:GetAttribute("Role") ~= "Seeker"
					or (currentPhase ~= "Hiding" and currentPhase ~= "Seeking")
				then
					return
				end

				local roundSpawns = Workspace:FindFirstChild("RoundSpawns")
				local post = roundSpawns and roundSpawns:FindFirstChild("SeekerHoldingSpawn")
				local camera = Workspace.CurrentCamera
				if not post or not post:IsA("BasePart") or not camera then
					return
				end

				local cameraPosition = camera.CFrame.Position
				if (post.Position - cameraPosition).Magnitude > 0.01 then
					camera.CFrame = CFrame.lookAt(cameraPosition, post.Position)
				end
			end
		end)
	end

	local function requestReset()
		if resetPendingRef.current then
			return
		end

		resetPendingRef.current = true
		rHeldRef.current = false
		rHoldGenerationRef.current += 1
		setButtonText("RESETTING...")
		resetRequested:FireServer()

		task.delay(1, function()
			resetPendingRef.current = false
			if mountedRef.current then
				setButtonText("RESET ROUND")
			end
		end)
	end

	local function requestReturnToLobby()
		if returnPendingRef.current then
			return
		end

		returnPendingRef.current = true
		setLobbyButtonText("LEAVING...")
		returnToLobbyRequested:FireServer()
	end

	local function beginKeyboardReset()
		if resetPendingRef.current or rHeldRef.current then
			return
		end

		rHeldRef.current = true
		rHoldGenerationRef.current += 1
		local thisGeneration = rHoldGenerationRef.current
		setButtonText("KEEP HOLDING R...")

		task.delay(R_HOLD_SECONDS, function()
			if rHeldRef.current and thisGeneration == rHoldGenerationRef.current then
				requestReset()
			end
		end)
	end

	local function cancelKeyboardReset()
		if not rHeldRef.current then
			return
		end

		rHeldRef.current = false
		rHoldGenerationRef.current += 1

		if not resetPendingRef.current then
			setButtonText("RESET ROUND")
		end
	end

	local function canRequestTag(): boolean
		return roundState:GetAttribute("Phase") == "Seeking"
			and localPlayer:GetAttribute("Role") == "Seeker"
	end

	local function requestTagAlongRay(ray: Ray)
		if not canRequestTag() then
			return
		end

		tagRequested:FireServer(ray.Origin, ray.Direction.Unit)
	end

	local function requestCenteredTag()
		local camera = Workspace.CurrentCamera
		if not camera or not canRequestTag() then
			return
		end

		tagRequested:FireServer(camera.CFrame.Position, camera.CFrame.LookVector)
	end

	React.useEffect(function()
		mountedRef.current = true

		local connections = {
			roundState:GetAttributeChangedSignal("Phase"):Connect(function()
				local nextPhase = roundState:GetAttribute("Phase")
				setPhase(nextPhase)
				if nextPhase == "Hiding" or nextPhase == "Seeking" then
					snapSeekerCameraToPost()
				end
			end),
			roundState:GetAttributeChangedSignal("TimeRemaining"):Connect(function()
				setTimeRemaining(roundState:GetAttribute("TimeRemaining"))
			end),
			roundState:GetAttributeChangedSignal("ConnectedPlayers"):Connect(function()
				setConnectedPlayers(roundState:GetAttribute("ConnectedPlayers"))
			end),
			roundState:GetAttributeChangedSignal("StartTimeRemaining"):Connect(function()
				setStartTimeRemaining(roundState:GetAttribute("StartTimeRemaining"))
			end),
			roundState:GetAttributeChangedSignal("SelectionUserIds"):Connect(function()
				setSelectionUserIds(roundState:GetAttribute("SelectionUserIds"))
			end),
			roundState:GetAttributeChangedSignal("SelectedSeekerUserId"):Connect(function()
				setSelectedSeekerUserId(roundState:GetAttribute("SelectedSeekerUserId"))
			end),
			roundState:GetAttributeChangedSignal("RoleSelectionDuration"):Connect(function()
				setRoleSelectionDuration(roundState:GetAttribute("RoleSelectionDuration"))
			end),
			roundState:GetAttributeChangedSignal("RoleSelectionEndTime"):Connect(function()
				setRoleSelectionEndTime(roundState:GetAttribute("RoleSelectionEndTime"))
			end),
			roundState:GetAttributeChangedSignal("HiderRosterJson"):Connect(function()
				setHiderRosterJson(roundState:GetAttribute("HiderRosterJson"))
			end),
			roundState:GetAttributeChangedSignal("PracticeModeActive"):Connect(function()
				setPracticeModeActive(roundState:GetAttribute("PracticeModeActive"))
			end),
			localPlayer:GetAttributeChangedSignal("Role"):Connect(function()
				local nextRole = localPlayer:GetAttribute("Role")
				setRole(nextRole)
				if nextRole == "Seeker" then
					snapSeekerCameraToPost()
				end
			end),
			returnToLobbyRequested.OnClientEvent:Connect(function(status: string)
				if status ~= "Failed" then
					return
				end

				returnPendingRef.current = false
				setLobbyButtonText("TELEPORT FAILED")
				task.delay(2, function()
					if mountedRef.current and not returnPendingRef.current then
						setLobbyButtonText("BACK TO LOBBY")
					end
				end)
			end),
			UserInputService.InputBegan:Connect(function(input, gameProcessed)
				if input.KeyCode == Enum.KeyCode.LeftAlt then
					altHeldRef.current = true
					setCursorMode(true)
					return
				end

				if input.KeyCode == Enum.KeyCode.R and not gameProcessed then
					beginKeyboardReset()
				elseif input.UserInputType == Enum.UserInputType.MouseButton1
					and not gameProcessed
					and not altHeldRef.current
					and roundState:GetAttribute("Phase") == "Seeking"
					and localPlayer:GetAttribute("Role") == "Seeker"
				then
					requestCenteredTag()
				end
			end),
			UserInputService.TouchTap:Connect(function(touchPositions, gameProcessed)
				if gameProcessed or #touchPositions ~= 1 or not canRequestTag() then
					return
				end

				local touchPosition = touchPositions[1]
				local tagButton = tagButtonRef.current
				if tagButton then
					local button = tagButton :: GuiObject
					local buttonPosition = button.AbsolutePosition
					local buttonSize = button.AbsoluteSize
					if touchPosition.X >= buttonPosition.X
						and touchPosition.X <= buttonPosition.X + buttonSize.X
						and touchPosition.Y >= buttonPosition.Y
						and touchPosition.Y <= buttonPosition.Y + buttonSize.Y
					then
						return
					end
				end

				local camera = Workspace.CurrentCamera
				if not camera then
					return
				end

				requestTagAlongRay(camera:ScreenPointToRay(touchPosition.X, touchPosition.Y))
			end),
			UserInputService.InputEnded:Connect(function(input)
				if input.KeyCode == Enum.KeyCode.LeftAlt then
					altHeldRef.current = false
					setCursorMode(false)
				elseif input.KeyCode == Enum.KeyCode.R then
					cancelKeyboardReset()
				end
			end),
			UserInputService.WindowFocusReleased:Connect(function()
				altHeldRef.current = false
				cancelKeyboardReset()
				setCursorMode(false)
			end),
			localPlayer.CharacterAdded:Connect(function()
				refreshLockedCursor()
				snapSeekerCameraToPost()
			end),
		}

		refreshLockedCursor()
		snapSeekerCameraToPost()

		return function()
			mountedRef.current = false
			rHeldRef.current = false
			rHoldGenerationRef.current += 1
			cameraSnapGenerationRef.current += 1
			for _, connection in connections do
				connection:Disconnect()
			end
		end
	end, {})

	local numericTimeRemaining = if typeof(timeRemaining) == "number" then timeRemaining else 0
	local numericConnectedPlayers = if typeof(connectedPlayers) == "number" then connectedPlayers else 0
	local numericStartTimeRemaining = if typeof(startTimeRemaining) == "number" then startTimeRemaining else 0
	local numericSelectedSeekerUserId = if typeof(selectedSeekerUserId) == "number" then selectedSeekerUserId else 0
	local numericRoleSelectionDuration = if typeof(roleSelectionDuration) == "number" then roleSelectionDuration else 5
	local numericRoleSelectionEndTime = if typeof(roleSelectionEndTime) == "number" then roleSelectionEndTime else 0
	local hiderRoster = parseHiderRoster(hiderRosterJson)
	local activeHiders: { HiderRosterItem } = {}
	local taggedHiders: { HiderRosterItem } = {}
	local winnerHiders: { HiderRosterItem } = {}
	local eliminatedHiders: { HiderRosterItem } = {}
	local localPlayerIsTagged = false
	local localPlayerIsWinner = false
	local localPlayerIsEliminated = false
	for _, hider in hiderRoster do
		if hider.status == "Active" then
			table.insert(activeHiders, hider)
		elseif hider.status == "Tagged" then
			table.insert(taggedHiders, hider)
			if hider.userId == localPlayer.UserId then
				localPlayerIsTagged = true
			end
		elseif hider.status == "Winner" then
			table.insert(winnerHiders, hider)
			if hider.userId == localPlayer.UserId then
				localPlayerIsWinner = true
			end
		else
			table.insert(eliminatedHiders, hider)
			if hider.userId == localPlayer.UserId then
				localPlayerIsEliminated = true
			end
		end
	end
	local selectionCandidates = parseUserIds(selectionUserIds)
	local waiting = phase == "WaitingToStart"
	local starting = waiting and numericStartTimeRemaining > 0
	local soloPracticeWaiting = starting
		and numericConnectedPlayers == 1
		and RunService:IsStudio()
		and roundState:GetAttribute("StudioPracticeEnabled") == true
	local selecting = phase == "SelectingRoles"
	local seeking = phase == "Seeking"
	local taggedHiderAlertVisible = seeking and role == "Hider" and localPlayerIsTagged
	local timerVisible = phase == "Hiding"
	local timerWarning = timerVisible and numericTimeRemaining <= 5 and numericTimeRemaining > 0
	local taggedHiderCount = #taggedHiders
	local hasPendingTags = taggedHiderCount > 0
	local taggedHiderNoun = if taggedHiderCount == 1 then "HIDER" else "HIDERS"
	local roundHidersResolved = #hiderRoster > 0 and #activeHiders == 0 and taggedHiderCount == 0
	local roundResultText = ""
	local roundResultWon = false
	if seeking and roundHidersResolved then
		if localPlayerIsWinner then
			roundResultText = "YOU WON"
			roundResultWon = true
		elseif localPlayerIsEliminated then
			roundResultText = "YOU LOST"
		elseif role == "Seeker" then
			roundResultWon = #winnerHiders == 0
			roundResultText = if roundResultWon then "YOU WON" else "YOU LOST"
		end
	end
	local roundResultVisible = roundResultText ~= ""
	local roundResultColor = if roundResultWon then WINNER_HIDER_COLOR else TAGGED_ALERT_COLOR

	React.useEffect(function()
		if not selecting or #selectionCandidates == 0 then
			setSelectionIndex(1)
			return
		end

		local targetIndex = table.find(selectionCandidates, numericSelectedSeekerUserId) or 1
		local fullCycles = math.max(3, math.ceil(18 / #selectionCandidates))
		local totalSteps = fullCycles * #selectionCandidates + targetIndex - 1
		local connection: RBXScriptConnection?

		local function updateSelection()
			local timeRemaining = math.max(0, numericRoleSelectionEndTime - Workspace:GetServerTimeNow())
			local progress = 1 - math.clamp(timeRemaining / math.max(0.1, numericRoleSelectionDuration), 0, 1)
			local easedProgress = 1 - (1 - progress) ^ 2
			local step = math.min(totalSteps, math.floor(easedProgress * (totalSteps + 1)))
			setSelectionIndex((step % #selectionCandidates) + 1)
		end

		updateSelection()
		connection = RunService.Heartbeat:Connect(updateSelection)

		return function()
			if connection then
				connection:Disconnect()
			end
		end
	end, {
		selecting,
		selectionUserIds,
		numericSelectedSeekerUserId,
		numericRoleSelectionDuration,
		numericRoleSelectionEndTime,
	})

	React.useEffect(function()
		local pulseScale = pulseScaleRef.current
		if not pulseScale then
			return
		end

		local scale = pulseScale :: UIScale
		if not timerWarning then
			scale.Scale = 1
			return
		end

		scale.Scale = 1.18
		local tween = TweenService:Create(
			scale,
			TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = 1 }
		)
		tween:Play()

		return function()
			tween:Cancel()
		end
	end, { numericTimeRemaining, timerWarning })

	React.useEffect(function()
		local blackout = blackoutRef.current
		if not blackout then
			return
		end

		local existingTween = blackoutTweenRef.current
		if existingTween then
			(existingTween :: Tween):Cancel()
		end

		local blackoutActive = phase == "Hiding" and role == "Seeker"
		local duration = if blackoutActive then BLACKOUT_FADE_IN_DURATION else BLACKOUT_FADE_OUT_DURATION
		local tween = TweenService:Create(
			blackout :: Frame,
			TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
			{ BackgroundTransparency = if blackoutActive then 0 else 1 }
		)
		blackoutTweenRef.current = tween
		tween:Play()

		return function()
			tween:Cancel()
			if blackoutTweenRef.current == tween then
				blackoutTweenRef.current = nil
			end
		end
	end, { phase, role })

	React.useEffect(function()
		local cameraLocked = phase == "Hiding" and role == "Seeker"
		if not cameraLocked then
			ContextActionService:UnbindAction(SEEKER_CAMERA_LOCK_ACTION)
			return
		end

		local previousMouseDeltaSensitivity = UserInputService.MouseDeltaSensitivity
		UserInputService.MouseDeltaSensitivity = 0
		ContextActionService:BindActionAtPriority(
			SEEKER_CAMERA_LOCK_ACTION,
			sinkSeekerCameraInput,
			false,
			SEEKER_CAMERA_LOCK_PRIORITY,
			Enum.UserInputType.MouseMovement,
			Enum.UserInputType.MouseWheel
		)

		return function()
			ContextActionService:UnbindAction(SEEKER_CAMERA_LOCK_ACTION)
			UserInputService.MouseDeltaSensitivity = previousMouseDeltaSensitivity
		end
	end, { phase, role })

	local touchEnabled = UserInputService.TouchEnabled
	local phaseText = if starting
		then if soloPracticeWaiting then "PRACTICE ROUND STARTING" else "ROUND STARTING"
		elseif waiting
		then "WAITING FOR PLAYERS"
		elseif selecting
		then "CHOOSING THE SEEKER"
		elseif seeking
		then if role == "Seeker"
			then if hasPendingTags
				then `{taggedHiderCount} {taggedHiderNoun} TAGGED\nKEEP LOOKING OR RETURN TO THE POST`
				elseif roundHidersResolved
				then if #winnerHiders > 0 then "ROUND COMPLETE!\nCHECK THE WINNERS LIST" else "ALL HIDERS ELIMINATED!"
				else if touchEnabled
					then "FIND A HIDER\nTAP THEM OR USE THE TAG BUTTON"
					else "FIND A HIDER\nAIM AND CLICK TO TAG"
			elseif role == "Hider"
			then if localPlayerIsTagged
				then "YOU'VE BEEN TAGGED.\nRUN TO THE POST BEFORE THE SEEKER TO WIN"
				else "REACH THE SEEKER POST TO WIN\nSTAY OUT OF SIGHT"
			elseif localPlayerIsWinner
			then "YOU REACHED THE POST FIRST!\nYOU WIN THIS ROUND"
			else "SEEKING"
		else if role == "Seeker"
		then "WAIT FOR PLAYERS TO HIDE"
		elseif role == "Hider"
		then "GO HIDE!"
		else "HIDING"
	local phaseColor = if waiting then WAITING_COLOR elseif seeking then SEEKING_COLOR else HIDING_COLOR
	local waitingStatusText = if starting
		then if soloPracticeWaiting
			then `Solo practice starting in {math.max(0, math.floor(numericStartTimeRemaining))}...`
			else `Starting in {math.max(0, math.floor(numericStartTimeRemaining))}...`
		else "Need at least 2 players"
	local roleText = if localPlayerIsWinner
		then "You won this round"
		elseif role == "Seeker"
		then if practiceModeActive == true then "You are the seeker (practice)" else "You are the seeker"
		elseif role == "Hider"
		then "You are hiding"
		elseif role == "Spectator"
		then "You are spectating"
		else ""
	local roleColor = if localPlayerIsWinner
		then WINNER_HIDER_COLOR
		elseif role == "Seeker"
		then SEEKING_COLOR
		elseif role == "Hider"
		then HIDING_COLOR
		else Color3.fromRGB(210, 216, 225)
	local hasRole = roleText ~= ""
	local compactSelectionCards = touchEnabled
	local controlsGuideText = if cursorActive
		then CURSOR_GUIDE_TEXT
		elseif seeking and role == "Seeker" and hasPendingTags
		then "LEFT CLICK  TAG MORE HIDERS\nRETURN TO POST  ELIMINATE ALL"
		elseif seeking and role == "Seeker"
		then "WASD  MOVE   •   MOUSE  LOOK\nLEFT CLICK  TAG A VISIBLE HIDER"
		else DEFAULT_GUIDE_TEXT
	local selectionCardWidth = if compactSelectionCards then 54 else 86
	local selectionAvatarSize = if compactSelectionCards then 42 else 72
	local selectionCards = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, if compactSelectionCards then 6 else 12),
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Center,
		}),
	}

	for index, userId in selectionCandidates do
		local highlighted = index == selectionIndex
		local candidatePlayer: Player? = nil
		for _, connectedPlayer in Players:GetPlayers() do
			if connectedPlayer.UserId == userId then
				candidatePlayer = connectedPlayer
				break
			end
		end

		local fallbackText = "?"
		if userId < 0 then
			local studioPlayerNumber = if candidatePlayer then string.match(candidatePlayer.Name, "(%d+)$") else nil
			fallbackText = `P{studioPlayerNumber or math.abs(userId)}`
		elseif candidatePlayer then
			local studioPlayerNumber = string.match(candidatePlayer.Name, "(%d+)$")
			fallbackText = if studioPlayerNumber and candidatePlayer.DisplayName == ""
				then `P{studioPlayerNumber}`
				else string.upper(string.sub(candidatePlayer.DisplayName, 1, 1))
		end

		selectionCards[`Candidate{userId}`] = e("Frame", {
			BackgroundColor3 = if highlighted then SELECTION_ACCENT_COLOR else SELECTION_DIM_COLOR,
			BackgroundTransparency = if highlighted then 0.05 else 0.48,
			BorderSizePixel = 0,
			LayoutOrder = index,
			Size = UDim2.fromOffset(selectionCardWidth, 104),
			ZIndex = 7,
		}, {
			Scale = e("UIScale", {
				Scale = if highlighted then 1.12 else 0.88,
			}),
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 14),
			}),
			Stroke = e("UIStroke", {
				Color = if highlighted then Color3.fromRGB(255, 236, 166) else Color3.fromRGB(125, 137, 158),
				Thickness = if highlighted then 3 else 1,
				Transparency = if highlighted then 0 else 0.55,
			}),
			AvatarFallback = e("Frame", {
				AnchorPoint = Vector2.new(0.5, 0),
				BackgroundColor3 = if highlighted then Color3.fromRGB(29, 37, 53) else Color3.fromRGB(25, 32, 46),
				BorderSizePixel = 0,
				Position = UDim2.new(0.5, 0, 0, 7),
				Size = UDim2.fromOffset(selectionAvatarSize, selectionAvatarSize),
				ZIndex = 8,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(1, 0),
				}),
				Initials = e("TextLabel", {
					BackgroundTransparency = 1,
					FontFace = GOTHAM_HEAVY,
					Size = UDim2.fromScale(1, 1),
					Text = fallbackText,
					TextColor3 = if highlighted then SELECTION_ACCENT_COLOR else Color3.fromRGB(169, 179, 197),
					TextScaled = true,
					ZIndex = 9,
				}, {
					TextConstraint = e("UITextSizeConstraint", {
						MaxTextSize = if compactSelectionCards then 20 else 30,
						MinTextSize = 12,
					}),
				}),
			}),
			Avatar = e("ImageLabel", {
				AnchorPoint = Vector2.new(0.5, 0),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Image = if userId > 0 then `rbxthumb://type=AvatarHeadShot&id={userId}&w=150&h=150` else "",
				ImageColor3 = if highlighted then Color3.new(1, 1, 1) else Color3.fromRGB(170, 176, 188),
				ImageTransparency = if highlighted then 0 else 0.3,
				Position = UDim2.new(0.5, 0, 0, 7),
				Size = UDim2.fromOffset(selectionAvatarSize, selectionAvatarSize),
				ZIndex = 10,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(1, 0),
				}),
			}),
			PlayerTag = e("TextLabel", {
				AnchorPoint = Vector2.new(0.5, 1),
				BackgroundTransparency = 1,
				FontFace = GOTHAM_BOLD,
				Position = UDim2.new(0.5, 0, 1, -6),
				Size = UDim2.new(1, -8, 0, 18),
				Text = if userId == localPlayer.UserId then "YOU" else "",
				TextColor3 = if highlighted then Color3.fromRGB(31, 37, 48) else Color3.fromRGB(221, 226, 235),
				TextSize = 12,
				ZIndex = 8,
			}),
		})
	end

	local compactRoster = UserInputService.TouchEnabled
	local rosterRowHeight = if compactRoster then 30 else 36
	local rosterWidth = if compactRoster then 198 else 244
	local function createRosterSection(
		sectionName: string,
		sectionColor: Color3,
		sectionItems: { HiderRosterItem },
		layoutOrder: number
	)
		local visibleRowCount = math.max(1, #sectionItems)
		local sectionHeight = 25 + visibleRowCount * rosterRowHeight
		local sectionChildren: { [string]: any } = {
			Header = e("TextLabel", {
				BackgroundColor3 = sectionColor,
				BackgroundTransparency = 0.82,
				BorderSizePixel = 0,
				FontFace = GOTHAM_BOLD,
				Position = UDim2.fromOffset(0, 0),
				Size = UDim2.new(1, 0, 0, 21),
				Text = `{string.upper(sectionName)}  {#sectionItems}`,
				TextColor3 = sectionColor,
				TextSize = if compactRoster then 11 else 12,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 5,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(0, 6),
				}),
				Padding = e("UIPadding", {
					PaddingLeft = UDim.new(0, 8),
				}),
			}),
		}

		if #sectionItems == 0 then
			sectionChildren.Empty = e("TextLabel", {
				BackgroundTransparency = 1,
				FontFace = GOTHAM_MEDIUM,
				Position = UDim2.fromOffset(8, 25),
				Size = UDim2.new(1, -16, 0, rosterRowHeight),
				Text = "None",
				TextColor3 = Color3.fromRGB(137, 148, 165),
				TextSize = if compactRoster then 11 else 12,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 5,
			})
		else
			for index, hider in sectionItems do
				local initials = if hider.isPractice
					then "BOT"
					else string.upper(string.sub(hider.name, 1, 1))
				local rowY = 25 + (index - 1) * rosterRowHeight
				sectionChildren[hider.id] = e("Frame", {
					BackgroundColor3 = Color3.fromRGB(25, 34, 49),
					BackgroundTransparency = 0.18,
					BorderSizePixel = 0,
					Position = UDim2.fromOffset(0, rowY),
					Size = UDim2.new(1, 0, 0, rosterRowHeight - 3),
					ZIndex = 5,
				}, {
					Corner = e("UICorner", {
						CornerRadius = UDim.new(0, 7),
					}),
					StatusBar = e("Frame", {
						BackgroundColor3 = sectionColor,
						BorderSizePixel = 0,
						Size = UDim2.new(0, 3, 1, 0),
						ZIndex = 6,
					}, {
						Corner = e("UICorner", {
							CornerRadius = UDim.new(0, 7),
						}),
					}),
					AvatarFallback = e("TextLabel", {
						AnchorPoint = Vector2.new(0, 0.5),
						BackgroundColor3 = sectionColor,
						BackgroundTransparency = 0.72,
						BorderSizePixel = 0,
						FontFace = GOTHAM_BOLD,
						Position = UDim2.new(0, 9, 0.5, 0),
						Size = UDim2.fromOffset(rosterRowHeight - 10, rosterRowHeight - 10),
						Text = initials,
						TextColor3 = sectionColor,
						TextScaled = true,
						ZIndex = 6,
					}, {
						Corner = e("UICorner", {
							CornerRadius = UDim.new(1, 0),
						}),
						TextConstraint = e("UITextSizeConstraint", {
							MaxTextSize = if compactRoster then 9 else 11,
							MinTextSize = 7,
						}),
					}),
					Avatar = e("ImageLabel", {
						AnchorPoint = Vector2.new(0, 0.5),
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Image = if hider.userId > 0
							then `rbxthumb://type=AvatarHeadShot&id={hider.userId}&w=100&h=100`
							else "",
						ImageTransparency = if sectionName == "Eliminated" then 0.45 else 0,
						Position = UDim2.new(0, 9, 0.5, 0),
						Size = UDim2.fromOffset(rosterRowHeight - 10, rosterRowHeight - 10),
						ZIndex = 7,
					}, {
						Corner = e("UICorner", {
							CornerRadius = UDim.new(1, 0),
						}),
					}),
					Name = e("TextLabel", {
						BackgroundTransparency = 1,
						FontFace = GOTHAM_MEDIUM,
						Position = UDim2.new(0, rosterRowHeight + 5, 0, 0),
						Size = UDim2.new(1, -(rosterRowHeight + 13), 1, 0),
						Text = if hider.userId == localPlayer.UserId then `{hider.name} (YOU)` else hider.name,
						TextColor3 = if sectionName == "Eliminated"
							then Color3.fromRGB(154, 162, 175)
							else Color3.fromRGB(232, 237, 245),
						TextSize = if compactRoster then 11 else 13,
						TextTruncate = Enum.TextTruncate.AtEnd,
						TextXAlignment = Enum.TextXAlignment.Left,
						ZIndex = 6,
					}),
				})
			end
		end

		return e("Frame", {
			BackgroundTransparency = 1,
			LayoutOrder = layoutOrder,
			Size = UDim2.new(1, 0, 0, sectionHeight),
		}, sectionChildren)
	end

	local activeSectionHeight = 25 + math.max(1, #activeHiders) * rosterRowHeight
	local taggedSectionHeight = 25 + math.max(1, #taggedHiders) * rosterRowHeight
	local winnerSectionHeight = 25 + math.max(1, #winnerHiders) * rosterRowHeight
	local eliminatedSectionHeight = 25 + math.max(1, #eliminatedHiders) * rosterRowHeight
	local rosterPanelHeight = 52
		+ activeSectionHeight
		+ taggedSectionHeight
		+ winnerSectionHeight
		+ eliminatedSectionHeight
		+ 12
	local rosterSections = {
		Layout = e("UIListLayout", {
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		Active = createRosterSection("Active", ACTIVE_HIDER_COLOR, activeHiders, 1),
		Tagged = createRosterSection("Tagged", TAGGED_HIDER_COLOR, taggedHiders, 2),
		Winners = createRosterSection("Winners", WINNER_HIDER_COLOR, winnerHiders, 3),
		Eliminated = createRosterSection("Eliminated", ELIMINATED_HIDER_COLOR, eliminatedHiders, 4),
	}

	return e(React.Fragment, nil, {
		SeekerBlackout = e("Frame", {
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(-100, -100),
			Size = UDim2.new(1, 200, 1, 200),
			ZIndex = 1,
			ref = blackoutRef,
		}),

		TaggedScreenBorder = e("Frame", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			Visible = taggedHiderAlertVisible,
			ZIndex = 10,
		}, {
			Top = e("Frame", {
				BackgroundColor3 = TAGGED_ALERT_COLOR,
				BorderSizePixel = 0,
				Size = UDim2.new(1, 0, 0, 12),
				ZIndex = 10,
			}),
			Bottom = e("Frame", {
				AnchorPoint = Vector2.new(0, 1),
				BackgroundColor3 = TAGGED_ALERT_COLOR,
				BorderSizePixel = 0,
				Position = UDim2.fromScale(0, 1),
				Size = UDim2.new(1, 0, 0, 12),
				ZIndex = 10,
			}),
			Left = e("Frame", {
				BackgroundColor3 = TAGGED_ALERT_COLOR,
				BorderSizePixel = 0,
				Size = UDim2.new(0, 12, 1, 0),
				ZIndex = 10,
			}),
			Right = e("Frame", {
				AnchorPoint = Vector2.new(1, 0),
				BackgroundColor3 = TAGGED_ALERT_COLOR,
				BorderSizePixel = 0,
				Position = UDim2.fromScale(1, 0),
				Size = UDim2.new(0, 12, 1, 0),
				ZIndex = 10,
			}),
		}),

		RoundResult = e("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Color3.fromRGB(10, 16, 25),
			BackgroundTransparency = 0.14,
			BorderSizePixel = 0,
			FontFace = GOTHAM_HEAVY,
			Position = UDim2.fromScale(0.5, 0.48),
			Size = UDim2.new(0.72, 0, 0, 150),
			Text = roundResultText,
			TextColor3 = roundResultColor,
			TextScaled = true,
			TextStrokeColor3 = Color3.fromRGB(5, 8, 13),
			TextStrokeTransparency = 0.12,
			Visible = roundResultVisible,
			ZIndex = 20,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 22),
			}),
			SizeConstraint = e("UISizeConstraint", {
				MaxSize = Vector2.new(720, 150),
				MinSize = Vector2.new(280, 110),
			}),
			Stroke = e("UIStroke", {
				Color = roundResultColor,
				Thickness = 4,
				Transparency = 0.08,
			}),
			TextConstraint = e("UITextSizeConstraint", {
				MaxTextSize = 92,
				MinTextSize = 44,
			}),
		}),

		PhaseLabel = e("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundTransparency = 1,
			FontFace = GOTHAM_BOLD,
			Position = if hasRole then UDim2.new(0.5, 0, 0, 58) else UDim2.new(0.5, 0, 0, 18),
			Size = UDim2.new(
				if taggedHiderAlertVisible then 0.82 else 0.68,
				0,
				0,
				if taggedHiderAlertVisible then 100 elseif seeking and role ~= "Spectator" then 78 else 42
			),
			Text = phaseText,
			TextColor3 = phaseColor,
			TextScaled = true,
			TextStrokeColor3 = Color3.fromRGB(10, 18, 28),
			TextStrokeTransparency = 0.35,
			TextWrapped = true,
			Visible = not selecting,
			ZIndex = 2,
		}, {
			UITextSizeConstraint = e("UITextSizeConstraint", {
				MaxTextSize = if taggedHiderAlertVisible then 30 else 36,
				MinTextSize = if taggedHiderAlertVisible then 14 else 20,
			}),
		}),

		Crosshair = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(34, 34),
			Visible = seeking and role == "Seeker" and not cursorActive,
			ZIndex = 4,
		}, {
			Top = e("Frame", {
				AnchorPoint = Vector2.new(0.5, 1),
				BackgroundColor3 = Color3.new(1, 1, 1),
				BorderSizePixel = 0,
				Position = UDim2.new(0.5, 0, 0.5, -4),
				Size = UDim2.fromOffset(2, 8),
			}),
			Bottom = e("Frame", {
				AnchorPoint = Vector2.new(0.5, 0),
				BackgroundColor3 = Color3.new(1, 1, 1),
				BorderSizePixel = 0,
				Position = UDim2.new(0.5, 0, 0.5, 4),
				Size = UDim2.fromOffset(2, 8),
			}),
			Left = e("Frame", {
				AnchorPoint = Vector2.new(1, 0.5),
				BackgroundColor3 = Color3.new(1, 1, 1),
				BorderSizePixel = 0,
				Position = UDim2.new(0.5, -4, 0.5, 0),
				Size = UDim2.fromOffset(8, 2),
			}),
			Right = e("Frame", {
				AnchorPoint = Vector2.new(0, 0.5),
				BackgroundColor3 = Color3.new(1, 1, 1),
				BorderSizePixel = 0,
				Position = UDim2.new(0.5, 4, 0.5, 0),
				Size = UDim2.fromOffset(8, 2),
			}),
			Dot = e("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = Color3.new(1, 1, 1),
				BorderSizePixel = 0,
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(4, 4),
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(1, 0),
				}),
			}),
		}),

		TagButton = e("TextButton", {
			ref = tagButtonRef,
			Active = true,
			AnchorPoint = Vector2.new(0.5, 0.5),
			AutoButtonColor = true,
			BackgroundColor3 = SEEKING_COLOR,
			BackgroundTransparency = 0.08,
			BorderSizePixel = 0,
			FontFace = GOTHAM_HEAVY,
			Position = UDim2.new(1, -190, 1, -105),
			Size = UDim2.fromOffset(88, 88),
			Text = "TAG",
			TextColor3 = Color3.new(1, 1, 1),
			TextSize = 22,
			TextStrokeColor3 = Color3.fromRGB(91, 20, 24),
			TextStrokeTransparency = 0.35,
			Visible = touchEnabled and seeking and role == "Seeker",
			ZIndex = 8,
			[React.Event.Activated] = requestCenteredTag,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(1, 0),
			}),
			Stroke = e("UIStroke", {
				Color = Color3.fromRGB(255, 224, 224),
				Thickness = 3,
				Transparency = 0.12,
			}),
			Scale = e("UIScale", {
				Scale = 1,
			}),
		}),

		TimerLabel = e("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundTransparency = 1,
			FontFace = GOTHAM_HEAVY,
			Position = if hasRole then UDim2.new(0.5, 0, 0, 104) else UDim2.new(0.5, 0, 0, 58),
			Size = UDim2.fromOffset(190, 100),
			Text = tostring(math.max(0, math.floor(numericTimeRemaining))),
			TextColor3 = if timerWarning then WARNING_TIMER_COLOR else NORMAL_TIMER_COLOR,
			TextScaled = true,
			TextStrokeColor3 = Color3.fromRGB(8, 12, 20),
			TextStrokeTransparency = 0.25,
			TextWrapped = true,
			Visible = timerVisible,
			ZIndex = 2,
		}, {
			PulseScale = e("UIScale", {
				ref = pulseScaleRef,
				Scale = 1,
			}),
		}),

		StatusLabel = e("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundTransparency = 1,
			FontFace = GOTHAM_MEDIUM,
			Position = UDim2.new(0.5, 0, 0, 66),
			Size = UDim2.new(0.6, 0, 0, 30),
			Text = waitingStatusText,
			TextColor3 = Color3.fromRGB(235, 239, 246),
			TextSize = 18,
			TextStrokeColor3 = Color3.fromRGB(8, 12, 20),
			TextStrokeTransparency = 0.55,
			Visible = waiting,
			ZIndex = 2,
		}),

		SelectionOverlay = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Color3.fromRGB(12, 18, 29),
			BackgroundTransparency = 0.08,
			BorderSizePixel = 0,
			Position = UDim2.new(0.5, 0, 0.42, 0),
			Size = UDim2.new(if compactSelectionCards then 0.92 else 0.82, 0, 0, 250),
			Visible = selecting,
			ZIndex = 5,
		}, {
			SizeConstraint = e("UISizeConstraint", {
				MaxSize = Vector2.new(620, 250),
				MinSize = Vector2.new(300, 230),
			}),
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 22),
			}),
			Stroke = e("UIStroke", {
				Color = SELECTION_ACCENT_COLOR,
				Thickness = 2,
				Transparency = 0.15,
			}),
			Gradient = e("UIGradient", {
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.fromRGB(31, 40, 61)),
					ColorSequenceKeypoint.new(1, Color3.fromRGB(12, 18, 29)),
				}),
				Rotation = 90,
			}),
			Title = e("TextLabel", {
				AnchorPoint = Vector2.new(0.5, 0),
				BackgroundTransparency = 1,
				FontFace = GOTHAM_HEAVY,
				Position = UDim2.new(0.5, 0, 0, 20),
				Size = UDim2.new(1, -30, 0, 36),
				Text = "WHO WILL SEEK?",
				TextColor3 = SELECTION_ACCENT_COLOR,
				TextScaled = true,
				TextStrokeColor3 = Color3.fromRGB(6, 10, 18),
				TextStrokeTransparency = 0.3,
				ZIndex = 7,
			}, {
				TextConstraint = e("UITextSizeConstraint", {
					MaxTextSize = 30,
					MinTextSize = 20,
				}),
			}),
			Subtitle = e("TextLabel", {
				AnchorPoint = Vector2.new(0.5, 0),
				BackgroundTransparency = 1,
				FontFace = GOTHAM_MEDIUM,
				Position = UDim2.new(0.5, 0, 0, 58),
				Size = UDim2.new(1, -30, 0, 22),
				Text = "THE ROULETTE IS SPINNING...",
				TextColor3 = Color3.fromRGB(221, 227, 239),
				TextSize = 14,
				ZIndex = 7,
			}),
			CandidateStrip = e("Frame", {
				AnchorPoint = Vector2.new(0.5, 0),
				BackgroundTransparency = 1,
				ClipsDescendants = true,
				Position = UDim2.new(0.5, 0, 0, 92),
				Size = UDim2.new(1, -28, 0, 128),
				ZIndex = 6,
			}, selectionCards),
		}),

		RoleLabel = e("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundColor3 = Color3.fromRGB(15, 22, 34),
			BackgroundTransparency = 0.2,
			BorderSizePixel = 0,
			FontFace = GOTHAM_BOLD,
			Position = UDim2.new(0.5, 0, 0, 14),
			Size = UDim2.fromOffset(if practiceModeActive == true then 280 else 220, 38),
			Text = roleText,
			TextColor3 = roleColor,
			TextSize = 20,
			TextStrokeColor3 = Color3.fromRGB(8, 12, 20),
			TextStrokeTransparency = 0.55,
			Visible = hasRole and not selecting,
			ZIndex = 2,
		}, {
			UICorner = e("UICorner", {
				CornerRadius = UDim.new(0, 9),
			}),
			UIStroke = e("UIStroke", {
				Color = roleColor,
				Thickness = 1.5,
				Transparency = 0.25,
			}),
		}),

		ResetButton = e("TextButton", {
			ref = resetButtonRef,
			Active = not resetPendingRef.current,
			AnchorPoint = Vector2.new(1, 0),
			BackgroundColor3 = Color3.fromRGB(38, 48, 66),
			BorderSizePixel = 0,
			FontFace = GOTHAM_BOLD,
			Modal = cursorActive,
			Position = UDim2.new(1, -20, 0, 20),
			Size = UDim2.fromOffset(138, 34),
			Text = buttonText,
			TextColor3 = Color3.new(1, 1, 1),
			TextSize = 12,
			ZIndex = 3,
			[React.Event.Activated] = requestReset,
		}, {
			UICorner = e("UICorner", {
				CornerRadius = UDim.new(0, 8),
			}),
			UIStroke = e("UIStroke", {
				ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
				Color = Color3.fromRGB(255, 111, 111),
				LineJoinMode = Enum.LineJoinMode.Round,
				Thickness = 2,
				Transparency = 0.15,
			}),
		}),

		ReturnToLobbyButton = e("TextButton", {
			Active = not returnPendingRef.current,
			AnchorPoint = Vector2.new(1, 0),
			BackgroundColor3 = Color3.fromRGB(31, 40, 55),
			BackgroundTransparency = 0.18,
			BorderSizePixel = 0,
			FontFace = GOTHAM_BOLD,
			Position = UDim2.new(1, -20, 0, 64),
			Size = UDim2.fromOffset(138, 34),
			Text = lobbyButtonText,
			TextColor3 = Color3.fromRGB(210, 220, 235),
			TextSize = 12,
			ZIndex = 3,
			[React.Event.Activated] = requestReturnToLobby,
		}, {
			UICorner = e("UICorner", {
				CornerRadius = UDim.new(0, 8),
			}),
			UIStroke = e("UIStroke", {
				ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
				Color = Color3.fromRGB(139, 164, 199),
				LineJoinMode = Enum.LineJoinMode.Round,
				Thickness = 1,
				Transparency = 0.45,
			}),
		}),

		HiderRosterPanel = e("Frame", {
			AnchorPoint = Vector2.new(1, 0),
			BackgroundColor3 = Color3.fromRGB(13, 20, 31),
			BackgroundTransparency = 0.12,
			BorderSizePixel = 0,
			Position = UDim2.new(1, if compactRoster then -10 else -20, 0, 112),
			Size = UDim2.fromOffset(rosterWidth, rosterPanelHeight),
			Visible = (phase == "Hiding" or seeking) and #hiderRoster > 0,
			ZIndex = 4,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 12),
			}),
			Stroke = e("UIStroke", {
				Color = Color3.fromRGB(91, 108, 134),
				Thickness = 1.25,
				Transparency = 0.38,
			}),
			Title = e("TextLabel", {
				BackgroundTransparency = 1,
				FontFace = GOTHAM_HEAVY,
				Position = UDim2.fromOffset(12, 8),
				Size = UDim2.new(1, -58, 0, 28),
				Text = "HIDER ROSTER",
				TextColor3 = Color3.fromRGB(236, 241, 249),
				TextSize = if compactRoster then 14 else 16,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 5,
			}),
			Total = e("TextLabel", {
				AnchorPoint = Vector2.new(1, 0),
				BackgroundColor3 = Color3.fromRGB(45, 58, 78),
				BackgroundTransparency = 0.18,
				BorderSizePixel = 0,
				FontFace = GOTHAM_BOLD,
				Position = UDim2.new(1, -10, 0, 10),
				Size = UDim2.fromOffset(28, 24),
				Text = tostring(#hiderRoster),
				TextColor3 = Color3.fromRGB(216, 225, 239),
				TextSize = 12,
				ZIndex = 5,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(1, 0),
				}),
			}),
			Sections = e("Frame", {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(10, 42),
				Size = UDim2.new(1, -20, 1, -50),
				ZIndex = 5,
			}, rosterSections),
		}),

		ControlsGuide = e("TextLabel", {
			AnchorPoint = Vector2.new(0, 1),
			BackgroundColor3 = Color3.fromRGB(15, 22, 34),
			BackgroundTransparency = 0.32,
			BorderSizePixel = 0,
			FontFace = GOTHAM_MEDIUM,
			Position = UDim2.new(0, 18, 1, -18),
			Size = UDim2.fromOffset(315, 62),
			Text = controlsGuideText,
			TextColor3 = if cursorActive then CURSOR_GUIDE_COLOR else DEFAULT_GUIDE_COLOR,
			TextSize = 13,
			TextTransparency = 0.12,
			TextXAlignment = Enum.TextXAlignment.Left,
			Visible = UserInputService.KeyboardEnabled,
			ZIndex = 2,
		}, {
			UICorner = e("UICorner", {
				CornerRadius = UDim.new(0, 8),
			}),
			UIPadding = e("UIPadding", {
				PaddingLeft = UDim.new(0, 14),
				PaddingRight = UDim.new(0, 14),
			}),
		}),
	})
end

return RoundApp
