const fs = require("fs");
const path = require("path");
const WebSocket = require("ws");

const PORT = Number(process.env.PORT || 8080);
const TICK_MS = 50;
const SNAPSHOT_MS = 100;
const ARMY_SPEED = 110;
const UNIT_SPACING = 9;
const EMIT_INTERVAL = UNIT_SPACING / ARMY_SPEED;
const ARRIVAL_INTERVAL = 0.055;
const FIELD_INTERVAL = 0.075;
const AI_RESERVE = 30;
const ACTIVE = ["RU","UA","PL","FR","DE","GB","CN","IN","IR","JP"];
const PLAYABLE = ["RU","UA","PL","FR","DE","GB","CN","IN","IR","JP","KZ","SA","MN","PK","TR","AF","ES","TM","SE","UZ","IQ","NO","FI"];
const LON_MIN=-12, LON_MAX=150, LAT_MIN=5, LAT_MAX=76;
const rooms = new Map();
let nextArmyId = 1;

function randomId() { return Math.random().toString(36).slice(2, 10); }
function token() { return randomId()+randomId()+randomId(); }
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
function geometryBounds(coords,b=[Infinity,Infinity,-Infinity,-Infinity]) {
  if (!Array.isArray(coords)) return b;
  if (coords.length>=2 && typeof coords[0]==="number" && typeof coords[1]==="number") {
    b[0]=Math.min(b[0],coords[0]); b[1]=Math.min(b[1],coords[1]); b[2]=Math.max(b[2],coords[0]); b[3]=Math.max(b[3],coords[1]);
    return b;
  }
  for (const c of coords) geometryBounds(c,b);
  return b;
}
function project(lon,lat) {
  return {x:(lon-LON_MIN)/(LON_MAX-LON_MIN)*1280,y:(LAT_MAX-lat)/(LAT_MAX-LAT_MIN)*720};
}
const centers={};
try {
  const geo=JSON.parse(fs.readFileSync(path.join(__dirname,"..","eurasia_countries.json"),"utf8"));
  for (const f of geo.features||[]) {
    const iso=isoOf(f);
    if (!PLAYABLE.includes(iso)) continue;
    const b=Array.isArray(f.bbox)&&f.bbox.length>=4 ? f.bbox : geometryBounds((f.geometry||{}).coordinates);
    centers[iso]=project((b[0]+b[2])/2,(b[1]+b[3])/2);
  }
} catch (e) {
  console.error("Failed to load map geometry:",e);
}
function routeInfo(source,target) {
  const a=centers[source]||{x:0,y:0}, b=centers[target]||{x:1,y:0};
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
function pointSegDist2(p,a,b) {
  const dx=b.x-a.x,dy=b.y-a.y,d=dx*dx+dy*dy;
  if (d<1e-9) return (p.x-a.x)**2+(p.y-a.y)**2;
  const t=Math.max(0,Math.min(1,((p.x-a.x)*dx+(p.y-a.y)*dy)/d));
  const x=a.x+dx*t,y=a.y+dy*t;
  return (p.x-x)**2+(p.y-y)**2;
}
function orient(a,b,c) { return (b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x); }
function segmentsTouch(a,b,c,d) {
  const o1=orient(a,b,c),o2=orient(a,b,d),o3=orient(c,d,a),o4=orient(c,d,b);
  if ((o1===0||o2===0||o1*o2<0)&&(o3===0||o4===0||o3*o4<0)) return true;
  const lim=7.7*7.7;
  return pointSegDist2(a,c,d)<=lim||pointSegDist2(b,c,d)<=lim||pointSegDist2(c,a,b)<=lim||pointSegDist2(d,a,b)<=lim;
}
function armySegment(a) {
  const head=routePoint(a,a.progress);
  const step=UNIT_SPACING/Math.max(1,a.route.routeLength);
  const tail=routePoint(a,Math.max(0,a.progress-step*Math.max(0,a.amount-1)));
  return {head,tail};
}

function makeGame(room) {
  const territories={};
  for (const iso of PLAYABLE) territories[iso]={owner:ACTIVE.includes(iso)?iso:"NEUTRAL",army:100,growth:0};
  const humanCountries=new Set([...room.players.values()].map(p=>p.country).filter(Boolean));
  const aiTimers={};
  for (const c of ACTIVE) if (!humanCountries.has(c)) aiTimers[c]=5+Math.random()*10;
  return {territories,armies:[],aiTimers,elapsed:0,snapshotClock:0,winner:"",fieldClocks:new Map()};
}
function publicRoom(room) {
  const host=room.players.get(room.hostToken);
  return {code:room.code,host_id:host?host.id:"",started:room.started,
    players:[...room.players.values()].map(p=>({id:p.id,name:p.name,country:p.country||"",connected:!!p.ws}))};
}
function broadcast(room,payload) {
  const data=JSON.stringify(payload);
  for (const p of room.players.values()) if (p.ws&&p.ws.readyState===WebSocket.OPEN) p.ws.send(data);
}
function broadcastRoom(room) { broadcast(room,{type:"room_state",state:publicRoom(room)}); }
function snapshot(room) {
  const g=room.game, territories={};
  for (const [iso,t] of Object.entries(g.territories)) territories[iso]={owner:t.owner,army:Math.max(0,Math.floor(t.army))};
  return {time:g.elapsed,territories,armies:g.armies.map(a=>({id:a.id,owner:a.owner,source:a.source,target:a.target,amount:Math.max(0,Math.floor(a.amount)),pending:Math.max(0,Math.floor(a.pending)),progress:a.progress}))};
}
function sendSnapshot(room) { broadcast(room,{type:"game_state",state:snapshot(room)}); }

function reservedFrom(g,source) {
  return g.armies.filter(a=>a.source===source).reduce((s,a)=>s+a.pending,0);
}
function addArmy(g,source,target,share,exact) {
  if (!g.territories[source]||!g.territories[target]||source===target) return false;
  const src=g.territories[source];
  const free=Math.max(0,src.army-reservedFrom(g,source));
  const requested=exact==null?Math.floor(free*share):Math.min(Math.floor(exact),Math.floor(free));
  if (requested<1) return false;
  g.armies.push({id:nextArmyId++,owner:src.owner,source,target,amount:0,pending:requested,emitClock:EMIT_INTERVAL,arrivalClock:0,progress:0,route:routeInfo(source,target)});
  return true;
}
function sendExact(g,source,target,amount) {
  const t=g.territories[source]; if (!t) return;
  const free=Math.max(0,t.army-reservedFrom(g,source)-AI_RESERVE);
  const count=Math.min(Math.floor(amount),Math.floor(free));
  if (count>0) addArmy(g,source,target,0,count);
}
function projectedAt(g,owner,target) {
  return g.armies.filter(a=>a.owner===owner&&a.target===target).reduce((s,a)=>s+a.amount+a.pending,0);
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
      if (a&&b) nearest=Math.min(nearest,Math.hypot(a.x-b.x,a.y-b.y));
    }
    const tt=g.territories[target];
    const score=(tt.army+18)*(tt.owner==="NEUTRAL"?0.78:1)+nearest*0.075;
    if (score<bestScore) {bestScore=score;best=target;}
  }
  if (!best) return;
  let rally=owned[0],dist=Infinity;
  for (const source of owned) {
    const a=centers[source],b=centers[best],d=a&&b?Math.hypot(a.x-b.x,a.y-b.y):9999;
    if (d<dist){dist=d;rally=source;}
  }
  const targetArmy=g.territories[best].army;
  const projected=g.territories[rally].army+projectedAt(g,owner,rally);
  const required=targetArmy*1.12+8;
  if (projected>=required && g.territories[rally].army>targetArmy+8) {
    const share=Math.max(0.52,Math.min(0.82,(targetArmy+Math.max(12,targetArmy*0.22))/g.territories[rally].army));
    addArmy(g,rally,best,share,null); return;
  }
  let need=Math.max(0,required-projected);
  const donors=owned.filter(x=>x!==rally).map(x=>({id:x,available:Math.max(0,g.territories[x].army-AI_RESERVE)})).filter(x=>x.available>4).sort((a,b)=>b.available-a.available);
  for (const d of donors) {
    if (need<=0) break;
    const n=Math.min(need,d.available); sendExact(g,d.id,rally,n); need-=n;
  }
}
function checkWinner(room) {
  const g=room.game,alive=new Set();
  for (const t of Object.values(g.territories)) if (t.owner!=="NEUTRAL"&&ACTIVE.includes(t.owner)) alive.add(t.owner);
  if (alive.size===1 && !g.winner) {
    g.winner=[...alive][0];
    broadcast(room,{type:"game_over",winner:g.winner});
  }
}
function tickRoom(room,dt) {
  const g=room.game;
  if (!g||g.winner) return;
  g.elapsed+=dt;
  for (const t of Object.values(g.territories)) {
    t.growth+=(t.owner==="NEUTRAL"?0.5:1.0)*dt;
    const whole=Math.floor(t.growth);
    if (whole>0){t.army+=whole;t.growth-=whole;}
  }
  for (const owner of Object.keys(g.aiTimers)) {
    if (!PLAYABLE.some(i=>g.territories[i].owner===owner)) continue;
    g.aiTimers[owner]-=dt;
    if (g.aiTimers[owner]<=0){aiDecide(g,owner);g.aiTimers[owner]=5+Math.random()*10;}
  }
  for (const a of g.armies) {
    if (a.pending>0) {
      if (!g.territories[a.source]||g.territories[a.source].owner!==a.owner){a.pending=0;}
      else {
        a.emitClock+=dt;
        while (a.emitClock>=EMIT_INTERVAL&&a.pending>0) {
          if (g.territories[a.source].army<1){a.pending=0;break;}
          a.emitClock-=EMIT_INTERVAL; g.territories[a.source].army-=1; a.amount+=1; a.pending-=1;
        }
      }
    }
    if (a.amount>0) a.progress=Math.min(1,a.progress+ARMY_SPEED*dt/a.route.routeLength);
  }
  const activeKeys=new Set();
  for (let i=0;i<g.armies.length;i++) for (let j=i+1;j<g.armies.length;j++) {
    const a=g.armies[i],b=g.armies[j];
    if (a.owner===b.owner||a.amount<=0||b.amount<=0) continue;
    const sa=armySegment(a),sb=armySegment(b);
    if (!segmentsTouch(sa.head,sa.tail,sb.head,sb.tail)) continue;
    const key=a.id<b.id?String(a.id)+":"+String(b.id):String(b.id)+":"+String(a.id);
    activeKeys.add(key);
    const clock=(g.fieldClocks.get(key)||0)+dt;
    if (clock>=FIELD_INTERVAL){a.amount-=1;b.amount-=1;g.fieldClocks.set(key,clock-FIELD_INTERVAL);} else g.fieldClocks.set(key,clock);
  }
  for (const key of [...g.fieldClocks.keys()]) if (!activeKeys.has(key)) g.fieldClocks.delete(key);
  for (const a of g.armies) {
    if (a.progress<1||a.amount<=0) continue;
    a.arrivalClock+=dt;
    while (a.arrivalClock>=ARRIVAL_INTERVAL&&a.amount>0) {
      a.arrivalClock-=ARRIVAL_INTERVAL;
      const t=g.territories[a.target]; a.amount-=1;
      if (t.owner===a.owner) t.army+=1;
      else if (t.army>0) t.army=Math.max(0,t.army-1);
      else {t.owner=a.owner;t.army=1;}
    }
  }
  g.armies=g.armies.filter(a=>a.amount>0||a.pending>0);
  checkWinner(room);
  g.snapshotClock+=dt;
  if (g.snapshotClock>=SNAPSHOT_MS/1000){g.snapshotClock=0;sendSnapshot(room);}
}

const wss=new WebSocket.Server({port:PORT});
wss.on("connection",ws=>{
  let room=null,player=null;
  send(ws,{type:"welcome"});
  ws.on("message",raw=>{
    let msg; try{msg=JSON.parse(raw.toString());}catch{return error(ws,"Некорректная команда.");}
    if (msg.type==="create_room") {
      if (room) return error(ws,"Вы уже находитесь в комнате.");
      const code=roomCode(),tok=token();
      player={id:randomId(),token:tok,name:String(msg.name||"Игрок").slice(0,24),country:"",ws};
      room={code,hostToken:tok,started:false,players:new Map([[tok,player]]),game:null};
      rooms.set(code,room);
      send(ws,{type:"session",player_id:player.id,token:tok,code});
      return broadcastRoom(room);
    }
    if (msg.type==="join_room") {
      if (room) return error(ws,"Вы уже находитесь в комнате.");
      const found=rooms.get(String(msg.code||""));
      if (!found) return error(ws,"Комната не найдена.");
      if (found.started) return error(ws,"Партия уже началась. Для возврата используется переподключение.");
      if (found.players.size>=10) return error(ws,"Комната заполнена.");
      const tok=token();
      player={id:randomId(),token:tok,name:String(msg.name||"Игрок").slice(0,24),country:"",ws};
      room=found;room.players.set(tok,player);
      send(ws,{type:"session",player_id:player.id,token:tok,code:room.code});
      return broadcastRoom(room);
    }
    if (msg.type==="reconnect") {
      const found=rooms.get(String(msg.code||""));
      const p=found?found.players.get(String(msg.token||"")):null;
      if (!found||!p) return error(ws,"Сессия комнаты не найдена.");
      room=found;player=p;player.ws=ws;
      send(ws,{type:"session",player_id:player.id,token:player.token,code:room.code});
      if (room.started) {
        send(ws,{type:"game_started",state:publicRoom(room)});
        send(ws,{type:"game_state",state:snapshot(room)});
        if (room.game&&room.game.winner) send(ws,{type:"game_over",winner:room.game.winner});
      } else broadcastRoom(room);
      return;
    }
    if (!room||!player) return error(ws,"Сначала создайте комнату или войдите в неё.");
    if (msg.type==="select_country") {
      if (room.started) return error(ws,"Партия уже началась.");
      const country=String(msg.country||"");
      if (!ACTIVE.includes(country)) return error(ws,"Недоступная страна.");
      for (const p of room.players.values()) if (p!==player&&p.country===country) return error(ws,"Эта страна уже занята.");
      player.country=country;return broadcastRoom(room);
    }
    if (msg.type==="start_room") {
      if (room.hostToken!==player.token) return error(ws,"Запустить игру может только создатель комнаты.");
      const players=[...room.players.values()];
      if (players.some(p=>!p.country)) return error(ws,"Каждый игрок должен выбрать страну.");
      room.started=true;room.game=makeGame(room);
      broadcast(room,{type:"game_started",state:publicRoom(room)});
      return sendSnapshot(room);
    }
    if (msg.type==="send_army") {
      if (!room.started||!room.game||room.game.winner) return;
      const from=String(msg.from||""),to=String(msg.to||"");
      if (!PLAYABLE.includes(from)||!PLAYABLE.includes(to)||from===to) return;
      const src=room.game.territories[from];
      if (!src||src.owner!==player.country) return error(ws,"Этой территорией управляет другая страна.");
      const share=Math.max(0.01,Math.min(1,Number(msg.share)||0.5));
      addArmy(room.game,from,to,share,null);
      return;
    }
  });
  ws.on("close",()=>{
    if (!room||!player) return;
    if (player.ws===ws) player.ws=null;
    if (!room.started) broadcastRoom(room);
  });
});
setInterval(()=>{for (const room of rooms.values()) if (room.started&&room.game) tickRoom(room,TICK_MS/1000);},TICK_MS);
console.log("World Strategy authoritative server listening on :"+PORT);
