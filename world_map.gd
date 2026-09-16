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
var mouse_down := false
var mouse_pos := Vector2.ZERO
var pinch_distance := 0.0
var ai_clock := 0.0
var anim_time := 0.0
var game_over := false
var game_started := false

func setup(_data:Dictionary, selected:String) -> void:
    player_country = selected
    _load_geojson()
    _ensure_territories()
    game_started = true
    queue_redraw()

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_STOP

func _feature_iso(props:Dictionary) -> String:
    var iso:String = str(props.get("ISO_A2",""))
    if iso == "" or iso == "-99": iso = str(props.get("ISO_A2_EH",""))
    if iso == "" or iso == "-99":
        var a3:String = str(props.get("ADM0_A3",""))
        var m:Dictionary = {"FRA":"FR","RUS":"RU","UKR":"UA","POL":"PL","DEU":"DE","GBR":"GB","CHN":"CN","IND":"IN","IRN":"IR","JPN":"JP","KAZ":"KZ","SAU":"SA","IDN":"ID","MNG":"MN","PAK":"PK","TUR":"TR","MMR":"MM","AFG":"AF","YEM":"YE","THA":"TH","ESP":"ES","TKM":"TM","SWE":"SE","UZB":"UZ","IRQ":"IQ","NOR":"NO","FIN":"FI","VNM":"VN","MYS":"MY","OMN":"OM"}
        iso = str(m.get(a3,a3))
    return iso

func _load_geojson() -> void:
    if not map_features.is_empty() or not FileAccess.file_exists(GEOJSON_PATH): return
    var f:FileAccess = FileAccess.open(GEOJSON_PATH,FileAccess.READ)
    if f == null: return
    var parsed:Variant = JSON.parse_string(f.get_as_text())
    if typeof(parsed) != TYPE_DICTIONARY: return
    for feature in parsed.get("features",[]):
        if PLAYABLE_IDS.has(_feature_iso(feature.get("properties",{}))): map_features.append(feature)

func _ensure_territories() -> void:
    for feature in map_features:
        var iso:String = _feature_iso(feature.get("properties",{}))
        if iso == "" or territories.has(iso): continue
        territories[iso] = {"owner":iso if ACTIVE_IDS.has(iso) else "NEUTRAL","army":START_ARMY}
        growth_fraction[iso] = 0.0

func grow_armies() -> void:
    if game_over: return
    for iso in territories.keys():
        var t:Dictionary = territories[iso]
        var rate:float = 1.0 if str(t.owner) != "NEUTRAL" else 0.5
        growth_fraction[iso] = float(growth_fraction.get(iso,0.0)) + rate
        var whole:int = int(floor(float(growth_fraction[iso])))
        if whole > 0:
            t.army = float(t.army) + whole
            growth_fraction[iso] = float(growth_fraction[iso]) - whole
    queue_redraw()

func _process(delta:float) -> void:
    if game_over: return
    anim_time += delta
    _move_armies(delta)
    ai_clock += delta
    if ai_clock >= 4.0:
        ai_clock = 0.0
        _ai_attack()
    queue_redraw()

func _base_project(lon:float,lat:float) -> Vector2:
    return Vector2((lon-LON_MIN)/(LON_MAX-LON_MIN)*size.x,(LAT_MAX-lat)/(LAT_MAX-LAT_MIN)*size.y)

func _project(lon:float,lat:float) -> Vector2:
    var c:Vector2 = size*0.5
    return c+(_base_project(lon,lat)-c)*zoom+pan

func _rings(feature:Dictionary) -> Array:
    var g:Dictionary = feature.get("geometry",{})
    var coords:Array = g.get("coordinates",[])
    var out:Array = []
    if str(g.get("type","")) == "Polygon" and not coords.is_empty(): out.append(coords[0])
    elif str(g.get("type","")) == "MultiPolygon":
        for p in coords:
            if not p.is_empty(): out.append(p[0])
    return out

func _poly(ring:Array) -> PackedVector2Array:
    var out:=PackedVector2Array()
    for q in ring:
        if q.size() >= 2: out.append(_project(float(q[0]),float(q[1])))
    return out

func _bounds(poly:PackedVector2Array) -> Rect2:
    var a:=Vector2(INF,INF)
    var b:=Vector2(-INF,-INF)
    for p in poly:
        a.x=minf(a.x,p.x); a.y=minf(a.y,p.y); b.x=maxf(b.x,p.x); b.y=maxf(b.y,p.y)
    return Rect2(a,b-a)

func _scaled_poly(poly:PackedVector2Array, center:Vector2, scale:float) -> PackedVector2Array:
    var out:=PackedVector2Array()
    for p in poly: out.append(center+(p-center)*scale)
    return out

func _owner_color(owner:String) -> Color:
    var c:Dictionary={"RU":Color(0.10,0.42,0.96),"UA":Color(0.98,0.72,0.08),"PL":Color(0.94,0.16,0.36),"FR":Color(0.10,0.68,0.94),"DE":Color(0.62,0.24,0.88),"GB":Color(0.12,0.72,0.48),"CN":Color(0.94,0.18,0.10),"IN":Color(1.0,0.43,0.06),"IR":Color(0.06,0.55,0.25),"JP":Color(0.94,0.34,0.68)}
    return c.get(owner,Color(0.055,0.065,0.072))

func _draw_sea() -> void:
    var base:=Color(0.004,0.014,0.027)
    draw_rect(Rect2(Vector2.ZERO,size),base)
    var center:=size*Vector2(0.57,0.47)
    var max_r:float=maxf(size.x,size.y)*0.86
    for i in range(12,0,-1):
        var f:float=float(i)/12.0
        var radius:float=max_r*f
        var alpha:float=0.012+(1.0-f)*0.012
        draw_circle(center,radius,Color(0.025,0.105,0.155,alpha))
    var edge:float=34.0
    for i in range(8):
        var inset:float=float(i)*edge
        var a:float=0.026-float(i)*0.0025
        draw_rect(Rect2(Vector2(inset,inset),size-Vector2(inset*2.0,inset*2.0)),Color(0.0,0.0,0.0,a),false,edge)
    var dot_spacing:float=64.0
    var y:float=32.0
    while y<size.y:
        var x:float=32.0
        while x<size.x:
            draw_circle(Vector2(x,y),0.7,Color(0.28,0.50,0.62,0.035))
            x+=dot_spacing
        y+=dot_spacing

func _draw_territory(poly:PackedVector2Array,owner:String,iso:String) -> void:
    var bb:Rect2=_bounds(poly)
    var center:Vector2=bb.get_center()
    if owner=="NEUTRAL":
        draw_colored_polygon(poly,Color(0.025,0.030,0.036))
        var neutral_inner:PackedVector2Array=_scaled_poly(poly,center,0.965)
        draw_colored_polygon(neutral_inner,Color(0.041,0.048,0.055))
        return
    var c:Color=_owner_color(owner)
    var selected:bool=iso==drag_source
    var base:Color=c.darkened(0.52 if not selected else 0.43)
    var middle:Color=c.darkened(0.33 if not selected else 0.24)
    var core:Color=c.darkened(0.18 if not selected else 0.10)
    draw_colored_polygon(poly,base)
    var mid_poly:PackedVector2Array=_scaled_poly(poly,center,0.955)
    draw_colored_polygon(mid_poly,middle)
    var core_poly:PackedVector2Array=_scaled_poly(poly,center,0.78)
    draw_colored_polygon(core_poly,Color(core.r,core.g,core.b,0.70))
    var light_poly:PackedVector2Array=_scaled_poly(poly,center,0.58)
    draw_colored_polygon(light_poly,Color(c.r,c.g,c.b,0.13))

func _draw_border(poly:PackedVector2Array,owner:String,iso:String) -> void:
    var is_player:bool=owner==player_country
    var selected:bool=iso==drag_source
    var glow:Color
    var core:Color
    var gw:float
    var cw:float
    if is_player:
        glow=Color(1.0,0.67,0.10,0.36 if not selected else 0.58)
        core=Color(1.0,0.84,0.30,0.96)
        gw=7.0 if selected else 5.0
        cw=2.5 if selected else 1.8
    elif owner=="NEUTRAL":
        glow=Color(0.18,0.30,0.38,0.08)
        core=Color(0.27,0.36,0.42,0.48)
        gw=2.2;cw=0.8
    else:
        var c:Color=_owner_color(owner)
        glow=Color(c.r,c.g,c.b,0.16 if not selected else 0.30)
        core=Color(c.r*0.72+0.28,c.g*0.72+0.28,c.b*0.72+0.28,0.82)
        gw=4.0 if selected else 2.8
        cw=1.5 if selected else 1.0
    for i in range(poly.size()):
        var a:Vector2=poly[i]
        var b:Vector2=poly[(i+1)%poly.size()]
        draw_line(a,b,glow,gw,true)
        draw_line(a,b,core,cw,true)

func _marker_offset(iso:String) -> Vector2:
    var o:Dictionary={"GB":Vector2(-10,-12),"FR":Vector2(-12,19),"DE":Vector2(8,-18),"PL":Vector2(19,9),"UA":Vector2(20,10),"JP":Vector2(20,0),"IR":Vector2(0,12),"IN":Vector2(0,12),"ID":Vector2(8,7),"MY":Vector2(12,-6)}
    return o.get(iso,Vector2.ZERO)

func _badge_box(bg:Color,border:Color,radius:int) -> StyleBoxFlat:
    var box:=StyleBoxFlat.new()
    box.bg_color=bg;box.border_color=border;box.set_border_width_all(1)
    box.corner_radius_top_left=radius;box.corner_radius_top_right=radius;box.corner_radius_bottom_left=radius;box.corner_radius_bottom_right=radius
    return box

func _draw_badge(center:Vector2,w:float,h:float,border:=Color(0.34,0.55,0.66,0.42)) -> void:
    var rect:=Rect2(center-Vector2(w*0.5,h*0.5),Vector2(w,h))
    draw_style_box(_badge_box(Color(0.003,0.012,0.022,0.86),border,9),rect)

func _draw_marker(iso:String,center:Vector2) -> void:
    var t:Dictionary=territories[iso]
    var owner:String=str(t.owner)
    var original_active:bool=ACTIVE_IDS.has(iso)
    var c:Vector2=center+_marker_offset(iso)
    var count:String=str(int(float(t.army)))
    if owner=="NEUTRAL":
        _draw_badge(c,44.0,25.0,Color(0.30,0.39,0.45,0.54))
        draw_string(ThemeDB.fallback_font,c+Vector2(-22,6),count,HORIZONTAL_ALIGNMENT_CENTER,44,15,Color(0.93,0.95,0.97))
        return
    var flag:String=str(FLAGS.get(owner,""))
    var show_name:bool=original_active and zoom>=1.04
    var compact:bool=zoom<0.90
    var w:float=74.0 if compact else (116.0 if show_name else 88.0)
    var h:float=39.0 if compact else (68.0 if show_name else 49.0)
    var border:Color=Color(1.0,0.76,0.22,0.64) if owner==player_country else Color(0.42,0.66,0.78,0.38)
    _draw_badge(c,w,h,border)
    var flag_y:float=-6.0 if compact else (-17.0 if show_name else -10.0)
    var flag_size:int=21 if compact else 24
    draw_string_outline(ThemeDB.fallback_font,c+Vector2(-w*0.5,flag_y),flag,HORIZONTAL_ALIGNMENT_CENTER,w,flag_size,3,Color(0,0,0,0.88))
    draw_string(ThemeDB.fallback_font,c+Vector2(-w*0.5,flag_y),flag,HORIZONTAL_ALIGNMENT_CENTER,w,flag_size,Color.WHITE)
    if show_name:
        var title:String=str(NAMES.get(iso,""))
        draw_string_outline(ThemeDB.fallback_font,c+Vector2(-w*0.5,8),title,HORIZONTAL_ALIGNMENT_CENTER,w,13,3,Color(0,0,0,0.92))
        draw_string(ThemeDB.fallback_font,c+Vector2(-w*0.5,8),title,HORIZONTAL_ALIGNMENT_CENTER,w,13,Color(0.92,0.95,0.98))
    var cy:float=14.0 if compact else (27.0 if show_name else 18.0)
    draw_string_outline(ThemeDB.fallback_font,c+Vector2(-w*0.5,cy),count,HORIZONTAL_ALIGNMENT_CENTER,w,18,3,Color(0,0,0,0.95))
    draw_string(ThemeDB.fallback_font,c+Vector2(-w*0.5,cy),count,HORIZONTAL_ALIGNMENT_CENTER,w,18,Color.WHITE)

func _curve_points(a:Vector2,b:Vector2) -> PackedVector2Array:
    var points:=PackedVector2Array()
    var d:Vector2=b-a
    var side:Vector2=Vector2(-d.y,d.x).normalized()
    var control:Vector2=(a+b)*0.5+side*minf(42.0,d.length()*0.11)
    for i in range(21):
        var t:float=float(i)/20.0
        points.append((1.0-t)*(1.0-t)*a+2.0*(1.0-t)*t*control+t*t*b)
    return points

func _draw_army(center:Vector2,amount:int,owner:String,direction:Vector2) -> void:
    if amount<=0:return
    var n:int=mini(amount,120)
    var side:Vector2=Vector2(-direction.y,direction.x)
    var color:Color=_owner_color(owner)
    for i in range(n):
        var seed:float=float(i)
        var along:float=(fmod(seed*17.37,100.0)/100.0-0.5)*78.0
        var across:float=(fmod(seed*31.91,100.0)/100.0-0.5)*25.0
        var p:Vector2=center-direction*along+side*across
        draw_circle(p,4.2,Color(color.r,color.g,color.b,0.09))
        draw_circle(p,2.15,Color(color.r,color.g,color.b,0.94))
    _draw_badge(center+Vector2(0,-34),42,23,Color(color.r,color.g,color.b,0.48))
    draw_string(ThemeDB.fallback_font,center+Vector2(-21,-29),str(amount),HORIZONTAL_ALIGNMENT_CENTER,42,13,Color.WHITE)

func _draw() -> void:
    _draw_sea()
    hit_polygons.clear();feature_centers.clear()
    var best:Dictionary={}
    for feature in map_features:
        var iso:String=_feature_iso(feature.get("properties",{}))
        if not territories.has(iso):continue
        var polys:Array=[]
        for ring in _rings(feature):
            var p:PackedVector2Array=_poly(ring)
            if p.size()<3:continue
            var owner:String=str(territories[iso].owner)
            _draw_territory(p,owner,iso)
            _draw_border(p,owner,iso)
            var bb:Rect2=_bounds(p)
            var area:float=bb.size.x*bb.size.y
            if area>float(best.get(iso,0.0)):
                best[iso]=area;feature_centers[iso]=bb.get_center()
            polys.append(p)
        if not polys.is_empty():hit_polygons[iso]=polys
    for iso in feature_centers.keys():_draw_marker(str(iso),Vector2(feature_centers[iso]))
    if drag_source!="" and feature_centers.has(drag_source):
        var finger:Vector2=mouse_pos
        if touches.size()==1:finger=Vector2(touches.values()[0])
        var source:Vector2=Vector2(feature_centers[drag_source])
        var route:PackedVector2Array=_curve_points(source,finger)
        var route_color:Color=_owner_color(player_country)
        draw_polyline(route,Color(route_color.r,route_color.g,route_color.b,0.13),5.0,true)
        draw_polyline(route,Color(route_color.r*0.55+0.45,route_color.g*0.55+0.45,route_color.b*0.55+0.45,0.82),1.5,true)
        var hover:String=_hit(finger)
        if hover!="" and feature_centers.has(hover):
            draw_circle(Vector2(feature_centers[hover]),16.0,Color(0.78,0.92,1.0,0.52),false,1.5)
    for a in armies:
        var pos:Vector2=a.pos
        var target:String=str(a.target)
        var dir:=Vector2.RIGHT
        if feature_centers.has(target):dir=(Vector2(feature_centers[target])-pos).normalized()
        _draw_army(pos,int(float(a.amount)),str(a.owner),dir)

func _hit(pos:Vector2) -> String:
    for iso in hit_polygons.keys():
        for p in hit_polygons[iso]:
            if Geometry2D.is_point_in_polygon(pos,p):return str(iso)
    return ""

func _send_army(from_iso:String,to_iso:String,share:=0.5,ai:=false) -> void:
    if game_over or from_iso=="" or to_iso=="" or from_iso==to_iso or not territories.has(from_iso) or not territories.has(to_iso):return
    var src:Dictionary=territories[from_iso]
    if str(src.owner)=="NEUTRAL" or (not ai and str(src.owner)!=player_country):return
    var amount:float=floor(float(src.army)*share)
    if amount<1.0 or not feature_centers.has(from_iso):return
    src.army=float(src.army)-amount
    armies.append({"owner":str(src.owner),"amount":amount,"pos":Vector2(feature_centers[from_iso]),"target":to_iso})

func _move_armies(delta:float) -> void:
    for i in range(armies.size()-1,-1,-1):
        if i>=armies.size():continue
        var a:Dictionary=armies[i]
        var target:String=str(a.target)
        if not feature_centers.has(target):continue
        var dest:Vector2=feature_centers[target]
        var pos:Vector2=a.pos
        if pos.distance_to(dest)<=ARMY_SPEED*delta:_arrive(i);continue
        a.pos=pos.move_toward(dest,ARMY_SPEED*delta)
    _resolve_collisions()

func _resolve_collisions() -> void:
    var i:int=0
    while i<armies.size():
        var j:int=i+1
        while j<armies.size():
            if str(armies[i].owner)!=str(armies[j].owner) and Vector2(armies[i].pos).distance_to(Vector2(armies[j].pos))<=24.0:
                var loss:float=minf(float(armies[i].amount),float(armies[j].amount))
                armies[i].amount=float(armies[i].amount)-loss;armies[j].amount=float(armies[j].amount)-loss
                if float(armies[j].amount)<=0:armies.remove_at(j);continue
                if float(armies[i].amount)<=0:armies.remove_at(i);i-=1;break
            j+=1
        i+=1

func _arrive(index:int) -> void:
    if index<0 or index>=armies.size():return
    var a:Dictionary=armies[index];armies.remove_at(index)
    var target:String=str(a.target)
    if not territories.has(target):return
    var t:Dictionary=territories[target]
    if str(t.owner)==str(a.owner):t.army=float(t.army)+float(a.amount);return
    var attackers:float=float(a.amount)
    var defenders:float=float(t.army)
    if attackers>defenders:t.owner=str(a.owner);t.army=attackers-defenders
    else:t.army=defenders-attackers
    _check_player_defeat()

func _check_player_defeat() -> void:
    if not game_started or game_over:return
    for iso in territories.keys():
        if str(territories[iso].owner)==player_country:return
    game_over=true;armies.clear();_show_defeat()

func _show_defeat() -> void:
    var shade:=ColorRect.new();shade.color=Color(0.01,0.02,0.04,0.82);shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);shade.mouse_filter=Control.MOUSE_FILTER_STOP;add_child(shade)
    var center:=CenterContainer.new();center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);shade.add_child(center)
    var box:=VBoxContainer.new();box.custom_minimum_size=Vector2(520,250);box.alignment=BoxContainer.ALIGNMENT_CENTER;center.add_child(box)
    var title:=Label.new();title.text="ВЫ ПРОИГРАЛИ";title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;title.add_theme_font_size_override("font_size",42);box.add_child(title)
    var sub:=Label.new();sub.text="Все территории вашей державы захвачены";sub.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;sub.add_theme_font_size_override("font_size",18);box.add_child(sub)
    var button:=Button.new();button.text="НАЧАТЬ ЗАНОВО";button.custom_minimum_size=Vector2(320,60);button.add_theme_font_size_override("font_size",20);button.pressed.connect(_restart);box.add_child(button)

func _restart() -> void:get_tree().reload_current_scene()

func _ai_attack() -> void:
    var sources:Array=[]
    for iso in territories.keys():
        var t:Dictionary=territories[iso]
        if str(t.owner)!="NEUTRAL" and str(t.owner)!=player_country and float(t.army)>=24.0:sources.append(str(iso))
    if sources.is_empty():return
    var source:String=str(sources[randi()%sources.size()])
    if not feature_centers.has(source):return
    var src:Dictionary=territories[source]
    var owner:String=str(src.owner)
    var candidates:Array=[]
    for iso in territories.keys():
        if str(iso)==source or not feature_centers.has(iso):continue
        var target:Dictionary=territories[iso]
        if str(target.owner)==owner:continue
        var dist:float=Vector2(feature_centers[source]).distance_to(Vector2(feature_centers[iso]))
        var neutral_bonus:float=0.65 if str(target.owner)=="NEUTRAL" else 1.0
        var score:float=(float(target.army)+20.0)*neutral_bonus+dist*0.09
        candidates.append({"iso":str(iso),"score":score})
    if candidates.is_empty():return
    candidates.sort_custom(func(a,b):return float(a.score)<float(b.score))
    var target_iso:String=str(candidates[0].iso)
    var target:Dictionary=territories[target_iso]
    if float(src.army)>float(target.army)*1.12+8.0:_send_army(source,target_iso,0.62,true)

func _gui_input(event:InputEvent) -> void:
    if game_over:return
    if event is InputEventScreenTouch:
        if event.pressed:
            touches[event.index]=event.position
            if touches.size()==1:drag_source=_hit(event.position);mouse_pos=event.position
            elif touches.size()==2:
                var vals:Array=touches.values();pinch_distance=Vector2(vals[0]).distance_to(Vector2(vals[1]));drag_source=""
        else:
            if touches.has(event.index):
                var release_pos:Vector2=event.position
                if touches.size()==1 and drag_source!="":_send_army(drag_source,_hit(release_pos))
                touches.erase(event.index)
                if touches.is_empty():drag_source=""
    elif event is InputEventScreenDrag:
        touches[event.index]=event.position;mouse_pos=event.position
        if touches.size()==2:
            var vals:Array=touches.values()
            var d:float=Vector2(vals[0]).distance_to(Vector2(vals[1]))
            if pinch_distance>0.0:zoom=clampf(zoom*d/pinch_distance,0.75,2.8)
            pinch_distance=d
    elif event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
        mouse_pos=event.position
        if event.pressed:mouse_down=true;drag_source=_hit(event.position)
        else:
            if mouse_down and drag_source!="":_send_army(drag_source,_hit(event.position))
            mouse_down=false;drag_source=""
    elif event is InputEventMouseMotion and mouse_down:
        mouse_pos=event.position;queue_redraw()
