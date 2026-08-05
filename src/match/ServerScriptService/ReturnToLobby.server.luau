--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

local LOBBY_PLACE_ID = 98577386131530

local roundState = ReplicatedStorage:WaitForChild("RoundState")
local returnToLobbyRequested = roundState:WaitForChild("ReturnToLobbyRequested") :: RemoteEvent
local pendingPlayers: { [Player]: boolean } = {}

local function returnPlayerToLobby(player: Player)
	if pendingPlayers[player] then
		return
	end

	pendingPlayers[player] = true
	local success, errorMessage = pcall(function()
		TeleportService:TeleportAsync(LOBBY_PLACE_ID, { player })
	end)

	if not success then
		pendingPlayers[player] = nil
		warn(`Unable to return {player.Name} to the Lobby: {tostring(errorMessage)}`)
		returnToLobbyRequested:FireClient(player, "Failed")
	end
end

returnToLobbyRequested.OnServerEvent:Connect(returnPlayerToLobby)

Players.PlayerRemoving:Connect(function(player)
	pendingPlayers[player] = nil
end)
