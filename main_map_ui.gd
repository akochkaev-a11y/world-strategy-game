extends "res://main_game_tuning.gd"

var world_map: Control
var map_action_bar: HBoxContainer

func _seed_countries() -> void:
    countries = {
        "RU": _c("Россия", 4200, 25, 7500, 6200, 3600, 7000, 6500, "рациональный"),
        "UA": _c("Украина", 1200, 7, 5200, 2300, 450, 3300, 2700, "агрессивный"),
        "PL": _c("Польша", 1800, 15, 3200, 2300, 750, 2700, 1600, "осторожный"),
        "FR": _c("Франция", 3000, 24, 4300, 4700, 4000, 3900, 3100, "дипломатический"),
        "DE": _c("Германия", 3200, 35, 4200, 4100, 1700, 3600, 1600, "осторожный"),
        "GB": _c("Великобритания", 3100, 24, 3900, 5200, 5200, 3500, 3000, "дипломатический"),
        "CN": _c("Китай", 7600, 75, 9000, 8500, 7800, 7600, 8100, "экономический"),
        "IN": _c("Индия", 3500, 30, 6500, 5200, 4200, 3900, 4500, "авантюрный"),
        "IR": _c("Иран", 1500, 10, 4600, 2200, 1600, 3200, 4400, "агрессивный"),
        "JP": _c("Япония", 3000, 32, 3600, 5200, 5500, 4300, 2000, "осторожный")
    }

    # Population is stored in millions. Values are rounded for game balance.
    countries["RU"]["population"] = 146.0
    countries["UA"]["population"] = 38.0
    countries["PL"]["population"] = 37.5
    countries["FR"]["population"] = 68.6
    countries["DE"]["population"] = 84.5
    countries["GB"]["population"] = 69.5
    countries["CN"]["population"] = 1408.0
    countries["IN"]["population"] = 1460.0
    countries["IR"]["population"] = 91.0
    countries["JP"]["population"] = 123.0

    var relations: Dictionary = {}
    for a in countries.keys():
        relations[a] = {}
        for b in countries.keys():
            if a != b:
                relations[a][b] = randi_range(-20, 30)
    for id in countries.keys():
        countries[id]["relations"] = relations[id]

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

func _refresh_selected() -> void:
    super._refresh_selected()
    if countries.has(selected_id):
        var c: Dictionary = countries[selected_id]
        _add_label(selected_panel, "Казна: %.0f млн" % float(c.treasury), 19)
    _style_all_buttons(selected_panel)

func _process(delta: float) -> void:
    super._process(delta)
    if world_map and is_instance_valid(world_map) and world_map.selected_id != selected_id:
        world_map.set_selected(selected_id)
