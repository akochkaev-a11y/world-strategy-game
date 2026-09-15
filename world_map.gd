extends Control

signal country_clicked(country_id: String)
signal attack_requested(from_id: String, to_id: String)

const GEOJSON_PATH := "res://eurasia_countries.json"
const LON_MIN := -12.0
const LON_MAX := 150.0
const LAT_MIN := 5.0
const LAT_MAX := 76.0
const FLAGS := {"RU":"🇷🇺","UA":"🇺🇦","PL":"🇵🇱","FR":"🇫🇷","DE":"🇩🇪","GB":"🇬🇧","CN":"🇨🇳","IN":"🇮🇳","IR":"🇮🇷","JP":"🇯🇵"}
const FLAG_COLORS := {"RU":[Color.WHITE,Color(0.05,0.25,0.70),Color(0.78,0.05,0.08)],"FR":[Color(0.05,0.20,0.62),Color.WHITE,Color(0.85,0.08,0.10)],"DE":[Color(0.05,0.05,0.05),Color(0.78,0.05,0.08),Color(0.95,0.72,0.05)],"GB":[Color(0.05,0.18,0.52),Color.WHITE,Color(0.75,0.05,0.08)],"CN":[Color(0.82,0.05,0.08),Color(0.95,0.78,0.05),Color(0.82,0.05,0.08)],"IN":[Color(0.95,0.45,0.08),Color.WHITE,Color(0.08,0.55,0.20)],"JP":[Color.WHITE,Color(0.82,0.05,0.12),Color.WHITE],"PL":[Color.WHITE,Color.WHITE,Color(0.82,0.08,0.16)],"UA":[Color(0.05,0.35,0.72),Color(0.05,0.35,0.72),Color(0.95,0.78,0.08)],"IR":[Color(0.10,0.55,0.25),Color.WHITE,Color(0.78,0.08,0.10)]}

var countries: Dictionary={}
var territories: Dictionary={}
var selected_id: String=""
var source_id: String=""
var map_features:Array=[]
var hit_polygons:Dictionary={}
var feature_centers:Dictionary={}
var zoom:float=1.0
var pan:Vector2=Vector2.ZERO
var touches:Dictionary={}
var pinch_distance:float=0.0

func setup(data:Dictionary,selected:String)->void:
    countries=data; selected_id=selected; _load_geojson(); _ensure_territories(); queue_redraw()
func set_selected(id:String)->void:selected_id=id;queue_redraw()
func _ready()->void:mouse_filter=Control.MOUSE_FILTER_STOP;_load_geojson();queue_redraw()
func _notification(what:int)->void:
    if what==NOTIFICATION_RESIZED:queue_redraw()
func _feature_iso(props:Dictionary)->String:
    var iso:=str(props.get("ISO_A2",""))
    if iso=="" or iso=="-99":iso=str(props.get("ISO_A2_EH",""))
    if iso=="" or iso=="-99":
        var a3:=str(props.get("ADM0_A3",""));var m:={"FRA":"FR","RUS":"RU","UKR":"UA","POL":"PL","DEU":"DE","GBR":"GB","CHN":"CN","IND":"IN","IRN":"IR","JPN":"JP"};iso=str(m.get(a3,a3))
    return iso
func _load_geojson()->void:
    if not map_features.is_empty() or not FileAccess.file_exists(GEOJSON_PATH):return
    var f:=FileAccess.open(GEOJSON_PATH,FileAccess.READ);if f==null:return
    var parsed=JSON.parse_string(f.get_as_text());if typeof(parsed)!=TYPE_DICTIONARY:return
    for feature in parsed.get("features",[]):
        var props:Dictionary=feature.get("properties",{});var continent:=str(props.get("CONTINENT",""));var bbox:Array=feature.get("bbox",[]);var ok:=true
        if bbox.size()>=4:ok=float(bbox[2])>=LON_MIN and float(bbox[0])<=LON_MAX and float(bbox[3])>=LAT_MIN and float(bbox[1])<=LAT_MAX
        if ok and (continent=="Europe" or continent=="Asia" or _feature_iso(props)=="RU"):map_features.append(feature)
    _ensure_territories()
func _ensure_territories()->void:
    for feature in map_features:
        var iso:=_feature_iso(feature.get("properties",{}));if iso=="":continue
        if not territories.has(iso):territories[iso]={"owner":iso if countries.has(iso) else "NEUTRAL","army":float(countries[iso].get("army",1000.0)) if countries.has(iso) else 100.0}
func grow_armies(amount:float)->void:
    for iso in territories.keys():territories[iso].army=float(territories[iso].army)+amount
    queue_redraw()
func _base_project(lon:float,lat:float)->Vector2:return Vector2((lon-LON_MIN)/(LON_MAX-LON_MIN)*size.x,(LAT_MAX-lat)/(LAT_MAX-LAT_MIN)*size.y)
func _project(lon:float,lat:float)->Vector2:
    var center:=size*0.5;return center+(_base_project(lon,lat)-center)*zoom+pan
func _rings(feature:Dictionary)->Array:
    var g:Dictionary=feature.get("geometry",{});var coords:Array=g.get("coordinates",[]);var out:Array=[]
    if str(g.get("type",""))=="Polygon" and not coords.is_empty():out.append(coords[0])
    elif str(g.get("type",""))=="MultiPolygon":
        for p in coords:
            if not p.is_empty():out.append(p[0])
    return out
func _poly(ring:Array)->PackedVector2Array:
    var out:=PackedVector2Array();for q in ring:
        if q.size()>=2:out.append(_project(float(q[0]),float(q[1])))
    return out
func _bounds(poly:PackedVector2Array)->Rect2:
    var a:=Vector2(INF,INF);var b:=Vector2(-INF,-INF)
    for p in poly:a.x=minf(a.x,p.x);a.y=minf(a.y,p.y);b.x=maxf(b.x,p.x);b.y=maxf(b.y,p.y)
    return Rect2(a,b-a)
func _clip(poly:PackedVector2Array,shape:PackedVector2Array,color:Color)->void:
    for c in Geometry2D.intersect_polygons(poly,shape):
        if c.size()>=3:draw_colored_polygon(c,color)
func _flag(poly:PackedVector2Array,owner:String)->void:
    if owner=="NEUTRAL" or not FLAG_COLORS.has(owner):draw_colored_polygon(poly,Color(0.32,0.34,0.32));return
    var colors:Array=FLAG_COLORS[owner];var b:=_bounds(poly)
    if owner=="FR":
        for i in range(3):
            var x1:=b.position.x+b.size.x*i/3.0;var x2:=b.position.x+b.size.x*(i+1)/3.0;_clip(poly,PackedVector2Array([Vector2(x1,b.position.y-2),Vector2(x2,b.position.y-2),Vector2(x2,b.end.y+2),Vector2(x1,b.end.y+2)]),colors[i])
    else:
        for i in range(3):
            var y1:=b.position.y+b.size.y*i/3.0;var y2:=b.position.y+b.size.y*(i+1)/3.0;_clip(poly,PackedVector2Array([Vector2(b.position.x-2,y1),Vector2(b.end.x+2,y1),Vector2(b.end.x+2,y2),Vector2(b.position.x-2,y2)]),colors[i])
func _draw()->void:
    draw_rect(Rect2(Vector2.ZERO,size),Color(0.035,0.12,0.20));hit_polygons.clear();feature_centers.clear()
    for feature in map_features:
        var iso:=_feature_iso(feature.get("properties",{}));if iso=="":continue
        var polys:Array=[];var total:=Vector2.ZERO;var n:=0
        for ring in _rings(feature):
            var p:=_poly(ring);if p.size()<3:continue
            var owner:=str(territories.get(iso,{"owner":"NEUTRAL"}).owner);_flag(p,owner)
            var border:=Color(1,0.82,0.08) if iso==selected_id or iso==source_id else Color(0.75,0.78,0.72);var width:=3.0 if iso==selected_id or iso==source_id else 1.0
            for i in range(p.size()):draw_line(p[i],p[(i+1)%p.size()],border,width,true)
            var bb:=_bounds(p);total+=bb.get_center();n+=1;polys.append(p)
        if not polys.is_empty():hit_polygons[iso]=polys;feature_centers[iso]=total/maxi(n,1)
    for iso in feature_centers.keys():
        var c:Vector2=feature_centers[iso];var t:Dictionary=territories[iso];var owner:=str(t.owner);var flag:=str(FLAGS.get(owner,"⚪"));var army:=int(float(t.army));var label:="%s %d"%[flag,army]
        draw_string_outline(ThemeDB.fallback_font,c-Vector2(45,-4),label,HORIZONTAL_ALIGNMENT_CENTER,90,14,3,Color.BLACK);draw_string(ThemeDB.fallback_font,c-Vector2(45,-4),label,HORIZONTAL_ALIGNMENT_CENTER,90,14,Color.WHITE)
func _hit(pos:Vector2)->String:
    for iso in hit_polygons.keys():
        for p in hit_polygons[iso]:
            if Geometry2D.is_point_in_polygon(pos,p):return iso
    return ""
func _choose(iso:String)->void:
    if iso=="":return
    selected_id=iso;country_clicked.emit(iso)
    var owner:=str(territories[iso].owner)
    if source_id=="":
        if owner=="RU":source_id=iso
    elif iso==source_id:source_id=""
    else:attack_requested.emit(source_id,iso);source_id=""
    queue_redraw()
func _gui_input(e:InputEvent)->void:
    if e is InputEventScreenTouch:
        if e.pressed:touches[e.index]=e.position
        else:
            if touches.size()<2:_choose(_hit(e.position))
            touches.erase(e.index);pinch_distance=0.0
    elif e is InputEventScreenDrag:
        touches[e.index]=e.position
        if touches.size()>=2:
            var vals:Array=touches.values();var d:float=Vector2(vals[0]).distance_to(Vector2(vals[1]));if pinch_distance>0.0:zoom=clampf(zoom*d/pinch_distance,0.8,4.0);pinch_distance=d;queue_redraw()
        else:pan+=e.relative;queue_redraw()
    elif e is InputEventMouseButton:
        if e.button_index==MOUSE_BUTTON_WHEEL_UP:zoom=minf(4.0,zoom*1.12);queue_redraw()
        elif e.button_index==MOUSE_BUTTON_WHEEL_DOWN:zoom=maxf(0.8,zoom/1.12);queue_redraw()
        elif e.button_index==MOUSE_BUTTON_LEFT and e.pressed:_choose(_hit(e.position))
    elif e is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):pan+=e.relative;queue_redraw()
