# Repository Guidelines

## Project Structure & Module Organization

This is a hybrid Rojo project: repository files own gameplay code and UI, while the evolving map, Terrain, Lighting, and other unlisted instances remain authored in Roblox Studio.

- `src/ServerScriptService/` contains server-authoritative round logic.
- `src/StarterGui/` contains the React-Lua HUD and its client bootstrap.
- `default.project.json` maps filesystem sources into Roblox services and declares replicated state.
- `wally.toml` and `wally.lock` define React-Lua dependencies; generated `Packages/` is ignored.
- `README.md` documents the current game state and Studio ownership boundaries.

There is no automated test directory yet. Add future tests under `tests/`, mirroring the relevant `src/` paths.

## Build, Test, and Development Commands

Install pinned tools and dependencies before development:

```sh
rokit install
wally install
rojo serve default.project.json
```

`rojo serve` exposes the project to the Rojo Studio plugin at `localhost:34872`. Validate filesystem mappings with:

```sh
rojo sourcemap default.project.json --output sourcemap.json
rojo build default.project.json --output build.rbxlx
```

Both outputs are generated and must remain uncommitted.

## Coding Style & Naming Conventions

Use strict Luau (`--!strict`) and tabs for indentation, matching existing files. Prefer typed function parameters and return values. Use `camelCase` for locals and functions, `PascalCase` for React components, and `UPPER_SNAKE_CASE` for constants. Follow Roblox suffixes: `*.server.luau` for server scripts and `*.client.luau` for client scripts. Keep round transitions server-authoritative; clients should only render replicated state or request actions through remotes.

## Testing Guidelines

No test framework or coverage threshold is configured. Before submitting changes, run `rojo build` and test in Roblox Studio. Exercise `WaitingToStart -> Hiding -> Seeking`, reset behavior, respawns, and desktop cursor handling. For UI changes, also check touch/gamepad behavior where applicable.

## Commit & Pull Request Guidelines

History currently contains only `Initial commit`, so no established convention exists. Use short, imperative subjects such as `Fix reset debounce` or `Add seeker timer`. Keep commits focused. Pull requests should explain behavior changes, list validation performed, link relevant issues, and include screenshots or video for UI/map changes. Call out any required Studio-side edits or publishing steps.

## Configuration Safety

Do not remove `$ignoreUnknownInstances` safeguards or change `servePlaceIds` without confirming the Studio ownership model and target place. Never commit generated packages, place builds, sourcemaps, secrets, or local editor files.
