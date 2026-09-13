extends Control

const SAVE_PATH := "user://geostrategy_save.json"
const UNIT_KEYS := ["army", "air", "navy", "def", "missile"]
const UNIT_LABELS := {
    "army": "Сухопутные",
    "air": "Авиация",
    "navy": "Флот",
    "def": "ПВО/ПРО",
    "missile": "Ракеты"
}
const UNIT_COST := {
    "army": 20.0,
    "air": 50.0,
    "navy": 70.0,
    "def": 45.0,
    "missile": 55.0
}

var countries: Dictionary = {}
var player_id: String = "RU"
var selected_id: String = "DE"
var speed: int = 1
var paused: bool = false
var minute_accum: float = 0.0
var bot_accum: float = 0.0
var news: Array[String] = []

var treasury_label: Label
var income_label: Label
var military_label: Label
var selected_panel: VBoxContainer
var countries_box: VBoxContainer
var army_box: VBoxContainer
var economy_box: VBoxContainer
var news_box: VBoxContainer
var tabs: TabContainer
var speed_buttons: Dictionary = {}

func _ready() -> void:
    _seed_countries()
    _build_ui()
    _push_news("Новая партия началась. Мир развивается самостоятельно.")
    _refresh_all()

func _process(delta: float) -> void:
    if paused:
        return
    minute_accum += delta * speed
    bot_accum += delta * speed
    while minute_accum >= 1.0:
        minute_accum -= 1.0
        _economic_tick()
    while bot_accum >= 5.0:
        bot_accum -= 5.0
        _bot_tick()

func _seed_countries() -> void:
    countries = {
        "RU": _c("Россия", 4200, 25, 7500, 6200, 3600, 7000, 6500, "рациональный"),
        "US": _c("США", 9000, 100, 9200, 9800, 10000, 8200, 8600, "рациональный"),
        "CN": _c("Китай", 7600, 75, 9000, 8500, 7800, 7600, 8100, "экономический"),
        "DE": _c("Германия", 3200, 35, 4200, 4100, 1700, 3600, 1600, "осторожный"),
        "FR": _c("Франция", 3000, 24, 4300, 4700, 4000, 3900, 3100, "дипломатический"),
        "GB": _c("Великобритания", 3100, 24, 3900, 5200, 5200, 3500, 3000, "дипломатический"),
        "IN": _c("Индия", 3500, 30, 6500, 5200, 4200, 3900, 4500, "авантюрный"),
        "TR": _c("Турция", 1800, 14, 4700, 3600, 2100, 3000, 2500, "агрессивный"),
        "JP": _c("Япония", 3000, 32, 3600, 5200, 5500, 4300, 2000, "осторожный"),
        "BR": _c("Бразилия", 1700, 12, 3300, 2200, 1800, 1700, 900, "экономический")
    }
    var relations: Dictionary = {}
    for a in countries.keys():
        relations[a] = {}
        for b in countries.keys():
            if a != b:
                relations[a][b] = randi_range(-20, 30)
    for id in countries.keys():
        countries[id]["relations"] = relations[id]

func _c(name: String, treasury: float, income: float, army: float, air: float, navy: float, def: float, missile: float, ai: String) -> Dictionary:
    return {
        "name": name,
        "treasury": treasury,
        "income": income,
        "economy": 100.0,
        "army": army,
        "air": air,
        "navy": navy,
        "def": def,
        "missile": missile,
        "ai": ai,
        "war_fatigue": 0.0,
        "relations": {}
    }

func _build_ui() -> void:
    var root := VBoxContainer.new()
    root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    root.add_theme_constant_override("separation", 6)
    add_child(root)

    var top := HBoxContainer.new()
    top.custom_minimum_size.y = 72
    root.add_child(top)

    var title := Label.new()
    title.text = "ГЕОСТРАТЕГИЯ v0.1"
    title.add_theme_font_size_override("font_size", 24)
    title.custom_minimum_size.x = 250
    top.add_child(title)

    treasury_label = Label.new()
    treasury_label.custom_minimum_size.x = 180
    top.add_child(treasury_label)

    income_label = Label.new()
    income_label.custom_minimum_size.x = 180
    top.add_child(income_label)

    military_label = Label.new()
    military_label.custom_minimum_size.x = 220
    top.add_child(military_label)

    var spacer := Control.new()
    spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    top.add_child(spacer)

    var pause_btn := Button.new()
    pause_btn.text = "Пауза"
    pause_btn.pressed.connect(_toggle_pause)
    top.add_child(pause_btn)

    for s in [1, 2, 5, 10]:
        var b := Button.new()
        b.text = "x%d" % s
        b.pressed.connect(_set_speed.bind(s))
        top.add_child(b)
        speed_buttons[s] = b

    var body := HBoxContainer.new()
    body.size_flags_vertical = Control.SIZE_EXPAND_FILL
    root.add_child(body)

    countries_box = VBoxContainer.new()
    countries_box.custom_minimum_size.x = 260

    var left_scroll := ScrollContainer.new()
    left_scroll.custom_minimum_size.x = 280
    left_scroll.add_child(countries_box)
    body.add_child(left_scroll)

    tabs = TabContainer.new()
    tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
    body.add_child(tabs)

    var world := VBoxContainer.new()
    world.name = "Карта"
    tabs.add_child(world)

    var info := Label.new()
    info.text = "МИР\n\nВыберите страну слева.\nВ прототипе карта представлена списком стран.\nСледующая версия заменит его интерактивной политической картой."
    info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    info.size_flags_vertical = Control.SIZE_EXPAND_FILL
    info.add_theme_font_size_override("font_size", 22)
    world.add_child(info)

    army_box = VBoxContainer.new()
    army_box.name = "Армия"
    tabs.add_child(army_box)

    economy_box = VBoxContainer.new()
    economy_box.name = "Экономика"
    tabs.add_child(economy_box)

    news_box = VBoxContainer.new()
    news_box.name = "Новости"
    tabs.add_child(news_box)

    var right_scroll := ScrollContainer.new()
    right_scroll.custom_minimum_size.x = 330

    selected_panel = VBoxContainer.new()
    selected_panel.custom_minimum_size.x = 310
    right_scroll.add_child(selected_panel)
    body.add_child(right_scroll)

    var bottom := HBoxContainer.new()
    bottom.custom_minimum_size.y = 54
    root.add_child(bottom)

    var save_btn := Button.new()
    save_btn.text = "Сохранить"
    save_btn.pressed.connect(_save_game)
    bottom.add_child(save_btn)

    var load_btn := Button.new()
    load_btn.text = "Загрузить"
    load_btn.pressed.connect(_load_game)
    bottom.add_child(load_btn)

    var ng_btn := Button.new()
    ng_btn.text = "Новая партия"
    ng_btn.pressed.connect(_new_game)
    bottom.add_child(ng_btn)

    var note := Label.new()
    note.text = "  1 секунда = 1 игровая минута (режим тестирования)"
    bottom.add_child(note)

func _refresh_all() -> void:
    _refresh_top()
    _refresh_country_list()
    _refresh_selected()
    _refresh_army()
    _refresh_economy()
    _refresh_news()

func _refresh_top() -> void:
    var p: Dictionary = countries[player_id]
    treasury_label.text = "Казна\n%.1f млн" % p.treasury
    income_label.text = "Доход\n+%.1f млн/мин" % p.income
    military_label.text = "Военный потенциал\n%d" % int(_total_power(p))
    for s in speed_buttons.keys():
        speed_buttons[s].disabled = (s == speed)

func _refresh_country_list() -> void:
    for n in countries_box.get_children():
        n.queue_free()

    var head := Label.new()
    head.text = "СТРАНЫ"
    head.add_theme_font_size_override("font_size", 20)
    countries_box.add_child(head)

    for id in countries.keys():
        var c: Dictionary = countries[id]
        var b := Button.new()
        b.text = "%s   [%d]" % [c.name, int(_total_power(c))]
        if id == player_id:
            b.text += "  ВЫ"
        b.pressed.connect(_select_country.bind(id))
        countries_box.add_child(b)

func _refresh_selected() -> void:
    for n in selected_panel.get_children():
        n.queue_free()

    if not countries.has(selected_id):
        return

    var c: Dictionary = countries[selected_id]
    var p: Dictionary = countries[player_id]

    _add_label(selected_panel, c.name, 26)
    _add_label(selected_panel, "Экономика: %.0f" % c.economy)
    _add_label(selected_panel, "Доход: %.1f млн/мин" % c.income)
    _add_label(selected_panel, "Военный потенциал: %d" % int(_total_power(c)))
    _add_label(selected_panel, "Характер ИИ: %s" % c.ai)

    if selected_id != player_id:
        _add_label(selected_panel, "Отношения: %d" % int(p.relations.get(selected_id, 0)))

        var help := Button.new()
        help.text = "Помощь: 100 млн"
        help.pressed.connect(_send_aid.bind(selected_id))
        selected_panel.add_child(help)

        var improve := Button.new()
        improve.text = "Улучшить отношения (-50 млн)"
        improve.pressed.connect(_improve_relations.bind(selected_id))
        selected_panel.add_child(improve)

        var attack := Button.new()
        attack.text = "ВОЕННАЯ ОПЕРАЦИЯ"
        attack.pressed.connect(_open_attack_dialog.bind(selected_id))
        selected_panel.add_child(attack)
    else:
        _add_label(selected_panel, "Это ваша страна.")

func _refresh_army() -> void:
    for n in army_box.get_children():
        n.queue_free()

    _add_label(army_box, "АРМИЯ - %s" % countries[player_id].name, 24)

    for key in UNIT_KEYS:
        var row := HBoxContainer.new()
        army_box.add_child(row)

        var l := Label.new()
        l.text = "%s: %d" % [UNIT_LABELS[key], int(countries[player_id][key])]
        l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        row.add_child(l)

        var b := Button.new()
        b.text = "+100 за %.0f млн" % _unit_price(player_id, key)
        b.pressed.connect(_buy_unit.bind(key))
        row.add_child(b)

func _refresh_economy() -> void:
    for n in economy_box.get_children():
        n.queue_free()

    var p: Dictionary = countries[player_id]
    _add_label(economy_box, "ЭКОНОМИКА", 24)
    _add_label(economy_box, "Уровень: %.1f" % p.economy)
    _add_label(economy_box, "Доход: %.1f млн/мин" % p.income)
    _add_label(economy_box, "Казна: %.1f млн" % p.treasury)

    for amount in [100.0, 500.0, 1000.0]:
        var b := Button.new()
        b.text = "Инвестировать %.0f млн" % amount
        b.pressed.connect(_invest.bind(amount))
        economy_box.add_child(b)

func _refresh_news() -> void:
    for n in news_box.get_children():
        n.queue_free()

    _add_label(news_box, "МИРОВЫЕ НОВОСТИ", 24)

    for item in news:
        _add_label(news_box, "• " + item)

func _add_label(parent: Node, text: String, size: int = 16) -> void:
    var l := Label.new()
    l.text = text
    l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    l.add_theme_font_size_override("font_size", size)
    parent.add_child(l)

func _select_country(id: String) -> void:
    selected_id = id
    _refresh_selected()

func _set_speed(s: int) -> void:
    speed = s
    paused = false
    _refresh_top()

func _toggle_pause() -> void:
    paused = not paused

func _economic_tick() -> void:
    for id in countries.keys():
        var c: Dictionary = countries[id]
        var upkeep: float = _total_power(c) * 0.00008
        c.treasury += max(0.0, c.income - upkeep)
        c.war_fatigue = max(0.0, c.war_fatigue - 0.02)
    _refresh_top()

func _bot_tick() -> void:
    for id in countries.keys():
        if id == player_id:
            continue

        var c: Dictionary = countries[id]
        var roll: float = randf()

        if roll < 0.55 and c.treasury > 150:
            var key: String = UNIT_KEYS.pick_random()
            var price: float = _unit_price(id, key)
            if c.treasury >= price:
                c.treasury -= price
                c[key] += 100.0
        elif roll < 0.8 and c.treasury >= 250:
            c.treasury -= 250
            c.economy += 1.0
            c.income *= 1.01
        elif roll > 0.93:
            _bot_may_attack(id)

    _refresh_all()

func _bot_may_attack(attacker_id: String) -> void:
    var candidates: Array = countries.keys().filter(func(x): return x != attacker_id)

    if candidates.is_empty():
        return

    var defender_id: String = candidates.pick_random()
    var a: Dictionary = countries[attacker_id]
    var d: Dictionary = countries[defender_id]
    var threshold: float = 1.5

    if a.ai == "агрессивный":
        threshold = 1.15
    elif a.ai == "осторожный":
        threshold = 1.8

    if _total_power(a) / max(1.0, _total_power(d)) > threshold:
        _resolve_battle(attacker_id, defender_id, 0.20, true)

func _unit_price(id: String, key: String) -> float:
    var c: Dictionary = countries[id]
    var growth: float = 1.0 + float(c[key]) / 20000.0
    return UNIT_COST[key] * growth

func _buy_unit(key: String) -> void:
    var p: Dictionary = countries[player_id]
    var price: float = _unit_price(player_id, key)

    if p.treasury < price:
        _push_news("Недостаточно средств для покупки: %s." % UNIT_LABELS[key])
        return

    p.treasury -= price
    p[key] += 100.0
    _push_news("%s усиливает направление «%s» на 100." % [p.name, UNIT_LABELS[key]])
    _refresh_all()

func _invest(amount: float) -> void:
    var p: Dictionary = countries[player_id]

    if p.treasury < amount:
        _push_news("Недостаточно средств для инвестиций.")
        return

    p.treasury -= amount
    var gain: float = amount / 250.0
    p.economy += gain
    p.income *= 1.0 + gain * 0.01
    _push_news("%s инвестирует %.0f млн в экономику." % [p.name, amount])
    _refresh_all()

func _send_aid(target: String) -> void:
    var p: Dictionary = countries[player_id]

    if p.treasury < 100:
        _push_news("Недостаточно средств для помощи.")
        return

    p.treasury -= 100
    countries[target].treasury += 100
    p.relations[target] = min(100, int(p.relations.get(target, 0)) + 8)
    countries[target].relations[player_id] = min(100, int(countries[target].relations.get(player_id, 0)) + 12)

    _push_news("%s предоставляет %s экономическую помощь: 100 млн." % [p.name, countries[target].name])
    _refresh_all()

func _improve_relations(target: String) -> void:
    var p: Dictionary = countries[player_id]

    if p.treasury < 50:
        return

    p.treasury -= 50
    p.relations[target] = min(100, int(p.relations.get(target, 0)) + 10)
    countries[target].relations[player_id] = min(100, int(countries[target].relations.get(player_id, 0)) + 6)

    _push_news("%s улучшает отношения с %s." % [p.name, countries[target].name])
    _refresh_all()

func _open_attack_dialog(target: String) -> void:
    var dialog := AcceptDialog.new()
    dialog.title = "Военная операция против %s" % countries[target].name
    dialog.ok_button_text = "НАЧАТЬ ОПЕРАЦИЮ"

    var box := VBoxContainer.new()
    var sliders: Dictionary = {}

    _add_label(box, "Выберите долю каждого рода сил. Противник не видит ваши цифры.", 16)

    for key in UNIT_KEYS:
        var row := HBoxContainer.new()
        box.add_child(row)

        var l := Label.new()
        l.text = UNIT_LABELS[key]
        l.custom_minimum_size.x = 130
        row.add_child(l)

        var slider := HSlider.new()
        slider.min_value = 0
        slider.max_value = 100
        slider.step = 5
        slider.value = 25
        slider.custom_minimum_size.x = 260
        row.add_child(slider)

        var val := Label.new()
        val.text = "25%"
        val.custom_minimum_size.x = 55
        row.add_child(val)

        slider.value_changed.connect(func(v): val.text = "%d%%" % int(v))
        sliders[key] = slider

    dialog.add_child(box)
    add_child(dialog)

    dialog.confirmed.connect(func():
        var weighted: float = 0.0
        for key in UNIT_KEYS:
            weighted += float(sliders[key].value) / 100.0

        var avg_fraction: float = clampf(
            weighted / float(UNIT_KEYS.size()),
            0.05,
            1.0
        )

        _resolve_battle(player_id, target, avg_fraction, false)
        dialog.queue_free()
    )

    dialog.canceled.connect(dialog.queue_free)
    dialog.popup_centered(Vector2i(620, 430))

func _resolve_battle(attacker_id: String, defender_id: String, attack_fraction: float, silent_bot: bool = false) -> void:
    var a: Dictionary = countries[attacker_id]
    var d: Dictionary = countries[defender_id]

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

        a[key] = max(0.0, float(a[key]) - al)
        d[key] = max(0.0, float(d[key]) - dl)

        destroyed_value += dl * UNIT_COST[key] / 100.0

    a.war_fatigue = min(100.0, a.war_fatigue + 5.0)
    d.war_fatigue = min(100.0, d.war_fatigue + 5.0)

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
        _push_news(
            "Операция %s против %s завершилась без решающего результата." %
            [a.name, d.name]
        )

    a.relations[defender_id] = max(
        -100,
        int(a.relations.get(defender_id, 0)) - 25
    )

    d.relations[attacker_id] = max(
        -100,
        int(d.relations.get(attacker_id, 0)) - 35
    )

    if not silent_bot or attacker_id == player_id or defender_id == player_id:
        selected_id = defender_id

    _refresh_all()

func _ai_defense_fraction(c: Dictionary) -> float:
    match c.ai:
        "осторожный":
            return randf_range(0.55, 0.85)
        "агрессивный":
            return randf_range(0.30, 0.60)
        "авантюрный":
            return randf_range(0.20, 0.80)
        _:
            return randf_range(0.40, 0.70)

func _combat_power(c: Dictionary, fraction: float, defender: bool) -> float:
    var ground: float = float(c.army) * fraction
    var air: float = float(c.air) * fraction
    var navy: float = float(c.navy) * fraction
    var defense: float = float(c.def) * fraction
    var missile: float = float(c.missile) * fraction

    var air_support: float = air * (
        1.0 - minf(
            0.55,
            defense / maxf(1.0, air + 5000.0)
        )
    )

    var total: float = (
        ground +
        air_support * 0.9 +
        navy * 0.45 +
        missile * 0.65 +
        defense * (0.7 if defender else 0.25)
    )

    if defender:
        total *= 1.15

    total *= 1.0 - float(c.war_fatigue) / 250.0
    return total

func _total_power(c: Dictionary) -> float:
    return float(
        c.army +
        c.air +
        c.navy +
        c.def +
        c.missile
    )

func _push_news(text: String) -> void:
    news.push_front(text)

    if news.size() > 25:
        news.resize(25)

    if is_instance_valid(news_box):
        _refresh_news()

func _save_game() -> void:
    var data: Dictionary = {
        "countries": countries,
        "player_id": player_id,
        "selected_id": selected_id,
        "news": news
    }

    var f: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)

    if f:
        f.store_string(JSON.stringify(data))
        _push_news("Партия сохранена.")

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

        _push_news("Сохранение загружено.")
        _refresh_all()

func _new_game() -> void:
    _seed_countries()
    news.clear()
    player_id = "RU"
    selected_id = "DE"
    _push_news("Начата новая партия.")
    _refresh_all()
