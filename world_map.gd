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
    var iso := str(props.get("ISO_A2",""))
    if iso == "" or iso == "-99": iso = str(props.get("ISO_A2_EH",""))
    if iso == "" or iso == "-99":
        var a3 := str(props.get("ADM0_A3",""))
        var m := {"FRA":"FR","RUS":"RU","UKR":"UA","POL":"PL","DEU":"DE","GBR":"GB","CHN":"CN","IND":"IN","IRN":"IR","JPN":"JP","KAZ":"KZ","SAU":"SA","IDN":"ID","MNG":"MN","PAK":"PK","TUR":"TR","MMR":"MM","AFG":"AF","YEM":"YE","THA":"TH","ESP":"ES","TKM":"TM","SWE":"SE","UZB":"UZ","IRQ":"IQ","NOR":"NO","FIN":"FI","VNM":"VN","MYS":"MY","OMN":"OM"}
        iso = str(m.get(a3,a3))
    return iso

func _load_geojson() -> void:
    if not map_features.is_empty() or not FileAccess.file_exists(GEOJSON_PATH): return
    var f := FileAccess.open(GEOJSON_PATH,FileAccess.READ)
    if f == null: return
    var parsed = JSON.parse_string(f.get_as_text())
    if typeof(parsed) != TYPE_DICTIONARY: return
    for feature in parsed.get("features",[]):
        if PLAYABLE_IDS.has(_feature_iso(feature.get("properties",{}))): map_features.append(feature)

func _ensure_territories() -> void:
    for feature in map_features:
        var iso := _feature_iso(feature.get("properties",{}))
        if iso == "" or territories.has(iso): continue
        territories[iso] = {"owner":iso if ACTIVE_IDS.has(iso) else "NEUTRAL","army":START_ARMY}
        growth_fraction[iso] = 0.0

func grow_armies() -> void:
    if game_over: return
    for iso in territories.keys():
        var t:Dictionary = territories[iso]
        var rate := 1.0 if str(t.owner) != "NEUTRAL" else 0.5
        growth_fraction[iso] = float(growth_fraction.get(iso,0.0)) + rate
        var whole := int(floor(float(growth_fraction[iso])))
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
    var c := size*0.5
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
    var out := PackedVector2Array()
    for q in ring:
        if q.size() >= 2: out.append(_project(float(q[0]),float(q[1])))
    return out

func _bounds(poly:PackedVector2Array) -> Rect2:
    var a := Vector2(INF,INF)
    var b := Vector2(-INF,-INF)
    for p in poly:
        a.x=minf(a.x,p.x); a.y=minf(a.y,p.y); b.x=maxf(b.x,p.x); b.y=maxf(b.y,p.y)
    return Rect2(a,b-a)

func _owner_color(owner:String) -> Color:
    var c := {"RU":Color(0.10,0.42,0.96),"UA":Color(0.98,0.72,0.08),"PL":Color(0.94,0.16,0.36),"FR":Color(0.10,0.68,0.94),"DE":Color(0.62,0.24,0.88),"GB":Color(0.12,0.72,0.48),"CN":Color(0.94,0.18,0.10),"IN":Color(1.0,0.43,0.06),"IR":Color(0.06,0.55,0.25),"JP":Color(0.94,0.34,0.68)}
    return c.get(owner,Color(0.055,0.065,0.072))

func _territory_color(owner:String) -> Color:
    if owner == "NEUTRAL": return Color(0.045,0.052,0.058)
    return _owner_color(owner).darkened(0.24)

func _draw_sea() -> void:
    draw_rect(Rect2(Vector2.ZERO,size),Color(0.008,0.027,0.050))
    var pulse := 0.5 + 0.5*sin(anim_time*0.22)
    draw_circle(size*Vector2(0.72,0.22),size.x*0.62,Color(0.015,0.085,0.13,0.18+0.03*pulse))
    draw_circle(size*Vector2(0.18,0.82),size.x*0.50,Color(0.015,0.060,0.10,0.18))
    var spacing := 72.0
    var shift := fmod(anim_time*2.0,spacing)
    var x := -spacing+shift
    while x < size.x+spacing:
        draw_line(Vector2(x,0),Vector2(x+size.y,size.y),Color(0.18,0.42,0.58,0.025),1.0)
        x += spacing

func _draw_border(poly:PackedVector2Array, owner:String) -> void:
    var player := owner == player_country
    var pulse := 0.5+0.5*sin(anim_time*2.4)
    var glow := Color(1.0,0.72,0.16,0.16+0.18*pulse) if player else Color(0.28,0.72,0.92,0.09)
    var core := Color(1.0,0.82,0.30,0.92) if player else Color(0.55,0.72,0.82,0.62)
    var glow_width := 6.0+2.0*pulse if player else 3.0
    var core_width := 2.2+0.5*pulse if player else 1.0
    for i in range(poly.size()):
        var a:=poly[i]; var b:=poly[(i+1)%poly.size()]
        draw_line(a,b,glow,glow_width,true)
        draw_line(a,b,core,core_width,true)

func _draw_marker(iso:String, center:Vector2) -> void:
    var t:Dictionary = territories[iso]
    var owner := str(t.owner)
    var title := str(NAMES.get(iso,"")) if ACTIVE_IDS.has(iso) else ""
    var flag := str(FLAGS.get(owner,"")) if owner != "NEUTRAL" else ""
    var show_name := zoom >= 0.92
    var flag_size := 30 if zoom >= 1.15 else 26
    if flag != "":
        draw_string_outline(ThemeDB.fallback_font,center+Vector2(-52,-19),flag,HORIZONTAL_ALIGNMENT_CENTER,104,flag_size,5,Color(0.0,0.01,0.02,0.9))
        draw_string(ThemeDB.fallback_font,center+Vector2(-52,-19),flag,HORIZONTAL_ALIGNMENT_CENTER,104,flag_size,Color.WHITE)
    if title != "" and show_name:
        draw_string_outline(ThemeDB.fallback_font,center+Vector2(-75,7),title,HORIZONTAL_ALIGNMENT_CENTER,150,15,4,Color(0.0,0.01,0.02,0.95))
        draw_string(ThemeDB.fallback_font,center+Vector2(-75,7),title,HORIZONTAL_ALIGNMENT_CENTER,150,15,Color(0.94,0.97,1.0))
    var count_y := 29.0 if title != "" and show_name else 12.0
    var count := str(int(float(t.army)))
    draw_string_outline(ThemeDB.fallback_font,center+Vector2(-58,count_y),count,HORIZONTAL_ALIGNMENT_CENTER,116,18,5,Color(0.0,0.01,0.02,0.95))
    draw_string(ThemeDB.fallback_font,center+Vector2(-58,count_y),count,HORIZONTAL_ALIGNMENT_CENTER,116,18,Color.WHITE)

func _curve_points(a:Vector2,b:Vector2) -> PackedVector2Array:
    var points:=PackedVector2Array()
    var d:=b-a
    var side:=Vector2(-d.y,d.x).normalized()
    var control:=(a+b)*0.5+side*minf(34.0,d.length()*0.10)
    for i in range(17):
        var t:=float(i)/16.0
        var p:=(1.0-t)*(1.0-t)*a+2.0*(1.0-t)*t*control+t*t*b
        points.append(p)
    return points

func _draw_army(center:Vector2, amount:int, owner:String, direction:Vector2) -> void:
    if amount <= 0: return
    var n := mini(amount,120)
    var side := Vector2(-direction.y,direction.x)
    var color := _owner_color(owner)
    for i in range(n):
        var seed := float(i)
        var along := (fmod(seed*17.37,100.0)/100.0-0.5)*78.0
        var across := (fmod(seed*31.91,100.0)/100.0-0.5)*25.0
        var wobble := sin(anim_time*4.0+seed*1.73)*3.2
        var drift := sin(anim_time*2.1+seed*0.61)*2.0
        var p:=center-direction*(along+drift)+side*(across+wobble)
        draw_circle(p,5.2,Color(color.r,color.g,color.b,0.10))
        draw_circle(p,2.45,Color(color.r,color.g,color.b,0.94))
        draw_circle(p-Vector2(0.6,0.7),0.65,Color(1,1,1,0.70))
    draw_circle(center+Vector2(0,-34),16.0,Color(0.006,0.022,0.038,0.92))
    draw_circle(center+Vector2(0,-34),16.0,Color(color.r,color.g,color.b,0.52),false,1.4)
    draw_string(ThemeDB.fallback_font,center+Vector2(-22,-29),str(amount),HORIZONTAL_ALIGNMENT_CENTER,44,13,Color.WHITE)

func _draw() -> void:
    _draw_sea()
    hit_polygons.clear(); feature_centers.clear()
    var best:Dictionary={}
    for feature in map_features:
        var iso:=_feature_iso(feature.get("properties",{}))
        if not territories.has(iso): continue
        var polys:Array=[]
        for ring in _rings(feature):
            var p:=_poly(ring)
            if p.size()<3: continue
            var owner:=str(territories[iso].owner)
            var fill:=_territory_color(owner)
            draw_colored_polygon(p,fill)
            if owner!="NEUTRAL":
                draw_colored_polygon(p,Color(_owner_color(owner).r,_owner_color(owner).g,_owner_color(owner).b,0.10+0.025*sin(anim_time*0.8)))
            _draw_border(p,owner)
            var bb:=_bounds(p); var area:=bb.size.x*bb.size.y
            if area>float(best.get(iso,0.0)):
                best[iso]=area; feature_centers[iso]=bb.get_center()
            polys.append(p)
        if not polys.is_empty(): hit_polygons[iso]=polys
    for iso in feature_centers.keys(): _draw_marker(str(iso),Vector2(feature_centers[iso]))
    if drag_source!="" and feature_centers.has(drag_source):
        var finger:=mouse_pos
        if touches.size()==1: finger=Vector2(touches.values()[0])
        var source:=Vector2(feature_centers[drag_source])
        var route:=_curve_points(source,finger)
        draw_polyline(route,Color(0.35,0.78,1.0,0.16),6.0,true)
        draw_polyline(route,Color(0.72,0.92,1.0,0.70),1.7,true)
        draw_circle(source,15.0+sin(anim_time*5.0)*2.0,Color(1.0,0.80,0.25,0.70),false,2.2)
    for a in armies:
        var pos:Vector2=a.pos; var target:=str(a.target); var dir:=Vector2.RIGHT
        if feature_centers.has(target): dir=(Vector2(feature_centers[target])-pos).normalized()
        _draw_army(pos,int(float(a.amount)),str(a.owner),dir)

func _hit(pos:Vector2) -> String:
    for iso in hit_polygons.keys():
        for p in hit_polygons[iso]:
            if Geometry2D.is_point_in_polygon(pos,p): return str(iso)
    return ""

func _send_army(from_iso:String,to_iso:String,share:=0.5,ai:=false) -> void:
    if game_over or from_iso=="" or to_iso=="" or from_iso==to_iso or not territories.has(from_iso) or not territories.has(to_iso): return
    var src:Dictionary=territories[from_iso]
    if str(src.owner)=="NEUTRAL" or (not ai and str(src.owner)!=player_country): return
    var amount:=floor(float(src.army)*share)
    if amount<1.0 or not feature_centers.has(from_iso): return
    src.army=float(src.army)-amount
    armies.append({"owner":str(src.owner),"amount":amount,"pos":Vector2(feature_centers[from_iso]),"target":to_iso})

func _move_armies(delta:float) -> void:
    for i in range(armies.size()-1,-1,-1):
        if i>=armies.size(): continue
        var a:Dictionary=armies[i]; var target:=str(a.target)
        if not feature_centers.has(target): continue
        var dest:Vector2=feature_centers[target]; var pos:Vector2=a.pos
        if pos.distance_to(dest)<=ARMY_SPEED*delta: _arrive(i); continue
        a.pos=pos.move_toward(dest,ARMY_SPEED*delta)
    _resolve_collisions()

func _resolve_collisions() -> void:
    var i:=0
    while i<armies.size():
        var j:=i+1
        while j<armies.size():
            if str(armies[i].owner)!=str(armies[j].owner) and Vector2(armies[i].pos).distance_to(Vector2(armies[j].pos))<=24.0:
                var loss:=minf(float(armies[i].amount),float(armies[j].amount))
                armies[i].amount=float(armies[i].amount)-loss; armies[j].amount=float(armies[j].amount)-loss
                if float(armies[j].amount)<=0: armies.remove_at(j); continue
                if float(armies[i].amount)<=0: armies.remove_at(i); i-=1; break
            j+=1
        i+=1

func _arrive(index:int) -> void:
    if index<0 or index>=armies.size(): return
    var a:Dictionary=armies[index]; armies.remove_at(index)
    var target:=str(a.target)
    if not territories.has(target): return
    var t:Dictionary=territories[target]
    if str(t.owner)==str(a.owner): t.army=float(t.army)+float(a.amount); return
    var attackers:=float(a.amount); var defenders:=float(t.army)
    if attackers>defenders:
        t.owner=str(a.owner); t.army=attackers-defenders
    else: t.army=defenders-attackers
    _check_player_defeat()

func _check_player_defeat() -> void:
    if not game_started or game_over: return
    for iso in territories.keys():
        if str(territories[iso].owner)==player_country: return
    game_over=true; armies.clear(); _show_defeat()

func _show_defeat() -> void:
    var shade:=ColorRect.new(); shade.color=Color(0.01,0.02,0.04,0.82); shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); shade.mouse_filter=Control.MOUSE_FILTER_STOP; add_child(shade)
    var center:=CenterContainer.new(); center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); shade.add_child(center)
    var box:=VBoxContainer.new(); box.custom_minimum_size=Vector2(520,250); box.alignment=BoxContainer.ALIGNMENT_CENTER; center.add_child(box)
    var title:=Label.new(); title.text="ВЫ ПРОИГРАЛИ"; title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; title.add_theme_font_size_override("font_size",42); box.add_child(title)
    var sub:=Label.new(); sub.text="Все территории вашей державы захвачены"; sub.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; sub.add_theme_font_size_override("font_size",18); box.add_child(sub)
    var button:=Button.new(); button.text="НАЧАТЬ ЗАНОВО"; button.custom_minimum_size=Vector2(320,60); button.add_theme_font_size_override("font_size",20); button.pressed.connect(_restart); box.add_child(button)

func _restart() -> void: get_tree().reload_current_scene()

func _ai_attack() -> void:
    var sources:Array=[]
    for iso in territories.keys():
        var t:Dictionary=territories[iso]
        if str(t.owner)!="NEUTRAL" and str(t.owner)!=player_country and float(t.army)>=24.0: sources.append(str(iso))
    if sources.is_empty(): return
    var source:=str(sources[randi()%sources.size()])
    if not feature_centers.has(source): return
    var src:Dictionary=territories[source]; var owner:=str(src.owner)
    var candidates:Array=[]
    for iso in territories.keys():
        if str(iso)==source or not feature_centers.has(iso): continue
        var target:Dictionary=territories[iso]
        if str(target.owner)==owner: continue
        var dist:=Vector2(feature_centers[source]).distance_to(Vector2(feature_centers[iso]))
        var neutral_bonus:=0.65 if str(target.owner)=="NEUTRAL" else 1.0
        var score:=(float(target.army)+20.0)*neutral_bonus+dist*0.09
        candidates.append({"iso":str(iso),"score":score})
    if candidates.is_empty(): return
    candidates.sort_custom(func(a,b): return float(a.score)<float(b.score))
    var target_iso:=str(candidates[0].iso)
    var target:Dictionary=territories[target_iso]
    if float(src.army)>float(target.army)*1.12+8.0: _send_army(source,target_iso,0.62,true)

func _gui_input(event:InputEvent) -> void:
    if game_over: return
    if event is InputEventScreenTouch:
        if event.pressed:
            touches[event.index]=event.position
            if touches.size()==1:
                drag_source=_hit(event.position); mouse_pos=event.position
            elif touches.size()==2:
                var vals:=touches.values(); pinch_distance=Vector2(vals[0]).distance_to(Vector2(vals[1])); drag_source=""
        else:
            if touches.has(event.index):
                var release_pos:=event.position
                if touches.size()==1 and drag_source!="": _send_army(drag_source,_hit(release_pos))
                touches.erase(event.index)
                if touches.is_empty(): drag_source=""
    elif event is InputEventScreenDrag:
        touches[event.index]=event.position; mouse_pos=event.position
        if touches.size()==2:
            var vals:=touches.values(); var d:=Vector2(vals[0]).distance_to(Vector2(vals[1]))
            if pinch_distance>0.0:
                var old_zoom:=zoom; zoom=clampf(zoom*d/pinch_distance,0.75,2.8)
                if absf(zoom-old_zoom)>0.001: queue_redraw()
            pinch_distance=d
    elif event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
        mouse_pos=event.position
        if event.pressed:
            mouse_down=true; drag_source=_hit(event.position)
        else:
            if mouse_down and drag_source!="": _send_army(drag_source,_hit(event.position))
            mouse_down=false; drag_source=""
    elif event is InputEventMouseMotion and mouse_down:
        mouse_pos=event.position; queue_redraw()
