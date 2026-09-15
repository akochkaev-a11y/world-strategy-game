extends Control

const GEOJSON_PATH := "res://eurasia_countries.json"
const LON_MIN := -12.0
const LON_MAX := 150.0
const LAT_MIN := 5.0
const LAT_MAX := 76.0
const ACTIVE_IDS := ["RU","UA","PL","FR","DE","GB","CN","IN","IR","JP"]
const NAMES := {"RU":"Россия","UA":"Украина","PL":"Польша","FR":"Франция","DE":"Германия","GB":"Великобритания","CN":"Китай","IN":"Индия","IR":"Иран","JP":"Япония"}
const FLAGS := {"RU":"🇷🇺","UA":"🇺🇦","PL":"🇵🇱","FR":"🇫🇷","DE":"🇩🇪","GB":"🇬🇧","CN":"🇨🇳","IN":"🇮🇳","IR":"🇮🇷","JP":"🇯🇵"}
const START_ARMY := 1000.0
const ACTIVE_GROWTH := 1.0
const NEUTRAL_GROWTH := 0.5
const ARMY_SPEED := 110.0
const COLLISION_RADIUS := 20.0

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
var drag_moved := false
var pinch_distance := 0.0
var pinch_center := Vector2.ZERO
var ai_clock := 0.0

func setup(_data: Dictionary, selected: String) -> void:
    player_country = selected
    _load_geojson()
    _ensure_territories()
    queue_redraw()

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_STOP

func _feature_iso(props: Dictionary) -> String:
    var iso := str(props.get("ISO_A2", ""))
    if iso == "" or iso == "-99": iso = str(props.get("ISO_A2_EH", ""))
    if iso == "" or iso == "-99":
        var a3 := str(props.get("ADM0_A3", ""))
        var m := {"FRA":"FR","RUS":"RU","UKR":"UA","POL":"PL","DEU":"DE","GBR":"GB","CHN":"CN","IND":"IN","IRN":"IR","JPN":"JP"}
        iso = str(m.get(a3, a3))
    return iso

func _load_geojson() -> void:
    if not map_features.is_empty() or not FileAccess.file_exists(GEOJSON_PATH): return
    var f := FileAccess.open(GEOJSON_PATH, FileAccess.READ)
    if f == null: return
    var parsed = JSON.parse_string(f.get_as_text())
    if typeof(parsed) != TYPE_DICTIONARY: return
    for feature in parsed.get("features", []):
        var props: Dictionary = feature.get("properties", {})
        var continent := str(props.get("CONTINENT", ""))
        if continent == "Europe" or continent == "Asia" or _feature_iso(props) == "RU": map_features.append(feature)

func _ensure_territories() -> void:
    for feature in map_features:
        var iso := _feature_iso(feature.get("properties", {}))
        if iso == "" or territories.has(iso): continue
        var active := ACTIVE_IDS.has(iso)
        territories[iso] = {"owner": iso if active else "NEUTRAL", "army": START_ARMY, "active": active}
        growth_fraction[iso] = 0.0

func grow_armies() -> void:
    for iso in territories.keys():
        var t: Dictionary = territories[iso]
        var rate := ACTIVE_GROWTH if str(t.owner) != "NEUTRAL" else NEUTRAL_GROWTH
        growth_fraction[iso] = float(growth_fraction.get(iso, 0.0)) + rate
        var whole := int(floor(float(growth_fraction[iso])))
        if whole > 0:
            t.army = float(t.army) + whole
            growth_fraction[iso] = float(growth_fraction[iso]) - whole
    queue_redraw()

func _process(delta: float) -> void:
    _move_armies(delta)
    ai_clock += delta
    if ai_clock >= 4.0:
        ai_clock = 0.0
        _ai_attack()

func _base_project(lon: float, lat: float) -> Vector2:
    return Vector2((lon-LON_MIN)/(LON_MAX-LON_MIN)*size.x,(LAT_MAX-lat)/(LAT_MAX-LAT_MIN)*size.y)

func _project(lon: float, lat: float) -> Vector2:
    var center := size*0.5
    return center + (_base_project(lon,lat)-center)*zoom + pan

func _rings(feature: Dictionary) -> Array:
    var g: Dictionary = feature.get("geometry", {})
    var coords: Array = g.get("coordinates", [])
    var out: Array = []
    if str(g.get("type", "")) == "Polygon" and not coords.is_empty(): out.append(coords[0])
    elif str(g.get("type", "")) == "MultiPolygon":
        for p in coords:
            if not p.is_empty(): out.append(p[0])
    return out

func _poly(ring: Array) -> PackedVector2Array:
    var out := PackedVector2Array()
    for q in ring:
        if q.size() >= 2: out.append(_project(float(q[0]),float(q[1])))
    return out

func _bounds(poly: PackedVector2Array) -> Rect2:
    var a := Vector2(INF,INF); var b := Vector2(-INF,-INF)
    for p in poly:
        a.x=minf(a.x,p.x); a.y=minf(a.y,p.y); b.x=maxf(b.x,p.x); b.y=maxf(b.y,p.y)
    return Rect2(a,b-a)

func _owner_color(owner: String) -> Color:
    var colors := {"RU":Color(0.18,0.38,0.78),"UA":Color(0.10,0.52,0.86),"PL":Color(0.85,0.25,0.35),"FR":Color(0.18,0.30,0.72),"DE":Color(0.18,0.18,0.18),"GB":Color(0.25,0.20,0.62),"CN":Color(0.82,0.10,0.10),"IN":Color(0.92,0.50,0.12),"IR":Color(0.10,0.55,0.25),"JP":Color(0.92,0.92,0.92)}
    return colors.get(owner, Color(0.34,0.36,0.38))

func _draw() -> void:
    draw_rect(Rect2(Vector2.ZERO,size),Color(0.035,0.10,0.16))
    hit_polygons.clear(); feature_centers.clear()
    var best_area: Dictionary = {}
    for feature in map_features:
        var iso := _feature_iso(feature.get("properties", {}))
        if iso == "" or not territories.has(iso): continue
        var polys: Array = []
        for ring in _rings(feature):
            var p := _poly(ring)
            if p.size() < 3: continue
            var owner := str(territories[iso].owner)
            draw_colored_polygon(p,_owner_color(owner))
            for i in range(p.size()): draw_line(p[i],p[(i+1)%p.size()],Color(0.80,0.84,0.86),1.2,true)
            var bb := _bounds(p); var area := bb.size.x*bb.size.y
            if area > float(best_area.get(iso,0.0)):
                best_area[iso]=area; feature_centers[iso]=bb.get_center()
            polys.append(p)
        if not polys.is_empty(): hit_polygons[iso]=polys
    for iso in feature_centers.keys():
        var t: Dictionary = territories[iso]
        var c: Vector2 = feature_centers[iso]
        var owner := str(t.owner)
        var title := NAMES.get(iso, "") if ACTIVE_IDS.has(iso) else ""
        var flag := FLAGS.get(owner, "") if owner != "NEUTRAL" else ""
        var line1 := (str(flag)+" "+str(title)).strip_edges()
        if line1 != "":
            draw_string_outline(ThemeDB.fallback_font,c-Vector2(70,10),line1,HORIZONTAL_ALIGNMENT_CENTER,140,15,4,Color.BLACK)
            draw_string(ThemeDB.fallback_font,c-Vector2(70,10),line1,HORIZONTAL_ALIGNMENT_CENTER,140,15,Color.WHITE)
        var count := str(int(float(t.army)))
        draw_string_outline(ThemeDB.fallback_font,c-Vector2(60,-9),count,HORIZONTAL_ALIGNMENT_CENTER,120,17,4,Color.BLACK)
        draw_string(ThemeDB.fallback_font,c-Vector2(60,-9),count,HORIZONTAL_ALIGNMENT_CENTER,120,17,Color.WHITE)
    for a in armies:
        var pos: Vector2 = a.pos
        draw_circle(pos,7.0,_owner_color(str(a.owner)))
        draw_circle(pos,7.0,Color.WHITE,false,2.0)
        var txt := str(int(float(a.amount)))
        draw_string_outline(ThemeDB.fallback_font,pos+Vector2(10,5),txt,HORIZONTAL_ALIGNMENT_LEFT,-1,13,3,Color.BLACK)
        draw_string(ThemeDB.fallback_font,pos+Vector2(10,5),txt,HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color.WHITE)

func _hit(pos: Vector2) -> String:
    for iso in hit_polygons.keys():
        for p in hit_polygons[iso]:
            if Geometry2D.is_point_in_polygon(pos,p): return str(iso)
    return ""

func _send_army(from_iso: String, to_iso: String, share := 0.5, ai := false) -> void:
    if from_iso == "" or to_iso == "" or from_iso == to_iso: return
    if not territories.has(from_iso) or not territories.has(to_iso): return
    var src: Dictionary = territories[from_iso]
    if str(src.owner) == "NEUTRAL": return
    if not ai and str(src.owner) != player_country: return
    var amount := floor(float(src.army)*share)
    if amount < 1.0 or not feature_centers.has(from_iso): return
    src.army = float(src.army)-amount
    armies.append({"owner":str(src.owner),"amount":amount,"pos":Vector2(feature_centers[from_iso]),"target":to_iso})
    queue_redraw()

func _move_armies(delta: float) -> void:
    for i in range(armies.size()-1,-1,-1):
        if i >= armies.size(): continue
        var a: Dictionary = armies[i]
        var target := str(a.target)
        if not feature_centers.has(target): continue
        var dest: Vector2 = feature_centers[target]
        var pos: Vector2 = a.pos
        var d := pos.distance_to(dest)
        if d <= ARMY_SPEED*delta:
            _arrive(i); continue
        a.pos = pos.move_toward(dest,ARMY_SPEED*delta)
    _resolve_collisions()
    queue_redraw()

func _resolve_collisions() -> void:
    var i := 0
    while i < armies.size():
        var j := i+1
        while j < armies.size():
            if str(armies[i].owner) != str(armies[j].owner) and Vector2(armies[i].pos).distance_to(Vector2(armies[j].pos)) <= COLLISION_RADIUS:
                var loss := minf(float(armies[i].amount),float(armies[j].amount))
                armies[i].amount=float(armies[i].amount)-loss; armies[j].amount=float(armies[j].amount)-loss
                if float(armies[j].amount)<=0: armies.remove_at(j); continue
                if float(armies[i].amount)<=0: armies.remove_at(i); i-=1; break
            j+=1
        i+=1

func _arrive(index: int) -> void:
    if index < 0 or index >= armies.size(): return
    var a: Dictionary = armies[index]; armies.remove_at(index)
    var target := str(a.target)
    if not territories.has(target): return
    var t: Dictionary = territories[target]
    if str(t.owner)==str(a.owner):
        t.army=float(t.army)+float(a.amount); return
    var attackers := float(a.amount); var defenders := float(t.army)
    if attackers > defenders:
        t.owner=str(a.owner); t.army=attackers-defenders; t.active=true
    else:
        t.army=defenders-attackers

func _ai_attack() -> void:
    if feature_centers.is_empty(): return
    var sources: Array = []
    for iso in territories.keys():
        var t: Dictionary = territories[iso]
        var owner := str(t.owner)
        if owner != "NEUTRAL" and owner != player_country and float(t.army)>=20.0: sources.append(str(iso))
    if sources.is_empty(): return
    var source := str(sources[randi()%sources.size()]); var owner := str(territories[source].owner)
    var targets: Array = []
    for iso in territories.keys():
        if str(territories[iso].owner)!=owner and feature_centers.has(iso): targets.append(str(iso))
    if targets.is_empty(): return
    targets.sort_custom(func(a,b): return Vector2(feature_centers[a]).distance_to(Vector2(feature_centers[source])) < Vector2(feature_centers[b]).distance_to(Vector2(feature_centers[source])))
    _send_army(source,str(targets[0]),0.5,true)

func _gui_input(event: InputEvent) -> void:
    if event is InputEventScreenTouch:
        if event.pressed:
            touches[event.index]=event.position
            if touches.size()==1:
                drag_source=_hit(event.position); drag_moved=false
            elif touches.size()==2:
                drag_source=""
                var pts:=touches.values(); pinch_distance=Vector2(pts[0]).distance_to(Vector2(pts[1])); pinch_center=(Vector2(pts[0])+Vector2(pts[1]))*0.5
        else:
            if touches.size()==1 and drag_source!="":
                var target:=_hit(event.position)
                if target!="": _send_army(drag_source,target)
            touches.erase(event.index)
            if touches.size()<2: pinch_distance=0.0
            drag_source=""
        accept_event()
    elif event is InputEventScreenDrag:
        if not touches.has(event.index): return
        touches[event.index]=event.position
        if touches.size()==2:
            var pts:=touches.values(); var new_dist:=Vector2(pts[0]).distance_to(Vector2(pts[1])); var new_center:=(Vector2(pts[0])+Vector2(pts[1]))*0.5
            if pinch_distance>0.0:
                var old_zoom:=zoom; zoom=clampf(zoom*(new_dist/pinch_distance),0.8,5.0)
                pan=(pan+(pinch_center-size*0.5)*(1.0-old_zoom/zoom))+(new_center-pinch_center)
            pinch_distance=new_dist; pinch_center=new_center; queue_redraw()
        elif touches.size()==1:
            if drag_source=="": pan+=event.relative; queue_redraw()
            else: drag_moved=true
        accept_event()
