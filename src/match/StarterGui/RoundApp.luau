--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(packages:WaitForChild("React"))

local roundState = ReplicatedStorage:WaitForChild("RoundState")
local resetRequested = roundState:WaitForChild("ResetRequested") :: RemoteEvent
local localPlayer = Players.LocalPlayer

local e = React.createElement

local WAITING_COLOR = Color3.fromRGB(255, 210, 105)
local HIDING_COLOR = Color3.fromRGB(104, 213, 255)
local SEEKING_COLOR = Color3.fromRGB(255, 92, 92)
local NORMAL_TIMER_COLOR = Color3.fromRGB(255, 255, 255)
local WARNING_TIMER_COLOR = Color3.fromRGB(255, 105, 105)
local DEFAULT_GUIDE_COLOR = Color3.fromRGB(222, 230, 241)
local CURSOR_GUIDE_COLOR = Color3.fromRGB(255, 220, 130)

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

local function RoundApp()
	local phase, setPhase = React.useState(roundState:GetAttribute("Phase"))
	local timeRemaining, setTimeRemaining = React.useState(roundState:GetAttribute("TimeRemaining"))
	local connectedPlayers, setConnectedPlayers = React.useState(roundState:GetAttribute("ConnectedPlayers"))
	local startTimeRemaining, setStartTimeRemaining = React.useState(roundState:GetAttribute("StartTimeRemaining"))
	local role, setRole = React.useState(localPlayer:GetAttribute("Role"))
	local buttonText, setButtonText = React.useState("RESET ROUND")
	local cursorActive, setCursorActive = React.useState(false)

	local mountedRef = React.useRef(false)
	local resetPendingRef = React.useRef(false)
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
			localPlayer:GetAttributeChangedSignal("Role"):Connect(function()
				setRole(localPlayer:GetAttribute("Role"))
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
	local waiting = phase == "WaitingToStart"
	local starting = waiting and numericConnectedPlayers >= 2 and numericStartTimeRemaining > 0
	local seeking = phase == "Seeking"
	local timerVisible = not waiting and not seeking
	local timerWarning = timerVisible and numericTimeRemaining <= 5 and numericTimeRemaining > 0

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
			Visible = hasRole,
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
			Size = UDim2.fromOffset(170, 46),
			Text = buttonText,
			TextColor3 = Color3.new(1, 1, 1),
			TextSize = 16,
			ZIndex = 3,
			[React.Event.Activated] = requestReset,
		}, {
			UICorner = e("UICorner", {
				CornerRadius = UDim.new(0, 10),
			}),
			UIStroke = e("UIStroke", {
				ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
				Color = Color3.fromRGB(255, 111, 111),
				LineJoinMode = Enum.LineJoinMode.Round,
				Thickness = 2,
				Transparency = 0.15,
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
