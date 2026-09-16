extends Control

const ACTIVE_ORDER := ["RU","UA","PL","FR","DE","GB","CN","IN","IR","JP"]
const ACTIVE_COUNTRIES := {
    "RU":"Россия", "UA":"Украина", "PL":"Польша", "FR":"Франция", "DE":"Германия",
    "GB":"Великобритания", "CN":"Китай", "IN":"Индия", "IR":"Иран", "JP":"Япония"
}
const FLAGS := {"RU":"🇷🇺","UA":"🇺🇦","PL":"🇵🇱","FR":"🇫🇷","DE":"🇩🇪","GB":"🇬🇧","CN":"🇨🇳","IN":"🇮🇳","IR":"🇮🇷","JP":"🇯🇵"}

var world_map: Control
var military_balance: Control
var army_clock := 0.0
var started := false
var chooser: PanelContainer
var camera_touches: Dictionary = {}
var camera_last_midpoint := Vector2.ZERO
var camera_last_distance := 0.0

func _ready() -> void:
    _show_country_chooser()

func _show_country_chooser() -> void:
    chooser = PanelContainer.new()
    chooser.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    chooser.modulate = Color(1, 1, 1, 0)
    add_child(chooser)

    var center := CenterContainer.new()
    center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    chooser.add_child(center)

    var box := VBoxContainer.new()
    box.custom_minimum_size = Vector2(760, 560)
    box.alignment = BoxContainer.ALIGNMENT_CENTER
    box.add_theme_constant_override("separation", 18)
    center.add_child(box)

    var title := Label.new()
    title.text = "ВЫБЕРИТЕ ДЕРЖАВУ"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.add_theme_font_size_override("font_size", 34)
    box.add_child(title)

    var subtitle := Label.new()
    subtitle.text = "Ведите страну к господству на карте Евразии"
    subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    subtitle.modulate = Color(0.72, 0.80, 0.88)
    subtitle.add_theme_font_size_override("font_size", 17)
    box.add_child(subtitle)

    var grid := GridContainer.new()
    grid.columns = 5
    grid.add_theme_constant_override("h_separation", 12)
    grid.add_theme_constant_override("v_separation", 12)
    box.add_child(grid)

    for iso in ACTIVE_ORDER:
        var b := Button.new()
        b.text = "%s\n%s" % [str(FLAGS.get(iso, "")), str(ACTIVE_COUNTRIES.get(iso, iso))]
        b.custom_minimum_size = Vector2(138, 145)
        b.add_theme_font_size_override("font_size", 19)
        b.tooltip_text = "Играть за %s" % str(ACTIVE_COUNTRIES.get(iso, iso))
        b.pressed.connect(_start_game.bind(iso))
        grid.add_child(b)

    var hint := Label.new()
    hint.text = "10 активных держав • 20 нейтральных стран • остальные территории исключены"
    hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    hint.modulate = Color(0.58, 0.68, 0.76)
    hint.add_theme_font_size_override("font_size", 14)
    box.add_child(hint)

    var tween := create_tween()
    tween.tween_property(chooser, "modulate:a", 1.0, 0.35)

func _start_game(selected: String) -> void:
    if is_instance_valid(chooser):
        chooser.queue_free()
    world_map = preload("res://world_map.gd").new()
    add_child(world_map)
    world_map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    world_map.setup(ACTIVE_COUNTRIES, selected)
    military_balance = preload("res://military_balance.gd").new()
    add_child(military_balance)
    military_balance.setup(world_map, selected)
    started = true

func _process(delta: float) -> void:
    if not started:
        return
    army_clock += delta
    while army_clock >= 1.0:
        army_clock -= 1.0
        if world_map and is_instance_valid(world_map):
            world_map.grow_armies()

func _input(event: InputEvent) -> void:
    if not started or not world_map or not is_instance_valid(world_map):
        return
    if event is InputEventScreenTouch:
        if event.pressed:
            camera_touches[event.index] = event.position
            if camera_touches.size() == 2:
                _begin_camera_gesture()
                world_map.drag_source = ""
                world_map.touches.clear()
                get_viewport().set_input_as_handled()
        else:
            if camera_touches.has(event.index):
                camera_touches.erase(event.index)
            if camera_touches.size() < 2:
                camera_last_distance = 0.0
                camera_last_midpoint = Vector2.ZERO
            if camera_touches.size() == 1:
                world_map.drag_source = ""
                world_map.touches.clear()
    elif event is InputEventScreenDrag:
        camera_touches[event.index] = event.position
        if camera_touches.size() == 2:
            _update_camera_gesture()
            world_map.drag_source = ""
            world_map.touches.clear()
            get_viewport().set_input_as_handled()

func _begin_camera_gesture() -> void:
    var vals:Array = camera_touches.values()
    if vals.size() != 2:
        return
    var a:Vector2 = Vector2(vals[0])
    var b:Vector2 = Vector2(vals[1])
    camera_last_midpoint = (a+b)*0.5
    camera_last_distance = a.distance_to(b)

func _update_camera_gesture() -> void:
    var vals:Array = camera_touches.values()
    if vals.size() != 2:
        return
    var a:Vector2 = Vector2(vals[0])
    var b:Vector2 = Vector2(vals[1])
    var midpoint:Vector2 = (a+b)*0.5
    var distance:float = a.distance_to(b)
    if camera_last_distance <= 0.0:
        camera_last_midpoint = midpoint
        camera_last_distance = distance
        return

    var old_zoom:float = float(world_map.zoom)
    var new_zoom:float = clampf(old_zoom * distance / camera_last_distance,1.0,2.8)
    var pan_delta:Vector2 = midpoint-camera_last_midpoint
    world_map.zoom = new_zoom

    if new_zoom <= 1.001:
        world_map.zoom = 1.0
        world_map.pan = Vector2.ZERO
    else:
        var current_pan:Vector2 = Vector2(world_map.pan)
        var focus_from_center:Vector2 = camera_last_midpoint-world_map.size*0.5
        if old_zoom > 0.0 and not is_equal_approx(new_zoom,old_zoom):
            current_pan -= focus_from_center*(new_zoom/old_zoom-1.0)
        current_pan += pan_delta
        world_map.pan = _clamp_camera_pan(current_pan,new_zoom)

    camera_last_midpoint = midpoint
    camera_last_distance = distance
    world_map.queue_redraw()

func _clamp_camera_pan(value:Vector2,current_zoom:float) -> Vector2:
    if current_zoom <= 1.0:
        return Vector2.ZERO
    var half_extra:Vector2 = world_map.size*(current_zoom-1.0)*0.5
    var margin:=Vector2(48.0,48.0)
    var limit_x:float = maxf(0.0,half_extra.x-margin.x)
    var limit_y:float = maxf(0.0,half_extra.y-margin.y)
    return Vector2(clampf(value.x,-limit_x,limit_x),clampf(value.y,-limit_y,limit_y))
