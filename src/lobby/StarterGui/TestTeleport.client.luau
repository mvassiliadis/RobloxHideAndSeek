--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local lobbyRemotes = ReplicatedStorage:WaitForChild("LobbyRemotes")
local teleportAllRequested = lobbyRemotes:WaitForChild("TeleportAllRequested") :: RemoteEvent
local screenGui = script.Parent :: ScreenGui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 1)
panel.BackgroundColor3 = Color3.fromRGB(19, 24, 34)
panel.BackgroundTransparency = 0.08
panel.BorderSizePixel = 0
panel.Position = UDim2.new(0.5, 0, 1, -32)
panel.Size = UDim2.fromOffset(310, 110)
panel.Parent = screenGui

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 14)
panelCorner.Parent = panel

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = Color3.fromRGB(255, 255, 255)
panelStroke.Transparency = 0.82
panelStroke.Thickness = 1
panelStroke.Parent = panel

local teleportButton = Instance.new("TextButton")
teleportButton.Name = "TeleportAllButton"
teleportButton.AnchorPoint = Vector2.new(0.5, 0)
teleportButton.AutoButtonColor = true
teleportButton.BackgroundColor3 = Color3.fromRGB(60, 132, 255)
teleportButton.BorderSizePixel = 0
teleportButton.Font = Enum.Font.GothamBold
teleportButton.Position = UDim2.new(0.5, 0, 0, 10)
teleportButton.Size = UDim2.fromOffset(290, 50)
teleportButton.Text = "TELEPORT ALL TO MATCH"
teleportButton.TextColor3 = Color3.fromRGB(255, 255, 255)
teleportButton.TextSize = 17
teleportButton.Parent = panel

local buttonCorner = Instance.new("UICorner")
buttonCorner.CornerRadius = UDim.new(0, 10)
buttonCorner.Parent = teleportButton

local statusLabel = Instance.new("TextLabel")
statusLabel.Name = "Status"
statusLabel.AnchorPoint = Vector2.new(0.5, 1)
statusLabel.BackgroundTransparency = 1
statusLabel.Font = Enum.Font.GothamMedium
statusLabel.Position = UDim2.new(0.5, 0, 1, -8)
statusLabel.Size = UDim2.new(1, -20, 0, 36)
statusLabel.Text = "TEST ONLY - Anyone can start the match"
statusLabel.TextColor3 = Color3.fromRGB(184, 193, 209)
statusLabel.TextSize = 12
statusLabel.TextWrapped = true
statusLabel.Parent = panel

local requestPending = false

local function setReady()
	requestPending = false
	teleportButton.Active = true
	teleportButton.AutoButtonColor = true
	teleportButton.BackgroundColor3 = Color3.fromRGB(60, 132, 255)
	teleportButton.Text = "TELEPORT ALL TO MATCH"
end

teleportButton.Activated:Connect(function()
	if requestPending then
		return
	end

	requestPending = true
	teleportButton.Active = false
	teleportButton.AutoButtonColor = false
	teleportButton.BackgroundColor3 = Color3.fromRGB(77, 87, 105)
	teleportButton.Text = "REQUESTING TELEPORT..."
	statusLabel.Text = "Contacting the server..."
	teleportAllRequested:FireServer()
end)

teleportAllRequested.OnClientEvent:Connect(function(status: string, message: string)
	statusLabel.Text = message

	if status == "Failed" then
		statusLabel.TextColor3 = Color3.fromRGB(255, 151, 151)
		setReady()
	elseif status == "Teleporting" then
		requestPending = true
		teleportButton.Active = false
		teleportButton.AutoButtonColor = false
		teleportButton.BackgroundColor3 = Color3.fromRGB(77, 87, 105)
		teleportButton.Text = "TELEPORTING..."
		statusLabel.TextColor3 = Color3.fromRGB(184, 193, 209)
	end
end)
