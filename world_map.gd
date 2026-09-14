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

var active_colors := {
    "RU": Color(0.18, 0.34, 0.70),
    "GB": Color(0.10, 0.24, 0.58),
    "FR": Color(0.12, 0.30, 0.72),
    "DE": Color(0.20, 0.20, 0.20),
    "TR": Color(0.78, 0.12, 0.16),
    "CN": Color(0.82, 0.12, 0.12),
    "IN": Color(0.95, 0.48, 0.12),
    "JP": Color(0.92, 0.92, 0.90)
}

func setup(data: Dictionary, selected: String) -> void:
    countries = data
    selected_id = selected
    mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    _load_geojson()
    queue_redraw()

func set_selected(id: String) -> void:
    selected_id = id
    queue_redraw()

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_STOP
    _load_geojson()
    queue_redraw()

func _notification(what: int) -> void:
    if what == NOTIFICATION_RESIZED:
        queue_redraw()

func _load_geojson() -> void:
    if not map_features.is_empty():
        return
    if not FileAccess.file_exists(GEOJSON_PATH):
        return
    var file := FileAccess.open(GEOJSON_PATH, FileAccess.READ)
    if file == null:
        return
    var parsed = JSON.parse_string(file.get_as_text())
    if typeof(parsed) != TYPE_DICTIONARY:
        return
    for feature in parsed.get("features", []):
        var props: Dictionary = feature.get("properties", {})
        var continent := str(props.get("CONTINENT", ""))
        var bbox: Array = feature.get("bbox", [])
        var touches_view := true
        if bbox.size() >= 4:
            touches_view = float(bbox[2]) >= LON_MIN and float(bbox[0]) <= LON_MAX and float(bbox[3]) >= LAT_MIN and float(bbox[1]) <= LAT_MAX
        if touches_view and (continent == "Europe" or continent == "Asia" or str(props.get("ISO_A2", "")) in ["RU", "TR"]):
            map_features.append(feature)

func _project(lon: float, lat: float) -> Vector2:
    var x := (lon - LON_MIN) / (LON_MAX - LON_MIN) * size.x
    var y := (LAT_MAX - lat) / (LAT_MAX - LAT_MIN) * size.y
    return Vector2(x, y)

func _geometry_rings(feature: Dictionary) -> Array:
    var geometry: Dictionary = feature.get("geometry", {})
    var kind := str(geometry.get("type", ""))
    var coords: Array = geometry.get("coordinates", [])
    var rings: Array = []
    if kind == "Polygon":
        if not coords.is_empty():
            rings.append(coords[0])
    elif kind == "MultiPolygon":
        for polygon in coords:
            if not polygon.is_empty():
                rings.append(polygon[0])
    return rings

func _screen_poly(ring: Array) -> PackedVector2Array:
    var out := PackedVector2Array()
    for point in ring:
        if point.size() >= 2:
            out.append(_project(float(point[0]), float(point[1])))
    return out

func _draw() -> void:
    draw_rect(Rect2(Vector2.ZERO, size), Color(0.035, 0.12, 0.20, 1.0))
    for lon in range(0, 151, 20):
        var p1 := _project(float(lon), LAT_MIN)
        var p2 := _project(float(lon), LAT_MAX)
        draw_line(p1, p2, Color(0.18,0.31,0.39,0.32), 1.0)
    for lat in range(10, 76, 10):
        var p3 := _project(LON_MIN, float(lat))
        var p4 := _project(LON_MAX, float(lat))
        draw_line(p3, p4, Color(0.18,0.31,0.39,0.32), 1.0)

    hit_polygons.clear()
    for feature in map_features:
        var props: Dictionary = feature.get("properties", {})
        var iso := str(props.get("ISO_A2", ""))
        var fill := Color(0.38, 0.42, 0.38, 1.0)
        if active_colors.has(iso):
            fill = active_colors[iso]
        var border := Color(0.90, 0.91, 0.84, 0.92)
        var width := 1.2
        if iso == selected_id:
            border = Color(1.0, 0.82, 0.12, 1.0)
            width = 3.2
        var feature_polys: Array = []
        for ring in _geometry_rings(feature):
            var poly := _screen_poly(ring)
            if poly.size() < 3:
                continue
            draw_colored_polygon(poly, fill)
            for i in range(poly.size()):
                draw_line(poly[i], poly[(i + 1) % poly.size()], border, width, true)
            feature_polys.append(poly)
        if countries.has(iso) and not feature_polys.is_empty():
            hit_polygons[iso] = feature_polys

    _draw_active_labels()
    draw_string(ThemeDB.fallback_font, Vector2(14, 25), "ПОЛИТИЧЕСКАЯ КАРТА ЕВРАЗИИ", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)

func _draw_active_labels() -> void:
    var labels := {
        "GB": Vector2(-3.0, 55.0), "FR": Vector2(2.0, 46.0), "DE": Vector2(10.5, 51.0),
        "TR": Vector2(35.0, 39.0), "RU": Vector2(67.0, 60.0), "CN": Vector2(104.0, 35.0),
        "IN": Vector2(79.0, 22.5), "JP": Vector2(138.0, 37.0)
    }
    for iso in labels.keys():
        if not countries.has(iso):
            continue
        var pos := _project(labels[iso].x, labels[iso].y)
        var title := str(countries[iso].get("name", iso))
        draw_string(ThemeDB.fallback_font, pos - Vector2(45, 0), title, HORIZONTAL_ALIGNMENT_CENTER, 90, 12, Color(1,1,1,0.96))

func _gui_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        for iso in hit_polygons.keys():
            for poly in hit_polygons[iso]:
                if Geometry2D.is_point_in_polygon(event.position, poly):
                    country_clicked.emit(iso)
                    accept_event()
                    return
