--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(packages:WaitForChild("React"))

local roundState = ReplicatedStorage:WaitForChild("RoundState")
local resetRequested = roundState:WaitForChild("ResetRequested") :: RemoteEvent
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

local DEFAULT_GUIDE_TEXT = "WASD  MOVE   •   MOUSE  LOOK\nHOLD ALT  CURSOR   •   HOLD R  RESET"
local CURSOR_GUIDE_TEXT = "CURSOR ACTIVE\nRELEASE ALT TO LOOK"
local R_HOLD_SECONDS = 1

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

local function RoundApp()
	local phase, setPhase = React.useState(roundState:GetAttribute("Phase"))
	local timeRemaining, setTimeRemaining = React.useState(roundState:GetAttribute("TimeRemaining"))
	local connectedPlayers, setConnectedPlayers = React.useState(roundState:GetAttribute("ConnectedPlayers"))
	local startTimeRemaining, setStartTimeRemaining = React.useState(roundState:GetAttribute("StartTimeRemaining"))
	local selectionUserIds, setSelectionUserIds = React.useState(roundState:GetAttribute("SelectionUserIds"))
	local selectedSeekerUserId, setSelectedSeekerUserId = React.useState(roundState:GetAttribute("SelectedSeekerUserId"))
	local roleSelectionDuration, setRoleSelectionDuration = React.useState(roundState:GetAttribute("RoleSelectionDuration"))
	local roleSelectionEndTime, setRoleSelectionEndTime = React.useState(roundState:GetAttribute("RoleSelectionEndTime"))
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
	local resetButtonRef = React.useRef(nil)
	local pulseScaleRef = React.useRef(nil)

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

	React.useEffect(function()
		mountedRef.current = true

		local connections = {
			roundState:GetAttributeChangedSignal("Phase"):Connect(function()
				setPhase(roundState:GetAttribute("Phase"))
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
			localPlayer:GetAttributeChangedSignal("Role"):Connect(function()
				setRole(localPlayer:GetAttribute("Role"))
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
				end
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
			localPlayer.CharacterAdded:Connect(refreshLockedCursor),
		}

		refreshLockedCursor()

		return function()
			mountedRef.current = false
			rHeldRef.current = false
			rHoldGenerationRef.current += 1
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
	local selectionCandidates = parseUserIds(selectionUserIds)
	local waiting = phase == "WaitingToStart"
	local starting = waiting and numericConnectedPlayers >= 2 and numericStartTimeRemaining > 0
	local selecting = phase == "SelectingRoles"
	local seeking = phase == "Seeking"
	local timerVisible = phase == "Hiding"
	local timerWarning = timerVisible and numericTimeRemaining <= 5 and numericTimeRemaining > 0

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

	local phaseText = if starting
		then "ROUND STARTING"
		elseif waiting
		then "WAITING FOR PLAYERS"
		elseif selecting
		then "CHOOSING THE SEEKER"
		elseif seeking
		then if role == "Seeker"
			then "FIND THEM!"
			elseif role == "Hider"
			then "STAY OUT OF SIGHT OF THE SEEKER"
			else "SEEKING"
		else if role == "Seeker"
		then "WAIT FOR PLAYERS TO HIDE"
		elseif role == "Hider"
		then "GO HIDE!"
		else "HIDING"
	local phaseColor = if waiting then WAITING_COLOR elseif seeking then SEEKING_COLOR else HIDING_COLOR
	local waitingStatusText = if starting
		then `Starting in {math.max(0, math.floor(numericStartTimeRemaining))}...`
		else "Need at least 2 players"
	local roleText = if role == "Seeker"
		then "You are the seeker"
		elseif role == "Hider"
		then "You are hiding"
		elseif role == "Spectator"
		then "You are spectating"
		else ""
	local roleColor = if role == "Seeker"
		then SEEKING_COLOR
		elseif role == "Hider"
		then HIDING_COLOR
		else Color3.fromRGB(210, 216, 225)
	local hasRole = roleText ~= ""
	local compactSelectionCards = UserInputService.TouchEnabled
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

	return e(React.Fragment, nil, {
		PhaseLabel = e("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundTransparency = 1,
			FontFace = GOTHAM_BOLD,
			Position = if hasRole then UDim2.new(0.5, 0, 0, 58) else UDim2.new(0.5, 0, 0, 18),
			Size = UDim2.new(0.68, 0, 0, 42),
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
				MaxTextSize = 36,
				MinTextSize = 20,
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
			Size = UDim2.fromOffset(220, 38),
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

		ControlsGuide = e("TextLabel", {
			AnchorPoint = Vector2.new(0, 1),
			BackgroundColor3 = Color3.fromRGB(15, 22, 34),
			BackgroundTransparency = 0.32,
			BorderSizePixel = 0,
			FontFace = GOTHAM_MEDIUM,
			Position = UDim2.new(0, 18, 1, -18),
			Size = UDim2.fromOffset(315, 62),
			Text = if cursorActive then CURSOR_GUIDE_TEXT else DEFAULT_GUIDE_TEXT,
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
