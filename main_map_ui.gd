extends "res://main_game_tuning.gd"

var world_map: Control
var map_action_bar: HBoxContainer

func _military_rating(c: Dictionary) -> int:
    # Display potential = the original raw military sum divided by 10,000.
    return int(round(_total_power(c) / 10000.0))

func _seed_countries() -> void:
    # For army/air/navy/air-defense values, one unit equals one person.
    # Missile values remain equipment/power units and do not consume population.
    countries = {
        "RU": _c("Россия", 4200, 25, 900000, 180000, 150000, 90000, 6500, "рациональный"),
        "UA": _c("Украина", 1200, 7, 700000, 80000, 30000, 90000, 2700, "агрессивный"),
        "PL": _c("Польша", 1800, 15, 150000, 30000, 15000, 21000, 1600, "осторожный"),
        "FR": _c("Франция", 3000, 24, 115000, 40000, 35000, 15000, 3100, "дипломатический"),
        "DE": _c("Германия", 3200, 35, 120000, 35000, 15000, 14000, 1600, "осторожный"),
        "GB": _c("Великобритания", 3100, 24, 75000, 30000, 28000, 8000, 3000, "дипломатический"),
        "CN": _c("Китай", 7600, 75, 975000, 400000, 300000, 360000, 8100, "экономический"),
        "IN": _c("Индия", 3500, 30, 900000, 175000, 160000, 220000, 4500, "авантюрный"),
        "IR": _c("Иран", 1500, 10, 350000, 70000, 30000, 160000, 4400, "агрессивный"),
        "JP": _c("Япония", 3000, 32, 150000, 50000, 25000, 22000, 2000, "осторожный")
    }

    # Population is stored in millions.
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

func _refresh_top() -> void:
    super._refresh_top()
    if countries.has(player_id):
        var p: Dictionary = countries[player_id]
        military_label.text = "Население %.1f млн\nВоенные %.2f млн\nПотенциал %d" % [
            float(p.get("population", 0.0)),
            _military_population(p),
            _military_rating(p)
        ]

func _refresh_selected() -> void:
    super._refresh_selected()
    if countries.has(selected_id):
        var c: Dictionary = countries[selected_id]
        for child in selected_panel.get_children():
            if child is Label and str(child.text).begins_with("Военный потенциал:"):
                child.text = "Военный потенциал: %d" % _military_rating(c)
        _add_label(selected_panel, "Казна: %.0f млн" % float(c.treasury), 19)
    _style_all_buttons(selected_panel)

func _refresh_army() -> void:
    for n in army_box.get_children():
        n.queue_free()

    _add_label(army_box, "АРМИЯ - %s" % countries[player_id].name, 24)
    _add_label(army_box, "1 единица = 1 военнослужащий. Ракеты личный состав не занимают.", 16)

    for key in UNIT_KEYS:
        var row := VBoxContainer.new()
        army_box.add_child(row)

        var l := Label.new()
        if key == "missile":
            l.text = "%s: %d (без личного состава)" % [UNIT_LABELS[key], int(countries[player_id][key])]
        else:
            l.text = "%s: %d чел." % [UNIT_LABELS[key], int(countries[player_id][key])]
        row.add_child(l)

        var buttons := HBoxContainer.new()
        buttons.add_theme_constant_override("separation", 5)
        row.add_child(buttons)

        for amount in [100, 1000, 10000]:
            var b := Button.new()
            var price: float = _unit_price(player_id, key) * float(amount) / 100.0
            b.text = "+%d\n%.0f млн" % [amount, price]
            b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
            b.custom_minimum_size.y = 54
            b.pressed.connect(_buy_unit_amount.bind(key, amount))
            buttons.add_child(b)

func _buy_unit_amount(key: String, amount: int) -> void:
    var p: Dictionary = countries[player_id]
    var price: float = _unit_price(player_id, key) * float(amount) / 100.0

    if float(p.treasury) < price:
        _push_news("Недостаточно средств для покупки: %s x%d." % [UNIT_LABELS[key], amount])
        return

    if not _can_recruit(p, key, float(amount)):
        _push_news("Недостаточно свободного населения для увеличения «%s» на %d человек." % [UNIT_LABELS[key], amount])
        return

    p.treasury -= price
    p[key] += float(amount)
    if key == "missile":
        _push_news("%s увеличивает запас «%s» на %d. Население не используется." % [p.name, UNIT_LABELS[key], amount])
    else:
        _push_news("%s увеличивает «%s» на %d человек." % [p.name, UNIT_LABELS[key], amount])
    _refresh_all()

func _process(delta: float) -> void:
    super._process(delta)
    if world_map and is_instance_valid(world_map) and world_map.selected_id != selected_id:
        world_map.set_selected(selected_id)
