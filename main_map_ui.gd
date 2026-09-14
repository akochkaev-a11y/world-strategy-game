extends "res://main_game_tuning.gd"

var world_map: Control
var map_action_bar: HBoxContainer

func _build_ui() -> void:
    super._build_ui()

    var left_scroll := countries_box.get_parent()
    if left_scroll is Control:
        left_scroll.hide()

    var world: VBoxContainer = tabs.get_node("Карта")
    for child in world.get_children():
        child.queue_free()

    var header := Label.new()
    header.text = "ПОЛИТИЧЕСКАЯ КАРТА - ЕВРОПА И ЕВРАЗИЯ"
    header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    header.add_theme_font_size_override("font_size", 20)
    world.add_child(header)

    world_map = preload("res://world_map.gd").new()
    world_map.name = "WorldMap"
    world_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    world_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
    world.add_child(world_map)
    world_map.country_clicked.connect(_on_map_country_clicked)

    map_action_bar = HBoxContainer.new()
    map_action_bar.alignment = BoxContainer.ALIGNMENT_CENTER
    map_action_bar.add_theme_constant_override("separation", 5)
    world.add_child(map_action_bar)

    var troop_btn := Button.new()
    troop_btn.text = "ВОЙСКА"
    troop_btn.custom_minimum_size = Vector2(105, 44)
    troop_btn.pressed.connect(func():
        if selected_id != player_id:
            _open_attack_dialog(selected_id)
    )
    map_action_bar.add_child(troop_btn)

    var diplomacy_btn := Button.new()
    diplomacy_btn.text = "ДИПЛОМАТИЯ"
    diplomacy_btn.custom_minimum_size = Vector2(105, 44)
    diplomacy_btn.pressed.connect(func(): _refresh_selected())
    map_action_bar.add_child(diplomacy_btn)

    var help_btn := Button.new()
    help_btn.text = "ПОМОЩЬ"
    help_btn.custom_minimum_size = Vector2(105, 44)
    help_btn.pressed.connect(func():
        if selected_id != player_id:
            _send_aid(selected_id)
    )
    map_action_bar.add_child(help_btn)

func _ready() -> void:
    super._ready()
    if world_map:
        world_map.setup(countries, selected_id)

func _on_map_country_clicked(id: String) -> void:
    selected_id = id
    if world_map:
        world_map.set_selected(id)
    _refresh_selected()

func _process(delta: float) -> void:
    super._process(delta)
    if world_map and is_instance_valid(world_map) and world_map.selected_id != selected_id:
        world_map.set_selected(selected_id)
EOF
