extends Control

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
    chooser.set_anchors_preset(Control.PRESET_CENTER)
    chooser.position = Vector2(330, 90)
    chooser.size = Vector2(620, 540)
    add_child(chooser)
    var box := VBoxContainer.new()
    chooser.add_child(box)
    var title := Label.new()
    title.text = "Выберите страну"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.add_theme_font_size_override("font_size", 28)
    box.add_child(title)
    for iso in ACTIVE_COUNTRIES.keys():
        var b := Button.new()
        b.text = "%s  %s" % [FLAGS.get(iso, ""), ACTIVE_COUNTRIES[iso]]
        b.custom_minimum_size = Vector2(560, 40)
        b.add_theme_font_size_override("font_size", 20)
        b.pressed.connect(_start_game.bind(str(iso)))
        box.add_child(b)

func _start_game(selected: String) -> void:
    if is_instance_valid(chooser): chooser.queue_free()
    world_map = preload("res://world_map.gd").new()
    add_child(world_map)
    world_map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    world_map.setup(ACTIVE_COUNTRIES, selected)
    started = true

func _process(delta: float) -> void:
    if not started: return
    army_clock += delta
    while army_clock >= 1.0:
        army_clock -= 1.0
        if world_map and is_instance_valid(world_map): world_map.grow_armies()
