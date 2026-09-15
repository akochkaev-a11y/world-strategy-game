extends Control

const GEOJSON_PATH := "res://eurasia_countries.json"
const LON_MIN := -12.0
const LON_MAX := 150.0
const LAT_MIN := 5.0
const LAT_MAX := 76.0
const ACTIVE_IDS := ["RU","UA","PL","FR","DE","GB","CN","IN","IR","JP"]
const NAMES := {"RU":"Россия","UA":"Украина","PL":"Польша","FR":"Франция","DE":"Германия","GB":"Великобритания","CN":"Китай","IN":"Индия","IR":"Иран","JP":"Япония"}
const FLAGS := {"RU":"🇷🇺","UA":"🇺🇦","PL":"🇵🇱","FR":"🇫🇷","DE":"🇩🇪","GB":"🇬🇧","CN":"🇨🇳","IN":"🇮🇳","IR":"🇮🇷","JP":"🇯🇵"}
const INITIAL_ARMY := {"RU":1320000.0,"UA":900000.0,"PL":216000.0,"FR":205000.0,"DE":184000.0,"GB":141000.0,"CN":2035000.0,"IN":1455000.0,"IR":610000.0,"JP":247000.0}
const ACTIVE_GROWTH := 1.0
const NEUTRAL_GROWTH := 0.5
const ARMY_SPEED := 110.0
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
    countries = data
    _load_geojson()
    _ensure_territories()
    queue_redraw()

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_STOP
    _load_geojson()
    _ensure_territories()
    queue_redraw()

func _notification(what: int) -> void:
    if what == NOTIFICATION_RESIZED:
        queue_redraw()

func _feature_iso(props: Dictionary) -> String:
    var iso: String = str(props.get("ISO_A2", ""))
    if iso == "" or iso == "-99": iso = str(props.get("ISO_A2_EH", ""))
    if iso == "" or iso == "-99":
        var a3: String = str(props.get("ADM0_A3", ""))
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
        var continent: String = str(props.get("CONTINENT", ""))
        if continent == "Europe" or continent == "Asia" or _feature_iso(props) == "RU": map_features.append(feature)

func _ensure_territories() -> void:
    for feature in map_features:
        var iso: String = _feature_iso(feature.get("properties", {}))
        if iso == "" or territories.has(iso): continue
        var active: bool = ACTIVE_IDS.has(iso)
        territories[iso] = {"owner": iso if active else "NEUTRAL", "army": float(INITIAL_ARMY.get(iso, 500.0)), "active": active}
        growth_fraction[iso] = 0.0

func grow_armies() -> void:
    for iso in territories.keys():
        var t: Dictionary = territories[iso]
        var rate: float = ACTIVE_GROWTH if bool(t.active) else NEUTRAL_GROWTH
        growth_fraction[iso] = float(growth_fraction.get(iso, 0.0)) + rate
        var whole: int = int(floor(float(growth_fraction[iso])))
        if whole > 0:
            t.army = float(t.army) + whole
            growth_fraction[iso] = float(growth_fraction[iso]) - whole
    queue_redraw()

func _process(delta: float) -> void:
    _move_armies(delta)
    ai_clock += delta
    if ai_clock >= 4.0:
        ai_clock = 0.0
        _active_ai_attack()

func _base_project(lon: float, lat: float) -> Vector2:
    return Vector2((lon-LON_MIN)/(LON_MAX-LON_MIN)*size.x,(LAT_MAX-lat)/(LAT_MAX-LAT_MIN)*size.y)

func _project(lon: float, lat: float) -> Vector2:
    var center := size*0.5
    return center+(_base_project(lon,lat)-center)*zoom+pan

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
    var a := Vector2(INF,INF)
    var b := Vector2(-INF,-INF)
    for p in poly:
        a.x=minf(a.x,p.x); a.y=minf(a.y,p.y); b.x=maxf(b.x,p.x); b.y=maxf(b.y,p.y)
    return Rect2(a,b-a)

func _clip_fill(poly: PackedVector2Array, rect: Rect2, color: Color) -> void:
    var rp := PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)])
    var pieces := Geometry2D.intersect_polygons(poly,rp)
    for piece in pieces:
        if piece.size() >= 3: draw_colored_polygon(piece,color)

func _draw_flag_polygon(poly: PackedVector2Array, owner: String) -> void:
    if owner == "NEUTRAL":
        draw_colored_polygon(poly,Color(0.34,0.36,0.38)); return
    var bb := _bounds(poly)
    if owner == "RU":
        _clip_fill(poly,Rect2(bb.position,Vector2(bb.size.x,bb.size.y/3.0)),Color.WHITE)
        _clip_fill(poly,Rect2(bb.position+Vector2(0,bb.size.y/3.0),Vector2(bb.size.x,bb.size.y/3.0)),Color(0.08,0.28,0.72))
        _clip_fill(poly,Rect2(bb.position+Vector2(0,bb.size.y*2.0/3.0),Vector2(bb.size.x,bb.size.y/3.0)),Color(0.78,0.08,0.12))
    elif owner == "UA":
        _clip_fill(poly,Rect2(bb.position,Vector2(bb.size.x,bb.size.y/2.0)),Color(0.05,0.42,0.78))
        _clip_fill(poly,Rect2(bb.position+Vector2(0,bb.size.y/2.0),Vector2(bb.size.x,bb.size.y/2.0)),Color(1.0,0.82,0.05))
    elif owner == "PL":
        _clip_fill(poly,Rect2(bb.position,Vector2(bb.size.x,bb.size.y/2.0)),Color.WHITE)
        _clip_fill(poly,Rect2(bb.position+Vector2(0,bb.size.y/2.0),Vector2(bb.size.x,bb.size.y/2.0)),Color(0.82,0.08,0.22))
    elif owner == "DE":
        _clip_fill(poly,Rect2(bb.position,Vector2(bb.size.x,bb.size.y/3.0)),Color(0.04,0.04,0.04))
        _clip_fill(poly,Rect2(bb.position+Vector2(0,bb.size.y/3.0),Vector2(bb.size.x,bb.size.y/3.0)),Color(0.78,0.04,0.08))
        _clip_fill(poly,Rect2(bb.position+Vector2(0,bb.size.y*2.0/3.0),Vector2(bb.size.x,bb.size.y/3.0)),Color(0.95,0.72,0.05))
    elif owner == "FR":
        _clip_fill(poly,Rect2(bb.position,Vector2(bb.size.x/3.0,bb.size.y)),Color(0.05,0.20,0.55))
        _clip_fill(poly,Rect2(bb.position+Vector2(bb.size.x/3.0,0),Vector2(bb.size.x/3.0,bb.size.y)),Color.WHITE)
        _clip_fill(poly,Rect2(bb.position+Vector2(bb.size.x*2.0/3.0,0),Vector2(bb.size.x/3.0,bb.size.y)),Color(0.82,0.08,0.12))
    elif owner == "IN":
        _clip_fill(poly,Rect2(bb.position,Vector2(bb.size.x,bb.size.y/3.0)),Color(1.0,0.55,0.12))
        _clip_fill(poly,Rect2(bb.position+Vector2(0,bb.size.y/3.0),Vector2(bb.size.x,bb.size.y/3.0)),Color.WHITE)
        _clip_fill(poly,Rect2(bb.position+Vector2(0,bb.size.y*2.0/3.0),Vector2(bb.size.x,bb.size.y/3.0)),Color(0.08,0.55,0.22))
    elif owner == "IR":
        _clip_fill(poly,Rect2(bb.position,Vector2(bb.size.x,bb.size.y/3.0)),Color(0.08,0.55,0.25))
        _clip_fill(poly,Rect2(bb.position+Vector2(0,bb.size.y/3.0),Vector2(bb.size.x,bb.size.y/3.0)),Color.WHITE)
        _clip_fill(poly,Rect2(bb.position+Vector2(0,bb.size.y*2.0/3.0),Vector2(bb.size.x,bb.size.y/3.0)),Color(0.78,0.08,0.12))
    elif owner == "JP":
        draw_colored_polygon(poly,Color.WHITE)
        draw_circle(bb.get_center(),minf(bb.size.x,bb.size.y)*0.22,Color(0.78,0.05,0.12))
    elif owner == "CN":
        draw_colored_polygon(poly,Color(0.82,0.08,0.08))
    elif owner == "GB":
        draw_colored_polygon(poly,Color(0.08,0.18,0.48))
        _clip_fill(poly,Rect2(Vector2(bb.position.x,bb.get_center().y-bb.size.y*0.10),Vector2(bb.size.x,bb.size.y*0.20)),Color.WHITE)
        _clip_fill(poly,Rect2(Vector2(bb.get_center().x-bb.size.x*0.08,bb.position.y),Vector2(bb.size.x*0.16,bb.size.y)),Color.WHITE)
        _clip_fill(poly,Rect2(Vector2(bb.position.x,bb.get_center().y-bb.size.y*0.055),Vector2(bb.size.x,bb.size.y*0.11)),Color(0.78,0.05,0.10))
        _clip_fill(poly,Rect2(Vector2(bb.get_center().x-bb.size.x*0.045,bb.position.y),Vector2(bb.size.x*0.09,bb.size.y)),Color(0.78,0.05,0.10))
    else:
        draw_colored_polygon(poly,Color(0.34,0.36,0.38))

func _draw() -> void:
    draw_rect(Rect2(Vector2.ZERO,size),Color(0.035,0.10,0.16))
    hit_polygons.clear(); feature_centers.clear()
    var best_area: Dictionary = {}
    for feature in map_features:
        var iso: String = _feature_iso(feature.get("properties", {}))
        if iso == "" or not territories.has(iso): continue
        var polys: Array = []
        for ring in _rings(feature):
            var p := _poly(ring)
            if p.size() < 3: continue
            var owner: String = str(territories[iso].owner)
            _draw_flag_polygon(p,owner)
            for i in range(p.size()): draw_line(p[i],p[(i+1)%p.size()],Color(0.78,0.82,0.84),1.2,true)
            var bb := _bounds(p)
            var area: float = bb.size.x*bb.size.y
            if area > float(best_area.get(iso,0.0)):
                best_area[iso]=area; feature_centers[iso]=bb.get_center()
            polys.append(p)
        if not polys.is_empty(): hit_polygons[iso]=polys
    for iso in feature_centers.keys():
        var t: Dictionary = territories[iso]
        if str(t.owner) == "NEUTRAL": continue
        var c: Vector2 = feature_centers[iso]
        var owner: String = str(t.owner)
        var label: String = "%s %s\n%d" % [FLAGS.get(owner,""),NAMES.get(iso,iso),int(float(t.army))]
        draw_string_outline(ThemeDB.fallback_font,c-Vector2(75,8),label,HORIZONTAL_ALIGNMENT_CENTER,150,16,4,Color.BLACK)
        draw_string(ThemeDB.fallback_font,c-Vector2(75,8),label,HORIZONTAL_ALIGNMENT_CENTER,150,16,Color.WHITE)
    for a in armies:
        var pos: Vector2 = a.pos
        var dir: Vector2 = Vector2.RIGHT
        if feature_centers.has(str(a.target)): dir=(Vector2(feature_centers[str(a.target)])-pos).normalized()
        var side := Vector2(-dir.y,dir.x)
        var rocket := PackedVector2Array([pos+dir*13.0,pos-dir*8.0+side*6.0,pos-dir*5.0,pos-dir*8.0-side*6.0])
        draw_colored_polygon(rocket,Color.WHITE)
        draw_circle(pos,4.5,Color(0.85,0.12,0.12) if str(a.owner)!="RU" else Color(0.10,0.42,0.85))
        var txt: String = str(int(float(a.amount)))
        draw_string_outline(ThemeDB.fallback_font,pos+Vector2(12,5),txt,HORIZONTAL_ALIGNMENT_LEFT,-1,13,3,Color.BLACK)
        draw_string(ThemeDB.fallback_font,pos+Vector2(12,5),txt,HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color.WHITE)

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
    src.army = float(src.army) - amount
    armies.append({"owner":str(src.owner),"amount":amount,"pos":feature_centers.get(from_iso,Vector2.ZERO),"target":to_iso})
    queue_redraw()

func _move_armies(delta: float) -> void:
    for i in range(armies.size()-1,-1,-1):
        if i >= armies.size(): continue
        var a: Dictionary = armies[i]
        var target_iso: String = str(a.target)
        if not feature_centers.has(target_iso): continue
        var target: Vector2 = feature_centers[target_iso]
        a.pos = Vector2(a.pos).move_toward(target, ARMY_SPEED*delta)
        if Vector2(a.pos).distance_to(target) < 8.0: _arrive(i,target_iso)
    _resolve_moving_collisions()
    queue_redraw()

func _resolve_moving_collisions() -> void:
    var i: int = 0
    while i < armies.size():
        var j: int = i+1
        while j < armies.size():
            var a: Dictionary = armies[i]; var b: Dictionary = armies[j]
            if str(a.owner) != str(b.owner) and Vector2(a.pos).distance_to(Vector2(b.pos)) <= COLLISION_RADIUS:
                var loss: float = minf(float(a.amount),float(b.amount))
                a.amount=float(a.amount)-loss; b.amount=float(b.amount)-loss
                if float(b.amount)<=0.0: armies.remove_at(j); continue
                if float(a.amount)<=0.0: armies.remove_at(i); i-=1; break
            j+=1
        i+=1

func _arrive(index: int, iso: String) -> void:
    if index < 0 or index >= armies.size(): return
    var a: Dictionary = armies[index]
    var t: Dictionary = territories[iso]
    var amount: float = float(a.amount)
    var owner: String = str(a.owner)
    if str(t.owner) == owner:
        t.army=float(t.army)+amount
    else:
        var loss: float=minf(amount,float(t.army))
        amount-=loss; t.army=float(t.army)-loss
        if amount>0.0 and float(t.army)<=0.0:
            t.owner=owner; t.active=true; t.army=amount
    armies.remove_at(index)

func _active_ai_attack() -> void:
    var options: Array = []
    for iso in territories.keys():
        var t: Dictionary=territories[iso]
        if bool(t.active) and str(t.owner)!="RU" and str(t.owner)!="NEUTRAL" and float(t.army)>=20.0: options.append(iso)
    if options.is_empty(): return
    var src_iso: String=str(options.pick_random())
    var src_center: Vector2=feature_centers.get(src_iso,Vector2.ZERO)
    var targets: Array=[]
    for iso in territories.keys():
        if iso!=src_iso and str(territories[iso].owner)!=str(territories[src_iso].owner): targets.append(iso)
    if targets.is_empty(): return
    targets.sort_custom(func(a,b): return src_center.distance_squared_to(feature_centers.get(a,Vector2.ZERO)) < src_center.distance_squared_to(feature_centers.get(b,Vector2.ZERO)))
    _send_army(src_iso,str(targets[0]),0.5)

func _zoom_at(screen_point: Vector2, factor: float) -> void:
    var old_zoom: float = zoom
    var new_zoom: float = clampf(old_zoom*factor,0.8,5.0)
    if is_equal_approx(new_zoom,old_zoom): return
    var center := size*0.5
    var world_offset := screen_point-center-pan
    pan -= world_offset*(new_zoom/old_zoom-1.0)
    zoom=new_zoom
    queue_redraw()

func _gui_input(e: InputEvent) -> void:
    if e is InputEventScreenTouch:
        if e.pressed:
            touches[e.index]=e.position
            if touches.size()==1:
                drag_source=_hit(e.position)
            else:
                drag_source=""
                var vals: Array=touches.values()
                if vals.size()>=2: pinch_distance=Vector2(vals[0]).distance_to(Vector2(vals[1]))
        else:
            var was_single: bool = touches.size()==1
            if was_single and drag_source!="": _send_army(drag_source,_hit(e.position),0.5)
            touches.erase(e.index)
            if touches.size()<2: pinch_distance=0.0
            drag_source=""
    elif e is InputEventScreenDrag:
        touches[e.index]=e.position
        if touches.size()>=2:
            drag_source=""
            var vals: Array=touches.values()
            var p0:=Vector2(vals[0]); var p1:=Vector2(vals[1])
            var d: float=p0.distance_to(p1)
            if pinch_distance>0.0: _zoom_at((p0+p1)*0.5,d/pinch_distance)
            pinch_distance=d
        elif drag_source=="":
            pan+=e.relative; queue_redraw()
    elif e is InputEventMouseButton:
        if e.button_index==MOUSE_BUTTON_WHEEL_UP: _zoom_at(e.position,1.12)
        elif e.button_index==MOUSE_BUTTON_WHEEL_DOWN: _zoom_at(e.position,1.0/1.12)
        elif e.button_index==MOUSE_BUTTON_LEFT:
            if e.pressed: mouse_drag_source=_hit(e.position)
            elif mouse_drag_source!="": _send_army(mouse_drag_source,_hit(e.position),0.5); mouse_drag_source=""
    elif e is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
        pan+=e.relative; queue_redraw()
