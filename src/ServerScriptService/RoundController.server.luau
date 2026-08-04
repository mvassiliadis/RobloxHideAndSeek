--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local roundState = ReplicatedStorage:WaitForChild("RoundState")
local resetRequested = roundState:WaitForChild("ResetRequested") :: RemoteEvent

local seekerSpotInstance = Workspace:FindFirstChild("SeekerSpot", true)
assert(seekerSpotInstance and seekerSpotInstance:IsA("BasePart"), "Workspace must contain a BasePart named SeekerSpot")
local seekerSpot = seekerSpotInstance :: BasePart
local triggerDecalInstance = seekerSpot.Parent:FindFirstChild("SeekerSpotTriggerDecal")
local triggerDecal = if triggerDecalInstance and triggerDecalInstance:IsA("BasePart")
	then triggerDecalInstance
	else nil

local WAITING_PHASE = "WaitingToStart"
local HIDING_PHASE = "Hiding"
local SEEKING_PHASE = "Seeking"
local RESET_DEBOUNCE_SECONDS = 1
local PROXIMITY_CHECK_SECONDS = 0.15

local generation = 0
local lastResetAt = 0

local function getHidingDuration(): number
	local configuredDuration = roundState:GetAttribute("HidingDuration")
	if typeof(configuredDuration) ~= "number" then
		return 30
	end

	return math.max(1, math.floor(configuredDuration))
end

local function getActivationDistance(): number
	local configuredDistance = roundState:GetAttribute("ActivationDistance")
	if typeof(configuredDistance) ~= "number" then
		return 4
	end

	return math.max(0, configuredDistance)
end

local function updateTriggerDecal()
	if not triggerDecal then
		return
	end

	local halfSize = seekerSpot.Size * 0.5
	local right = seekerSpot.CFrame.RightVector
	local up = seekerSpot.CFrame.UpVector
	local look = seekerSpot.CFrame.LookVector
	local halfExtentX = math.abs(right.X) * halfSize.X + math.abs(up.X) * halfSize.Y + math.abs(look.X) * halfSize.Z
	local halfExtentY = math.abs(right.Y) * halfSize.X + math.abs(up.Y) * halfSize.Y + math.abs(look.Y) * halfSize.Z
	local halfExtentZ = math.abs(right.Z) * halfSize.X + math.abs(up.Z) * halfSize.Y + math.abs(look.Z) * halfSize.Z
	local diameter = 2 * (math.max(halfExtentX, halfExtentZ) + getActivationDistance())

	triggerDecal.Size = Vector3.new(diameter, 0.05, diameter)
	triggerDecal.Position = Vector3.new(
		seekerSpot.Position.X,
		seekerSpot.Position.Y - halfExtentY + 0.03,
		seekerSpot.Position.Z
	)
end

local function distanceFromSpot(worldPosition: Vector3): number
	local localPosition = seekerSpot.CFrame:PointToObjectSpace(worldPosition)
	local halfSize = seekerSpot.Size * 0.5
	local closestLocalPosition = Vector3.new(
		math.clamp(localPosition.X, -halfSize.X, halfSize.X),
		math.clamp(localPosition.Y, -halfSize.Y, halfSize.Y),
		math.clamp(localPosition.Z, -halfSize.Z, halfSize.Z)
	)
	local closestWorldPosition = seekerSpot.CFrame:PointToWorldSpace(closestLocalPosition)

	return (worldPosition - closestWorldPosition).Magnitude
end

local function runHidingPhase(thisGeneration: number)
	for timeRemaining = getHidingDuration(), 1, -1 do
		if thisGeneration ~= generation then
			return
		end

		roundState:SetAttribute("TimeRemaining", timeRemaining)
		task.wait(1)
	end

	if thisGeneration ~= generation then
		return
	end

	roundState:SetAttribute("TimeRemaining", 0)
	roundState:SetAttribute("Phase", SEEKING_PHASE)
end

local function tryStartHidingPhase()
	if roundState:GetAttribute("Phase") ~= WAITING_PHASE then
		return
	end

	local thisGeneration = generation
	roundState:SetAttribute("Phase", HIDING_PHASE)
	roundState:SetAttribute("TimeRemaining", getHidingDuration())
	task.spawn(runHidingPhase, thisGeneration)
end

local function resetRound()
	generation += 1

	local currentRound = roundState:GetAttribute("RoundNumber")
	if typeof(currentRound) ~= "number" then
		currentRound = 0
	end

	roundState:SetAttribute("RoundNumber", currentRound + 1)
	roundState:SetAttribute("TimeRemaining", 0)
	roundState:SetAttribute("Phase", WAITING_PHASE)
end

roundState:GetAttributeChangedSignal("ActivationDistance"):Connect(updateTriggerDecal)
updateTriggerDecal()

seekerSpot.Touched:Connect(function(hit)
	local character = hit:FindFirstAncestorOfClass("Model")
	if character and Players:GetPlayerFromCharacter(character) then
		tryStartHidingPhase()
	end
end)

task.spawn(function()
	while true do
		if roundState:GetAttribute("Phase") == WAITING_PHASE then
			for _, player in Players:GetPlayers() do
				local character = player.Character
				local rootPart = character and character:FindFirstChild("HumanoidRootPart")

				if rootPart and rootPart:IsA("BasePart") then
					if distanceFromSpot(rootPart.Position) <= getActivationDistance() then
						tryStartHidingPhase()
						break
					end
				end
			end
		end

		task.wait(PROXIMITY_CHECK_SECONDS)
	end
end)

resetRequested.OnServerEvent:Connect(function(_player)
	local now = os.clock()
	if now - lastResetAt < RESET_DEBOUNCE_SECONDS then
		return
	end

	lastResetAt = now
	resetRound()
end)

resetRound()
