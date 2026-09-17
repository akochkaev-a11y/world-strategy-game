extends Control

const GEOJSON_PATH := "res://eurasia_countries.json"
const LON_MIN := -12.0
const LON_MAX := 150.0
const LAT_MIN := 5.0
const LAT_MAX := 76.0
const ACTIVE_IDS := ["RU","UA","PL","FR","DE","GB","CN","IN","IR","JP"]
const BACKGROUND_IDS := ["ID","MY","TH","MM","VN","YE","OM"]
const PLAYABLE_IDS := ["RU","UA","PL","FR","DE","GB","CN","IN","IR","JP","KZ","SA","MN","PK","TR","AF","ES","TM","SE","UZ","IQ","NO","FI"]
const MAP_IDS := ["RU","UA","PL","FR","DE","GB","CN","IN","IR","JP","KZ","SA","ID","MN","PK","TR","MM","AF","YE","TH","ES","TM","SE","UZ","IQ","NO","FI","VN","MY","OM"]
const NAMES := {"RU":"Россия","UA":"Украина","PL":"Польша","FR":"Франция","DE":"Германия","GB":"Великобритания","CN":"Китай","IN":"Индия","IR":"Иран","JP":"Япония"}
const FLAGS := {"RU":"🇷🇺","UA":"🇺🇦","PL":"🇵🇱","FR":"🇫🇷","DE":"🇩🇪","GB":"🇬🇧","CN":"🇨🇳","IN":"🇮🇳","IR":"🇮🇷","JP":"🇯🇵"}
const START_ARMY := 100.0
const ARMY_SPEED := 110.0
const AI_RESERVE := 30.0

var player_country := ""
var territories:Dictionary={}
var armies:Array[Dictionary]=[]
var map_features:Array=[]
var hit_polygons:Dictionary={}
var feature_centers:Dictionary={}
var growth_fraction:Dictionary={}
var ai_timers:Dictionary={}
var collision_flashes:Array[Dictionary]=[]
var zoom:=1.0
var pan:=Vector2.ZERO
var touches:Dictionary={}
var drag_source:=""
var mouse_down:=false
var mouse_pos:=Vector2.ZERO
var pinch_distance:=0.0
var pinch_midpoint:=Vector2.ZERO
var camera_gesture:=false
var suppress_single_touch:=false
var anim_time:=0.0
var game_over:=false
var game_started:=false
var time_scale:=1.0
var speed_button:Button

func setup(_data:Dictionary,selected:String)->void:
    player_country=selected;_load_geojson();_ensure_territories();_reset_ai_timers();game_started=territories.size()==PLAYABLE_IDS.size();queue_redraw()
func _ready()->void:
    mouse_filter=Control.MOUSE_FILTER_STOP
    speed_button=Button.new();speed_button.text="×1";speed_button.custom_minimum_size=Vector2(72,48);speed_button.set_anchors_preset(Control.PRESET_TOP_RIGHT);speed_button.position=Vector2(-88,16);speed_button.add_theme_font_size_override("font_size",20);speed_button.pressed.connect(_toggle_speed);add_child(speed_button)
func _toggle_speed()->void:
    time_scale=2.0 if time_scale<1.5 else 1.0;speed_button.text="×2" if time_scale>1.5 else "×1";speed_button.modulate=Color(1.0,0.82,0.32) if time_scale>1.5 else Color.WHITE
func _feature_iso(props:Dictionary)->String:
    var iso:String=str(props.get("ISO_A2",""))
    if iso=="" or iso=="-99":iso=str(props.get("ISO_A2_EH",""))
    if iso=="" or iso=="-99":
        var a3:String=str(props.get("ADM0_A3",""));var m:Dictionary={"FRA":"FR","RUS":"RU","UKR":"UA","POL":"PL","DEU":"DE","GBR":"GB","CHN":"CN","IND":"IN","IRN":"IR","JPN":"JP","KAZ":"KZ","SAU":"SA","IDN":"ID","MNG":"MN","PAK":"PK","TUR":"TR","MMR":"MM","AFG":"AF","YEM":"YE","THA":"TH","ESP":"ES","TKM":"TM","SWE":"SE","UZB":"UZ","IRQ":"IQ","NOR":"NO","FIN":"FI","VNM":"VN","MYS":"MY","OMN":"OM"};iso=str(m.get(a3,a3))
    return iso
func _load_geojson()->void:
    map_features.clear()
    if not FileAccess.file_exists(GEOJSON_PATH):push_error("Missing map geometry: "+GEOJSON_PATH);return
    var f:FileAccess=FileAccess.open(GEOJSON_PATH,FileAccess.READ)
    if f==null:return
    var parsed:Variant=JSON.parse_string(f.get_as_text())
    if typeof(parsed)!=TYPE_DICTIONARY:return
    var seen:Dictionary={}
    for raw_feature in parsed.get("features",[]):
        if typeof(raw_feature)!=TYPE_DICTIONARY:continue
        var feature:Dictionary=raw_feature;var props:Dictionary=feature.get("properties",{});var iso:String=_feature_iso(props);var geom:Dictionary=feature.get("geometry",{});var geom_type:String=str(geom.get("type",""))
        if not MAP_IDS.has(iso) or (geom_type!="Polygon" and geom_type!="MultiPolygon"):continue
        if seen.has(iso):push_error("Duplicate map geometry: "+iso);continue
        seen[iso]=true;map_features.append(feature)
    for iso in MAP_IDS:
        if not seen.has(iso):push_error("Missing map geometry: "+str(iso))
    if map_features.size()!=MAP_IDS.size():push_error("Map geometry count must be exactly 30, got "+str(map_features.size()))
func _ensure_territories()->void:
    territories.clear();growth_fraction.clear()
    if map_features.size()!=MAP_IDS.size():return
    for feature in map_features:
        var iso:String=_feature_iso(feature.get("properties",{}))
        if not PLAYABLE_IDS.has(iso) or territories.has(iso):continue
        territories[iso]={"owner":iso if ACTIVE_IDS.has(iso) else "NEUTRAL","army":START_ARMY};growth_fraction[iso]=0.0
    if territories.size()!=23:push_error("Territory count must be exactly 23, got "+str(territories.size()));territories.clear()
func grow_armies()->void:
    if game_over:return
    for iso in territories.keys():
        var t:Dictionary=territories[iso];var base_rate:float=1.0 if str(t.owner)!="NEUTRAL" else 0.5;var rate:float=base_rate*time_scale;growth_fraction[iso]=float(growth_fraction.get(iso,0.0))+rate;var whole:int=int(floor(float(growth_fraction[iso])))
        if whole>0:t.army=float(t.army)+whole;growth_fraction[iso]=float(growth_fraction[iso])-whole
    queue_redraw()
func _reset_ai_timers()->void:
    ai_timers.clear()
    for owner in ACTIVE_IDS:
        if str(owner)!=player_country:ai_timers[str(owner)]=randf_range(5.0,15.0)
func _process(delta:float)->void:
    if game_over:return
    var sim_delta:float=delta*time_scale;anim_time+=sim_delta;_move_armies(sim_delta);_update_ai(sim_delta);_update_collision_flashes(sim_delta);queue_redraw()
func _update_ai(delta:float)->void:
    for owner in ACTIVE_IDS:
        var id:String=str(owner)
        if id==player_country or not ai_timers.has(id):continue
        ai_timers[id]=float(ai_timers[id])-delta
        if float(ai_timers[id])<=0.0:
            _ai_decide(id);ai_timers[id]=randf_range(5.0,15.0)
func _base_project(lon:float,lat:float)->Vector2:return Vector2((lon-LON_MIN)/(LON_MAX-LON_MIN)*size.x,(LAT_MAX-lat)/(LAT_MAX-LAT_MIN)*size.y)
func _project(lon:float,lat:float)->Vector2:
    var c:Vector2=size*0.5;return c+(_base_project(lon,lat)-c)*zoom+pan
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
func _polygon_area(poly:PackedVector2Array)->float:
    if poly.size()<3:return 0.0
    var total:float=0.0
    for i in range(poly.size()):var a:Vector2=poly[i];var b:Vector2=poly[(i+1)%poly.size()];total+=a.x*b.y-b.x*a.y
    return absf(total)*0.5
func _segment_distance_squared(p:Vector2,a:Vector2,b:Vector2)->float:
    var ab:Vector2=b-a;var denom:float=ab.length_squared()
    if denom<=0.0001:return p.distance_squared_to(a)
    var t:float=clampf((p-a).dot(ab)/denom,0.0,1.0);return p.distance_squared_to(a+ab*t)
func _edge_clearance_squared(p:Vector2,poly:PackedVector2Array)->float:
    var best:float=INF
    for i in range(poly.size()):best=minf(best,_segment_distance_squared(p,poly[i],poly[(i+1)%poly.size()]))
    return best
func _safe_anchor(poly:PackedVector2Array)->Vector2:
    if poly.size()<3:return Vector2.ZERO
    var bb:Rect2=_bounds(poly);var best:Vector2=poly[0];var best_clearance:float=-1.0;var search_rect:Rect2=bb
    for pass_index in range(4):
        var steps:int=16
        for gy in range(steps+1):
            for gx in range(steps+1):
                var p:Vector2=search_rect.position+Vector2(search_rect.size.x*float(gx)/float(steps),search_rect.size.y*float(gy)/float(steps))
                if not Geometry2D.is_point_in_polygon(p,poly):continue
                var clearance:float=_edge_clearance_squared(p,poly)
                if clearance>best_clearance:best_clearance=clearance;best=p
        var span:Vector2=search_rect.size/float(steps)*2.5;search_rect=Rect2(best-span*0.5,span)
    return best
func _scaled_poly(poly:PackedVector2Array,center:Vector2,scale:float)->PackedVector2Array:
    var out:=PackedVector2Array()
    for p in poly:out.append(center+(p-center)*scale)
    return out
func _owner_color(owner:String)->Color:
    var c:Dictionary={"RU":Color(0.10,0.42,0.96),"UA":Color(0.98,0.72,0.08),"PL":Color(0.94,0.16,0.36),"FR":Color(0.10,0.68,0.94),"DE":Color(0.62,0.24,0.88),"GB":Color(0.12,0.72,0.48),"CN":Color(0.94,0.18,0.10),"IN":Color(1.0,0.43,0.06),"IR":Color(0.06,0.55,0.25),"JP":Color(0.94,0.34,0.68)};return c.get(owner,Color(0.055,0.065,0.072))
func _draw_sea()->void:
    draw_rect(Rect2(Vector2.ZERO,size),Color(0.004,0.014,0.027));var center:=size*Vector2(0.57,0.47);var max_r:float=maxf(size.x,size.y)*0.86
    for i in range(12,0,-1):var f:float=float(i)/12.0;draw_circle(center,max_r*f,Color(0.025,0.105,0.155,0.012+(1.0-f)*0.012))
    var edge:float=34.0
    for i in range(8):var inset:float=float(i)*edge;draw_rect(Rect2(Vector2(inset,inset),size-Vector2(inset*2.0,inset*2.0)),Color(0,0,0,0.026-float(i)*0.0025),false,edge)
func _draw_territory(poly:PackedVector2Array,owner:String,iso:String)->void:
    var center:Vector2=_safe_anchor(poly)
    if owner=="BACKGROUND":draw_colored_polygon(poly,Color(0.018,0.023,0.028));draw_colored_polygon(_scaled_poly(poly,center,0.965),Color(0.030,0.036,0.041));return
    if owner=="NEUTRAL":draw_colored_polygon(poly,Color(0.025,0.030,0.036));draw_colored_polygon(_scaled_poly(poly,center,0.965),Color(0.041,0.048,0.055));return
    var c:Color=_owner_color(owner);var selected:bool=iso==drag_source;draw_colored_polygon(poly,c.darkened(0.52 if not selected else 0.43));draw_colored_polygon(_scaled_poly(poly,center,0.955),c.darkened(0.33 if not selected else 0.24));var core:Color=c.darkened(0.18 if not selected else 0.10);draw_colored_polygon(_scaled_poly(poly,center,0.78),Color(core.r,core.g,core.b,0.70));draw_colored_polygon(_scaled_poly(poly,center,0.58),Color(c.r,c.g,c.b,0.13))
func _draw_border(poly:PackedVector2Array,owner:String,iso:String)->void:
    var is_player:bool=owner==player_country;var selected:bool=iso==drag_source;var glow:Color;var core:Color;var gw:float;var cw:float
    if owner=="BACKGROUND":glow=Color(0.12,0.20,0.25,0.05);core=Color(0.20,0.27,0.31,0.34);gw=1.8;cw=0.7
    elif is_player:glow=Color(1.0,0.67,0.10,0.36 if not selected else 0.58);core=Color(1.0,0.84,0.30,0.96);gw=7.0 if selected else 5.0;cw=2.5 if selected else 1.8
    elif owner=="NEUTRAL":glow=Color(0.18,0.30,0.38,0.08);core=Color(0.27,0.36,0.42,0.48);gw=2.2;cw=0.8
    else:
        var c:Color=_owner_color(owner);glow=Color(c.r,c.g,c.b,0.16 if not selected else 0.30);core=Color(c.r*0.72+0.28,c.g*0.72+0.28,c.b*0.72+0.28,0.82);gw=4.0 if selected else 2.8;cw=1.5 if selected else 1.0
    for i in range(poly.size()):var a:Vector2=poly[i];var b:Vector2=poly[(i+1)%poly.size()];draw_line(a,b,glow,gw,true);draw_line(a,b,core,cw,true)
func _draw_marker(iso:String,center:Vector2)->void:
    if not territories.has(iso):return
    var t:Dictionary=territories[iso];var owner:String=str(t.owner);var c:Vector2=center;var count:String=str(int(float(t.army)))
    if owner=="NEUTRAL":draw_string_outline(ThemeDB.fallback_font,c+Vector2(-22,6),count,HORIZONTAL_ALIGNMENT_CENTER,44,15,3,Color(0,0,0,0.94));draw_string(ThemeDB.fallback_font,c+Vector2(-22,6),count,HORIZONTAL_ALIGNMENT_CENTER,44,15,Color(0.90,0.93,0.95));return
    var flag:String=str(FLAGS.get(owner,""));var show_name:bool=ACTIVE_IDS.has(iso) and zoom>=1.04;var w:float=116.0 if show_name else 88.0;var flag_y:float=-13.0 if show_name else -8.0;draw_string_outline(ThemeDB.fallback_font,c+Vector2(-w*0.5,flag_y),flag,HORIZONTAL_ALIGNMENT_CENTER,w,25,4,Color(0,0,0,0.92));draw_string(ThemeDB.fallback_font,c+Vector2(-w*0.5,flag_y),flag,HORIZONTAL_ALIGNMENT_CENTER,w,25,Color.WHITE)
    if show_name:
        var title:String=str(NAMES.get(iso,""));draw_string_outline(ThemeDB.fallback_font,c+Vector2(-w*0.5,10),title,HORIZONTAL_ALIGNMENT_CENTER,w,13,3,Color(0,0,0,0.96));draw_string(ThemeDB.fallback_font,c+Vector2(-w*0.5,10),title,HORIZONTAL_ALIGNMENT_CENTER,w,13,Color(0.94,0.97,1.0))
    var cy:float=30.0 if show_name else 19.0;draw_string_outline(ThemeDB.fallback_font,c+Vector2(-w*0.5,cy),count,HORIZONTAL_ALIGNMENT_CENTER,w,18,4,Color(0,0,0,0.96));draw_string(ThemeDB.fallback_font,c+Vector2(-w*0.5,cy),count,HORIZONTAL_ALIGNMENT_CENTER,w,18,Color.WHITE)
func _curve_points(a:Vector2,b:Vector2)->PackedVector2Array:
    var points:=PackedVector2Array();var d:Vector2=b-a;var side:Vector2=Vector2(-d.y,d.x).normalized();var control:Vector2=(a+b)*0.5+side*minf(42.0,d.length()*0.11)
    for i in range(21):var t:float=float(i)/20.0;points.append((1.0-t)*(1.0-t)*a+2.0*(1.0-t)*t*control+t*t*b)
    return points
func _draw_army(center:Vector2,amount:int,owner:String,direction:Vector2)->void:
    if amount<=0:return
    var n:int=amount if amount<=160 else mini(amount,240);var side:Vector2=Vector2(-direction.y,direction.x);var color:Color=_owner_color(owner)
    for i in range(n):
        var seed:float=float(i);var along:float=(fmod(seed*17.37,100.0)/100.0-0.5)*82.0;var across:float=(fmod(seed*31.91,100.0)/100.0-0.5)*28.0;var wave:float=sin(anim_time*3.0+seed*1.71)*2.2;var bob:float=cos(anim_time*2.4+seed*0.93)*1.6;var p:Vector2=center-direction*(along+bob)+side*(across+wave);draw_circle(p,4.0,Color(color.r,color.g,color.b,0.08));draw_circle(p,2.0,Color(color.r,color.g,color.b,0.94))
    draw_string_outline(ThemeDB.fallback_font,center+Vector2(-24,-31),str(amount),HORIZONTAL_ALIGNMENT_CENTER,48,13,3,Color(0,0,0,0.9));draw_string(ThemeDB.fallback_font,center+Vector2(-24,-31),str(amount),HORIZONTAL_ALIGNMENT_CENTER,48,13,Color.WHITE)
func _draw()->void:
    _draw_sea();hit_polygons.clear();feature_centers.clear();var best:Dictionary={}
    for feature in map_features:
        var iso:String=_feature_iso(feature.get("properties",{}));var is_playable:bool=PLAYABLE_IDS.has(iso);var owner:String="BACKGROUND" if BACKGROUND_IDS.has(iso) else str(territories[iso].owner) if territories.has(iso) else "BACKGROUND";var polys:Array=[]
        for ring in _rings(feature):
            var p:PackedVector2Array=_poly(ring)
            if p.size()<3:continue
            _draw_territory(p,owner,iso);_draw_border(p,owner,iso)
            if is_playable:
                var area:float=_polygon_area(p)
                if area>float(best.get(iso,0.0)):best[iso]=area;feature_centers[iso]=_safe_anchor(p)
                polys.append(p)
        if is_playable and not polys.is_empty():hit_polygons[iso]=polys
    for iso in feature_centers.keys():_draw_marker(str(iso),Vector2(feature_centers[iso]))
    if drag_source!="" and feature_centers.has(drag_source) and not camera_gesture:
        var finger:Vector2=mouse_pos
        if touches.size()==1:finger=Vector2(touches.values()[0])
        var source:Vector2=Vector2(feature_centers[drag_source]);var route:PackedVector2Array=_curve_points(source,finger);var route_color:Color=_owner_color(player_country);draw_polyline(route,Color(route_color.r,route_color.g,route_color.b,0.13),5.0,true);draw_polyline(route,Color(route_color.r*0.55+0.45,route_color.g*0.55+0.45,route_color.b*0.55+0.45,0.82),1.5,true)
    for a in armies:
        var pos:Vector2=a.pos;var target:String=str(a.target);var dir:=Vector2.RIGHT
        if feature_centers.has(target):dir=(Vector2(feature_centers[target])-pos).normalized()
        _draw_army(pos,int(float(a.amount)),str(a.owner),dir)
    for flash in collision_flashes:
        var alpha:float=clampf(float(flash.life)/0.35,0.0,1.0);draw_circle(Vector2(flash.pos),18.0*(1.0-alpha)+7.0,Color(1.0,0.82,0.45,alpha*0.65),false,2.0)
func _hit(pos:Vector2)->String:
    for iso in hit_polygons.keys():
        if not PLAYABLE_IDS.has(str(iso)):continue
        for p in hit_polygons[iso]:
            if Geometry2D.is_point_in_polygon(pos,p):return str(iso)
    return ""
func _player_source_at(pos:Vector2)->String:
    var iso:String=_hit(pos)
    if iso!="" and territories.has(iso) and str(territories[iso].owner)==player_country:return iso
    return ""
func _send_army(from_iso:String,to_iso:String,share:=0.5,ai:=false)->void:
    if game_over or not PLAYABLE_IDS.has(from_iso) or not PLAYABLE_IDS.has(to_iso) or from_iso==to_iso or not territories.has(from_iso) or not territories.has(to_iso):return
    var src:Dictionary=territories[from_iso]
    if str(src.owner)=="NEUTRAL" or (not ai and str(src.owner)!=player_country):return
    var amount:float=floor(float(src.army)*share)
    if amount<1.0 or not feature_centers.has(from_iso):return
    src.army=float(src.army)-amount;armies.append({"owner":str(src.owner),"amount":amount,"pos":Vector2(feature_centers[from_iso]),"target":to_iso})
func _send_amount(from_iso:String,to_iso:String,amount:float)->void:
    if not territories.has(from_iso):return
    var available:float=float(territories[from_iso].army);var send:float=minf(floor(amount),floor(maxf(0.0,available-AI_RESERVE)))
    if send<1.0:return
    _send_army(from_iso,to_iso,send/available,true)
func _move_armies(delta:float)->void:
    for i in range(armies.size()-1,-1,-1):
        if i>=armies.size():continue
        var a:Dictionary=armies[i];var target:String=str(a.target)
        if not PLAYABLE_IDS.has(target) or not feature_centers.has(target):armies.remove_at(i);continue
        var dest:Vector2=feature_centers[target];var pos:Vector2=a.pos
        if pos.distance_to(dest)<=ARMY_SPEED*delta:_arrive(i);continue
        a.pos=pos.move_toward(dest,ARMY_SPEED*delta)
    _resolve_collisions()
func _resolve_collisions()->void:
    var i:int=0
    while i<armies.size():
        var j:int=i+1
        while j<armies.size():
            if str(armies[i].owner)!=str(armies[j].owner) and Vector2(armies[i].pos).distance_to(Vector2(armies[j].pos))<=24.0:
                var collision_pos:Vector2=(Vector2(armies[i].pos)+Vector2(armies[j].pos))*0.5;var loss:float=minf(float(armies[i].amount),float(armies[j].amount));collision_flashes.append({"pos":collision_pos,"life":0.35});armies[i].amount=float(armies[i].amount)-loss;armies[j].amount=float(armies[j].amount)-loss
                if float(armies[j].amount)<=0:armies.remove_at(j);continue
                if float(armies[i].amount)<=0:armies.remove_at(i);i-=1;break
            j+=1
        i+=1
func _update_collision_flashes(delta:float)->void:
    for i in range(collision_flashes.size()-1,-1,-1):
        collision_flashes[i].life=float(collision_flashes[i].life)-delta
        if float(collision_flashes[i].life)<=0.0:collision_flashes.remove_at(i)
func _arrive(index:int)->void:
    if index<0 or index>=armies.size():return
    var a:Dictionary=armies[index];armies.remove_at(index);var target:String=str(a.target)
    if not PLAYABLE_IDS.has(target) or not territories.has(target):return
    var t:Dictionary=territories[target]
    if str(t.owner)==str(a.owner):t.army=float(t.army)+float(a.amount);return
    var attackers:float=float(a.amount);var defenders:float=float(t.army)
    if attackers>defenders:t.owner=str(a.owner);t.army=attackers-defenders
    else:t.army=defenders-attackers
    _check_end_state()
func _check_end_state()->void:
    if not game_started or game_over:return
    var player_alive:bool=false;var rival_alive:bool=false
    for iso in territories.keys():
        var owner:String=str(territories[iso].owner)
        if owner==player_country:player_alive=true
        elif owner!="NEUTRAL" and ACTIVE_IDS.has(owner):rival_alive=true
    if not player_alive:game_over=true;armies.clear();_show_end_overlay("ВЫ ПРОИГРАЛИ","Все территории вашей державы захвачены")
    elif not rival_alive:game_over=true;armies.clear();_show_end_overlay("ВЫ ПОБЕДИЛИ","Все державы-соперники уничтожены")
func _show_end_overlay(title_text:String,subtitle_text:String)->void:
    var shade:=ColorRect.new();shade.color=Color(0.01,0.02,0.04,0.82);shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);shade.mouse_filter=Control.MOUSE_FILTER_STOP;add_child(shade)
    var center:=CenterContainer.new();center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);shade.add_child(center)
    var box:=VBoxContainer.new();box.custom_minimum_size=Vector2(520,250);box.alignment=BoxContainer.ALIGNMENT_CENTER;center.add_child(box)
    var title:=Label.new();title.text=title_text;title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;title.add_theme_font_size_override("font_size",42);box.add_child(title)
    var sub:=Label.new();sub.text=subtitle_text;sub.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;sub.add_theme_font_size_override("font_size",18);box.add_child(sub)
    var button:=Button.new();button.text="НАЧАТЬ ЗАНОВО";button.custom_minimum_size=Vector2(320,60);button.add_theme_font_size_override("font_size",20);button.pressed.connect(_restart);box.add_child(button)
func _restart()->void:get_tree().reload_current_scene()
func _projected_at(owner:String,target_iso:String)->float:
    var total:float=0.0
    for a in armies:
        if str(a.owner)==owner and str(a.target)==target_iso:total+=float(a.amount)
    return total
func _ai_decide(owner:String)->void:
    var owned:Array=[];var targets:Array=[]
    for iso in territories.keys():
        var id:String=str(iso);var t:Dictionary=territories[iso]
        if str(t.owner)==owner:owned.append(id)
        else:targets.append(id)
    if owned.is_empty() or targets.is_empty():return
    var best_target:String="";var best_score:float=INF
    for target_id in targets:
        if not feature_centers.has(target_id):continue
        var target:Dictionary=territories[target_id];var nearest:float=INF
        for source_id in owned:
            if feature_centers.has(source_id):nearest=minf(nearest,Vector2(feature_centers[source_id]).distance_to(Vector2(feature_centers[target_id])))
        var neutral_factor:float=0.78 if str(target.owner)=="NEUTRAL" else 1.0;var score:float=(float(target.army)+18.0)*neutral_factor+nearest*0.075
        if score<best_score:best_score=score;best_target=str(target_id)
    if best_target=="":return
    var rally:String="";var rally_dist:float=INF
    for source_id in owned:
        if not feature_centers.has(source_id):continue
        var d:float=Vector2(feature_centers[source_id]).distance_to(Vector2(feature_centers[best_target]))
        if d<rally_dist:rally_dist=d;rally=str(source_id)
    if rally=="":return
    var target_army:float=float(territories[best_target].army);var projected:float=float(territories[rally].army)+_projected_at(owner,rally);var required:float=target_army*1.12+8.0
    if projected>=required and float(territories[rally].army)>target_army+8.0:
        var attack_share:float=clampf((target_army+maxf(12.0,target_army*0.22))/float(territories[rally].army),0.52,0.82);_send_army(rally,best_target,attack_share,true);return
    var need:float=maxf(0.0,required-projected);var donors:Array=[]
    for source_id in owned:
        if str(source_id)==rally:continue
        var available:float=maxf(0.0,float(territories[str(source_id)].army)-AI_RESERVE)
        if available>4.0:donors.append({"id":str(source_id),"available":available})
    donors.sort_custom(func(a,b):return float(a.available)>float(b.available))
    for donor in donors:
        if need<=0.0:break
        var send:float=minf(float(donor.available),need);_send_amount(str(donor.id),rally,send);need-=send
func _touch_pair()->Array:
    var vals:Array=touches.values()
    if vals.size()!=2:return []
    return [Vector2(vals[0]),Vector2(vals[1])]
func _begin_camera_gesture()->void:
    var pair:Array=_touch_pair()
    if pair.size()!=2:return
    camera_gesture=true;suppress_single_touch=true;drag_source="";var a:Vector2=pair[0];var b:Vector2=pair[1];pinch_distance=a.distance_to(b);pinch_midpoint=(a+b)*0.5
func _clamp_pan(value:Vector2,current_zoom:float)->Vector2:
    if current_zoom<=1.001:return Vector2.ZERO
    var half_extra:Vector2=size*(current_zoom-1.0)*0.5;var limit_x:float=maxf(0.0,half_extra.x-48.0);var limit_y:float=maxf(0.0,half_extra.y-48.0);return Vector2(clampf(value.x,-limit_x,limit_x),clampf(value.y,-limit_y,limit_y))
func _update_camera_gesture()->void:
    var pair:Array=_touch_pair()
    if pair.size()!=2:return
    var a:Vector2=pair[0];var b:Vector2=pair[1];var midpoint:Vector2=(a+b)*0.5;var distance:float=a.distance_to(b)
    if pinch_distance<=0.0:pinch_distance=distance;pinch_midpoint=midpoint;return
    var old_zoom:float=zoom;var new_zoom:float=clampf(old_zoom*distance/pinch_distance,1.0,2.8);var new_pan:Vector2=pan+(midpoint-pinch_midpoint)
    if old_zoom>0.0 and not is_equal_approx(new_zoom,old_zoom):var focus:Vector2=pinch_midpoint-size*0.5-pan;new_pan-=focus*(new_zoom/old_zoom-1.0)
    zoom=new_zoom
    if zoom<=1.001:zoom=1.0;pan=Vector2.ZERO
    else:pan=_clamp_pan(new_pan,zoom)
    pinch_distance=distance;pinch_midpoint=midpoint;queue_redraw()
func _gui_input(event:InputEvent)->void:
    if game_over:return
    if event is InputEventScreenTouch:
        if event.pressed:
            if touches.is_empty():suppress_single_touch=false
            touches[event.index]=event.position;mouse_pos=event.position
            if touches.size()==1 and not suppress_single_touch:drag_source=_player_source_at(event.position)
            elif touches.size()==2:_begin_camera_gesture()
            elif touches.size()>2:camera_gesture=false;suppress_single_touch=true;drag_source=""
        else:
            var was_camera:bool=camera_gesture or suppress_single_touch;var release_pos:Vector2=event.position
            if touches.has(event.index):touches.erase(event.index)
            if not was_camera and touches.is_empty() and drag_source!="":_send_army(drag_source,_hit(release_pos))
            if touches.size()<2:camera_gesture=false;pinch_distance=0.0;pinch_midpoint=Vector2.ZERO;drag_source=""
            if touches.is_empty():suppress_single_touch=false
    elif event is InputEventScreenDrag:
        if touches.has(event.index):touches[event.index]=event.position
        mouse_pos=event.position
        if touches.size()==2 and camera_gesture:_update_camera_gesture()
    elif event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
        mouse_pos=event.position
        if event.pressed:mouse_down=true;drag_source=_player_source_at(event.position)
        else:
            if mouse_down and drag_source!="":_send_army(drag_source,_hit(event.position))
            mouse_down=false;drag_source=""
    elif event is InputEventMouseMotion and mouse_down:mouse_pos=event.position;queue_redraw()
