--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

local MATCH_PLACE_ID = 88216950471180

local lobbyRemotes = ReplicatedStorage:WaitForChild("LobbyRemotes")
local teleportAllRequested = lobbyRemotes:WaitForChild("TeleportAllRequested") :: RemoteEvent

local teleportInProgress = false

local function teleportAllPlayers(requestingPlayer: Player)
	if teleportInProgress then
		teleportAllRequested:FireClient(requestingPlayer, "Teleporting", "A teleport is already in progress...")
		return
	end

	local playersToTeleport = Players:GetPlayers()
	if #playersToTeleport == 0 then
		return
	end

	teleportInProgress = true
	teleportAllRequested:FireAllClients(
		"Teleporting",
		`Sending {#playersToTeleport} player{if #playersToTeleport == 1 then "" else "s"} to the match...`
	)

	local success, errorMessage = pcall(function()
		TeleportService:TeleportAsync(MATCH_PLACE_ID, playersToTeleport)
	end)

	if not success then
		teleportInProgress = false
		warn(`Unable to teleport Lobby players to the Match: {tostring(errorMessage)}`)
		teleportAllRequested:FireAllClients(
			"Failed",
			"Teleport failed. Teleports must be tested from a published Roblox server."
		)
	end
end

teleportAllRequested.OnServerEvent:Connect(teleportAllPlayers)
