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
var match_time := 0.0
var timer_label: Label
var chooser: PanelContainer

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
    hint.text = "10 активных держав • 13 нейтральных стран • 23 игровые территории"
    hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    hint.modulate = Color(0.58, 0.68, 0.76)
    hint.add_theme_font_size_override("font_size", 14)
    box.add_child(hint)

    var tween := create_tween()
    tween.tween_property(chooser, "modulate:a", 1.0, 0.35)

func _start_game(selected: String) -> void:
    if is_instance_valid(chooser):
        chooser.queue_free()
    world_map = preload("res://optimized_world_map.gd").new()
    add_child(world_map)
    world_map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    world_map.setup(ACTIVE_COUNTRIES, selected)
    military_balance = preload("res://military_balance.gd").new()
    add_child(military_balance)
    military_balance.setup(world_map, selected)
    timer_label = Label.new()
    timer_label.position = Vector2(18,16)
    timer_label.size = Vector2(150,42)
    timer_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    timer_label.add_theme_font_size_override("font_size",22)
    timer_label.add_theme_color_override("font_color",Color(0.92,0.96,0.99))
    timer_label.add_theme_color_override("font_shadow_color",Color(0,0,0,0.85))
    timer_label.add_theme_constant_override("shadow_offset_x",2)
    timer_label.add_theme_constant_override("shadow_offset_y",2)
    add_child(timer_label)
    match_time = 0.0
    _update_timer()
    started = true

func _process(delta: float) -> void:
    if not started:
        return
    match_time += delta
    _update_timer()
    army_clock += delta
    while army_clock >= 1.0:
        army_clock -= 1.0
        if world_map and is_instance_valid(world_map):
            world_map.grow_armies()

func _update_timer() -> void:
    if not is_instance_valid(timer_label): return
    var total_seconds: int = int(match_time)
    var minutes: int = total_seconds / 60
    var seconds: int = total_seconds % 60
    timer_label.text = "%02d:%02d" % [minutes,seconds]
