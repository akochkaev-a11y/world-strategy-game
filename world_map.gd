extends Control

signal country_clicked(country_id: String)

var countries: Dictionary = {}
var selected_id: String = ""
var polygons: Dictionary = {}
var colors: Dictionary = {}

func setup(data: Dictionary, selected: String) -> void:
    countries = data
    selected_id = selected
    mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    queue_redraw()

func set_selected(id: String) -> void:
    selected_id = id
    queue_redraw()

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_STOP
    queue_redraw()

func _notification(what: int) -> void:
    if what == NOTIFICATION_RESIZED:
        queue_redraw()

func _poly(points: Array[Vector2]) -> PackedVector2Array:
    var out := PackedVector2Array()
    for p in points:
        out.append(Vector2(p.x * size.x, p.y * size.y))
    return out

func _country_shapes() -> Dictionary:
    return {
        "GB": [Vector2(0.155,0.30),Vector2(0.135,0.34),Vector2(0.14,0.40),Vector2(0.125,0.46),Vector2(0.15,0.52),Vector2(0.18,0.47),Vector2(0.18,0.39),Vector2(0.17,0.34)],
        "FR": [Vector2(0.17,0.48),Vector2(0.25,0.46),Vector2(0.29,0.53),Vector2(0.25,0.63),Vector2(0.18,0.60),Vector2(0.15,0.53)],
        "DE": [Vector2(0.29,0.42),Vector2(0.36,0.42),Vector2(0.39,0.50),Vector2(0.35,0.56),Vector2(0.29,0.53),Vector2(0.27,0.48)],
        "TR": [Vector2(0.42,0.64),Vector2(0.53,0.62),Vector2(0.61,0.68),Vector2(0.55,0.73),Vector2(0.44,0.72),Vector2(0.40,0.68)],
        "RU": [Vector2(0.36,0.27),Vector2(0.48,0.19),Vector2(0.62,0.18),Vector2(0.76,0.24),Vector2(0.91,0.29),Vector2(0.96,0.40),Vector2(0.88,0.49),Vector2(0.75,0.48),Vector2(0.67,0.55),Vector2(0.55,0.53),Vector2(0.47,0.48),Vector2(0.40,0.42),Vector2(0.35,0.35)],
        "CN": [Vector2(0.59,0.54),Vector2(0.70,0.49),Vector2(0.79,0.54),Vector2(0.82,0.64),Vector2(0.75,0.73),Vector2(0.63,0.72),Vector2(0.55,0.65)],
        "IN": [Vector2(0.55,0.70),Vector2(0.64,0.71),Vector2(0.68,0.78),Vector2(0.63,0.90),Vector2(0.56,0.82),Vector2(0.52,0.75)],
        "JP": [Vector2(0.88,0.56),Vector2(0.91,0.60),Vector2(0.90,0.66),Vector2(0.87,0.70),Vector2(0.85,0.65),Vector2(0.86,0.60)]
    }

func _land_mass() -> PackedVector2Array:
    return _poly([
        Vector2(0.09,0.28),Vector2(0.17,0.20),Vector2(0.29,0.18),Vector2(0.37,0.21),Vector2(0.47,0.15),Vector2(0.62,0.13),Vector2(0.79,0.18),Vector2(0.94,0.27),Vector2(0.98,0.40),Vector2(0.93,0.51),Vector2(0.84,0.54),Vector2(0.81,0.72),Vector2(0.70,0.79),Vector2(0.64,0.92),Vector2(0.52,0.87),Vector2(0.46,0.72),Vector2(0.37,0.68),Vector2(0.30,0.63),Vector2(0.23,0.67),Vector2(0.15,0.60),Vector2(0.10,0.48),Vector2(0.12,0.39)
    ])

func _draw() -> void:
    draw_rect(Rect2(Vector2.ZERO, size), Color(0.025,0.075,0.13,1.0))
    for x in range(0, 11):
        var px := size.x * float(x) / 10.0
        draw_line(Vector2(px,0),Vector2(px,size.y),Color(0.10,0.22,0.30,0.45),1.0)
    for y in range(0, 9):
        var py := size.y * float(y) / 8.0
        draw_line(Vector2(0,py),Vector2(size.x,py),Color(0.10,0.22,0.30,0.45),1.0)
    draw_colored_polygon(_land_mass(), Color(0.13,0.18,0.17,1.0))
    var shapes := _country_shapes()
    polygons.clear()
    colors = {"RU":Color(0.18,0.34,0.55,1),"DE":Color(0.27,0.38,0.48,1),"FR":Color(0.30,0.39,0.52,1),"GB":Color(0.29,0.35,0.50,1),"TR":Color(0.48,0.31,0.18,1),"CN":Color(0.52,0.25,0.20,1),"IN":Color(0.48,0.35,0.20,1),"JP":Color(0.47,0.23,0.26,1)}
    for id in shapes.keys():
        var poly := _poly(shapes[id])
        polygons[id] = poly
        var fill: Color = colors.get(id, Color(0.22,0.30,0.28,1.0))
        if id == selected_id:
            fill = Color(0.15,0.62,0.30,1.0)
        draw_colored_polygon(poly, fill)
        for i in range(poly.size()):
            draw_line(poly[i], poly[(i+1)%poly.size()], Color(0.78,0.86,0.86,0.75), 2.0)
        var center := Vector2.ZERO
        for p in poly:
            center += p
        center /= max(1, poly.size())
        var name := str(countries.get(id, {}).get("name", id))
        var power := int(_total_power(countries.get(id, {})))
        draw_string(ThemeDB.fallback_font, center - Vector2(0,7), name, HORIZONTAL_ALIGNMENT_CENTER, 105, 14, Color(0.95,0.98,0.98,1))
        draw_string(ThemeDB.fallback_font, center + Vector2(0,10), "%dk" % int(power / 1000), HORIZONTAL_ALIGNMENT_CENTER, 75, 11, Color(0.80,0.90,0.90,0.9))
    draw_string(ThemeDB.fallback_font, Vector2(18,28), "ЕВРОПА И ЕВРАЗИЯ", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.92,0.96,0.98,1))
    draw_string(ThemeDB.fallback_font, Vector2(18,size.y-18), "Нажимайте на страну: войска, дипломатия, помощь и другие действия", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.78,0.86,0.90,1))

func _total_power(c: Dictionary) -> float:
    var total := 0.0
    for key in ["army","air","navy","def","missile"]:
        total += float(c.get(key,0.0))
    return total

func _gui_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        for id in polygons.keys():
            if Geometry2D.is_point_in_polygon(event.position, polygons[id]):
                country_clicked.emit(id)
                accept_event()
                return

# Build trigger after removing the accidental EOF marker.
