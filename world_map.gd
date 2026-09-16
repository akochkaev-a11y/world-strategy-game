extends Control

const GEOJSON_PATH := "res://eurasia_countries.json"
const LON_MIN := -12.0
const LON_MAX := 150.0
const LAT_MIN := 5.0
const LAT_MAX := 76.0
const ACTIVE_IDS := ["RU","UA","PL","FR","DE","GB","CN","IN","IR","JP"]
const PLAYABLE_IDS := ["RU","UA","PL","FR","DE","GB","CN","IN","IR","JP","KZ","SA","ID","MN","PK","TR","MM","AF","YE","TH","ES","TM","SE","UZ","IQ","NO","FI","VN","MY","OM"]
const NAMES := {"RU":"Россия","UA":"Украина","PL":"Польша","FR":"Франция","DE":"Германия","GB":"Великобритания","CN":"Китай","IN":"Индия","IR":"Иран","JP":"Япония"}
const FLAGS := {"RU":"🇷🇺","UA":"🇺🇦","PL":"🇵🇱","FR":"🇫🇷","DE":"🇩🇪","GB":"🇬🇧","CN":"🇨🇳","IN":"🇮🇳","IR":"🇮🇷","JP":"🇯🇵"}
const START_ARMY := 100.0
const ARMY_SPEED := 110.0
const MAX_DRAWN_SOLDIERS := 42
var player_country := ""
var territories: Dictionary = {}
var armies: Array[Dictionary] = []
var map_features: Array = []
var hit_polygons: Dictionary = {}
var feature_centers: Dictionary = {}
var growth_fraction: Dictionary = {}
var zoom := 1.0
var pan := Vector2.ZERO
var touches: Dictionary = {}
var drag_source := ""
var pinch_distance := 0.0
var pinch_center := Vector2.ZERO
var ai_clock := 0.0
var anim_time := 0.0
var game_over := false
var game_started := false
func setup(_data:Dictionary,selected:String)->void:player_country=selected;_load_geojson();_ensure_territories();game_started=true;queue_redraw()
func _ready()->void:mouse_filter=Control.MOUSE_FILTER_STOP
func _feature_iso(props:Dictionary)->String:
 var iso:=str(props.get("ISO_A2",""));if iso=="" or iso=="-99":iso=str(props.get("ISO_A2_EH",""))
 if iso=="" or iso=="-99":
  var a3:=str(props.get("ADM0_A3",""));var m:={"FRA":"FR","RUS":"RU","UKR":"UA","POL":"PL","DEU":"DE","GBR":"GB","CHN":"CN","IND":"IN","IRN":"IR","JPN":"JP","KAZ":"KZ","SAU":"SA","IDN":"ID","MNG":"MN","PAK":"PK","TUR":"TR","MMR":"MM","AFG":"AF","YEM":"YE","THA":"TH","ESP":"ES","TKM":"TM","SWE":"SE","UZB":"UZ","IRQ":"IQ","NOR":"NO","FIN":"FI","VNM":"VN","MYS":"MY","OMN":"OM"};iso=str(m.get(a3,a3))
 return iso
func _load_geojson()->void:
 if not map_features.is_empty() or not FileAccess.file_exists(GEOJSON_PATH):return
 var f:=FileAccess.open(GEOJSON_PATH,FileAccess.READ);if f==null:return
 var parsed=JSON.parse_string(f.get_as_text());if typeof(parsed)!=TYPE_DICTIONARY:return
 for feature in parsed.get("features",[]):
  if PLAYABLE_IDS.has(_feature_iso(feature.get("properties",{}))):map_features.append(feature)
func _ensure_territories()->void:
 for feature in map_features:
  var iso:=_feature_iso(feature.get("properties",{}));if iso=="" or territories.has(iso):continue
  var active:=ACTIVE_IDS.has(iso);territories[iso]={"owner":iso if active else "NEUTRAL","army":START_ARMY};growth_fraction[iso]=0.0
func grow_armies()->void:
 if game_over:return
 for iso in territories.keys():
  var t:Dictionary=territories[iso];var rate:float=1.0 if str(t.owner)!="NEUTRAL" else 0.5;growth_fraction[iso]=float(growth_fraction.get(iso,0.0))+rate;var whole:=int(floor(float(growth_fraction[iso])))
  if whole>0:t.army=float(t.army)+whole;growth_fraction[iso]=float(growth_fraction[iso])-whole
 queue_redraw()
func _process(delta:float)->void:
 if game_over:return
 anim_time+=delta;_move_armies(delta);ai_clock+=delta;if ai_clock>=4.0:ai_clock=0.0;_ai_attack()
func _base_project(lon:float,lat:float)->Vector2:return Vector2((lon-LON_MIN)/(LON_MAX-LON_MIN)*size.x,(LAT_MAX-lat)/(LAT_MAX-LAT_MIN)*size.y)
func _project(lon:float,lat:float)->Vector2:var c:=size*0.5;return c+(_base_project(lon,lat)-c)*zoom+pan
func _rings(feature:Dictionary)->Array:
 var g:Dictionary=feature.get("geometry",{});var coords:Array=g.get("coordinates",[]);var out:Array=[]
 if str(g.get("type",""))=="Polygon" and not coords.is_empty():out.append(coords[0])
 elif str(g.get("type",""))=="MultiPolygon":
  for p in coords:
   if not p.is_empty():out.append(p[0])
 return out
func _poly(ring:Array)->PackedVector2Array:
 var out:=PackedVector2Array()
 for q in ring:
  if q.size()>=2:out.append(_project(float(q[0]),float(q[1])))
 return out
func _bounds(poly:PackedVector2Array)->Rect2:
 var a:=Vector2(INF,INF);var b:=Vector2(-INF,-INF)
 for p in poly:a.x=minf(a.x,p.x);a.y=minf(a.y,p.y);b.x=maxf(b.x,p.x);b.y=maxf(b.y,p.y)
 return Rect2(a,b-a)
func _owner_color(owner:String)->Color:
 var c:={"RU":Color(0.16,0.48,0.96),"UA":Color(0.98,0.76,0.08),"PL":Color(0.94,0.18,0.38),"FR":Color(0.20,0.72,0.92),"DE":Color(0.70,0.28,0.88),"GB":Color(0.18,0.72,0.48),"CN":Color(0.94,0.22,0.12),"IN":Color(1.0,0.48,0.08),"IR":Color(0.08,0.58,0.24),"JP":Color(0.92,0.38,0.68)};return c.get(owner,Color(0.30,0.33,0.36))
func _draw_soldiers(center:Vector2,amount:int,owner:String,direction:Vector2)->void:
 var n:int=mini(amount,MAX_DRAWN_SOLDIERS);var side:=Vector2(-direction.y,direction.x)
 for i in range(n):
  var row:int=i/4;var col:int=i%4;var wave:=sin(anim_time*6.0+float(i)*1.7)*2.4;var stagger:=sin(float(i)*2.13)*2.2;var p:=center-direction*((float(row)-float(n/8))*7.5+stagger)+side*((float(col)-1.5)*7.5+wave);draw_circle(p,4.5,Color(0.02,0.03,0.04,0.72));draw_circle(p,3.0,_owner_color(owner));draw_circle(p-Vector2(0.8,0.8),0.8,Color(1,1,1,0.65))
 draw_circle(center+Vector2(0,-27),15.0,Color(0.02,0.05,0.08,0.94));draw_string(ThemeDB.fallback_font,center+Vector2(-19,-22),str(amount),HORIZONTAL_ALIGNMENT_CENTER,38,12,Color.WHITE)
func _draw()->void:
 draw_rect(Rect2(Vector2.ZERO,size),Color(0.025,0.075,0.12));hit_polygons.clear();feature_centers.clear();var best:Dictionary={}
 for feature in map_features:
  var iso:=_feature_iso(feature.get("properties",{}));if not territories.has(iso):continue
  var polys:Array=[]
  for ring in _rings(feature):
   var p:=_poly(ring);if p.size()<3:continue
   var owner:=str(territories[iso].owner);var fill:=_owner_color(owner);if owner==player_country:fill=fill.lightened(0.06);draw_colored_polygon(p,fill)
   var border:=Color(0.98,0.83,0.28) if owner==player_country else Color(0.68,0.75,0.80);var width:float=3.0+sin(anim_time*2.5)*0.7 if owner==player_country else 1.15
   for i in range(p.size()):draw_line(p[i],p[(i+1)%p.size()],border,width,true)
   var bb:=_bounds(p);var area:=bb.size.x*bb.size.y;if area>float(best.get(iso,0.0)):best[iso]=area;feature_centers[iso]=bb.get_center()
   polys.append(p)
  if not polys.is_empty():hit_polygons[iso]=polys
 for iso in feature_centers.keys():
  var t:Dictionary=territories[iso];var c:Vector2=feature_centers[iso];var owner:=str(t.owner);var title:=str(NAMES.get(iso,"")) if ACTIVE_IDS.has(iso) else "";var flag:=str(FLAGS.get(owner,"")) if owner!="NEUTRAL" else ""
  if flag!="":draw_string_outline(ThemeDB.fallback_font,c-Vector2(50,14),flag,HORIZONTAL_ALIGNMENT_CENTER,100,28,4,Color.BLACK);draw_string(ThemeDB.fallback_font,c-Vector2(50,14),flag,HORIZONTAL_ALIGNMENT_CENTER,100,28,Color.WHITE)
  if title!="":draw_string_outline(ThemeDB.fallback_font,c-Vector2(70,-12),title,HORIZONTAL_ALIGNMENT_CENTER,140,15,4,Color.BLACK);draw_string(ThemeDB.fallback_font,c-Vector2(70,-12),title,HORIZONTAL_ALIGNMENT_CENTER,140,15,Color.WHITE)
  var count:=str(int(float(t.army)));draw_string_outline(ThemeDB.fallback_font,c-Vector2(60,-30),count,HORIZONTAL_ALIGNMENT_CENTER,120,17,4,Color.BLACK);draw_string(ThemeDB.fallback_font,c-Vector2(60,-30),count,HORIZONTAL_ALIGNMENT_CENTER,120,17,Color.WHITE)
 if drag_source!="" and feature_centers.has(drag_source) and touches.size()==1:
  var finger:Vector2=Vector2(touches.values()[0]);var source_pos:Vector2=Vector2(feature_centers[drag_source]);draw_line(source_pos,finger,Color(1,1,1,0.42),2.0,true);draw_circle(source_pos,13.0+sin(anim_time*5.0)*2.0,Color(1,0.83,0.28,0.55),false,2.5)
  var hover:=_hit(finger);if hover!="" and feature_centers.has(hover):draw_circle(Vector2(feature_centers[hover]),19.0+sin(anim_time*5.0)*2.0,Color(1,1,1,0.48),false,2.5)
 for a in armies:
  var pos:Vector2=a.pos;var target:=str(a.target);var dir:=Vector2.RIGHT;if feature_centers.has(target):dir=(Vector2(feature_centers[target])-pos).normalized();_draw_soldiers(pos,int(float(a.amount)),str(a.owner),dir)
func _hit(pos:Vector2)->String:
 for iso in hit_polygons.keys():
  for p in hit_polygons[iso]:
   if Geometry2D.is_point_in_polygon(pos,p):return str(iso)
 return ""
func _send_army(from_iso:String,to_iso:String,share:=0.5,ai:=false)->void:
 if game_over or from_iso=="" or to_iso=="" or from_iso==to_iso or not territories.has(from_iso) or not territories.has(to_iso):return
 var src:Dictionary=territories[from_iso];if str(src.owner)=="NEUTRAL" or (not ai and str(src.owner)!=player_country):return
 var amount:float=floor(float(src.army)*share);if amount<1.0 or not feature_centers.has(from_iso):return
 src.army=float(src.army)-amount;armies.append({"owner":str(src.owner),"amount":amount,"pos":Vector2(feature_centers[from_iso]),"target":to_iso});queue_redraw()
func _move_armies(delta:float)->void:
 for i in range(armies.size()-1,-1,-1):
  if i>=armies.size():continue
  var a:Dictionary=armies[i];var target:=str(a.target);if not feature_centers.has(target):continue
  var dest:Vector2=feature_centers[target];var pos:Vector2=a.pos;if pos.distance_to(dest)<=ARMY_SPEED*delta:_arrive(i);continue
  a.pos=pos.move_toward(dest,ARMY_SPEED*delta)
 _resolve_collisions();queue_redraw()
func _resolve_collisions()->void:
 var i:=0
 while i<armies.size():
  var j:=i+1
  while j<armies.size():
   if str(armies[i].owner)!=str(armies[j].owner) and Vector2(armies[i].pos).distance_to(Vector2(armies[j].pos))<=20.0:
    var loss:=minf(float(armies[i].amount),float(armies[j].amount));armies[i].amount=float(armies[i].amount)-loss;armies[j].amount=float(armies[j].amount)-loss
    if float(armies[j].amount)<=0:armies.remove_at(j);continue
    if float(armies[i].amount)<=0:armies.remove_at(i);i-=1;break
   j+=1
  i+=1
func _arrive(index:int)->void:
 if index<0 or index>=armies.size():return
 var a:Dictionary=armies[index];armies.remove_at(index);var target:=str(a.target);if not territories.has(target):return
 var t:Dictionary=territories[target]
 if str(t.owner)==str(a.owner):t.army=float(t.army)+float(a.amount);return
 var attackers:=float(a.amount);var defenders:=float(t.army)
 if attackers>defenders:t.owner=str(a.owner);t.army=attackers-defenders
 else:t.army=defenders-attackers
 _check_player_defeat();queue_redraw()
func _check_player_defeat()->void:
 if not game_started or game_over:return
 for iso in territories.keys():
  if str(territories[iso].owner)==player_country:return
 game_over=true;armies.clear();_show_defeat()
func _show_defeat()->void:
 var shade:=ColorRect.new();shade.color=Color(0.01,0.02,0.04,0.78);shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);shade.mouse_filter=Control.MOUSE_FILTER_STOP;add_child(shade)
 var center:=CenterContainer.new();center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);shade.add_child(center);var box:=VBoxContainer.new();box.custom_minimum_size=Vector2(520,250);box.alignment=BoxContainer.ALIGNMENT_CENTER;center.add_child(box)
 var title:=Label.new();title.text="ВЫ ПРОИГРАЛИ";title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;title.add_theme_font_size_override("font_size",42);box.add_child(title)
 var sub:=Label.new();sub.text="Все территории вашей державы захвачены";sub.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;sub.add_theme_font_size_override("font_size",18);box.add_child(sub)
 var button:=Button.new();button.text="НАЧАТЬ ЗАНОВО";button.custom_minimum_size=Vector2(320,60);button.add_theme_font_size_override("font_size",20);button.pressed.connect(_restart);box.add_child(button)
func _restart()->void:get_tree().reload_current_scene()
func _ai_attack()->void:
 var sources:Array=[]
 for iso in territories.keys():
  var t:Dictionary=territories[iso];var owner:=str(t.owner);if owner!="NEUTRAL" and owner!=player_country and float(t.army)>=30.0:sources.append(str(iso))
 if sources.is_empty():return
 var source:=str(sources[randi()%sources.size()]);var owner:=str(territories[source].owner);var sa:=float(territories[source].army);var best_target:="";var best_score:float=-1000000.0
 for iso in territories.keys():
  if str(territories[iso].owner)==owner or not feature_centers.has(iso):continue
  var ta:=float(territories[iso].army);var dist:=Vector2(feature_centers[source]).distance_to(Vector2(feature_centers[iso]));var score:float=(80.0 if str(territories[iso].owner)=="NEUTRAL" else 0.0)+maxf(0.0,sa-ta)*1.8+(55.0 if str(territories[iso].owner)==player_country and ta<sa*0.75 else 0.0)-dist*0.22
  if score>best_score:best_score=score;best_target=str(iso)
 if best_target!="" and (best_score>0.0 or sa>180.0):_send_army(source,best_target,0.5,true)
func _gui_input(event:InputEvent)->void:
 if game_over:return
 if event is InputEventScreenTouch:
  if event.pressed:
   touches[event.index]=event.position
   if touches.size()==1:drag_source=_hit(event.position)
   elif touches.size()==2:drag_source="";var pts:=touches.values();pinch_distance=Vector2(pts[0]).distance_to(Vector2(pts[1]));pinch_center=(Vector2(pts[0])+Vector2(pts[1]))*0.5
  else:
   if touches.size()==1 and drag_source!="":var target:=_hit(event.position);if target!="":_send_army(drag_source,target)
   touches.erase(event.index);if touches.size()<2:pinch_distance=0.0;drag_source=""
  accept_event()
 elif event is InputEventScreenDrag:
  if not touches.has(event.index):return
  touches[event.index]=event.position
  if touches.size()==2:
   var pts:=touches.values();var nd:=Vector2(pts[0]).distance_to(Vector2(pts[1]));var nc:=(Vector2(pts[0])+Vector2(pts[1]))*0.5
   if pinch_distance>0.0:var oz:=zoom;zoom=clampf(zoom*(nd/pinch_distance),0.8,5.0);pan=(pan+(pinch_center-size*0.5)*(1.0-oz/zoom))+(nc-pinch_center)
   pinch_distance=nd;pinch_center=nc;queue_redraw()
  elif touches.size()==1 and drag_source=="":pan+=event.relative;queue_redraw()
  accept_event()