extends Control

var world_map: Control
var player_country := ""
var refresh_clock := 0.0
var rows: Array = []

const NAMES := {"RU":"Россия","UA":"Украина","PL":"Польша","FR":"Франция","DE":"Германия","GB":"Великобритания","CN":"Китай","IN":"Индия","IR":"Иран","JP":"Япония"}
const FLAGS := {"RU":"🇷🇺","UA":"🇺🇦","PL":"🇵🇱","FR":"🇫🇷","DE":"🇩🇪","GB":"🇬🇧","CN":"🇨🇳","IN":"🇮🇳","IR":"🇮🇷","JP":"🇯🇵"}

func setup(map: Control, selected: String) -> void:
    world_map = map
    player_country = selected
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    set_anchors_preset(Control.PRESET_RIGHT_WIDE)
    offset_left = -230.0
    offset_right = -10.0
    offset_top = 14.0
    offset_bottom = -14.0
    _refresh()

func _process(delta: float) -> void:
    refresh_clock += delta
    if refresh_clock >= 0.25:
        refresh_clock = 0.0
        _refresh()

func _refresh() -> void:
    if not world_map or not is_instance_valid(world_map):
        return
    rows.clear()
    for iso in world_map.territories.keys():
        var t: Dictionary = world_map.territories[iso]
        var owner := str(t.owner)
        if owner == "NEUTRAL":
            continue
        rows.append({"owner":owner,"army":int(float(t.army))})
    rows.sort_custom(func(a,b): return int(a.army) > int(b.army))
    queue_redraw()

func _draw() -> void:
    var panel := Rect2(Vector2.ZERO, size)
    draw_rect(panel, Color(0.015,0.035,0.06,0.78), true)
    draw_rect(panel, Color(0.55,0.68,0.78,0.30), false, 1.0)
    draw_string(ThemeDB.fallback_font, Vector2(12,28), "ВОЕННЫЙ БАЛАНС", HORIZONTAL_ALIGNMENT_CENTER, int(size.x)-24, 17, Color.WHITE)
    draw_line(Vector2(12,38), Vector2(size.x-12,38), Color(0.55,0.68,0.78,0.32), 1.0)
    var y := 62.0
    for i in range(rows.size()):
        if y > size.y - 12.0:
            break
        var r: Dictionary = rows[i]
        var owner := str(r.owner)
        var name := str(NAMES.get(owner, owner))
        var flag := str(FLAGS.get(owner, ""))
        var text := "%s %s" % [flag, name]
        var color := Color(1.0,0.84,0.30) if owner == player_country else Color(0.91,0.94,0.97)
        if i < 3:
            draw_circle(Vector2(13,y-5), 3.5, Color(1.0,0.78,0.18,0.9))
        draw_string(ThemeDB.fallback_font, Vector2(22,y), text, HORIZONTAL_ALIGNMENT_LEFT, 142, 14, color)
        draw_string(ThemeDB.fallback_font, Vector2(166,y), str(int(r.army)), HORIZONTAL_ALIGNMENT_RIGHT, 42, 14, color)
        y += 20.0
