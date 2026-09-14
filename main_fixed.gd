extends "res://main.gd"

const POPULATION_M := {
    "RU": 146.0,
    "US": 342.0,
    "CN": 1408.0,
    "DE": 84.0,
    "FR": 68.6,
    "GB": 69.5,
    "IN": 1460.0,
    "TR": 87.0,
    "JP": 123.0,
    "BR": 213.0
}

const PERSONNEL_PER_POWER_M := {
    "army": 0.00010,
    "air": 0.00005,
    "navy": 0.00005,
    "def": 0.00004,
    "missile": 0.00003
}

func _ready() -> void:
    super._ready()
    _ensure_population_data()
    _style_all_buttons(self)
    _refresh_all()

func _seed_countries() -> void:
    super._seed_countries()
    _ensure_population_data()

func _ensure_population_data() -> void:
    for id in countries.keys():
        if POPULATION_M.has(id):
            countries[id]["population"] = float(countries[id].get("population", POPULATION_M[id]))
        else:
            countries[id]["population"] = float(countries[id].get("population", 100.0))
        if not countries[id].has("attack_prefs"):
            countries[id]["attack_prefs"] = {
                "army": 25.0,
                "air": 25.0,
                "navy": 25.0,
                "def": 25.0,
                "missile": 25.0
            }

func _process(delta: float) -> void:
    if paused:
        return
    minute_accum += delta * speed
    bot_accum += delta * speed
    while minute_accum >= 60.0:
        minute_accum -= 60.0
        _economic_tick()
    while bot_accum >= 5.0:
        bot_accum -= 5.0
        _bot_tick()

func _military_population(c: Dictionary) -> float:
    var total := 0.0
    for key in UNIT_KEYS:
        total += float(c[key]) * float(PERSONNEL_PER_POWER_M[key])
    return total

func _civilian_population(c: Dictionary) -> float:
    return maxf(0.0, float(c.get("population", 100.0)) - _military_population(c))

func _effective_income(c: Dictionary) -> float:
    var pop := maxf(1.0, float(c.get("population", 100.0)))
    var civilian_share := clampf(_civilian_population(c) / pop, 0.0, 1.0)
    return float(c.income) * civilian_share

func _can_recruit(c: Dictionary, key: String, amount: float) -> bool:
    var pop := maxf(1.0, float(c.get("population", 100.0)))
    var future_military := _military_population(c) + amount * float(PERSONNEL_PER_POWER_M[key])
    return future_military <= pop * 0.12

func _economic_tick() -> void:
    for id in countries.keys():
        var c: Dictionary = countries[id]
        var upkeep: float = _total_power(c) * 0.00008
        c.treasury += maxf(0.0, _effective_income(c) - upkeep)
        c.war_fatigue = maxf(0.0, float(c.war_fatigue) - 0.02)
    _refresh_top()

func _buy_unit(key: String) -> void:
    var p: Dictionary = countries[player_id]
    var price: float = _unit_price(player_id, key)

    if p.treasury < price:
        _push_news("Недостаточно средств для покупки: %s." % UNIT_LABELS[key])
        return

    if not _can_recruit(p, key, 100.0):
        _push_news("Недостаточно свободного населения для дальнейшего увеличения армии.")
        return

    p.treasury -= price
    p[key] += 100.0
    _push_news("%s усиливает направление «%s» на 100." % [p.name, UNIT_LABELS[key]])
    _refresh_all()

func _bot_tick() -> void:
    for id in countries.keys():
        if id == player_id:
            continue

        var c: Dictionary = countries[id]
        var roll: float = randf()

        if roll < 0.55 and c.treasury > 150:
            var key: String = UNIT_KEYS.pick_random()
            var price: float = _unit_price(id, key)
            if c.treasury >= price and _can_recruit(c, key, 100.0):
                c.treasury -= price
                c[key] += 100.0
        elif roll < 0.8 and c.treasury >= 250:
            c.treasury -= 250
            c.economy += 1.0
            c.income *= 1.01
        elif roll > 0.93:
            _bot_may_attack(id)

    _refresh_all()

func _refresh_top() -> void:
    var p: Dictionary = countries[player_id]
    treasury_label.text = "Казна\n%.1f млн" % p.treasury
    income_label.text = "Доход\n+%.1f млн/мин" % _effective_income(p)
    military_label.text = "Население %.1f млн\nВоенные %.2f млн\nПотенциал %d" % [
        float(p.get("population", 0.0)),
        _military_population(p),
        int(_total_power(p))
    ]
    for s in speed_buttons.keys():
        speed_buttons[s].disabled = (s == speed)

func _refresh_selected() -> void:
    super._refresh_selected()
    if countries.has(selected_id):
        var c: Dictionary = countries[selected_id]
        _add_label(selected_panel, "Население: %.1f млн" % float(c.get("population", 0.0)))
        _add_label(selected_panel, "Военные: %.2f млн" % _military_population(c))
        _add_label(selected_panel, "Гражданское население: %.2f млн" % _civilian_population(c))
        _add_label(selected_panel, "Фактический доход: %.1f млн/мин" % _effective_income(c))
    _style_all_buttons(selected_panel)

func _refresh_country_list() -> void:
    super._refresh_country_list()
    _style_all_buttons(countries_box)

func _refresh_army() -> void:
    super._refresh_army()
    _style_all_buttons(army_box)

func _refresh_economy() -> void:
    for n in economy_box.get_children():
        n.queue_free()

    var p: Dictionary = countries[player_id]
    _add_label(economy_box, "ЭКОНОМИКА", 24)
    _add_label(economy_box, "Население: %.1f млн" % float(p.get("population", 0.0)))
    _add_label(economy_box, "Военные: %.2f млн" % _military_population(p))
    _add_label(economy_box, "Гражданское население: %.2f млн" % _civilian_population(p))
    _add_label(economy_box, "Уровень экономики: %.1f" % p.economy)
    _add_label(economy_box, "Номинальный доход: %.1f млн/мин" % p.income)
    _add_label(economy_box, "Фактический доход: %.1f млн/мин" % _effective_income(p))
    _add_label(economy_box, "Казна: %.1f млн" % p.treasury)

    for amount in [100.0, 500.0, 1000.0]:
        var b := Button.new()
        b.text = "Инвестировать %.0f млн" % amount
        b.pressed.connect(_invest.bind(amount))
        economy_box.add_child(b)

    _style_all_buttons(economy_box)

func _style_all_buttons(node: Node) -> void:
    for child in node.get_children():
        if child is Button:
            child.custom_minimum_size.y = maxf(child.custom_minimum_size.y, 64.0)
            child.add_theme_font_size_override("font_size", 20)
        _style_all_buttons(child)

func _open_attack_dialog(target: String) -> void:
    var dialog := AcceptDialog.new()
    dialog.title = "Военная операция против %s" % countries[target].name
    dialog.ok_button_text = ""

    var box := VBoxContainer.new()
    var sliders: Dictionary = {}
    var prefs: Dictionary = countries[player_id].get("attack_prefs", {})

    _add_label(box, "Выберите долю каждого рода сил. Противник не видит ваши цифры.", 18)

    for key in UNIT_KEYS:
        var row := HBoxContainer.new()
        box.add_child(row)

        var l := Label.new()
        l.text = UNIT_LABELS[key]
        l.custom_minimum_size.x = 150
        l.add_theme_font_size_override("font_size", 18)
        row.add_child(l)

        var slider := HSlider.new()
        slider.min_value = 0
        slider.max_value = 100
        slider.step = 5
        slider.value = float(prefs.get(key, 25.0))
        slider.custom_minimum_size.x = 280
        slider.custom_minimum_size.y = 54
        row.add_child(slider)

        var val := Label.new()
        val.text = "%d%%" % int(slider.value)
        val.custom_minimum_size.x = 65
        val.add_theme_font_size_override("font_size", 18)
        row.add_child(val)

        slider.value_changed.connect(func(v): val.text = "%d%%" % int(v))
        sliders[key] = slider

    var buttons := HBoxContainer.new()
    box.add_child(buttons)

    var cancel_btn := Button.new()
    cancel_btn.text = "ОТМЕНА"
    cancel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    buttons.add_child(cancel_btn)

    var start_btn := Button.new()
    start_btn.text = "НАЧАТЬ ОПЕРАЦИЮ"
    start_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    buttons.add_child(start_btn)

    dialog.add_child(box)
    add_child(dialog)
    _style_all_buttons(dialog)

    start_btn.pressed.connect(func():
        var weighted: float = 0.0
        var new_prefs: Dictionary = {}
        for key in UNIT_KEYS:
            var chosen := float(sliders[key].value)
            new_prefs[key] = chosen
            weighted += chosen / 100.0
        countries[player_id]["attack_prefs"] = new_prefs
        var avg_fraction: float = clampf(weighted / float(UNIT_KEYS.size()), 0.05, 1.0)
        _resolve_battle(player_id, target, avg_fraction, false)
        dialog.queue_free()
    )

    cancel_btn.pressed.connect(dialog.queue_free)
    dialog.canceled.connect(dialog.queue_free)
    dialog.popup_centered(Vector2i(680, 430))

func _resolve_battle(attacker_id: String, defender_id: String, attack_fraction: float, silent_bot: bool = false) -> void:
    var a: Dictionary = countries[attacker_id]
    var d: Dictionary = countries[defender_id]

    if defender_id == player_id and attacker_id != player_id:
        _push_news("ВНИМАНИЕ: %s атакует Россию!" % a.name)

    var defense_fraction: float = _ai_defense_fraction(d)
    var attack_power: float = _combat_power(a, attack_fraction, false) * randf_range(0.90, 1.10)
    var defense_power: float = _combat_power(d, defense_fraction, true) * randf_range(0.90, 1.10)
    var ratio: float = attack_power / maxf(1.0, defense_power)

    var a_loss: float = 0.12
    var d_loss: float = 0.12
    var winner: String = ""

    if ratio > 1.5:
        winner = attacker_id
        a_loss = randf_range(0.05, 0.12)
        d_loss = randf_range(0.40, 0.60)
    elif ratio > 1.12:
        winner = attacker_id
        a_loss = randf_range(0.08, 0.15)
        d_loss = randf_range(0.20, 0.35)
    elif ratio < 0.67:
        winner = defender_id
        a_loss = randf_range(0.40, 0.60)
        d_loss = randf_range(0.05, 0.12)
    elif ratio < 0.89:
        winner = defender_id
        a_loss = randf_range(0.20, 0.35)
        d_loss = randf_range(0.08, 0.15)
    else:
        a_loss = randf_range(0.10, 0.20)
        d_loss = randf_range(0.10, 0.20)

    var destroyed_value: float = 0.0

    for key in UNIT_KEYS:
        var av: float = float(a[key]) * attack_fraction
        var dv: float = float(d[key]) * defense_fraction
        var al: float = av * a_loss
        var dl: float = dv * d_loss

        a[key] = maxf(0.0, float(a[key]) - al)
        d[key] = maxf(0.0, float(d[key]) - dl)
        destroyed_value += dl * UNIT_COST[key] / 100.0

    a.war_fatigue = minf(100.0, float(a.war_fatigue) + 5.0)
    d.war_fatigue = minf(100.0, float(d.war_fatigue) + 5.0)

    if winner != "":
        countries[winner].treasury += destroyed_value * 0.5
        _push_news(
            "%s побеждает в столкновении с %s. Награда %.0f млн." %
            [
                countries[winner].name,
                countries[defender_id if winner == attacker_id else attacker_id].name,
                destroyed_value * 0.5
            ]
        )
    else:
        _push_news("Операция %s против %s завершилась без решающего результата." % [a.name, d.name])

    a.relations[defender_id] = max(-100, int(a.relations.get(defender_id, 0)) - 25)
    d.relations[attacker_id] = max(-100, int(d.relations.get(attacker_id, 0)) - 35)

    if not silent_bot or attacker_id == player_id or defender_id == player_id:
        selected_id = defender_id

    _refresh_all()

    if defender_id == player_id and attacker_id != player_id:
        _show_attack_alert(attacker_id, winner)

func _show_attack_alert(attacker_id: String, winner: String) -> void:
    var was_paused := paused
    paused = true
    Input.vibrate_handheld(500)

    var dialog := AcceptDialog.new()
    dialog.title = "НА ВАС НАПАЛИ"
    dialog.ok_button_text = ""

    var box := VBoxContainer.new()
    var result_text := "Бой завершился без решающего результата."
    if winner == player_id:
        result_text = "Атака отбита. Вы победили в обороне."
    elif winner == attacker_id:
        result_text = "Противник победил в этом столкновении."

    _add_label(box, "%s атакует Россию!" % countries[attacker_id].name, 24)
    _add_label(box, result_text, 20)
    _add_label(box, "Можно сразу нанести ответный удар.", 18)

    var buttons := HBoxContainer.new()
    box.add_child(buttons)

    var close_btn := Button.new()
    close_btn.text = "ЗАКРЫТЬ"
    close_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    buttons.add_child(close_btn)

    var counter_btn := Button.new()
    counter_btn.text = "ОТВЕТНЫЙ УДАР"
    counter_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    buttons.add_child(counter_btn)

    dialog.add_child(box)
    add_child(dialog)
    _style_all_buttons(dialog)

    close_btn.pressed.connect(func():
        paused = was_paused
        dialog.queue_free()
    )

    counter_btn.pressed.connect(func():
        paused = was_paused
        dialog.queue_free()
        selected_id = attacker_id
        _refresh_selected()
        _open_attack_dialog(attacker_id)
    )

    dialog.canceled.connect(func():
        paused = was_paused
        dialog.queue_free()
    )
    dialog.popup_centered(Vector2i(700, 340))

func _load_game() -> void:
    if not FileAccess.file_exists(SAVE_PATH):
        _push_news("Сохранение пока отсутствует.")
        return

    var f: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
    var data = JSON.parse_string(f.get_as_text())

    if typeof(data) == TYPE_DICTIONARY:
        countries = data.get("countries", countries)
        player_id = data.get("player_id", player_id)
        selected_id = data.get("selected_id", selected_id)

        news.clear()
        for x in data.get("news", []):
            news.append(str(x))

        _ensure_population_data()
        _push_news("Сохранение загружено.")
        _refresh_all()
        _style_all_buttons(self)
