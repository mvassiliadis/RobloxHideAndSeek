# Repository Guidelines

## Project Structure & Module Organization

This is a two-place hybrid Rojo project: repository files own Match gameplay code and UI, while the evolving Match map, Lobby, Terrain, Lighting, and other unlisted instances remain authored in Roblox Studio.

- `src/match/ServerScriptService/` contains server-authoritative round logic.
- `src/match/StarterGui/` contains the React-Lua HUD and its client bootstrap.
- `match.project.json` maps Match filesystem sources and replicated state to place `88216950471180`.
- `lobby.project.json` safely targets place `98577386131530` and remains minimal until lobby code is implemented.
- Add future Lobby-owned scripts beneath `src/lobby/` and map them explicitly in `lobby.project.json`.
- `wally.toml` and `wally.lock` define React-Lua dependencies; generated `Packages/` is ignored.
- `README.md` documents the current game state and Studio ownership boundaries.

There is no automated test directory yet. Add future tests under `tests/`, mirroring the relevant `src/` paths.

## Build, Test, and Development Commands

Install pinned tools and dependencies before development:

```sh
rokit install
wally install
rojo serve match.project.json
```

Use `rojo serve lobby.project.json` instead when the Lobby place is open. `rojo serve` exposes the selected project to the Rojo Studio plugin at `localhost:34872`. Validate both filesystem mappings with:

```sh
rojo sourcemap match.project.json --output match-sourcemap.json
rojo build match.project.json --output match.rbxlx
rojo sourcemap lobby.project.json --output lobby-sourcemap.json
rojo build lobby.project.json --output lobby.rbxlx
```

Both outputs are generated and must remain uncommitted.

## Coding Style & Naming Conventions

Use strict Luau (`--!strict`) and tabs for indentation, matching existing files. Prefer typed function parameters and return values. Use `camelCase` for locals and functions, `PascalCase` for React components, and `UPPER_SNAKE_CASE` for constants. Follow Roblox suffixes: `*.server.luau` for server scripts and `*.client.luau` for client scripts. Keep round transitions server-authoritative; clients should only render replicated state or request actions through remotes.

## Testing Guidelines

No test framework or coverage threshold is configured. Before submitting changes, run `rojo build` and test in Roblox Studio. Exercise `WaitingToStart -> Hiding -> Seeking`, reset behavior, respawns, and desktop cursor handling. For UI changes, also check touch/gamepad behavior where applicable.

## Commit & Pull Request Guidelines

History currently contains only `Initial commit`, so no established convention exists. Use short, imperative subjects such as `Fix reset debounce` or `Add seeker timer`. Keep commits focused. Pull requests should explain behavior changes, list validation performed, link relevant issues, and include screenshots or video for UI/map changes. Call out any required Studio-side edits or publishing steps.

Do not create pull requests unless the user explicitly requests one. For commit-and-push requests, use Git directly to commit and push the current branch.

## Configuration Safety

Do not remove `$ignoreUnknownInstances` safeguards or change `servePlaceIds` without confirming the Studio ownership model and target place. Never connect a project to the other place, or commit generated packages, place builds, sourcemaps, secrets, or local editor files.
