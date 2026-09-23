# GeoStrategy

Android geopolitical strategy game built with Godot 4.3. It supports an offline
single-player simulation and server-authoritative WebSocket multiplayer for up to
10 players. Multiplayer rooms, simulation, AI, combat, captures, match time,
results, and session-token reconnection are owned by `server/server.js`.

The playable world currently includes Eurasia, North America, Central America,
the Caribbean, and South America. Sixteen countries are active powers; the
remaining playable territories begin neutral. Country lists and shared gameplay
settings are defined once in `game_config.json` and consumed by the client,
server, and CI validation.

Bot opponents have Easy, Medium, and Hard levels. Easy preserves the original
decision timing and strategy; higher levels react sooner, keep a smaller reserve,
and commit stronger attacks. The room host selects one level for all multiplayer
bots. A territory captured from a neutral owner is protected from new enemy
orders for 60 seconds; friendly reinforcements remain allowed.
