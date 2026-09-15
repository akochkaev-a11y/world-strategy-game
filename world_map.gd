extends Control

const GEOJSON_PATH := "res://eurasia_countries.json"
const LON_MIN := -12.0
const LON_MAX := 150.0
const LAT_MIN := 5.0
const LAT_MAX := 76.0
const ACTIVE_IDS := ["RU","UA","PL","FR","DE","GB","CN","IN","IR","JP"]
const NAMES := {"RU":"Россия","UA":"Украина","PL":"Польша","FR":"Франция","DE":"Германия","GB":"Великобритания","CN":"Китай","IN":"Индия","IR":"Иран","JP":"Япония"}
const FLAGS := {"RU":"🇷🇺","UA":"🇺🇦","PL":"🇵🇱","FR":"🇫🇷","DE":"🇩🇪","GB":"🇬🇧","CN":"🇨🇳","IN":"🇮🇳","IR":"🇮🇷","JP":"🇯🇵"}
const COLORS := {"RU":Color(0.20,0.42,0.78),"UA":Color(0.22,0.55,0.85),"PL":Color(0.85,0.30,0.38),"FR":Color(0.20,0.35,0.75),"DE":Color(0.20,0.20,0.20),"GB":Color(0.35,0.25,0.65),"CN":Color(0.82,0.16,0.16),"IN":Color(0.90,0.52,0.18),"IR":Color(0.16,0.55,0.28),"JP":Color(0.92,0.92,0.92)}
const ACTIVE_GROWTH := 1.0
const NEUTRAL_GROWTH := 0.5
const ARMY_SPEED := 85.0
const COLLISION_RADIUS := 20.0

var countries: Dictionary = {}
var territories: Dictionary = {}
var armies: Array[Dictionary] = []
var map_features: Array = []
var hit_polygons: Dictionary = {}
var feature_centers: Dictionary = {}
var zoom: float = 1.0
var pan: Vector2 = Vector2.ZERO
var touches: Dictionary = {}
var pinch_distance: float = 0.0
var drag_source: String = ""
var mouse_drag_source: String = ""
var growth_fraction: Dictionary = {}
var ai_clock: float = 0.0

func setup(data: Dictionary, _selected: String) -> void:
    countries = data; _load_geojson(); _ensure_territories(); queue_redraw()
func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_STOP; _load_geojson(); _ensure_territories(); queue_redraw()
func _notification(what: int) -> void:
    if what == NOTIFICATION_RESIZED: queue_redraw()
func _feature_iso(props: Dictionary) -> String:
    var iso: String = str(props.get("ISO_A2", ""))
    if iso == "" or iso == "-99": iso = str(props.get("ISO_A2_EH", ""))
    if iso == "" or iso == "-99":
        var a3: String = str(props.get("ADM0_A3", "")); var m := {"FRA":"FR","RUS":"RU","UKR":"UA","POL":"PL","DEU":"DE","GBR":"GB","CHN":"CN","IND":"IN","IRN":"IR","JPN":"JP"}; iso = str(m.get(a3, a3))
    return iso
func _load_geojson() -> void:
    if not map_features.is_empty() or not FileAccess.file_exists(GEOJSON_PATH): return
    var f := FileAccess.open(GEOJSON_PATH, FileAccess.READ)
    if f == null: return
    var parsed = JSON.parse_string(f.get_as_text())
    if typeof(parsed) != TYPE_DICTIONARY: return
    for feature in parsed.get("features", []):
        var props: Dictionary = feature.get("properties", {}); var continent: String = str(props.get("CONTINENT", ""))
        if continent == "Europe" or continent == "Asia" or _feature_iso(props) == "RU": map_features.append(feature)
func _ensure_territories() -> void:
    for feature in map_features:
        var iso: String = _feature_iso(feature.get("properties", {}))
        if iso == "" or territories.has(iso): continue
        var active: bool = ACTIVE_IDS.has(iso)
        territories[iso] = {"owner": iso if active else "NEUTRAL", "army": 1000.0 if active else 500.0, "active": active}; growth_fraction[iso] = 0.0
func grow_armies() -> void:
    for iso in territories.keys():
        var t: Dictionary = territories[iso]; var rate: float = ACTIVE_GROWTH if bool(t.active) else NEUTRAL_GROWTH
        growth_fraction[iso] = float(growth_fraction.get(iso, 0.0)) + rate
        var whole: int = int(floor(float(growth_fraction[iso])))
        if whole > 0: t.army = float(t.army) + whole; growth_fraction[iso] = float(growth_fraction[iso]) - whole
    queue_redraw()
func _process(delta: float) -> void:
    _move_armies(delta); ai_clock += delta
    if ai_clock >= 4.0: ai_clock = 0.0; _active_ai_attack()
func _base_project(lon: float, lat: float) -> Vector2: return Vector2((lon-LON_MIN)/(LON_MAX-LON_MIN)*size.x,(LAT_MAX-lat)/(LAT_MAX-LAT_MIN)*size.y)
func _project(lon: float, lat: float) -> Vector2:
    var center := size*0.5; return center+(_base_project(lon,lat)-center)*zoom+pan
func _rings(feature: Dictionary) -> Array:
    var g: Dictionary = feature.get("geometry", {}); var coords: Array = g.get("coordinates", []); var out: Array = []
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
    for p in poly: a.x=minf(a.x,p.x); a.y=minf(a.y,p.y); b.x=maxf(b.x,p.x); b.y=maxf(b.y,p.y)
    return Rect2(a,b-a)
func _draw() -> void:
    draw_rect(Rect2(Vector2.ZERO,size),Color(0.035,0.10,0.16)); hit_polygons.clear(); feature_centers.clear()
    for feature in map_features:
        var iso: String = _feature_iso(feature.get("properties", {}))
        if iso == "" or not territories.has(iso): continue
        var polys: Array = []; var total := Vector2.ZERO; var n: int = 0
        for ring in _rings(feature):
            var p := _poly(ring)
            if p.size() < 3: continue
            var owner: String = str(territories[iso].owner); var fill: Color = Color(0.34,0.36,0.38) if owner == "NEUTRAL" else COLORS.get(owner, Color(0.34,0.36,0.38))
            draw_colored_polygon(p, fill)
            for i in range(p.size()): draw_line(p[i],p[(i+1)%p.size()],Color(0.75,0.78,0.78),1.2,true)
            var bb := _bounds(p); total += bb.get_center(); n += 1; polys.append(p)
        if not polys.is_empty(): hit_polygons[iso]=polys; feature_centers[iso]=total/maxi(n,1)
    for iso in feature_centers.keys():
        var t: Dictionary = territories[iso]
        if str(t.owner) == "NEUTRAL": continue
        var c: Vector2 = feature_centers[iso]; var owner: String = str(t.owner); var label: String = "%s %s\n%d" % [FLAGS.get(owner,""), NAMES.get(owner,owner), int(float(t.army))]
        draw_string_outline(ThemeDB.fallback_font,c-Vector2(60,0),label,HORIZONTAL_ALIGNMENT_CENTER,120,14,3,Color.BLACK); draw_string(ThemeDB.fallback_font,c-Vector2(60,0),label,HORIZONTAL_ALIGNMENT_CENTER,120,14,Color.WHITE)
    for a in armies:
        var pos: Vector2 = a.pos; draw_circle(pos,9.0,Color.WHITE); draw_circle(pos,7.0,COLORS.get(str(a.owner),Color.GRAY)); var txt: String = str(int(float(a.amount)))
        draw_string_outline(ThemeDB.fallback_font,pos+Vector2(10,5),txt,HORIZONTAL_ALIGNMENT_LEFT,-1,13,3,Color.BLACK); draw_string(ThemeDB.fallback_font,pos+Vector2(10,5),txt,HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color.WHITE)
func _hit(pos: Vector2) -> String:
    for iso in hit_polygons.keys():
        for p in hit_polygons[iso]:
            if Geometry2D.is_point_in_polygon(pos,p): return iso
    return ""
func _send_army(from_iso: String, to_iso: String, share: float = 0.5) -> void:
    if from_iso == "" or to_iso == "" or from_iso == to_iso or not territories.has(from_iso) or not territories.has(to_iso): return
    var src: Dictionary = territories[from_iso]
    if str(src.owner) == "NEUTRAL": return
    var amount: float = floor(float(src.army) * share)
    if amount < 1.0: return
    src.army = float(src.army) - amount; armies.append({"owner":str(src.owner),"amount":amount,"pos":feature_centers.get(from_iso,Vector2.ZERO),"target":to_iso}); queue_redraw()
func _move_armies(delta: float) -> void:
    for i in range(armies.size()-1,-1,-1):
        if i >= armies.size(): continue
        var a: Dictionary = armies[i]; var target_iso: String = str(a.target)
        if not feature_centers.has(target_iso): continue
        var target: Vector2 = feature_centers[target_iso]; a.pos = Vector2(a.pos).move_toward(target, ARMY_SPEED*delta)
        if Vector2(a.pos).distance_to(target) < 8.0: _arrive(i,target_iso)
    _resolve_moving_collisions(); queue_redraw()
func _resolve_moving_collisions() -> void:
    var i: int = 0
    while i < armies.size():
        var j: int = i+1
        while j < armies.size():
            var a: Dictionary = armies[i]; var b: Dictionary = armies[j]
            if str(a.owner) != str(b.owner) and Vector2(a.pos).distance_to(Vector2(b.pos)) <= COLLISION_RADIUS:
                var loss: float = minf(float(a.amount),float(b.amount)); a.amount=float(a.amount)-loss; b.amount=float(b.amount)-loss
                if float(b.amount)<=0.0: armies.remove_at(j); continue
                if float(a.amount)<=0.0: armies.remove_at(i); i-=1; break
            j+=1
        i+=1
func _arrive(index: int, iso: String) -> void:
    if index < 0 or index >= armies.size(): return
    var a: Dictionary = armies[index]; var t: Dictionary = territories[iso]; var amount: float = float(a.amount); var owner: String = str(a.owner)
    if str(t.owner) == owner: t.army=float(t.army)+amount
    else:
        var loss: float=minf(amount,float(t.army)); amount-=loss; t.army=float(t.army)-loss
        if amount>0.0 and float(t.army)<=0.0: t.owner=owner; t.active=true; t.army=amount
    armies.remove_at(index)
func _active_ai_attack() -> void:
    var options: Array = []
    for iso in territories.keys():
        var t: Dictionary=territories[iso]
        if bool(t.active) and str(t.owner)!="RU" and str(t.owner)!="NEUTRAL" and float(t.army)>=20.0: options.append(iso)
    if options.is_empty(): return
    var src_iso: String=str(options.pick_random()); var src_center: Vector2=feature_centers.get(src_iso,Vector2.ZERO); var targets: Array=[]
    for iso in territories.keys():
        if iso!=src_iso and str(territories[iso].owner)!=str(territories[src_iso].owner): targets.append(iso)
    if targets.is_empty(): return
    targets.sort_custom(func(a,b): return src_center.distance_squared_to(feature_centers.get(a,Vector2.ZERO)) < src_center.distance_squared_to(feature_centers.get(b,Vector2.ZERO)))
    _send_army(src_iso,str(targets[0]),0.5)
func _gui_input(e: InputEvent) -> void:
    if e is InputEventScreenTouch:
        if e.pressed: touches[e.index]=e.position; drag_source=_hit(e.position) if touches.size()==1 else ""
        else:
            if touches.size()==1 and drag_source!="": _send_army(drag_source,_hit(e.position),0.5)
            touches.erase(e.index); pinch_distance=0.0; drag_source=""
    elif e is InputEventScreenDrag:
        touches[e.index]=e.position
        if touches.size()>=2:
            var vals: Array=touches.values(); var d: float=Vector2(vals[0]).distance_to(Vector2(vals[1]))
            if pinch_distance>0.0: zoom=clampf(zoom*d/pinch_distance,0.8,5.0)
            pinch_distance=d; queue_redraw()
        else: pan+=e.relative; queue_redraw()
    elif e is InputEventMouseButton:
        if e.button_index==MOUSE_BUTTON_WHEEL_UP: zoom=minf(5.0,zoom*1.12); queue_redraw()
        elif e.button_index==MOUSE_BUTTON_WHEEL_DOWN: zoom=maxf(0.8,zoom/1.12); queue_redraw()
        elif e.button_index==MOUSE_BUTTON_LEFT:
            if e.pressed: mouse_drag_source=_hit(e.position)
            elif mouse_drag_source!="": _send_army(mouse_drag_source,_hit(e.position),0.5); mouse_drag_source=""
    elif e is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE): pan+=e.relative; queue_redraw()
