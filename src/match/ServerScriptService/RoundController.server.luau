--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local MIN_PLAYERS = 2
local MAX_HIDERS = 4
local MAX_ROUND_PLAYERS = 1 + MAX_HIDERS
local AUTOMATIC_START_DELAY = 5

local WAITING_PHASE = "WaitingToStart"
local HIDING_PHASE = "Hiding"
local SEEKING_PHASE = "Seeking"
local SEEKER_ROLE = "Seeker"
local HIDER_ROLE = "Hider"
local SPECTATOR_ROLE = "Spectator"
local RESET_DEBOUNCE_SECONDS = 1
local CHARACTER_SPAWN_OFFSET = 3

type Role = "Seeker" | "Hider" | "Spectator"

local roundState = ReplicatedStorage:WaitForChild("RoundState")
local resetRequested = roundState:WaitForChild("ResetRequested") :: RemoteEvent
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
local seekerReleaseSpawn = getSpawnMarker("SeekerReleaseSpawn")
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
configureSpawnMarker(seekerReleaseSpawn)
for _, marker in hiderSpawns do
	configureSpawnMarker(marker)
end

local generation = 0
local lastResetAt = 0
local roleAssignments: { [Player]: Role } = {}
local hiderSpawnAssignments: { [Player]: BasePart } = {}
local seekerPlayer: Player? = nil

local function getHidingDuration(): number
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
		if roundState:GetAttribute("Phase") == SEEKING_PHASE then
			return seekerReleaseSpawn
		end

		return seekerHoldingSpawn
	elseif role == HIDER_ROLE then
		return hiderSpawnAssignments[player] or waitingSpawn
	end

	return waitingSpawn
end

local function pivotCharacterToMarker(character: Model, marker: BasePart)
	character:PivotTo(marker.CFrame * CFrame.new(0, CHARACTER_SPAWN_OFFSET, 0))
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
		pivotCharacterToMarker(character, getAssignedSpawn(player))
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

	pivotCharacterToMarker(character, getAssignedSpawn(player))
	setCharacterLocked(character, shouldLockPlayer(player))
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
			pivotCharacterToMarker(character, seekerReleaseSpawn)
		end
	end
	roundState:SetAttribute("Phase", SEEKING_PHASE)
end

local function startRound(thisGeneration: number)
	if thisGeneration ~= generation or roundState:GetAttribute("Phase") ~= WAITING_PHASE then
		return
	end

	local connectedPlayers = getConnectedPlayers(nil)
	updateConnectedPlayers(nil)
	if #connectedPlayers < MIN_PLAYERS then
		roundState:SetAttribute("StartTimeRemaining", 0)
		return
	end

	clearAssignments()
	local shuffledPlayers = shuffledCopy(connectedPlayers)
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
		player:SetAttribute("Role", role)
	end

	roundState:SetAttribute("StartTimeRemaining", 0)
	movePlayersToAssignedSpawns(nil)
	roundState:SetAttribute("Phase", HIDING_PHASE)
	if seekerPlayer then
		movePlayerToAssignedSpawn(seekerPlayer)
	end
	roundState:SetAttribute("TimeRemaining", getHidingDuration())
	task.spawn(runHidingPhase, thisGeneration)
end

scheduleAutomaticStart = function(excludedPlayer: Player?)
	if roundState:GetAttribute("Phase") ~= WAITING_PHASE then
		updateConnectedPlayers(excludedPlayer)
		return
	end

	generation += 1
	local thisGeneration = generation
	local connectedPlayerCount = #getConnectedPlayers(excludedPlayer)
	roundState:SetAttribute("ConnectedPlayers", connectedPlayerCount)

	if connectedPlayerCount < MIN_PLAYERS then
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

		startRound(thisGeneration)
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
	roleAssignments[player] = nil
	hiderSpawnAssignments[player] = nil
	updateConnectedPlayers(player)

	if departingRole == SEEKER_ROLE then
		resetRound(player)
	elseif departingRole == HIDER_ROLE then
		local remainingHiders = 0
		for assignedPlayer, role in roleAssignments do
			if role == HIDER_ROLE and assignedPlayer.Parent == Players then
				remainingHiders += 1
			end
		end

		if remainingHiders == 0 then
			resetRound(player)
		end
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
for _, player in Players:GetPlayers() do
	setupPlayer(player)
end
resetRound(nil)
