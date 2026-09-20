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

The default port is `8080` and can be overridden with `PORT`.

## Protocol summary

- Lobby commands: `create_room`, `join_room`, `select_country`, `start_room`.
- A successful create/join returns a persistent `session` with `session_token`.
- `reconnect` accepts the room code and the same token, including after a match starts.
- Player orders use `send_army` with `source`, `target`, and `share`.
- `army_started` makes a new stream visible immediately.
- Authoritative `game_state` snapshots contain revision, server timer, players,
  AI countries, territories, moving units, phase, and winner.
- `game_over` is broadcast to every connected player at the same server tick.

New players cannot join a running match. A disconnected player's country remains
reserved and idle until that player reconnects; automatic AI takeover is deferred.
