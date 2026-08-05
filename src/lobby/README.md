# Lobby source

This directory is reserved for filesystem-owned Lobby code.

Add Lobby server scripts beneath `ServerScriptService/`, client UI beneath
`StarterGui/`, and shared Lobby instances beneath `ReplicatedStorage/`. Map each
new source explicitly in `lobby.project.json`; Studio-owned Lobby instances must
remain protected by `$ignoreUnknownInstances`.

## Temporary match teleport

`TestTeleport` adds a playtest-only button that lets any Lobby player ask the
server to teleport everyone currently connected to the Match place. Roblox does
not perform place teleports during Studio playtests, so test the actual teleport
from a published Lobby server.
