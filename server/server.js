const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const WebSocket = require("ws");

const PORT = Number(process.env.PORT || 8080);
const TICK_MS = 50;
const SNAPSHOT_MS = 100;
const ROOM_RETENTION_MS = 6 * 60 * 60 * 1000;
const ARMY_SPEED = 110;
const UNIT_SPACING = 9;
const UNIT_RADIUS = 3.2;
const EMIT_INTERVAL = UNIT_SPACING / ARMY_SPEED;
const COLLISION_RADIUS = UNIT_RADIUS * 2.25;
const AI_RESERVE = 30;
const ACTIVE = ["RU","UA","PL","FR","DE","GB","CN","IN","IR","JP"];
const PLAYABLE = ["RU","UA","PL","FR","DE","GB","CN","IN","IR","JP","KZ","SA","MN","PK","TR","AF","ES","TM","SE","UZ","IQ","NO","FI"];
const LON_MIN=-12, LON_MAX=150, LAT_MIN=5, LAT_MAX=76;
const rooms = new Map();
let nextArmyId = 1;

function randomId() { return crypto.randomBytes(8).toString("hex"); }
function token() { return crypto.randomBytes(32).toString("base64url"); }
function roomCode() {
  let value="";
  do value=String(Math.floor(100000+Math.random()*900000)); while (rooms.has(value));
  return value;
}
function send(ws,payload) {
  if (ws && ws.readyState===WebSocket.OPEN) ws.send(JSON.stringify(payload));
}
function error(ws,message) { send(ws,{type:"error",message}); }

function isoOf(feature) {
  const p=feature.properties||{};
  let iso=p.ISO_A2;
  if (!iso || iso==="-99") iso=p.ISO_A2_EH;
  const map={FRA:"FR",RUS:"RU",UKR:"UA",POL:"PL",DEU:"DE",GBR:"GB",CHN:"CN",IND:"IN",IRN:"IR",JPN:"JP",KAZ:"KZ",SAU:"SA",MNG:"MN",PAK:"PK",TUR:"TR",AFG:"AF",ESP:"ES",TKM:"TM",SWE:"SE",UZB:"UZ",IRQ:"IQ",NOR:"NO",FIN:"FI"};
  if (!iso || iso==="-99") iso=map[p.ADM0_A3]||"";
  return iso;
}
function project(lon,lat) {
  return {x:(lon-LON_MIN)/(LON_MAX-LON_MIN)*1280,y:(LAT_MAX-lat)/(LAT_MAX-LAT_MIN)*720};
}
function ringsOf(feature) {
  const g=feature.geometry||{}, c=g.coordinates||[];
  if (g.type==="Polygon" && c.length) return [c[0]];
  if (g.type==="MultiPolygon") return c.filter(p=>p.length).map(p=>p[0]);
  return [];
}
function polygonArea(poly) {
  let total=0;
  for(let i=0;i<poly.length;i++){
    const a=poly[i],b=poly[(i+1)%poly.length];
    total+=a.x*b.y-b.x*a.y;
  }
  return Math.abs(total)*0.5;
}
function bounds(poly) {
  let minX=Infinity,minY=Infinity,maxX=-Infinity,maxY=-Infinity;
  for(const p of poly){minX=Math.min(minX,p.x);minY=Math.min(minY,p.y);maxX=Math.max(maxX,p.x);maxY=Math.max(maxY,p.y);}
  return {x:minX,y:minY,w:maxX-minX,h:maxY-minY};
}
function pointInPolygon(p,poly) {
  let inside=false;
  for(let i=0,j=poly.length-1;i<poly.length;j=i++){
    const a=poly[i],b=poly[j];
    const hit=((a.y>p.y)!==(b.y>p.y)) && (p.x<(b.x-a.x)*(p.y-a.y)/(b.y-a.y)+a.x);
    if(hit) inside=!inside;
  }
  return inside;
}
function safeAnchor(poly) {
  const b=bounds(poly),center={x:b.x+b.w/2,y:b.y+b.h/2};
  if(pointInPolygon(center,poly)) return center;
  let best=poly[0],bestD=Infinity;
  for(let gy=1;gy<8;gy++) for(let gx=1;gx<8;gx++){
    const p={x:b.x+b.w*gx/8,y:b.y+b.h*gy/8};
    if(!pointInPolygon(p,poly)) continue;
    const d=(p.x-center.x)**2+(p.y-center.y)**2;
    if(d<bestD){bestD=d;best=p;}
  }
  return best;
}
const centers={};
try {
  const geo=JSON.parse(fs.readFileSync(path.join(__dirname,"..","eurasia_countries.json"),"utf8"));
  for (const f of geo.features||[]) {
    const iso=isoOf(f);
    if (!PLAYABLE.includes(iso)) continue;
    let best=null,bestArea=-1;
    for(const ring of ringsOf(f)){
      const poly=ring.map(q=>project(Number(q[0]),Number(q[1])));
      const area=polygonArea(poly);
      if(area>bestArea){bestArea=area;best=safeAnchor(poly);}
    }
    if(best) centers[iso]=best;
  }
  const missing=PLAYABLE.filter(x=>!centers[x]);
  if(missing.length) throw new Error("Missing centers: "+missing.join(","));
} catch (e) {
  console.error("Failed to load map geometry:",e);
  process.exit(1);
}

function routeInfo(source,target) {
  const a=centers[source], b=centers[target];
  const dx=b.x-a.x, dy=b.y-a.y, len=Math.hypot(dx,dy)||1;
  const side={x:-dy/len,y:dx/len};
  const bend=Math.min(42,len*0.11);
  const c={x:(a.x+b.x)/2+side.x*bend,y:(a.y+b.y)/2+side.y*bend};
  const routeLength=Math.max(1,Math.hypot(c.x-a.x,c.y-a.y)+Math.hypot(b.x-c.x,b.y-c.y));
  return {a,b,c,routeLength};
}
function routePoint(army,t) {
  const r=army.route, q=Math.max(0,Math.min(1,t)), u=1-q;
  return {x:u*u*r.a.x+2*u*q*r.c.x+q*q*r.b.x,y:u*u*r.a.y+2*u*q*r.c.y+q*q*r.b.y};
}

function makeGame(room) {
  const territories={};
  for (const iso of PLAYABLE) territories[iso]={owner:ACTIVE.includes(iso)?iso:"NEUTRAL",army:100,growth:0};
  const humanCountries=new Set([...room.players.values()].map(p=>p.country).filter(Boolean));
  const aiTimers={};
  for (const c of ACTIVE) if (!humanCountries.has(c)) aiTimers[c]=5+Math.random()*10;
  return {
    territories,
    armies:[],
    aiTimers,
    aiCountries:[...Object.keys(aiTimers)],
    elapsed:0,
    snapshotClock:0,
    winner:"",
    onArmyStarted:null
  };
}
function publicRoom(room) {
  const host=room.players.get(room.hostToken);
  return {
    code:room.code,
    host_id:host?host.id:"",
    started:room.started,
    players:[...room.players.values()].map(p=>({id:p.id,name:p.name,country:p.country||"",connected:!!p.ws&&p.ws.readyState===WebSocket.OPEN}))
  };
}
function broadcast(room,payload) {
  const data=JSON.stringify(payload);
  for (const p of room.players.values()) if (p.ws&&p.ws.readyState===WebSocket.OPEN) p.ws.send(data);
}
function broadcastRoom(room) { broadcast(room,{type:"room_state",state:publicRoom(room)}); }
function snapshot(room) {
  const g=room.game, territories={};
  for (const [iso,t] of Object.entries(g.territories)) territories[iso]={owner:t.owner,army:Math.max(0,Math.floor(t.army))};
  return {
    revision:room.revision,
    phase:g.winner?"finished":"running",
    time:g.elapsed,
    winner:g.winner,
    players:[...room.players.values()].map(p=>({id:p.id,name:p.name,country:p.country||"",connected:!!p.ws&&p.ws.readyState===WebSocket.OPEN})),
    ai_countries:g.aiCountries.slice(),
    territories,
    armies:g.armies.map(a=>({
      id:a.id,
      owner:a.owner,
      source:a.source,
      target:a.target,
      amount:a.units.length,
      pending:Math.max(0,Math.floor(a.pending)),
      progress:a.units.length?Math.max(...a.units):0,
      units:a.units.slice(),
      route_length:a.route.routeLength
    }))
  };
}
function sendSnapshot(room) { broadcast(room,{type:"game_state",state:snapshot(room)}); }

function publicArmy(army) {
  return {
    id:army.id,
    owner:army.owner,
    source:army.source,
    target:army.target,
    amount:army.units.length,
    pending:Math.max(0,Math.floor(army.pending)),
    progress:army.units.length?Math.max(...army.units):0,
    units:army.units.slice(),
    route_length:army.route.routeLength
  };
}

function reservedFrom(g,source) {
  return g.armies.filter(a=>a.source===source).reduce((s,a)=>s+a.pending,0);
}
function addArmy(g,source,target,share,exact) {
  if (!g.territories[source]||!g.territories[target]||source===target) return false;
  const src=g.territories[source];
  if(src.owner==="NEUTRAL") return false;
  const free=Math.max(0,src.army-reservedFrom(g,source));
  const requested=exact==null?Math.floor(free*share):Math.min(Math.floor(exact),Math.floor(free));
  if (requested<1) return false;
  const army={
    id:nextArmyId++,
    owner:src.owner,
    source,
    target,
    pending:requested,
    emitClock:EMIT_INTERVAL,
    units:[],
    route:routeInfo(source,target)
  };
  g.armies.push(army);
  if (typeof g.onArmyStarted==="function") g.onArmyStarted(publicArmy(army));
  return army;
}
function sendExact(g,source,target,amount) {
  const t=g.territories[source];
  if (!t) return;
  const free=Math.max(0,t.army-reservedFrom(g,source)-AI_RESERVE);
  const count=Math.min(Math.floor(amount),Math.floor(free));
  if (count>0) addArmy(g,source,target,0,count);
}
function projectedAt(g,owner,target) {
  return g.armies.filter(a=>a.owner===owner&&a.target===target).reduce((s,a)=>s+a.units.length+a.pending,0);
}
function aiDecide(g,owner) {
  const owned=PLAYABLE.filter(i=>g.territories[i].owner===owner);
  const targets=PLAYABLE.filter(i=>g.territories[i].owner!==owner);
  if (!owned.length||!targets.length) return;
  let best="",bestScore=Infinity;
  for (const target of targets) {
    let nearest=Infinity;
    for (const source of owned) {
      const a=centers[source],b=centers[target];
      nearest=Math.min(nearest,Math.hypot(a.x-b.x,a.y-b.y));
    }
    const tt=g.territories[target];
    const score=(tt.army+18)*(tt.owner==="NEUTRAL"?0.78:1)+nearest*0.075;
    if (score<bestScore) {bestScore=score;best=target;}
  }
  if (!best) return;
  let rally=owned[0],dist=Infinity;
  for (const source of owned) {
    const a=centers[source],b=centers[best],d=Math.hypot(a.x-b.x,a.y-b.y);
    if (d<dist){dist=d;rally=source;}
  }
  const targetArmy=g.territories[best].army;
  const projected=g.territories[rally].army+projectedAt(g,owner,rally);
  const required=targetArmy*1.12+8;
  if (projected>=required && g.territories[rally].army>targetArmy+8) {
    const share=Math.max(0.52,Math.min(0.82,(targetArmy+Math.max(12,targetArmy*0.22))/g.territories[rally].army));
    addArmy(g,rally,best,share,null);
    return;
  }
  let need=Math.max(0,required-projected);
  const donors=owned
    .filter(x=>x!==rally)
    .map(x=>({id:x,available:Math.max(0,g.territories[x].army-AI_RESERVE)}))
    .filter(x=>x.available>4)
    .sort((a,b)=>b.available-a.available);
  for (const d of donors) {
    if (need<=0) break;
    const n=Math.min(need,d.available);
    sendExact(g,d.id,rally,n);
    need-=n;
  }
}

function emitAndMove(g,dt) {
  for(const a of g.armies){
    if(a.pending>0){
      const source=g.territories[a.source];
      if(!source||source.owner!==a.owner){
        a.pending=0;
      }else{
        a.emitClock+=dt;
        while(a.emitClock>=EMIT_INTERVAL && a.pending>0){
          if(source.army<1){a.pending=0;break;}
          a.emitClock-=EMIT_INTERVAL;
          source.army-=1;
          a.pending-=1;
          a.units.push(0);
        }
      }
    }
    const dp=ARMY_SPEED*dt/a.route.routeLength;
    for(let i=0;i<a.units.length;i++) a.units[i]=Math.min(1,a.units[i]+dp);
  }
}

function resolveUnitCollisions(g) {
  const cellSize=Math.max(8,COLLISION_RADIUS);
  const cells=new Map();
  const dead=new Map();
  const isDead=(id,index)=>dead.has(id)&&dead.get(id).has(index);
  const markDead=(id,index)=>{
    if(!dead.has(id)) dead.set(id,new Set());
    dead.get(id).add(index);
  };
  for(const army of g.armies){
    for(let i=0;i<army.units.length;i++){
      if(army.units[i]>=1) continue;
      const pos=routePoint(army,army.units[i]);
      const cx=Math.floor(pos.x/cellSize),cy=Math.floor(pos.y/cellSize);
      let collided=false;
      for(let ox=-1;ox<=1&&!collided;ox++) for(let oy=-1;oy<=1&&!collided;oy++){
        const bucket=cells.get((cx+ox)+":"+(cy+oy));
        if(!bucket) continue;
        for(const other of bucket){
          if(other.army.owner===army.owner || isDead(other.army.id,other.index)) continue;
          const dx=other.pos.x-pos.x,dy=other.pos.y-pos.y;
          if(dx*dx+dy*dy<=COLLISION_RADIUS*COLLISION_RADIUS){
            markDead(army.id,i);
            markDead(other.army.id,other.index);
            collided=true;
            break;
          }
        }
      }
      if(!collided){
        const key=cx+":"+cy;
        if(!cells.has(key)) cells.set(key,[]);
        cells.get(key).push({army,index:i,pos});
      }
    }
  }
  if(dead.size){
    for(const army of g.armies){
      const killed=dead.get(army.id);
      if(!killed) continue;
      army.units=army.units.filter((_,i)=>!killed.has(i));
    }
  }
}

function resolveArrivals(g) {
  for(const a of g.armies){
    let arrived=0;
    for(const p of a.units) if(p>=1) arrived++;
    if(!arrived) continue;
    a.units=a.units.filter(p=>p<1);
    const t=g.territories[a.target];
    for(let i=0;i<arrived;i++){
      if(t.owner===a.owner){
        t.army+=1;
      }else if(t.army>0){
        t.army=Math.max(0,t.army-1);
      }else{
        t.owner=a.owner;
        t.army=1;
      }
    }
  }
}

function checkWinner(room) {
  const g=room.game,alive=new Set();
  for (const t of Object.values(g.territories)) if (t.owner!=="NEUTRAL"&&ACTIVE.includes(t.owner)) alive.add(t.owner);
  for (const a of g.armies) if ((a.pending>0||a.units.length>0)&&ACTIVE.includes(a.owner)) alive.add(a.owner);
  if (alive.size===1 && !g.winner) {
    g.winner=[...alive][0];
    sendSnapshot(room);
    broadcast(room,{type:"game_over",winner:g.winner});
  }
}

function tickRoom(room,dt) {
  const g=room.game;
  if (!g||g.winner) return;
  g.elapsed+=dt;
  room.revision++;
  for (const t of Object.values(g.territories)) {
    t.growth+=(t.owner==="NEUTRAL"?0.5:1.0)*dt;
    const whole=Math.floor(t.growth);
    if (whole>0){t.army+=whole;t.growth-=whole;}
  }
  for (const owner of Object.keys(g.aiTimers)) {
    if (!PLAYABLE.some(i=>g.territories[i].owner===owner)) continue;
    g.aiTimers[owner]-=dt;
    if (g.aiTimers[owner]<=0){
      aiDecide(g,owner);
      g.aiTimers[owner]=5+Math.random()*10;
    }
  }
  emitAndMove(g,dt);
  resolveUnitCollisions(g);
  resolveArrivals(g);
  g.armies=g.armies.filter(a=>a.pending>0||a.units.length>0);
  checkWinner(room);
  g.snapshotClock+=dt;
  if (g.snapshotClock>=SNAPSHOT_MS/1000){
    g.snapshotClock=0;
    sendSnapshot(room);
  }
}

function startServer(options={}) {
const port=options.port==null?PORT:Number(options.port);
const startLoop=options.startLoop!==false;
const wss=new WebSocket.Server({port,maxPayload:16*1024});
wss.on("connection",ws=>{
  let room=null,player=null;
  send(ws,{type:"welcome"});

  ws.on("message",raw=>{
    let msg;
    try{msg=JSON.parse(raw.toString());}catch{return error(ws,"Некорректная команда.");}

    if (msg.type==="create_room") {
      if (room) return error(ws,"Вы уже находитесь в комнате.");
      const code=roomCode(),tok=token();
      player={id:randomId(),token:tok,name:String(msg.name||"Игрок").slice(0,24),country:"",ws};
      room={code,hostToken:tok,started:false,players:new Map([[tok,player]]),game:null,createdAt:Date.now(),lastActivity:Date.now(),revision:0};
      rooms.set(code,room);
      send(ws,{type:"session",player_id:player.id,session_token:tok,code});
      return broadcastRoom(room);
    }

    if (msg.type==="join_room") {
      if (room) return error(ws,"Вы уже находитесь в комнате.");
      const found=rooms.get(String(msg.code||""));
      if (!found) return error(ws,"Комната не найдена.");
      if (found.started) return error(ws,"Партия уже началась. На прежнем телефоне используйте «Вернуться в партию».");
      if (found.players.size>=10) return error(ws,"Комната заполнена.");
      const tok=token();
      player={id:randomId(),token:tok,name:String(msg.name||"Игрок").slice(0,24),country:"",ws};
      room=found;
      room.lastActivity=Date.now();
      room.players.set(tok,player);
      send(ws,{type:"session",player_id:player.id,session_token:tok,code:room.code});
      return broadcastRoom(room);
    }

    if (msg.type==="reconnect") {
      const found=rooms.get(String(msg.code||""));
      const reconnectToken=String(msg.session_token||msg.token||"");
      const p=found?found.players.get(reconnectToken):null;
      if (!found||!p) return error(ws,"Сессия комнаты не найдена.");
      room=found;
      room.lastActivity=Date.now();
      player=p;
      if(player.ws && player.ws!==ws && player.ws.readyState===WebSocket.OPEN) player.ws.close();
      player.ws=ws;
      send(ws,{type:"session",player_id:player.id,session_token:player.token,code:room.code});
      if (room.started) {
        send(ws,{type:"game_started",state:publicRoom(room)});
        send(ws,{type:"game_state",state:snapshot(room)});
        if (room.game&&room.game.winner) send(ws,{type:"game_over",winner:room.game.winner});
      } else {
        broadcastRoom(room);
      }
      return;
    }

    if (!room||!player) return error(ws,"Сначала создайте комнату или войдите в неё.");

    if (msg.type==="select_country") {
      if (room.started) return error(ws,"Партия уже началась.");
      const country=String(msg.country||"");
      if (!ACTIVE.includes(country)) return error(ws,"Недоступная страна.");
      for (const p of room.players.values()) if (p!==player&&p.country===country) return error(ws,"Эта страна уже занята.");
      player.country=country;
      return broadcastRoom(room);
    }

    if (msg.type==="start_room") {
      if (room.started) return error(ws,"Партия уже началась.");
      if (room.hostToken!==player.token) return error(ws,"Запустить игру может только создатель комнаты.");
      const players=[...room.players.values()];
      if (players.some(p=>!p.country)) return error(ws,"Каждый игрок должен выбрать страну.");
      room.started=true;
      room.game=makeGame(room);
      room.game.onArmyStarted=army=>broadcast(room,{type:"army_started",server_time:room.game.elapsed,army});
      broadcast(room,{type:"game_started",state:publicRoom(room)});
      return sendSnapshot(room);
    }

    if (msg.type==="send_army") {
      if (!room.started||!room.game||room.game.winner) return;
      const from=String(msg.source||msg.from||""),to=String(msg.target||msg.to||"");
      if (!PLAYABLE.includes(from)||!PLAYABLE.includes(to)||from===to) return;
      const src=room.game.territories[from];
      if (!src||src.owner!==player.country) return error(ws,"Этой территорией управляет другая страна.");
      const rawShare=Number(msg.share);
      const share=Number.isFinite(rawShare)?Math.max(0.01,Math.min(1,rawShare)):0.5;
      if(addArmy(room.game,from,to,share,null)) sendSnapshot(room);
      return;
    }
  });

  ws.on("close",()=>{
    if (!room||!player) return;
    if (player.ws===ws) player.ws=null;
    room.lastActivity=Date.now();
    if (!room.started) broadcastRoom(room);
  });
});

let previousTick=Date.now();
const loop=startLoop?setInterval(()=>{
  const now=Date.now();
  const dt=Math.max(0.001,Math.min(0.25,(now-previousTick)/1000));
  previousTick=now;
  for (const [code,room] of rooms) {
    if (room.started&&room.game) tickRoom(room,dt);
    const connected=[...room.players.values()].some(p=>p.ws&&p.ws.readyState===WebSocket.OPEN);
    if(!connected && now-room.lastActivity>ROOM_RETENTION_MS) rooms.delete(code);
  }
},TICK_MS):null;

const close=()=>new Promise(resolve=>{
  if(loop) clearInterval(loop);
  for(const client of wss.clients) client.terminate();
  wss.close(()=>resolve());
});
wss.gameClose=close;
return wss;
}

if (require.main===module) {
  startServer();
  console.log("World Strategy authoritative server listening on :"+PORT);
}

module.exports={
  ACTIVE,
  PLAYABLE,
  addArmy,
  checkWinner,
  makeGame,
  resolveArrivals,
  resolveUnitCollisions,
  snapshot,
  startServer,
  tickRoom
};
