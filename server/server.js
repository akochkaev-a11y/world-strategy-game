const WebSocket = require("ws");
const PORT = Number(process.env.PORT || 8080);
const wss = new WebSocket.Server({ port: PORT });
const rooms = new Map();
const ACTIVE = ["RU","UA","PL","FR","DE","GB","CN","IN","IR","JP"];

function id() { return Math.random().toString(36).slice(2, 10); }
function code() {
  let value = "";
  do value = String(Math.floor(100000 + Math.random() * 900000));
  while (rooms.has(value));
  return value;
}
function send(ws, payload) {
  if (ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify(payload));
}
function publicState(room) {
  return {
    code: room.code,
    host_id: room.hostId,
    started: room.started,
    players: [...room.players.values()].map(p => ({ id:p.id, name:p.name, country:p.country || "" }))
  };
}
function broadcast(room, payload) {
  const data = JSON.stringify(payload);
  for (const p of room.players.values()) {
    if (p.ws.readyState === WebSocket.OPEN) p.ws.send(data);
  }
}
function roomState(room) {
  broadcast(room, { type:"room_state", state:publicState(room) });
}
function error(ws, message) { send(ws, { type:"error", message }); }

wss.on("connection", ws => {
  const playerId = id();
  let room = null;
  send(ws, { type:"welcome", player_id:playerId });

  ws.on("message", raw => {
    let msg;
    try { msg = JSON.parse(raw.toString()); } catch { return error(ws, "Некорректная команда."); }

    if (msg.type === "create_room") {
      if (room) return error(ws, "Вы уже находитесь в комнате.");
      const roomCode = code();
      room = { code:roomCode, hostId:playerId, started:false, players:new Map() };
      room.players.set(playerId, { id:playerId, name:String(msg.name || "Игрок").slice(0,24), country:"", ws });
      rooms.set(roomCode, room);
      return roomState(room);
    }

    if (msg.type === "join_room") {
      if (room) return error(ws, "Вы уже находитесь в комнате.");
      const found = rooms.get(String(msg.code || "").toUpperCase());
      if (!found) return error(ws, "Комната не найдена.");
      if (found.started) return error(ws, "Партия уже началась.");
      if (found.players.size >= 10) return error(ws, "Комната заполнена.");
      room = found;
      room.players.set(playerId, { id:playerId, name:String(msg.name || "Игрок").slice(0,24), country:"", ws });
      return roomState(room);
    }

    if (!room) return error(ws, "Сначала создайте комнату или войдите в неё.");

    if (msg.type === "select_country") {
      if (room.started) return error(ws, "Партия уже началась.");
      const country = String(msg.country || "");
      if (!ACTIVE.includes(country)) return error(ws, "Недоступная страна.");
      for (const p of room.players.values()) {
        if (p.id !== playerId && p.country === country) return error(ws, "Эта страна уже занята.");
      }
      room.players.get(playerId).country = country;
      return roomState(room);
    }

    if (msg.type === "start_room") {
      if (room.hostId !== playerId) return error(ws, "Запустить игру может только создатель комнаты.");
      const players = [...room.players.values()];
      if (players.some(p => !p.country)) return error(ws, "Каждый игрок должен выбрать страну.");
      room.started = true;
      const state = publicState(room);
      state.ai_countries = ACTIVE.filter(c => !players.some(p => p.country === c));
      return broadcast(room, { type:"game_started", state });
    }
  });

  ws.on("close", () => {
    if (!room) return;
    room.players.delete(playerId);
    if (room.players.size === 0) {
      rooms.delete(room.code);
      return;
    }
    if (room.hostId === playerId) room.hostId = room.players.keys().next().value;
    roomState(room);
  });
});

console.log(`World Strategy lobby server listening on :${PORT}`);
