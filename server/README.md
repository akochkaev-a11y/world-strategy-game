# GeoStrategy authoritative multiplayer server

The Node.js WebSocket server owns every multiplayer match. Android clients send
commands and render the state returned by the server; they do not run multiplayer
growth, AI, combat, captures, the match clock, or victory checks locally.

## Run and test

```bash
npm ci
npm test
npm start
```

The default bind address is `0.0.0.0:8080`. `HOST` and `PORT` can override it.
When a TLS reverse proxy is enabled, run the service with `HOST=127.0.0.1` so
the raw WebSocket port is not exposed publicly.

## Protocol summary

- Lobby commands: `create_room`, `join_room`, `select_country`, `start_room`.
- A successful create/join returns a persistent `session` with `session_token`.
- `reconnect` accepts the room code and the same token, including after a match starts.
- `leave_room` revokes the saved seat and prevents later reconnection with that token.
- Player orders use `send_army` with `source`, `target`, and `share`.
- `army_started` makes a new stream visible immediately.
- Authoritative `game_state` snapshots contain revision, server timer, players,
  AI countries, territories, moving units, phase, and winner.
- `game_over` is broadcast to every connected player at the same server tick.
- Every new client sends the shared `protocol_version`. Version 1 also accepts
  the previous client without this field, so the current rollout does not force
  both phones to update simultaneously.

Connections have a payload limit, a command-rate limit, and ping/pong health
checks. Country lists and shared gameplay settings come from `game_config.json`.

New players cannot join a running match. A disconnected player's country remains
reserved and idle until that player reconnects; automatic AI takeover is deferred.
