extends Control

const ACTIVE_ORDER := ["RU","UA","PL","FR","DE","GB","CN","IN","IR","JP"]
const ACTIVE_COUNTRIES := {
    "RU":"Россия", "UA":"Украина", "PL":"Польша", "FR":"Франция", "DE":"Германия",
    "GB":"Великобритания", "CN":"Китай", "IN":"Индия", "IR":"Иран", "JP":"Япония"
}
const FLAGS := {"RU":"🇷🇺","UA":"🇺🇦","PL":"🇵🇱","FR":"🇫🇷","DE":"🇩🇪","GB":"🇬🇧","CN":"🇨🇳","IN":"🇮🇳","IR":"🇮🇷","JP":"🇯🇵"}

var world_map: Control
var army_clock := 0.0
var started := false
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
    started = true

func _process(delta: float) -> void:
    if not started:
        return
    army_clock += delta
    while army_clock >= 1.0:
        army_clock -= 1.0
        if world_map and is_instance_valid(world_map):
            world_map.grow_armies()
