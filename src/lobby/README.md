# Lobby source

This directory is reserved for filesystem-owned Lobby code.

Add Lobby server scripts beneath `ServerScriptService/`, client UI beneath
`StarterGui/`, and shared Lobby instances beneath `ReplicatedStorage/`. Map each
new source explicitly in `lobby.project.json`; Studio-owned Lobby instances must
remain protected by `$ignoreUnknownInstances`.
