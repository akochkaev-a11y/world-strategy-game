extends "res://main_diplomacy.gd"

const ACTIVITY_IDLE := "idle"
const ACTIVITY_ECONOMY := "economy"
const ACTIVITY_MILITARY := "military"
const ACTIVITY_WAR := "war"
const ACTIVITY_ALLIANCE := "alliance"

func _ensure_population_data() -> void:
    super._ensure_population_data()
    for id in countries.keys():
        if not countries[id].has("activity"):
            countries[id]["activity"] = ACTIVITY_IDLE
        if not countries[id].has("activity_ticks"):
            countries[id]["activity_ticks"] = 0

func _mark_activity(id: String, activity: String, ticks: int = 4) -> void:
    if countries.has(id):
        countries[id]["activity"] = activity
        countries[id]["activity_ticks"] = ticks

func _tick_activity() -> void:
    for id in countries.keys():
        var left := int(countries[id].get("activity_ticks", 0))
        if left > 0:
            left -= 1
            countries[id]["activity_ticks"] = left
            if left <= 0:
                countries[id]["activity"] = ACTIVITY_IDLE

func _bot_tick() -> void:
    _tick_activity()
    for id in countries.keys():
        if id == player_id:
            continue
        var c: Dictionary = countries[id]
        var roll := randf()
        if roll < 0.48 and c.treasury > 150:
            var key: String = UNIT_KEYS.pick_random()
            var price: float = _unit_price(id, key)
            if c.treasury >= price and _can_recruit(c, key, 100.0):
                c.treasury -= price
                c[key] += 100.0
                _mark_activity(id, ACTIVITY_MILITARY)
        elif roll < 0.70 and c.treasury >= 250:
            c.treasury -= 250
            c.economy += 1.0
            c.income *= 1.01
            _mark_activity(id, ACTIVITY_ECONOMY)
        elif roll < 0.78:
            _bot_diplomacy(id)
        elif roll > 0.90:
            _bot_may_attack(id)
    _refresh_all()

func _bot_may_attack(attacker_id: String) -> void:
    var candidates: Array = countries.keys().filter(func(x):
        return x != attacker_id and not _are_allies(attacker_id, x)
    )
    if candidates.is_empty():
        return

    var defender_id: String
    if player_id != attacker_id and player_id in candidates and randf() < 0.35:
        defender_id = player_id
    else:
        defender_id = candidates.pick_random()

    # Absolute rule: allies never attack each other.
    if _are_allies(attacker_id, defender_id):
        return

    var a: Dictionary = countries[attacker_id]
    var d: Dictionary = countries[defender_id]
    var strength_ratio: float = _total_power(a) / maxf(1.0, _total_power(d))
    var relations: int = int(a.relations.get(defender_id, 0))
    var threshold: float = 1.15
    if a.ai == "агрессивный":
        threshold = 0.82
    elif a.ai == "осторожный":
        threshold = 1.35
    if relations <= -50:
        threshold -= 0.20
    elif relations <= -20:
        threshold -= 0.10

    if strength_ratio > threshold:
        _mark_activity(attacker_id, ACTIVITY_WAR, 6)
        _mark_activity(defender_id, ACTIVITY_WAR, 6)
        _resolve_battle(attacker_id, defender_id, randf_range(0.18, 0.35), true)

func _bot_diplomacy(id: String) -> void:
    var candidates: Array = countries.keys().filter(func(x): return x != id and x != player_id)
    if candidates.is_empty():
        return
    var other: String = candidates.pick_random()
    if int(countries[id].relations.get(other, 0)) >= 35 and not _are_allies(id, other) and randf() < 0.20:
        _set_alliance(id, other, true)
        _mark_activity(id, ACTIVITY_ALLIANCE, 6)
        _mark_activity(other, ACTIVITY_ALLIANCE, 6)

func _open_attack_dialog(target: String) -> void:
    if _are_allies(player_id, target):
        _show_simple_notice("СОЮЗНИК", "%s - союзник России. Сначала расторгните союз." % countries[target].name)
        return
    super._open_attack_dialog(target)

func _activity_icon(id: String) -> String:
    match str(countries[id].get("activity", ACTIVITY_IDLE)):
        ACTIVITY_ECONOMY:
            return "🟢"
        ACTIVITY_MILITARY:
            return "🔴"
        ACTIVITY_WAR:
            return "⚔️"
        ACTIVITY_ALLIANCE:
            return "🔵"
        _:
            return "⚪"

func _refresh_country_list() -> void:
    for n in countries_box.get_children():
        n.queue_free()

    var head := Label.new()
    head.text = "СТРАНЫ   🟢 экономика   🔴 вооружение   ⚔️ война   🔵 союз"
    head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    head.add_theme_font_size_override("font_size", 18)
    countries_box.add_child(head)

    var grid := GridContainer.new()
    grid.columns = 2
    grid.add_theme_constant_override("h_separation", 8)
    grid.add_theme_constant_override("v_separation", 6)
    countries_box.add_child(grid)

    for id in countries.keys():
        var c: Dictionary = countries[id]
        var b := Button.new()
        var ally_text := "  🤝" if id != player_id and _are_allies(player_id, id) else ""
        b.text = "%s %s  [%d]%s" % [_activity_icon(id), c.name, int(_total_power(c)), ally_text]
        if id == player_id:
            b.text += "  ВЫ"
        b.custom_minimum_size.x = 245
        b.pressed.connect(_select_country.bind(id))
        grid.add_child(b)
    _style_all_buttons(countries_box)

func _refresh_news() -> void:
    for n in news_box.get_children():
        n.queue_free()
    _add_label(news_box, "МИРОВЫЕ НОВОСТИ - ТОЛЬКО ВОЙНЫ", 24)
    var battle_count := 0
    for item in news:
        var text := str(item)
        if text.begins_with("БИТВА:"):
            _add_label(news_box, "• " + text)
            battle_count += 1
    if battle_count == 0:
        _add_label(news_box, "Боевых столкновений пока не было.", 16)

func _resolve_battle(attacker_id: String, defender_id: String, attack_fraction: float, silent_bot: bool = false) -> void:
    # Safety net so no code path can make allies fight each other.
    if _are_allies(attacker_id, defender_id):
        return
    _mark_activity(attacker_id, ACTIVITY_WAR, 6)
    _mark_activity(defender_id, ACTIVITY_WAR, 6)
    super._resolve_battle(attacker_id, defender_id, attack_fraction, silent_bot)

func _toggle_alliance_with(target: String) -> void:
    var was_allied := _are_allies(player_id, target)
    super._toggle_alliance_with(target)
    if _are_allies(player_id, target) != was_allied:
        _mark_activity(player_id, ACTIVITY_ALLIANCE, 6)
        _mark_activity(target, ACTIVITY_ALLIANCE, 6)

func _show_simple_notice(title_text: String, body_text: String) -> void:
    var dialog := AcceptDialog.new()
    dialog.title = title_text
    dialog.dialog_text = body_text
    dialog.ok_button_text = "ПОНЯТНО"
    add_child(dialog)
    _style_all_buttons(dialog)
    dialog.confirmed.connect(dialog.queue_free)
    dialog.canceled.connect(dialog.queue_free)
    dialog.popup_centered(Vector2i(620, 260))
