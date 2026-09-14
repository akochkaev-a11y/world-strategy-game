extends Control

signal country_clicked(country_id: String)

const GEOJSON_PATH := "res://eurasia_countries.json"
const LON_MIN := -12.0
const LON_MAX := 150.0
const LAT_MIN := 5.0
const LAT_MAX := 76.0

var countries: Dictionary = {}
var selected_id: String = ""
var map_features: Array = []
var hit_polygons: Dictionary = {}

const FLAG_COLORS := {
    "RU": [Color.WHITE, Color(0.05,0.25,0.70), Color(0.78,0.05,0.08)],
    "FR": [Color(0.05,0.20,0.62), Color.WHITE, Color(0.85,0.08,0.10)],
    "DE": [Color(0.05,0.05,0.05), Color(0.78,0.05,0.08), Color(0.95,0.72,0.05)],
    "GB": [Color(0.05,0.18,0.52), Color.WHITE, Color(0.75,0.05,0.08)],
    "TR": [Color(0.82,0.05,0.08), Color.WHITE, Color(0.82,0.05,0.08)],
    "CN": [Color(0.82,0.05,0.08), Color(0.95,0.78,0.05), Color(0.82,0.05,0.08)],
    "IN": [Color(0.95,0.45,0.08), Color.WHITE, Color(0.08,0.55,0.20)],
    "JP": [Color.WHITE, Color(0.82,0.05,0.12), Color.WHITE],
    "IT": [Color(0.05,0.55,0.25), Color.WHITE, Color(0.82,0.05,0.08)],
    "ES": [Color(0.75,0.05,0.08), Color(0.95,0.72,0.05), Color(0.75,0.05,0.08)],
    "PL": [Color.WHITE, Color.WHITE, Color(0.82,0.08,0.16)],
    "UA": [Color(0.05,0.35,0.72), Color(0.05,0.35,0.72), Color(0.95,0.78,0.08)],
    "BY": [Color(0.80,0.08,0.10), Color(0.80,0.08,0.10), Color(0.10,0.52,0.20)],
    "KZ": [Color(0.10,0.65,0.78), Color(0.95,0.78,0.08), Color(0.10,0.65,0.78)],
    "IR": [Color(0.10,0.55,0.25), Color.WHITE, Color(0.78,0.08,0.10)],
    "SA": [Color(0.05,0.45,0.20), Color.WHITE, Color(0.05,0.45,0.20)],
    "PK": [Color(0.05,0.35,0.16), Color.WHITE, Color(0.05,0.35,0.16)],
    "KR": [Color.WHITE, Color(0.75,0.08,0.12), Color(0.08,0.20,0.55)],
    "KP": [Color(0.05,0.25,0.65), Color(0.82,0.05,0.10), Color(0.05,0.25,0.65)]
}

func setup(data: Dictionary, selected: String) -> void:
    countries=data; selected_id=selected; mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND; _load_geojson(); queue_redraw()
func set_selected(id:String)->void: selected_id=id; queue_redraw()
func _ready()->void: mouse_filter=Control.MOUSE_FILTER_STOP; _load_geojson(); queue_redraw()
func _notification(what:int)->void:
    if what==NOTIFICATION_RESIZED: queue_redraw()

func _load_geojson()->void:
    if not map_features.is_empty() or not FileAccess.file_exists(GEOJSON_PATH): return
    var file:=FileAccess.open(GEOJSON_PATH,FileAccess.READ)
    if file==null: return
    var parsed=JSON.parse_string(file.get_as_text())
    if typeof(parsed)!=TYPE_DICTIONARY: return
    for feature in parsed.get("features",[]):
        var props:Dictionary=feature.get("properties",{})
        var continent:=str(props.get("CONTINENT","")); var bbox:Array=feature.get("bbox",[]); var touches:=true
        if bbox.size()>=4: touches=float(bbox[2])>=LON_MIN and float(bbox[0])<=LON_MAX and float(bbox[3])>=LAT_MIN and float(bbox[1])<=LAT_MAX
        if touches and (continent=="Europe" or continent=="Asia" or str(props.get("ISO_A2","")) in ["RU","TR"]): map_features.append(feature)

func _project(lon:float,lat:float)->Vector2: return Vector2((lon-LON_MIN)/(LON_MAX-LON_MIN)*size.x,(LAT_MAX-lat)/(LAT_MAX-LAT_MIN)*size.y)
func _geometry_rings(feature:Dictionary)->Array:
    var geometry:Dictionary=feature.get("geometry",{}); var kind:=str(geometry.get("type","")); var coords:Array=geometry.get("coordinates",[]); var rings:Array=[]
    if kind=="Polygon" and not coords.is_empty(): rings.append(coords[0])
    elif kind=="MultiPolygon":
        for polygon in coords:
            if not polygon.is_empty(): rings.append(polygon[0])
    return rings
func _screen_poly(ring:Array)->PackedVector2Array:
    var out:=PackedVector2Array()
    for point in ring:
        if point.size()>=2: out.append(_project(float(point[0]),float(point[1])))
    return out

func _draw_flag_polygon(poly:PackedVector2Array, iso:String)->void:
    if not FLAG_COLORS.has(iso): draw_colored_polygon(poly,Color(0.32,0.35,0.32)); return
    var colors:Array=FLAG_COLORS[iso]
    var min_y:=INF; var max_y:=-INF
    for p in poly: min_y=minf(min_y,p.y); max_y=maxf(max_y,p.y)
    var h:float=max_y-min_y
    for band in range(3):
        var y1:=min_y+h*band/3.0; var y2:=min_y+h*(band+1)/3.0
        var rect:=PackedVector2Array([Vector2(-10,y1),Vector2(size.x+10,y1),Vector2(size.x+10,y2),Vector2(-10,y2)])
        for clipped in Geometry2D.intersect_polygons(poly,rect):
            if clipped.size()>=3: draw_colored_polygon(clipped,colors[band])

func _draw()->void:
    draw_rect(Rect2(Vector2.ZERO,size),Color(0.035,0.12,0.20,1.0)); hit_polygons.clear()
    for feature in map_features:
        var props:Dictionary=feature.get("properties",{}); var iso:=str(props.get("ISO_A2","")); var feature_polys:Array=[]
        for ring in _geometry_rings(feature):
            var poly:=_screen_poly(ring)
            if poly.size()<3: continue
            _draw_flag_polygon(poly,iso)
            var border:=Color(0.88,0.90,0.82,0.9); var width:=1.0
            if iso==selected_id: border=Color(1.0,0.82,0.08); width=3.0
            for i in range(poly.size()): draw_line(poly[i],poly[(i+1)%poly.size()],border,width,true)
            feature_polys.append(poly)
        if countries.has(iso) and not feature_polys.is_empty(): hit_polygons[iso]=feature_polys
    _draw_active_labels()
    draw_string(ThemeDB.fallback_font,Vector2(14,25),"ПОЛИТИЧЕСКАЯ КАРТА ЕВРАЗИИ",HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color.WHITE)

func _draw_active_labels()->void:
    var labels={"GB":Vector2(-3,55),"FR":Vector2(2,46),"DE":Vector2(10.5,51),"ES":Vector2(-4,40),"IT":Vector2(12.5,42),"PL":Vector2(19,52),"UA":Vector2(31,49),"BY":Vector2(28,54),"TR":Vector2(35,39),"RU":Vector2(67,60),"KZ":Vector2(68,48),"IR":Vector2(53,32),"SA":Vector2(45,23),"PK":Vector2(69,29),"IN":Vector2(79,22.5),"CN":Vector2(104,35),"KP":Vector2(127,40),"KR":Vector2(128,36),"JP":Vector2(138,37)}
    for iso in labels.keys():
        if not countries.has(iso): continue
        var pos:=_project(labels[iso].x,labels[iso].y); var title:=str(countries[iso].get("name",iso)); draw_string(ThemeDB.fallback_font,pos-Vector2(38,0),title,HORIZONTAL_ALIGNMENT_CENTER,76,11,Color.WHITE)

func _gui_input(event:InputEvent)->void:
    if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
        for iso in hit_polygons.keys():
            for poly in hit_polygons[iso]:
                if Geometry2D.is_point_in_polygon(event.position,poly): country_clicked.emit(iso); accept_event(); return
