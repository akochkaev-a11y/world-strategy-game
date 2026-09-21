const assert = require("node:assert/strict");
const { once } = require("node:events");
const test = require("node:test");
const WebSocket = require("ws");

const {
  ACTIVE,
  BACKGROUND,
  GAME_CONFIG,
  NEUTRAL,
  PLAYABLE,
  PROTOCOL_VERSION,
  addArmy,
  checkEliminations,
  checkWinner,
  makeGame,
  resolveArrivals,
  resolveUnitCollisions,
  startServer,
  tickRoom
} = require("../server");

function fakeRoom(humanCountries=["RU"]) {
  const players = new Map();
  humanCountries.forEach((country,index)=>players.set(`token-${index}`,{
    id:`player-${index}`,
    token:`token-${index}`,
    name:`Player ${index}`,
    country,
    ws:null
  }));
  const room={code:"123456",hostToken:"token-0",started:true,players,game:null,revision:0};
  room.game=makeGame(room);
  return room;
}

function inbox(ws) {
  const messages=[];
  ws.on("message",raw=>messages.push(JSON.parse(raw.toString())));
  return {
    async take(predicate,timeout=1500) {
      const started=Date.now();
      while(Date.now()-started<timeout) {
        const index=messages.findIndex(predicate);
        if(index>=0) return messages.splice(index,1)[0];
        await new Promise(resolve=>setTimeout(resolve,5));
      }
      assert.fail(`Timed out waiting for message; buffered=${JSON.stringify(messages)}`);
    }
  };
}

async function connect(port) {
  const ws=new WebSocket(`ws://127.0.0.1:${port}`);
  const box=inbox(ws);
  await once(ws,"open");
  const welcome=await box.take(message=>message.type==="welcome");
  assert.equal(welcome.protocol_version,PROTOCOL_VERSION);
  return {ws,box};
}

function command(ws,payload,protocolVersion=PROTOCOL_VERSION) {
  ws.send(JSON.stringify({...payload,protocol_version:protocolVersion}));
}

test("shared game configuration has unique and complete country groups",()=>{
  assert.equal(PROTOCOL_VERSION,GAME_CONFIG.protocol_version);
  assert.equal(ACTIVE.length,16);
  assert.equal(NEUTRAL.length,39);
  assert.equal(BACKGROUND.length,7);
  assert.equal(PLAYABLE.length,55);
  assert.equal(new Set([...PLAYABLE,...BACKGROUND]).size,62);
});

test("authoritative game owns growth, AI assignments, movement, collisions and capture",()=>{
  const room=fakeRoom(["RU"]);
  const game=room.game;
  assert.equal(ACTIVE.length,16);
  assert.equal(Object.keys(game.territories).length,55);
  assert.equal(game.territories.PT.owner,"PT");
  assert.equal(game.territories.US.owner,"US");
  assert.equal(game.territories.BR.owner,"BR");
  assert.equal(game.territories.CL.owner,"NEUTRAL");
  assert.equal(game.aiCountries.includes("RU"),false);
  assert.equal(game.aiCountries.includes("DE"),true);
  assert.equal(game.aiCountries.includes("US"),true);
  for(const owner of Object.keys(game.aiTimers)) game.aiTimers[owner]=999;

  tickRoom(room,2);
  assert.equal(game.territories.RU.army,102);
  assert.equal(game.territories.KZ.army,101);

  const moving=addArmy(game,"RU","UA",0.5,null);
  assert.ok(moving);
  assert.equal(moving.pending,51);
  tickRoom(room,0.1);
  assert.ok(moving.units.length>0);
  assert.ok(game.territories.RU.army<102);

  const opposing=addArmy(game,"DE","UA",0,1);
  moving.pending=0;
  moving.units=[0.4];
  opposing.pending=0;
  opposing.units=[0.4];
  opposing.route=moving.route;
  resolveUnitCollisions(game);
  assert.equal(moving.units.length,0);
  assert.equal(opposing.units.length,0);

  game.territories.UA.army=1;
  const capture=addArmy(game,"RU","UA",0,2);
  capture.pending=0;
  capture.units=[1,1];
  resolveArrivals(game);
  assert.equal(game.territories.UA.owner,"RU");
  assert.equal(game.territories.UA.army,1);

  const eliminated=[];
  game.onCountryEliminated=country=>eliminated.push(country);
  for(const territory of Object.values(game.territories)) {
    if(territory.owner==="DE") territory.owner="CN";
  }
  game.armies=game.armies.filter(army=>army.owner!=="DE");
  checkEliminations(room);
  assert.ok(eliminated.includes("DE"));
  assert.equal(game.winner,"");

  for(const country of ACTIVE) game.territories[country].owner="RU";
  game.armies=[];
  checkWinner(room);
  assert.equal(game.winner,"RU");
});

test("room protocol starts one game, broadcasts armies, rejects strangers and reconnects by token",async t=>{
  const server=startServer({port:0,startLoop:false});
  await once(server,"listening");
  t.after(async()=>server.gameClose());
  const port=server.address().port;

  const first=await connect(port);
  command(first.ws,{type:"create_room",name:"Host"});
  const firstSession=await first.box.take(message=>message.type==="session");
  await first.box.take(message=>message.type==="room_state");
  command(first.ws,{type:"select_country",country:"RU"});
  await first.box.take(message=>message.type==="room_state"&&message.state.players[0].country==="RU");

  const second=await connect(port);
  command(second.ws,{type:"join_room",code:firstSession.code,name:"Guest"});
  const secondSession=await second.box.take(message=>message.type==="session");
  assert.ok(secondSession.session_token);
  command(second.ws,{type:"select_country",country:"DE"});
  await second.box.take(message=>message.type==="room_state"&&message.state.players.some(p=>p.country==="DE"));

  command(first.ws,{type:"start_room"});
  await first.box.take(message=>message.type==="game_started");
  const initial=await first.box.take(message=>message.type==="game_state");
  assert.equal(initial.player_country,"RU");
  assert.equal(initial.state.players.length,2);
  assert.equal(initial.state.ai_countries.includes("RU"),false);
  assert.equal(initial.state.ai_countries.includes("DE"),false);

  command(second.ws,{type:"send_army",source:"RU",target:"KZ",share:0.5});
  const forbidden=await second.box.take(message=>message.type==="error");
  assert.match(forbidden.message,/другая страна/);

  command(first.ws,{type:"send_army",source:"RU",target:"KZ",share:0.5});
  const started=await second.box.take(message=>message.type==="army_started");
  assert.equal(started.army.owner,"RU");
  assert.equal(started.army.pending,50);

  first.ws.close();
  await once(first.ws,"close");
  const resumed=await connect(port);
  command(resumed.ws,{type:"reconnect",code:firstSession.code,session_token:firstSession.session_token});
  await resumed.box.take(message=>message.type==="session");
  const resumedStart=await resumed.box.take(message=>message.type==="game_started");
  assert.equal(resumedStart.player_country,"RU");
  const resumedState=await resumed.box.take(message=>message.type==="game_state");
  assert.equal(resumedState.state.players.find(p=>p.country==="RU").connected,true);

  const stranger=await connect(port);
  command(stranger.ws,{type:"join_room",code:firstSession.code,name:"Stranger"});
  const rejected=await stranger.box.take(message=>message.type==="error");
  assert.match(rejected.message,/началась/);

  command(resumed.ws,{type:"leave_room"});
  await resumed.box.take(message=>message.type==="left_room");
  const revoked=await connect(port);
  command(revoked.ws,{type:"reconnect",code:firstSession.code,session_token:firstSession.session_token});
  const revokedError=await revoked.box.take(message=>message.type==="error");
  assert.match(revokedError.message,/не найдена/);

  revoked.ws.close();
  second.ws.close();
  stranger.ws.close();
});

test("protocol mismatch and command flooding are rejected",async t=>{
  const server=startServer({port:0,startLoop:false,maxMessagesPerWindow:2,heartbeatMs:0});
  await once(server,"listening");
  t.after(async()=>server.gameClose());
  const port=server.address().port;

  const legacy=await connect(port);
  legacy.ws.send(JSON.stringify({type:"create_room",name:"Legacy"}));
  await legacy.box.take(message=>message.type==="session");
  await legacy.box.take(message=>message.type==="room_state");

  const outdated=await connect(port);
  command(outdated.ws,{type:"create_room",name:"Old"},PROTOCOL_VERSION-1);
  const mismatch=await outdated.box.take(message=>message.type==="error");
  assert.match(mismatch.message,/несовместима/);

  const client=await connect(port);
  command(client.ws,{type:"create_room",name:"Fast"});
  await client.box.take(message=>message.type==="session");
  await client.box.take(message=>message.type==="room_state");
  command(client.ws,{type:"select_country",country:"RU"});
  await client.box.take(message=>message.type==="room_state");
  command(client.ws,{type:"select_country",country:"DE"});
  const limited=await client.box.take(message=>message.type==="error");
  assert.match(limited.message,/Слишком много команд/);

  legacy.ws.close();
  outdated.ws.close();
  client.ws.close();
});
