# Multiplayer lobby server

Stage 1 server: rooms, 1-10 players, country selection and synchronized start.

Run locally:

```bash
cd server
npm install
npm start
```

The Android client currently asks for the WebSocket server address. For two phones over the Internet deploy this folder to any Node.js host that supports WebSockets and enter its `wss://...` address on both phones.

Gameplay state synchronization is intentionally not part of stage 1; that is the next multiplayer stage.
