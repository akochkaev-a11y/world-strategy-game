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
        "GB": [Vector2(0.12,0.27),Vector2(0.105,0.33),Vector2(0.112,0.39),Vector2(0.10,0.45),Vector2(0.125,0.50),Vector2(0.15,0.47),Vector2(0.158,0.39),Vector2(0.148,0.32)],
        "FR": [Vector2(0.17,0.46),Vector2(0.225,0.445),Vector2(0.27,0.49),Vector2(0.265,0.56),Vector2(0.225,0.61),Vector2(0.18,0.585),Vector2(0.155,0.52)],
        "DE": [Vector2(0.275,0.405),Vector2(0.33,0.40),Vector2(0.355,0.445),Vector2(0.35,0.51),Vector2(0.31,0.545),Vector2(0.275,0.515),Vector2(0.26,0.46)],
        "TR": [Vector2(0.395,0.61),Vector2(0.49,0.595),Vector2(0.57,0.63),Vector2(0.56,0.675),Vector2(0.485,0.695),Vector2(0.415,0.68),Vector2(0.38,0.645)],
        "RU": [Vector2(0.34,0.255),Vector2(0.42,0.205),Vector2(0.53,0.18),Vector2(0.66,0.185),Vector2(0.77,0.215),Vector2(0.89,0.26),Vector2(0.955,0.325),Vector2(0.94,0.40),Vector2(0.865,0.455),Vector2(0.77,0.46),Vector2(0.69,0.50),Vector2(0.60,0.515),Vector2(0.515,0.485),Vector2(0.455,0.455),Vector2(0.40,0.42),Vector2(0.365,0.36),Vector2(0.345,0.31)],
        "CN": [Vector2(0.565,0.525),Vector2(0.655,0.485),Vector2(0.745,0.505),Vector2(0.80,0.555),Vector2(0.805,0.63),Vector2(0.755,0.695),Vector2(0.665,0.72),Vector2(0.59,0.69),Vector2(0.545,0.62)],
        "IN": [Vector2(0.535,0.68),Vector2(0.605,0.69),Vector2(0.655,0.75),Vector2(0.64,0.825),Vector2(0.59,0.905),Vector2(0.555,0.84),Vector2(0.52,0.755)],
        "JP": [Vector2(0.865,0.555),Vector2(0.892,0.575),Vector2(0.905,0.615),Vector2(0.895,0.66),Vector2(0.87,0.705),Vector2(0.85,0.67),Vector2(0.852,0.61)]
    }

func _land_mass() -> PackedVector2Array:
    return _poly([
        Vector2(0.075,0.245),Vector2(0.16,0.19),Vector2(0.255,0.17),Vector2(0.35,0.19),Vector2(0.43,0.15),Vector2(0.56,0.12),Vector2(0.70,0.14),Vector2(0.84,0.19),Vector2(0.95,0.255),Vector2(0.985,0.35),Vector2(0.955,0.46),Vector2(0.88,0.52),Vector2(0.83,0.63),Vector2(0.78,0.74),Vector2(0.69,0.79),Vector2(0.64,0.92),Vector2(0.56,0.89),Vector2(0.50,0.76),Vector2(0.43,0.70),Vector2(0.34,0.66),Vector2(0.27,0.64),Vector2(0.19,0.66),Vector2(0.12,0.58),Vector2(0.08,0.48),Vector2(0.09,0.36)
    ])

func _flag_color(id: String) -> Color:
    match id:
        "RU": return Color(0.10,0.35,0.72,1.0)
        "DE": return Color(0.92,0.72,0.10,1.0)
        "FR": return Color(0.08,0.28,0.67,1.0)
        "GB": return Color(0.08,0.22,0.55,1.0)
        "TR": return Color(0.78,0.06,0.08,1.0)
        "CN": return Color(0.78,0.05,0.06,1.0)
        "IN": return Color(0.95,0.52,0.10,1.0)
        "JP": return Color(0.92,0.92,0.92,1.0)
        _: return Color(0.30,0.36,0.34,1.0)

func _draw_flag_mark(id: String, center: Vector2) -> void:
    var w := 34.0
    var h := 18.0
    var x := center.x - w * 0.5
    var y := center.y - 31.0
    match id:
        "RU":
            draw_rect(Rect2(x,y,w,h/3.0),Color.WHITE)
            draw_rect(Rect2(x,y+h/3.0,w,h/3.0),Color(0.10,0.35,0.72))
            draw_rect(Rect2(x,y+2.0*h/3.0,w,h/3.0),Color(0.78,0.08,0.10))
        "DE":
            draw_rect(Rect2(x,y,w,h/3.0),Color(0.03,0.03,0.03))
            draw_rect(Rect2(x,y+h/3.0,w,h/3.0),Color(0.78,0.06,0.08))
            draw_rect(Rect2(x,y+2.0*h/3.0,w,h/3.0),Color(0.95,0.72,0.08))
        "FR":
            draw_rect(Rect2(x,y,w/3.0,h),Color(0.08,0.28,0.67))
            draw_rect(Rect2(x+w/3.0,y,w/3.0,h),Color.WHITE)
            draw_rect(Rect2(x+2.0*w/3.0,y,w/3.0,h),Color(0.82,0.08,0.10))
        "GB":
            draw_rect(Rect2(x,y,w,h),Color(0.08,0.22,0.55))
            draw_line(Vector2(x,y),Vector2(x+w,y+h),Color.WHITE,3.0)
            draw_line(Vector2(x+w,y),Vector2(x,y+h),Color.WHITE,3.0)
            draw_line(Vector2(x+w*0.5,y),Vector2(x+w*0.5,y+h),Color(0.82,0.05,0.08),3.0)
            draw_line(Vector2(x,y+h*0.5),Vector2(x+w,y+h*0.5),Color(0.82,0.05,0.08),3.0)
        "TR":
            draw_rect(Rect2(x,y,w,h),Color(0.78,0.06,0.08))
            draw_circle(Vector2(x+13,y+9),5.0,Color.WHITE)
            draw_circle(Vector2(x+15,y+9),4.0,Color(0.78,0.06,0.08))
        "CN":
            draw_rect(Rect2(x,y,w,h),Color(0.78,0.05,0.06))
            draw_circle(Vector2(x+8,y+6),2.7,Color(1.0,0.82,0.08))
        "IN":
            draw_rect(Rect2(x,y,w,h/3.0),Color(0.95,0.52,0.10))
            draw_rect(Rect2(x,y+h/3.0,w,h/3.0),Color.WHITE)
            draw_rect(Rect2(x,y+2.0*h/3.0,w,h/3.0),Color(0.08,0.50,0.18))
        "JP":
            draw_rect(Rect2(x,y,w,h),Color.WHITE)
            draw_circle(Vector2(x+w*0.5,y+h*0.5),4.5,Color(0.78,0.05,0.08))
    draw_rect(Rect2(x,y,w,h),Color(0.05,0.05,0.05,0.8),false,1.0)

func _draw() -> void:
    draw_rect(Rect2(Vector2.ZERO, size), Color(0.025,0.075,0.13,1.0))
    for x in range(0, 11):
        var px := size.x * float(x) / 10.0
        draw_line(Vector2(px,0),Vector2(px,size.y),Color(0.10,0.22,0.30,0.35),1.0)
    for y in range(0, 9):
        var py := size.y * float(y) / 8.0
        draw_line(Vector2(0,py),Vector2(size.x,py),Color(0.10,0.22,0.30,0.35),1.0)

    draw_colored_polygon(_land_mass(), Color(0.12,0.16,0.15,1.0))
    var shapes := _country_shapes()
    polygons.clear()
    for id in shapes.keys():
        var poly := _poly(shapes[id])
        polygons[id] = poly
        var fill := _flag_color(id)
        draw_colored_polygon(poly, fill)
        var border_color := Color(1.0,0.80,0.18,1.0) if id == selected_id else Color(0.92,0.96,0.96,0.95)
        var border_width := 4.0 if id == selected_id else 2.0
        for i in range(poly.size()):
            draw_line(poly[i], poly[(i+1)%poly.size()], border_color, border_width)

        var center := Vector2.ZERO
        for p in poly:
            center += p
        center /= max(1, poly.size())
        _draw_flag_mark(id, center)
        var name := str(countries.get(id, {}).get("name", id))
        var power := int(_total_power(countries.get(id, {})))
        var text_color := Color(0.05,0.05,0.05,1.0) if id == "JP" or id == "DE" or id == "IN" else Color.WHITE
        draw_string(ThemeDB.fallback_font, center - Vector2(52,2), name, HORIZONTAL_ALIGNMENT_CENTER, 104, 14, text_color)
        draw_string(ThemeDB.fallback_font, center - Vector2(38,-15), "%dk" % int(power / 1000), HORIZONTAL_ALIGNMENT_CENTER, 76, 11, text_color)

    draw_string(ThemeDB.fallback_font, Vector2(18,28), "ЕВРОПА И ЕВРАЗИЯ", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.92,0.96,0.98,1))
    draw_string(ThemeDB.fallback_font, Vector2(18,size.y-18), "Нажмите на страну: войска, дипломатия, помощь", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.78,0.86,0.90,1))

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
