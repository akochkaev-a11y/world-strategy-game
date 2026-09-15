extends Control

const ACTIVE_COUNTRIES := {
    "RU":"Россия", "UA":"Украина", "PL":"Польша", "FR":"Франция", "DE":"Германия",
    "GB":"Великобритания", "CN":"Китай", "IN":"Индия", "IR":"Иран", "JP":"Япония"
}

var world_map: Control
var army_clock: float = 0.0

func _ready() -> void:
    world_map = preload("res://world_map.gd").new()
    world_map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(world_map)
    world_map.setup(ACTIVE_COUNTRIES, "RU")

func _process(delta: float) -> void:
    army_clock += delta
    while army_clock >= 1.0:
        army_clock -= 1.0
        if world_map and is_instance_valid(world_map):
            world_map.grow_armies()
