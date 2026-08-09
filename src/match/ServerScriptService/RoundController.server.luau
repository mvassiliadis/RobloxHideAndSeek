--!strict

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local MIN_PLAYERS = 2
local MAX_HIDERS = 4
local MAX_ROUND_PLAYERS = 1 + MAX_HIDERS
local AUTOMATIC_START_DELAY = 5
local ROLE_SELECTION_DURATION = 5
local PRACTICE_ROLE_SELECTION_DURATION = 1

local WAITING_PHASE = "WaitingToStart"
local SELECTING_PHASE = "SelectingRoles"
local HIDING_PHASE = "Hiding"
local SEEKING_PHASE = "Seeking"
local SEEKER_ROLE = "Seeker"
local HIDER_ROLE = "Hider"
local SPECTATOR_ROLE = "Spectator"
local RESET_DEBOUNCE_SECONDS = 1
local CHARACTER_SPAWN_OFFSET = 3
local WAITING_SPAWN_COLUMNS = 4
local WAITING_SPAWN_SPACING = 6
local MAX_TAG_DISTANCE = 300
local MAX_CAMERA_ORIGIN_OFFSET = 8
local TAG_REQUEST_COOLDOWN = 0.15
local POST_CAPTURE_RADIUS = 8
local POST_AWAY_RADIUS = 12
local ROUND_COMPLETE_DELAY = 2
local POST_INDICATOR_SEGMENT_COUNT = 24
local POST_GROUND_SAMPLE_COUNT = 8
local POST_GROUND_SAMPLE_RADIUS = POST_CAPTURE_RADIUS
local POST_GROUND_RAY_START_HEIGHT = 16
local POST_GROUND_RAY_LENGTH = 128
local POST_INDICATOR_FILL_HEIGHT = 0.035
local POST_INDICATOR_BOUNDARY_HEIGHT = 0.055
local POST_INDICATOR_SURFACE_GAP = 0.008
local POST_INDICATOR_COLOR = Color3.fromRGB(255, 92, 92)

type Role = "Seeker" | "Hider" | "Spectator"
type TagTarget = Player | Model
type HiderStatus = "Active" | "Tagged" | "Eliminated"
type HiderRosterEntry = {
	id: string,
	userId: number,
	name: string,
	status: HiderStatus,
	isPractice: boolean,
}

local roundState = ReplicatedStorage:WaitForChild("RoundState")
local resetRequested = roundState:WaitForChild("ResetRequested") :: RemoteEvent
local tagRequested = roundState:WaitForChild("TagRequested") :: RemoteEvent
local roundRandom = Random.new()

local roundSpawnsInstance = Workspace:FindFirstChild("RoundSpawns")
assert(
	roundSpawnsInstance and (roundSpawnsInstance:IsA("Folder") or roundSpawnsInstance:IsA("Model")),
	"Workspace.RoundSpawns must be a Folder or Model"
)
local roundSpawns = roundSpawnsInstance :: Folder | Model

local hiderSpawnsInstance = roundSpawns:FindFirstChild("HiderSpawns")
assert(
	hiderSpawnsInstance and (hiderSpawnsInstance:IsA("Folder") or hiderSpawnsInstance:IsA("Model")),
	"Workspace.RoundSpawns.HiderSpawns must be a Folder or Model"
)
local hiderSpawnsContainer = hiderSpawnsInstance :: Folder | Model

local function getSpawnMarker(name: string): BasePart
	local marker = roundSpawns:FindFirstChild(name)
	assert(marker and marker:IsA("BasePart"), `Workspace.RoundSpawns.{name} must be a BasePart`)

	return marker :: BasePart
end

local function configureSpawnMarker(marker: BasePart)
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanTouch = false
	marker.CanQuery = false
	marker.Transparency = 1
end

local waitingSpawn = getSpawnMarker("WaitingSpawn")
local seekerHoldingSpawn = getSpawnMarker("SeekerHoldingSpawn")
local hiderSpawns: { BasePart } = {}

for _, child in hiderSpawnsContainer:GetChildren() do
	if child:IsA("BasePart") then
		table.insert(hiderSpawns, child)
	end
end

assert(
	#hiderSpawns >= MAX_HIDERS,
	`Workspace.RoundSpawns.HiderSpawns must contain at least {MAX_HIDERS} BaseParts`
)

configureSpawnMarker(waitingSpawn)
configureSpawnMarker(seekerHoldingSpawn)
for _, marker in hiderSpawns do
	configureSpawnMarker(marker)
end

local seekerPostIndicator = Instance.new("Model")
seekerPostIndicator.Name = "RuntimeSeekerPostIndicator"
seekerPostIndicator:SetAttribute("RuntimeGenerated", true)

local seekerPostIndicatorAnchor = Instance.new("Part")
seekerPostIndicatorAnchor.Name = "Anchor"
seekerPostIndicatorAnchor.Anchored = true
seekerPostIndicatorAnchor.CanCollide = false
seekerPostIndicatorAnchor.CanQuery = false
seekerPostIndicatorAnchor.CanTouch = false
seekerPostIndicatorAnchor.CastShadow = false
seekerPostIndicatorAnchor.Size = Vector3.new(0.1, 0.1, 0.1)
seekerPostIndicatorAnchor.Transparency = 1
seekerPostIndicatorAnchor.Parent = seekerPostIndicator
seekerPostIndicator.PrimaryPart = seekerPostIndicatorAnchor

local seekerPostIndicatorFill = Instance.new("Part")
seekerPostIndicatorFill.Name = "CaptureArea"
seekerPostIndicatorFill.Anchored = true
seekerPostIndicatorFill.CanCollide = false
seekerPostIndicatorFill.CanQuery = false
seekerPostIndicatorFill.CanTouch = false
seekerPostIndicatorFill.CastShadow = false
seekerPostIndicatorFill.Color = POST_INDICATOR_COLOR
seekerPostIndicatorFill.Material = Enum.Material.Neon
seekerPostIndicatorFill.Shape = Enum.PartType.Cylinder
seekerPostIndicatorFill.Size = Vector3.new(
	POST_INDICATOR_FILL_HEIGHT,
	POST_CAPTURE_RADIUS * 2,
	POST_CAPTURE_RADIUS * 2
)
seekerPostIndicatorFill.Transparency = 1
seekerPostIndicatorFill.Parent = seekerPostIndicator

local seekerPostIndicatorSegments: { Part } = {}
local postIndicatorSegmentLength = (2 * math.pi * POST_CAPTURE_RADIUS / POST_INDICATOR_SEGMENT_COUNT) * 0.72
for index = 1, POST_INDICATOR_SEGMENT_COUNT do
	local segment = Instance.new("Part")
	segment.Name = `Boundary{index}`
	segment.Anchored = true
	segment.CanCollide = false
	segment.CanQuery = false
	segment.CanTouch = false
	segment.CastShadow = false
	segment.Color = POST_INDICATOR_COLOR
	segment.Material = Enum.Material.Neon
	segment.Size = Vector3.new(0.32, POST_INDICATOR_BOUNDARY_HEIGHT, postIndicatorSegmentLength)
	segment.Transparency = 1
	segment.Parent = seekerPostIndicator
	table.insert(seekerPostIndicatorSegments, segment)
end

local seekerPostBillboard = Instance.new("BillboardGui")
seekerPostBillboard.Name = "Label"
seekerPostBillboard.Adornee = seekerPostIndicatorAnchor
seekerPostBillboard.AlwaysOnTop = true
seekerPostBillboard.Enabled = false
seekerPostBillboard.LightInfluence = 0
seekerPostBillboard.MaxDistance = 250
seekerPostBillboard.Size = UDim2.fromOffset(230, 58)
seekerPostBillboard.StudsOffsetWorldSpace = Vector3.new(0, 3.8, 0)
seekerPostBillboard.Parent = seekerPostIndicatorAnchor

local seekerPostLabel = Instance.new("TextLabel")
seekerPostLabel.BackgroundColor3 = Color3.fromRGB(15, 22, 34)
seekerPostLabel.BackgroundTransparency = 0.16
seekerPostLabel.BorderSizePixel = 0
seekerPostLabel.Font = Enum.Font.GothamBold
seekerPostLabel.Size = UDim2.fromScale(1, 1)
seekerPostLabel.Text = "SEEKER POST\nRETURN TAGS HERE"
seekerPostLabel.TextColor3 = Color3.fromRGB(255, 230, 230)
seekerPostLabel.TextScaled = true
seekerPostLabel.TextStrokeColor3 = Color3.fromRGB(40, 8, 12)
seekerPostLabel.TextStrokeTransparency = 0.45
seekerPostLabel.Parent = seekerPostBillboard

local seekerPostLabelCorner = Instance.new("UICorner")
seekerPostLabelCorner.CornerRadius = UDim.new(0, 10)
seekerPostLabelCorner.Parent = seekerPostLabel

local seekerPostLabelStroke = Instance.new("UIStroke")
seekerPostLabelStroke.Color = POST_INDICATOR_COLOR
seekerPostLabelStroke.Thickness = 2
seekerPostLabelStroke.Transparency = 0.12
seekerPostLabelStroke.Parent = seekerPostLabel

local seekerPostLabelPadding = Instance.new("UIPadding")
seekerPostLabelPadding.PaddingBottom = UDim.new(0, 5)
seekerPostLabelPadding.PaddingLeft = UDim.new(0, 9)
seekerPostLabelPadding.PaddingRight = UDim.new(0, 9)
seekerPostLabelPadding.PaddingTop = UDim.new(0, 5)
seekerPostLabelPadding.Parent = seekerPostLabel

local seekerPostGroundRaycastParameters = RaycastParams.new()
seekerPostGroundRaycastParameters.FilterType = Enum.RaycastFilterType.Exclude
seekerPostGroundRaycastParameters.FilterDescendantsInstances = { roundSpawns, seekerPostIndicator }
seekerPostGroundRaycastParameters.IgnoreWater = false

local seekerPostSurfaceCFrame = CFrame.new()

local function getHorizontalPostCFrame(height: number): CFrame
	local postCFrame = seekerHoldingSpawn.CFrame
	local horizontalLookVector = Vector3.new(postCFrame.LookVector.X, 0, postCFrame.LookVector.Z)
	if horizontalLookVector.Magnitude < 0.001 then
		horizontalLookVector = Vector3.new(0, 0, -1)
	else
		horizontalLookVector = horizontalLookVector.Unit
	end

	local position = Vector3.new(postCFrame.Position.X, height, postCFrame.Position.Z)
	return CFrame.lookAt(position, position + horizontalLookVector)
end

local function getSeekerPostGroundHeight(horizontalPostCFrame: CFrame): number
	local groundHeights: { number } = {}
	for sampleIndex = 1, POST_GROUND_SAMPLE_COUNT do
		local angle = (sampleIndex - 1) / POST_GROUND_SAMPLE_COUNT * 2 * math.pi
		local sampleOrigin = horizontalPostCFrame:PointToWorldSpace(Vector3.new(
			math.cos(angle) * POST_GROUND_SAMPLE_RADIUS,
			POST_GROUND_RAY_START_HEIGHT,
			math.sin(angle) * POST_GROUND_SAMPLE_RADIUS
		))
		local result = Workspace:Raycast(
			sampleOrigin,
			Vector3.new(0, -POST_GROUND_RAY_LENGTH, 0),
			seekerPostGroundRaycastParameters
		)
		if result then
			table.insert(groundHeights, result.Position.Y)
		end
	end

	if #groundHeights == 0 then
		return seekerHoldingSpawn.Position.Y
	end

	table.sort(groundHeights)
	local middleIndex = math.floor((#groundHeights + 1) / 2)
	if #groundHeights % 2 == 0 then
		return (groundHeights[middleIndex] + groundHeights[middleIndex + 1]) / 2
	end

	return groundHeights[middleIndex]
end

local function updateSeekerPostIndicatorTransform()
	local horizontalPostCFrame = getHorizontalPostCFrame(seekerHoldingSpawn.Position.Y)
	local groundHeight = getSeekerPostGroundHeight(horizontalPostCFrame)
	seekerPostSurfaceCFrame = getHorizontalPostCFrame(groundHeight)
	seekerPostIndicatorAnchor.CFrame = seekerPostSurfaceCFrame
	seekerPostIndicatorFill.CFrame = seekerPostSurfaceCFrame
		* CFrame.new(0, POST_INDICATOR_FILL_HEIGHT / 2 + POST_INDICATOR_SURFACE_GAP, 0)
		* CFrame.Angles(0, 0, math.rad(90))

	for index, segment in seekerPostIndicatorSegments do
		local angle = (index - 1) / POST_INDICATOR_SEGMENT_COUNT * 2 * math.pi
		local relativePosition = Vector3.new(
			math.cos(angle) * POST_CAPTURE_RADIUS,
			POST_INDICATOR_BOUNDARY_HEIGHT / 2 + POST_INDICATOR_SURFACE_GAP,
			math.sin(angle) * POST_CAPTURE_RADIUS
		)
		local worldPosition = seekerPostSurfaceCFrame:PointToWorldSpace(relativePosition)
		local tangent = seekerPostSurfaceCFrame:VectorToWorldSpace(Vector3.new(-math.sin(angle), 0, math.cos(angle)))
		segment.CFrame = CFrame.lookAt(worldPosition, worldPosition + tangent, seekerPostSurfaceCFrame.UpVector)
	end
end

local function getPlanarDistanceFromSeekerPost(position: Vector3): number
	local relativePosition = seekerPostSurfaceCFrame:PointToObjectSpace(position)
	return Vector2.new(relativePosition.X, relativePosition.Z).Magnitude
end

local function updateSeekerPostIndicatorVisibility()
	local visible = roundState:GetAttribute("Phase") == SEEKING_PHASE
	seekerPostIndicatorFill.Transparency = if visible then 0.76 else 1
	for _, segment in seekerPostIndicatorSegments do
		segment.Transparency = if visible then 0.08 else 1
	end
	seekerPostBillboard.Enabled = visible
end

seekerPostIndicator.Parent = Workspace
updateSeekerPostIndicatorTransform()
updateSeekerPostIndicatorVisibility()
seekerHoldingSpawn:GetPropertyChangedSignal("CFrame"):Connect(updateSeekerPostIndicatorTransform)
roundState:GetAttributeChangedSignal("Phase"):Connect(updateSeekerPostIndicatorVisibility)

local generation = 0
local lastResetAt = 0
local roleAssignments: { [Player]: Role } = {}
local hiderSpawnAssignments: { [Player]: BasePart } = {}
local waitingSpawnSlots: { [Player]: number } = {}
local seekerPlayer: Player? = nil
local practiceHiders: { Model } = {}
local practiceHiderFolder: Folder? = nil
local taggedHiderTargets: { TagTarget } = {}
local taggedHiderSet: { [Instance]: boolean } = {}
local hiderRoster: { [string]: HiderRosterEntry } = {}
local hiderRosterOrder: { string } = {}
local hiderRosterKeyByTarget: { [Instance]: string } = {}
local seekerWasAwayFromPost = false
local lastTagRequestAt: { [Player]: number } = {}

local function replicateHiderRoster()
	local serializedRoster: { HiderRosterEntry } = {}
	for _, rosterKey in hiderRosterOrder do
		local entry = hiderRoster[rosterKey]
		if entry then
			table.insert(serializedRoster, entry)
		end
	end

	roundState:SetAttribute("HiderRosterJson", HttpService:JSONEncode(serializedRoster))
end

local function clearPendingTags()
	for _, taggedHider in taggedHiderTargets do
		if taggedHider.Parent then
			taggedHider:SetAttribute("Tagged", nil)
		end
	end

	table.clear(taggedHiderTargets)
	table.clear(taggedHiderSet)
	seekerWasAwayFromPost = false
end

local function clearHiderRoster()
	table.clear(hiderRoster)
	table.clear(hiderRosterOrder)
	table.clear(hiderRosterKeyByTarget)
	roundState:SetAttribute("HiderRosterJson", "[]")
end

local function clearPracticeHiders()
	local folder = practiceHiderFolder
	if folder then
		folder:Destroy()
	end

	practiceHiderFolder = nil
	table.clear(practiceHiders)
	roundState:SetAttribute("PracticeModeActive", false)
end

local function getPracticeHiderCount(): number
	local configuredCount = roundState:GetAttribute("StudioPracticeHiderCount")
	if typeof(configuredCount) ~= "number" then
		return 2
	end

	return math.clamp(math.floor(configuredCount), 1, MAX_HIDERS)
end

local function shouldUsePracticeHiders(connectedPlayers: { Player }): boolean
	return RunService:IsStudio()
		and roundState:GetAttribute("StudioPracticeEnabled") == true
		and #connectedPlayers == 1
end

local function canStartRound(connectedPlayers: { Player }): boolean
	return #connectedPlayers >= MIN_PLAYERS or shouldUsePracticeHiders(connectedPlayers)
end

local function getHidingDuration(): number
	if roundState:GetAttribute("PracticeModeActive") == true then
		local practiceDuration = roundState:GetAttribute("StudioPracticeHidingDuration")
		if typeof(practiceDuration) == "number" then
			return math.max(1, math.floor(practiceDuration))
		end
		return 3
	end

	local configuredDuration = roundState:GetAttribute("HidingDuration")
	if typeof(configuredDuration) ~= "number" then
		return 30
	end

	return math.max(1, math.floor(configuredDuration))
end

local function shuffledCopy<T>(items: { T }): { T }
	local shuffled = table.clone(items)

	for index = #shuffled, 2, -1 do
		local swapIndex = roundRandom:NextInteger(1, index)
		shuffled[index], shuffled[swapIndex] = shuffled[swapIndex], shuffled[index]
	end

	return shuffled
end

local function registerHiderTarget(target: TagTarget)
	local rosterKey: string
	local userId = 0
	local displayName: string
	local isPractice = not target:IsA("Player")

	if target:IsA("Player") then
		local targetPlayer = target :: Player
		rosterKey = `player:{targetPlayer.UserId}`
		userId = targetPlayer.UserId
		displayName = if targetPlayer.DisplayName ~= "" then targetPlayer.DisplayName else targetPlayer.Name
	else
		local practiceHider = target :: Model
		local practiceIndex = practiceHider:GetAttribute("PracticeIndex")
		rosterKey = `practice:{tostring(practiceIndex)}`
		displayName = practiceHider.Name
	end

	hiderRoster[rosterKey] = {
		id = rosterKey,
		userId = userId,
		name = displayName,
		status = "Active",
		isPractice = isPractice,
	}
	table.insert(hiderRosterOrder, rosterKey)
	hiderRosterKeyByTarget[target] = rosterKey
end

local function setHiderStatus(target: TagTarget, status: HiderStatus)
	local rosterKey = hiderRosterKeyByTarget[target]
	local entry = rosterKey and hiderRoster[rosterKey]
	if entry then
		entry.status = status
	end
end

local function createPracticeBodyPart(
	model: Model,
	name: string,
	size: Vector3,
	color: Color3,
	cframe: CFrame,
	shape: Enum.PartType?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = true
	part.CastShadow = true
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Size = size
	part.CFrame = cframe
	if shape then
		part.Shape = shape
	end
	part.Parent = model

	return part
end

local function createPracticeHider(index: number, marker: BasePart, parent: Folder): Model
	local model = Instance.new("Model")
	model.Name = `Practice Hider {index}`
	model:SetAttribute("PracticeHider", true)
	model:SetAttribute("PracticeIndex", index)
	model.Parent = parent

	local baseCFrame = marker.CFrame
	local shirtColor = if index % 2 == 0
		then Color3.fromRGB(75, 145, 255)
		else Color3.fromRGB(93, 211, 151)
	local skinColor = Color3.fromRGB(246, 205, 171)
	local pantsColor = Color3.fromRGB(48, 58, 78)

	local torso = createPracticeBodyPart(
		model,
		"Torso",
		Vector3.new(2, 2, 1),
		shirtColor,
		baseCFrame * CFrame.new(0, 3.1, 0),
		nil
	)
	createPracticeBodyPart(
		model,
		"Left Arm",
		Vector3.new(0.8, 2, 0.8),
		skinColor,
		baseCFrame * CFrame.new(-1.45, 3.1, 0),
		nil
	)
	createPracticeBodyPart(
		model,
		"Right Arm",
		Vector3.new(0.8, 2, 0.8),
		skinColor,
		baseCFrame * CFrame.new(1.45, 3.1, 0),
		nil
	)
	createPracticeBodyPart(
		model,
		"Left Leg",
		Vector3.new(0.9, 2, 0.9),
		pantsColor,
		baseCFrame * CFrame.new(-0.5, 1.05, 0),
		nil
	)
	createPracticeBodyPart(
		model,
		"Right Leg",
		Vector3.new(0.9, 2, 0.9),
		pantsColor,
		baseCFrame * CFrame.new(0.5, 1.05, 0),
		nil
	)
	local head = createPracticeBodyPart(
		model,
		"Head",
		Vector3.new(1.8, 1.8, 1.8),
		skinColor,
		baseCFrame * CFrame.new(0, 5.05, 0),
		Enum.PartType.Ball
	)
	model.PrimaryPart = torso

	local nameplate = Instance.new("BillboardGui")
	nameplate.Name = "PracticeNameplate"
	nameplate.Adornee = head
	nameplate.AlwaysOnTop = false
	nameplate.LightInfluence = 0
	nameplate.MaxDistance = 120
	nameplate.Size = UDim2.fromOffset(150, 32)
	nameplate.StudsOffset = Vector3.new(0, 1.6, 0)
	nameplate.Parent = head

	local label = Instance.new("TextLabel")
	label.BackgroundColor3 = Color3.fromRGB(16, 23, 34)
	label.BackgroundTransparency = 0.18
	label.BorderSizePixel = 0
	label.Font = Enum.Font.GothamBold
	label.Size = UDim2.fromScale(1, 1)
	label.Text = string.upper(model.Name)
	label.TextColor3 = Color3.fromRGB(230, 239, 255)
	label.TextScaled = true
	label.TextStrokeTransparency = 0.45
	label.Parent = nameplate

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = label

	return model
end

local function spawnPracticeHiders()
	local folder = Instance.new("Folder")
	folder.Name = "StudioPracticeHiders"
	folder.Parent = Workspace
	practiceHiderFolder = folder

	local shuffledMarkers = shuffledCopy(hiderSpawns)
	for index = 1, getPracticeHiderCount() do
		local practiceHider = createPracticeHider(index, shuffledMarkers[index], folder)
		table.insert(practiceHiders, practiceHider)
		registerHiderTarget(practiceHider)
	end

	roundState:SetAttribute("PracticeModeActive", true)
end

local function serializeUserIds(players: { Player }): string
	local userIds: { string } = {}

	for _, player in players do
		table.insert(userIds, tostring(player.UserId))
	end

	return table.concat(userIds, ",")
end

local function getConnectedPlayers(excludedPlayer: Player?): { Player }
	local connectedPlayers: { Player } = {}

	for _, player in Players:GetPlayers() do
		if player ~= excludedPlayer then
			table.insert(connectedPlayers, player)
		end
	end

	return connectedPlayers
end

local function updateConnectedPlayers(excludedPlayer: Player?)
	roundState:SetAttribute("ConnectedPlayers", #getConnectedPlayers(excludedPlayer))
end

local function clearAssignments()
	clearPendingTags()
	clearPracticeHiders()
	clearHiderRoster()

	if seekerPlayer then
		local character = seekerPlayer.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		if rootPart and rootPart:IsA("BasePart") then
			rootPart.Anchored = false
		end
	end

	seekerPlayer = nil
	table.clear(roleAssignments)
	table.clear(hiderSpawnAssignments)

	for _, player in Players:GetPlayers() do
		player:SetAttribute("Role", nil)
	end
end

local function getAssignedSpawn(player: Player): BasePart
	local role = roleAssignments[player]
	if role == SEEKER_ROLE then
		return seekerHoldingSpawn
	elseif role == HIDER_ROLE then
		return hiderSpawnAssignments[player] or waitingSpawn
	end

	return waitingSpawn
end

local function getWaitingSpawnOffset(player: Player): Vector3
	local assignedSlot = waitingSpawnSlots[player]
	if not assignedSlot then
		local occupiedSlots: { [number]: boolean } = {}
		for _, slot in waitingSpawnSlots do
			occupiedSlots[slot] = true
		end

		assignedSlot = 1
		while occupiedSlots[assignedSlot] do
			assignedSlot += 1
		end
		waitingSpawnSlots[player] = assignedSlot
	end

	local zeroBasedSlot = assignedSlot - 1
	local column = zeroBasedSlot % WAITING_SPAWN_COLUMNS
	local row = math.floor(zeroBasedSlot / WAITING_SPAWN_COLUMNS)
	local xOffset = (column - (WAITING_SPAWN_COLUMNS - 1) / 2) * WAITING_SPAWN_SPACING
	local zOffset = (row - 0.5) * WAITING_SPAWN_SPACING

	return Vector3.new(xOffset, 0, zOffset)
end

local function pivotCharacterToAssignedSpawn(player: Player, character: Model)
	local marker = getAssignedSpawn(player)
	if marker == seekerHoldingSpawn then
		-- Local +Z is behind the marker. Use an explicit look-at transform so
		-- character pivot offsets cannot introduce an angular error.
		local spawnPosition = seekerPostSurfaceCFrame:PointToWorldSpace(
			Vector3.new(0, CHARACTER_SPAWN_OFFSET, POST_CAPTURE_RADIUS)
		)
		local postTarget = Vector3.new(
			seekerPostSurfaceCFrame.Position.X,
			spawnPosition.Y,
			seekerPostSurfaceCFrame.Position.Z
		)
		character:PivotTo(CFrame.lookAt(spawnPosition, postTarget))
		return
	end

	local waitingOffset = if marker == waitingSpawn then getWaitingSpawnOffset(player) else Vector3.zero
	character:PivotTo(marker.CFrame * CFrame.new(waitingOffset.X, CHARACTER_SPAWN_OFFSET, waitingOffset.Z))
end

local function setCharacterLocked(character: Model, locked: boolean)
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if rootPart and rootPart:IsA("BasePart") then
		rootPart.Anchored = locked
	end
end

local function shouldLockPlayer(player: Player): boolean
	return roleAssignments[player] == SEEKER_ROLE and roundState:GetAttribute("Phase") == HIDING_PHASE
end

local function movePlayerToAssignedSpawn(player: Player)
	local character = player.Character
	if character and character.Parent then
		pivotCharacterToAssignedSpawn(player, character)
		setCharacterLocked(character, shouldLockPlayer(player))
	end
end

local function movePlayersToAssignedSpawns(excludedPlayer: Player?)
	for _, player in getConnectedPlayers(excludedPlayer) do
		movePlayerToAssignedSpawn(player)
	end
end

local function positionCharacterWhenReady(player: Player, character: Model)
	local rootPart = character:WaitForChild("HumanoidRootPart", 10)
	if not rootPart or player.Character ~= character or not character.Parent then
		return
	end

	pivotCharacterToAssignedSpawn(player, character)
	setCharacterLocked(character, shouldLockPlayer(player))

	if player == seekerPlayer and #taggedHiderTargets > 0 then
		-- Respawning at the post must not count as returning with a tagged hider.
		seekerWasAwayFromPost = false
	end
end

local scheduleAutomaticStart: (excludedPlayer: Player?) -> ()
local resetRound: (excludedPlayer: Player?) -> ()

local function runHidingPhase(thisGeneration: number)
	for timeRemaining = getHidingDuration(), 1, -1 do
		if thisGeneration ~= generation or roundState:GetAttribute("Phase") ~= HIDING_PHASE then
			return
		end

		roundState:SetAttribute("TimeRemaining", timeRemaining)
		task.wait(1)
	end

	if thisGeneration ~= generation or roundState:GetAttribute("Phase") ~= HIDING_PHASE then
		return
	end

	roundState:SetAttribute("TimeRemaining", 0)
	if seekerPlayer and seekerPlayer.Parent == Players then
		local character = seekerPlayer.Character
		if character and character.Parent then
			setCharacterLocked(character, false)
		end
	end
	roundState:SetAttribute("Phase", SEEKING_PHASE)
end

local function finishRoleSelection(thisGeneration: number)
	if thisGeneration ~= generation or roundState:GetAttribute("Phase") ~= SELECTING_PHASE then
		return
	end

	for player, role in roleAssignments do
		if player.Parent == Players then
			player:SetAttribute("Role", role)
		end
	end

	movePlayersToAssignedSpawns(nil)
	roundState:SetAttribute("Phase", HIDING_PHASE)
	if seekerPlayer then
		movePlayerToAssignedSpawn(seekerPlayer)
	end
	roundState:SetAttribute("TimeRemaining", getHidingDuration())
	roundState:SetAttribute("RoleSelectionEndTime", 0)
	roundState:SetAttribute("SelectionUserIds", "")
	roundState:SetAttribute("SelectedSeekerUserId", 0)
	task.spawn(runHidingPhase, thisGeneration)
end

local function beginRoleSelection(thisGeneration: number)
	if thisGeneration ~= generation or roundState:GetAttribute("Phase") ~= WAITING_PHASE then
		return
	end

	local connectedPlayers = getConnectedPlayers(nil)
	updateConnectedPlayers(nil)
	if not canStartRound(connectedPlayers) then
		roundState:SetAttribute("StartTimeRemaining", 0)
		return
	end

	local practiceRound = shouldUsePracticeHiders(connectedPlayers)
	clearAssignments()
	local shuffledPlayers = shuffledCopy(connectedPlayers)
	local roulettePlayers = shuffledCopy(connectedPlayers)
	local shuffledHiderSpawns = shuffledCopy(hiderSpawns)
	local activePlayerCount = math.min(#shuffledPlayers, MAX_ROUND_PLAYERS)

	seekerPlayer = shuffledPlayers[1]
	for index, player in shuffledPlayers do
		local role: Role
		if index == 1 then
			role = SEEKER_ROLE
		elseif index <= activePlayerCount then
			role = HIDER_ROLE
			hiderSpawnAssignments[player] = shuffledHiderSpawns[index - 1]
		else
			role = SPECTATOR_ROLE
		end

		roleAssignments[player] = role
		if role == HIDER_ROLE then
			registerHiderTarget(player)
		end
	end
	if practiceRound then
		spawnPracticeHiders()
	end
	replicateHiderRoster()
	local roleSelectionDuration = if practiceRound then PRACTICE_ROLE_SELECTION_DURATION else ROLE_SELECTION_DURATION

	roundState:SetAttribute("StartTimeRemaining", 0)
	roundState:SetAttribute("TimeRemaining", 0)
	roundState:SetAttribute("RoleSelectionDuration", roleSelectionDuration)
	roundState:SetAttribute("SelectionUserIds", serializeUserIds(roulettePlayers))
	roundState:SetAttribute("SelectedSeekerUserId", (seekerPlayer :: Player).UserId)
	roundState:SetAttribute("RoleSelectionEndTime", Workspace:GetServerTimeNow() + roleSelectionDuration)
	roundState:SetAttribute("Phase", SELECTING_PHASE)

	task.delay(roleSelectionDuration, function()
		finishRoleSelection(thisGeneration)
	end)
end

scheduleAutomaticStart = function(excludedPlayer: Player?)
	if roundState:GetAttribute("Phase") ~= WAITING_PHASE then
		updateConnectedPlayers(excludedPlayer)
		return
	end

	generation += 1
	local thisGeneration = generation
	local connectedPlayers = getConnectedPlayers(excludedPlayer)
	local connectedPlayerCount = #connectedPlayers
	roundState:SetAttribute("ConnectedPlayers", connectedPlayerCount)

	if not canStartRound(connectedPlayers) then
		roundState:SetAttribute("StartTimeRemaining", 0)
		return
	end

	roundState:SetAttribute("StartTimeRemaining", AUTOMATIC_START_DELAY)
	task.spawn(function()
		for timeRemaining = AUTOMATIC_START_DELAY, 1, -1 do
			if thisGeneration ~= generation or roundState:GetAttribute("Phase") ~= WAITING_PHASE then
				return
			end

			roundState:SetAttribute("StartTimeRemaining", timeRemaining)
			task.wait(1)
		end

		if thisGeneration ~= generation or roundState:GetAttribute("Phase") ~= WAITING_PHASE then
			return
		end

		beginRoleSelection(thisGeneration)
	end)
end

resetRound = function(excludedPlayer: Player?)
	generation += 1

	local currentRound = roundState:GetAttribute("RoundNumber")
	if typeof(currentRound) ~= "number" then
		currentRound = 0
	end

	clearAssignments()
	roundState:SetAttribute("RoundNumber", currentRound + 1)
	roundState:SetAttribute("TimeRemaining", 0)
	roundState:SetAttribute("StartTimeRemaining", 0)
	roundState:SetAttribute("RoleSelectionEndTime", 0)
	roundState:SetAttribute("SelectionUserIds", "")
	roundState:SetAttribute("SelectedSeekerUserId", 0)
	roundState:SetAttribute("Phase", WAITING_PHASE)
	updateConnectedPlayers(excludedPlayer)
	movePlayersToAssignedSpawns(excludedPlayer)

	if excludedPlayer then
		task.defer(function()
			scheduleAutomaticStart(nil)
		end)
	else
		scheduleAutomaticStart(nil)
	end
end

local function getTagTargetFromDescendant(descendant: Instance): TagTarget?
	local ancestor: Instance? = descendant
	while ancestor do
		if ancestor:IsA("Model") then
			local player = Players:GetPlayerFromCharacter(ancestor)
			if player and roleAssignments[player] == HIDER_ROLE then
				return player
			end
		end
		ancestor = ancestor.Parent
	end

	for _, practiceHider in practiceHiders do
		if descendant == practiceHider or descendant:IsDescendantOf(practiceHider) then
			return practiceHider
		end
	end

	return nil
end

local function isTagTargetValid(target: TagTarget): boolean
	if target:IsA("Player") then
		local targetPlayer = target :: Player
		local targetCharacter = targetPlayer.Character
		local targetHumanoid = targetCharacter and targetCharacter:FindFirstChildOfClass("Humanoid")
		return targetPlayer.Parent == Players
			and roleAssignments[targetPlayer] == HIDER_ROLE
			and targetCharacter ~= nil
			and targetHumanoid ~= nil
			and targetHumanoid.Health > 0
	end

	local practiceHider = target :: Model
	return practiceHider.Parent == practiceHiderFolder and table.find(practiceHiders, practiceHider) ~= nil
end

local function getRemainingHiderCount(): number
	local remainingHiders = 0
	for _, practiceHider in practiceHiders do
		if practiceHider.Parent == practiceHiderFolder then
			remainingHiders += 1
		end
	end
	for assignedPlayer, role in roleAssignments do
		if role == HIDER_ROLE and assignedPlayer.Parent == Players then
			remainingHiders += 1
		end
	end

	return remainingHiders
end

local function removeTaggedHider(target: TagTarget): boolean
	if not taggedHiderSet[target] then
		return false
	end

	taggedHiderSet[target] = nil
	local taggedIndex = table.find(taggedHiderTargets, target)
	if taggedIndex then
		table.remove(taggedHiderTargets, taggedIndex)
	end
	if target.Parent then
		target:SetAttribute("Tagged", nil)
	end

	if #taggedHiderTargets == 0 then
		seekerWasAwayFromPost = false
	end

	return true
end

local function pruneInvalidTaggedHiders()
	local rosterChanged = false
	for index = #taggedHiderTargets, 1, -1 do
		local target = taggedHiderTargets[index]
		if not isTagTargetValid(target) then
			taggedHiderSet[target] = nil
			table.remove(taggedHiderTargets, index)
			if target.Parent then
				target:SetAttribute("Tagged", nil)
			end

			if target:IsA("Player") then
				local targetPlayer = target :: Player
				if targetPlayer.Parent == Players and roleAssignments[targetPlayer] == HIDER_ROLE then
					setHiderStatus(targetPlayer, "Active")
				else
					setHiderStatus(targetPlayer, "Eliminated")
				end
			else
				setHiderStatus(target, "Eliminated")
			end
			rosterChanged = true
		end
	end

	if #taggedHiderTargets == 0 then
		seekerWasAwayFromPost = false
	end
	if rosterChanged then
		replicateHiderRoster()
	end
end

local function eliminateTaggedHiders()
	local targetsToEliminate = table.clone(taggedHiderTargets)
	clearPendingTags()

	for _, taggedHider in targetsToEliminate do
		if isTagTargetValid(taggedHider) then
			setHiderStatus(taggedHider, "Eliminated")
			if taggedHider:IsA("Player") then
				local taggedPlayer = taggedHider :: Player
				roleAssignments[taggedPlayer] = SPECTATOR_ROLE
				hiderSpawnAssignments[taggedPlayer] = nil
				if taggedPlayer.Parent == Players then
					taggedPlayer:SetAttribute("Role", SPECTATOR_ROLE)
					movePlayerToAssignedSpawn(taggedPlayer)
				end
			else
				local taggedPracticeHider = taggedHider :: Model
				local practiceIndex = table.find(practiceHiders, taggedPracticeHider)
				if practiceIndex then
					table.remove(practiceHiders, practiceIndex)
				end
				taggedPracticeHider:Destroy()
			end
		end
	end
	replicateHiderRoster()

	if getRemainingHiderCount() == 0 then
		local thisGeneration = generation
		task.delay(ROUND_COMPLETE_DELAY, function()
			if thisGeneration == generation
				and roundState:GetAttribute("Phase") == SEEKING_PHASE
				and getRemainingHiderCount() == 0
			then
				resetRound(nil)
			end
		end)
	end
end

local function isFiniteVector3(value: Vector3): boolean
	return value.X == value.X
		and value.Y == value.Y
		and value.Z == value.Z
		and math.abs(value.X) < math.huge
		and math.abs(value.Y) < math.huge
		and math.abs(value.Z) < math.huge
end

local function handleTagRequest(player: Player, cameraOrigin: unknown, cameraDirection: unknown)
	local now = os.clock()
	local lastRequestAt = lastTagRequestAt[player] or 0
	if now - lastRequestAt < TAG_REQUEST_COOLDOWN then
		return
	end
	lastTagRequestAt[player] = now

	if roundState:GetAttribute("Phase") ~= SEEKING_PHASE
		or player ~= seekerPlayer
		or roleAssignments[player] ~= SEEKER_ROLE
		or typeof(cameraOrigin) ~= "Vector3"
		or typeof(cameraDirection) ~= "Vector3"
	then
		return
	end

	local origin = cameraOrigin :: Vector3
	local direction = cameraDirection :: Vector3
	if not isFiniteVector3(origin) or not isFiniteVector3(direction) then
		return
	end

	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not head or not head:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then
		return
	end

	local directionMagnitude = direction.Magnitude
	if directionMagnitude < 0.9 or directionMagnitude > 1.1 then
		return
	end

	if (origin - head.Position).Magnitude > MAX_CAMERA_ORIGIN_OFFSET then
		return
	end

	local raycastParameters = RaycastParams.new()
	raycastParameters.FilterType = Enum.RaycastFilterType.Exclude
	raycastParameters.FilterDescendantsInstances = { character }
	raycastParameters.IgnoreWater = false

	local raycastResult = Workspace:Raycast(origin, direction.Unit * MAX_TAG_DISTANCE, raycastParameters)
	if not raycastResult then
		return
	end

	local target = getTagTargetFromDescendant(raycastResult.Instance)
	if not target or not isTagTargetValid(target) or taggedHiderSet[target] then
		return
	end

	local firstPendingTag = #taggedHiderTargets == 0
	taggedHiderSet[target] = true
	table.insert(taggedHiderTargets, target)
	target:SetAttribute("Tagged", true)
	setHiderStatus(target, "Tagged")
	replicateHiderRoster()

	if firstPendingTag then
		local seekerRoot = character:FindFirstChild("HumanoidRootPart")
		seekerWasAwayFromPost = seekerRoot ~= nil
			and seekerRoot:IsA("BasePart")
			and getPlanarDistanceFromSeekerPost(seekerRoot.Position) > POST_AWAY_RADIUS
	end
end

local function setupPlayer(player: Player)
	if roundState:GetAttribute("Phase") == WAITING_PHASE then
		player:SetAttribute("Role", nil)
	else
		roleAssignments[player] = SPECTATOR_ROLE
		player:SetAttribute("Role", SPECTATOR_ROLE)
	end

	player.CharacterAdded:Connect(function(character)
		task.spawn(positionCharacterWhenReady, player, character)
	end)

	if player.Character then
		task.spawn(positionCharacterWhenReady, player, player.Character)
	end

	if roundState:GetAttribute("Phase") == WAITING_PHASE then
		scheduleAutomaticStart(nil)
	else
		updateConnectedPlayers(nil)
		movePlayerToAssignedSpawn(player)
	end
end

Players.PlayerAdded:Connect(setupPlayer)

Players.PlayerRemoving:Connect(function(player)
	player:SetAttribute("Role", nil)
	waitingSpawnSlots[player] = nil
	lastTagRequestAt[player] = nil
	local phase = roundState:GetAttribute("Phase")

	if phase == WAITING_PHASE then
		generation += 1
		roundState:SetAttribute("StartTimeRemaining", 0)
		updateConnectedPlayers(player)
		task.defer(function()
			scheduleAutomaticStart(nil)
		end)
		return
	end

	local departingRole = roleAssignments[player]
	if taggedHiderSet[player] then
		removeTaggedHider(player)
	end
	if departingRole == HIDER_ROLE then
		setHiderStatus(player, "Eliminated")
		replicateHiderRoster()
	end
	roleAssignments[player] = nil
	hiderSpawnAssignments[player] = nil
	updateConnectedPlayers(player)

	if departingRole == SEEKER_ROLE then
		resetRound(player)
	elseif departingRole == HIDER_ROLE then
		if getRemainingHiderCount() == 0 then
			resetRound(player)
		end
	end
end)

tagRequested.OnServerEvent:Connect(handleTagRequest)

RunService.Heartbeat:Connect(function()
	if roundState:GetAttribute("Phase") ~= SEEKING_PHASE or #taggedHiderTargets == 0 or not seekerPlayer then
		return
	end

	pruneInvalidTaggedHiders()
	if #taggedHiderTargets == 0 then
		return
	end

	local seekerCharacter = seekerPlayer.Character
	local seekerRoot = seekerCharacter and seekerCharacter:FindFirstChild("HumanoidRootPart")
	local seekerHumanoid = seekerCharacter and seekerCharacter:FindFirstChildOfClass("Humanoid")
	if not seekerRoot or not seekerRoot:IsA("BasePart") or not seekerHumanoid or seekerHumanoid.Health <= 0 then
		return
	end

	local distanceFromPost = getPlanarDistanceFromSeekerPost(seekerRoot.Position)
	if distanceFromPost > POST_AWAY_RADIUS then
		seekerWasAwayFromPost = true
	elseif seekerWasAwayFromPost and distanceFromPost <= POST_CAPTURE_RADIUS then
		eliminateTaggedHiders()
	end
end)

resetRequested.OnServerEvent:Connect(function(_player)
	local now = os.clock()
	if now - lastResetAt < RESET_DEBOUNCE_SECONDS then
		return
	end

	lastResetAt = now
	resetRound(nil)
end)

roundState:SetAttribute("ConnectedPlayers", 0)
roundState:SetAttribute("StartTimeRemaining", 0)
roundState:SetAttribute("RoleSelectionDuration", ROLE_SELECTION_DURATION)
roundState:SetAttribute("RoleSelectionEndTime", 0)
roundState:SetAttribute("SelectionUserIds", "")
roundState:SetAttribute("SelectedSeekerUserId", 0)
roundState:SetAttribute("HiderRosterJson", "[]")
roundState:SetAttribute("PracticeModeActive", false)
for _, player in Players:GetPlayers() do
	setupPlayer(player)
end
resetRound(nil)
