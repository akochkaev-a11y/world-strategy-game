extends Control

var world_map: Control
var player_country := ""
var refresh_clock := 0.0
var ranking: Array = []
var totals: Dictionary = {}
var territory_counts: Dictionary = {}

const NAMES := {"RU":"Россия","UA":"Украина","PL":"Польша","FR":"Франция","DE":"Германия","GB":"Великобритания","CN":"Китай","IN":"Индия","IR":"Иран","JP":"Япония"}
const FLAGS := {"RU":"🇷🇺","UA":"🇺🇦","PL":"🇵🇱","FR":"🇫🇷","DE":"🇩🇪","GB":"🇬🇧","CN":"🇨🇳","IN":"🇮🇳","IR":"🇮🇷","JP":"🇯🇵"}

func setup(map: Control, selected: String) -> void:
    world_map = map
    player_country = selected
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
    offset_left = 14.0
    offset_right = -14.0
    offset_top = -92.0
    offset_bottom = -12.0
    _refresh()

func _process(delta: float) -> void:
    refresh_clock += delta
    if refresh_clock >= 0.20:
        refresh_clock = 0.0
        _refresh()

func _refresh() -> void:
    if not world_map or not is_instance_valid(world_map): return
    totals.clear()
    territory_counts.clear()
    ranking.clear()
    for iso in world_map.territories.keys():
        var t: Dictionary = world_map.territories[iso]
        var owner: String = str(t.owner)
        if owner == "NEUTRAL": continue
        totals[owner] = int(totals.get(owner, 0)) + int(float(t.army))
        territory_counts[owner] = int(territory_counts.get(owner, 0)) + 1
    for a in world_map.armies:
        var owner: String = str(a.owner)
        if owner != "NEUTRAL": totals[owner] = int(totals.get(owner, 0)) + int(float(a.amount))
    for owner in totals.keys():
        ranking.append(str(owner))
    ranking.sort_custom(func(a,b):
        var ta: int = int(totals.get(str(a),0))
        var tb: int = int(totals.get(str(b),0))
        if ta == tb: return str(a) < str(b)
        return ta > tb
    )
    queue_redraw()

func _draw() -> void:
    draw_style_box(_glass_box(), Rect2(Vector2.ZERO,size))
    var count: int = ranking.size()
    if count <= 0: return
    var pad: float = 10.0
    var gap: float = 4.0
    var usable: float = size.x - pad * 2.0 - gap * float(maxi(count - 1,0))
    var cell_w: float = usable / float(count)
    for i in range(count):
        var owner: String = str(ranking[i])
        var total: int = int(totals.get(owner,0))
        var lands: int = int(territory_counts.get(owner,0))
        var x: float = pad + float(i) * (cell_w + gap)
        var rect := Rect2(Vector2(x,8.0),Vector2(cell_w,64.0))
        var player: bool = owner == player_country
        if player:
            draw_rect(rect,Color(0.95,0.70,0.12,0.10),true)
            draw_rect(rect,Color(1.0,0.82,0.30,0.78),false,1.4)
        elif i < 3:
            draw_rect(rect,Color(0.10,0.23,0.34,0.28),true)
        if i > 0:
            draw_line(Vector2(x-gap*0.5,17),Vector2(x-gap*0.5,63),Color(0.28,0.48,0.60,0.18),1.0)
        var flag: String = str(FLAGS.get(owner,""))
        var color: Color = Color(1.0,0.84,0.34) if player else Color(0.92,0.96,0.99)
        draw_string(ThemeDB.fallback_font,Vector2(x,32),flag,HORIZONTAL_ALIGNMENT_CENTER,int(cell_w),20,Color.WHITE)
        draw_string(ThemeDB.fallback_font,Vector2(x,55),"%d  •  %d тер." % [total,lands],HORIZONTAL_ALIGNMENT_CENTER,int(cell_w),15,color)
        if cell_w >= 92.0:
            var name: String = str(NAMES.get(owner,owner))
            draw_string(ThemeDB.fallback_font,Vector2(x,71),name,HORIZONTAL_ALIGNMENT_CENTER,int(cell_w),10,Color(0.64,0.73,0.80))

func _glass_box() -> StyleBoxFlat:
    var box:=StyleBoxFlat.new()
    box.bg_color=Color(0.008,0.024,0.041,0.90)
    box.border_color=Color(0.25,0.54,0.70,0.30)
    box.set_border_width_all(1)
    box.corner_radius_top_left=14
    box.corner_radius_top_right=14
    box.corner_radius_bottom_left=14
    box.corner_radius_bottom_right=14
    return box
