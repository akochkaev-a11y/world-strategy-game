extends Control

var world_map: Control
var player_country := ""
var refresh_clock := 0.0
var rows: Array = []
var totals: Dictionary = {}

const NAMES := {"RU":"Россия","UA":"Украина","PL":"Польша","FR":"Франция","DE":"Германия","GB":"Великобритания","CN":"Китай","IN":"Индия","IR":"Иран","JP":"Япония"}
const FLAGS := {"RU":"🇷🇺","UA":"🇺🇦","PL":"🇵🇱","FR":"🇫🇷","DE":"🇩🇪","GB":"🇬🇧","CN":"🇨🇳","IN":"🇮🇳","IR":"🇮🇷","JP":"🇯🇵"}

func setup(map: Control, selected: String) -> void:
    world_map = map
    player_country = selected
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    set_anchors_preset(Control.PRESET_RIGHT_WIDE)
    offset_left = -285.0
    offset_right = -12.0
    offset_top = 14.0
    offset_bottom = -14.0
    _refresh()

func _process(delta: float) -> void:
    refresh_clock += delta
    if refresh_clock >= 0.20:
        refresh_clock = 0.0
        _refresh()

func _refresh() -> void:
    if not world_map or not is_instance_valid(world_map): return
    rows.clear(); totals.clear()
    for iso in world_map.territories.keys():
        var t: Dictionary = world_map.territories[iso]
        var owner := str(t.owner)
        if owner == "NEUTRAL": continue
        var army := int(float(t.army))
        rows.append({"owner":owner,"army":army})
        totals[owner] = int(totals.get(owner, 0)) + army
    for a in world_map.armies:
        var owner := str(a.owner)
        if owner != "NEUTRAL": totals[owner] = int(totals.get(owner, 0)) + int(float(a.amount))
    rows.sort_custom(func(a,b):
        var ta := int(totals.get(str(a.owner),0)); var tb := int(totals.get(str(b.owner),0))
        if ta == tb:
            if str(a.owner) == str(b.owner): return int(a.army) > int(b.army)
            return str(a.owner) < str(b.owner)
        return ta > tb
    )
    queue_redraw()

func _draw() -> void:
    draw_style_box(_glass_box(), Rect2(Vector2.ZERO,size))
    draw_string(ThemeDB.fallback_font,Vector2(16,31),"ВОЕННЫЙ БАЛАНС",HORIZONTAL_ALIGNMENT_CENTER,int(size.x)-32,18,Color(0.93,0.97,1.0))
    draw_line(Vector2(14,43),Vector2(size.x-14,43),Color(0.35,0.72,0.95,0.32),1.0)
    var y := 68.0
    var last_owner := ""
    for i in range(rows.size()):
        if y > size.y-14.0: break
        var r:Dictionary=rows[i]; var owner:=str(r.owner); var total:=int(totals.get(owner,0))
        if owner != last_owner and last_owner != "":
            draw_line(Vector2(16,y-12),Vector2(size.x-16,y-12),Color(0.30,0.48,0.62,0.20),1.0)
        var color:=Color(1.0,0.83,0.28) if owner==player_country else Color(0.90,0.95,0.99)
        var text := "%s %s (%d)" % [str(FLAGS.get(owner,"")),str(NAMES.get(owner,owner)),total]
        if owner==player_country: draw_rect(Rect2(Vector2(8,y-17),Vector2(size.x-16,22)),Color(0.95,0.72,0.12,0.08),true)
        draw_string(ThemeDB.fallback_font,Vector2(18,y),text,HORIZONTAL_ALIGNMENT_LEFT,205,14,color)
        draw_string(ThemeDB.fallback_font,Vector2(size.x-52,y),str(int(r.army)),HORIZONTAL_ALIGNMENT_RIGHT,36,14,color)
        y+=19.0; last_owner=owner

func _glass_box() -> StyleBoxFlat:
    var box:=StyleBoxFlat.new()
    box.bg_color=Color(0.012,0.032,0.055,0.88)
    box.border_color=Color(0.30,0.66,0.88,0.36)
    box.set_border_width_all(1)
    box.corner_radius_top_left=14;box.corner_radius_top_right=14;box.corner_radius_bottom_left=14;box.corner_radius_bottom_right=14
    return box
