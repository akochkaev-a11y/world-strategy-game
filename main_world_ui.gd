extends "res://main_economy_ai.gd"

const ACTIVITY_IDLE := "idle"
const ACTIVITY_ECONOMY := "economy"
const ACTIVITY_MILITARY := "military"
const ACTIVITY_WAR := "war"
const ACTIVITY_ALLIANCE := "alliance"

const WAR_SCORE_THRESHOLD := 60.0
const WAR_MIN_RESERVE_CYCLES := 2.5
const WAR_BASE_COOLDOWN_TICKS := 24
const WAR_EXTRA_COOLDOWN_TICKS := 12
const WAR_LOSER_EXTRA_COOLDOWN_TICKS := 12

func _ensure_population_data() -> void:
    super._ensure_population_data()
    for id in countries.keys():
        if not countries[id].has("activity"):
            countries[id]["activity"] = ACTIVITY_IDLE
        if not countries[id].has("activity_ticks"):
            countries[id]["activity_ticks"] = 0
        if not countries[id].has("war_cooldown"):
            countries[id]["war_cooldown"] = 0

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

func _tick_war_cooldowns() -> void:
    for id in countries.keys():
        var left := int(countries[id].get("war_cooldown", 0))
        if left > 0:
            countries[id]["war_cooldown"] = left - 1

func _bot_tick() -> void:
    _tick_activity()
    _tick_war_cooldowns()
    for id in countries.keys():
        if id == player_id:
            continue
        var c: Dictionary = countries[id]
        var spendable: float = _bot_spendable_treasury(c)
        var roll := randf()
        if roll < 0.42 and spendable > 150.0:
            var key: String = UNIT_KEYS.pick_random()
            var price: float = _unit_price(id, key)
            if spendable >= price and _can_recruit(c, key, 100.0):
                c.treasury -= price
                c[key] += 100.0
                _mark_activity(id, ACTIVITY_MILITARY)
        elif roll < 0.62 and spendable >= 250.0:
            c.treasury -= 250.0
            c.economy += 1.0
            c.income *= 1.01
            _mark_activity(id, ACTIVITY_ECONOMY)
        elif roll < 0.78:
            _bot_diplomacy(id)
        elif roll > 0.97:
            _bot_may_attack(id)
    _refresh_all()

func _war_personality_score(ai_type: String) -> float:
    match ai_type:
        "агрессивный":
            return 20.0
        "авантюрный":
            return 10.0
        "осторожный":
            return -20.0
        "дипломатический":
            return -15.0
        "экономический":
            return -10.0
        _:
            return 0.0

func _allied_power(country_id: String) -> float:
    var total: float = 0.0
    for ally_id in countries[country_id].get("allies", []):
        if countries.has(ally_id):
            total += _total_power(countries[ally_id])
    return total

func _war_target_score(attacker_id: String, defender_id: String) -> float:
    var a: Dictionary = countries[attacker_id]
    var d: Dictionary = countries[defender_id]
    var score: float = 20.0 + _war_personality_score(str(a.ai))

    var relations: int = int(a.relations.get(defender_id, 0))
    if relations <= -60:
        score += 25.0
    elif relations <= -30:
        score += 15.0
    elif relations >= 40:
        score -= 35.0
    elif relations >= 0:
        score -= 12.0

    var strength_ratio: float = _total_power(a) / maxf(1.0, _total_power(d))
    if strength_ratio >= 1.50:
        score += 25.0
    elif strength_ratio >= 1.20:
        score += 15.0
    elif strength_ratio < 0.70:
        score -= 40.0
    elif strength_ratio < 0.90:
        score -= 25.0

    score -= float(a.war_fatigue) * 0.40

    var attacker_income: float = maxf(1.0, _effective_income(a))
    var reserve_cycles: float = float(a.treasury) / attacker_income
    if reserve_cycles >= 8.0:
        score += 10.0
    elif reserve_cycles < 4.0:
        score -= 15.0

    if float(a.economy) < 80.0:
        score -= 15.0
    elif float(a.economy) > 120.0:
        score += 5.0

    var defender_allies_power: float = _allied_power(defender_id)
    if defender_allies_power > _total_power(d) * 0.50:
        score -= 10.0
    if defender_allies_power > _total_power(a):
        score -= 25.0

    if float(d.treasury) > float(a.treasury) * 1.5:
        score += 5.0

    return score + randf_range(0.0, 8.0)

func _bot_may_attack(attacker_id: String) -> void:
    if int(countries[attacker_id].get("war_cooldown", 0)) > 0:
        return

    var a: Dictionary = countries[attacker_id]
    var minimum_reserve: float = maxf(100.0, _effective_income(a) * WAR_MIN_RESERVE_CYCLES)
    if float(a.treasury) < minimum_reserve:
        return
    if float(a.war_fatigue) >= 70.0:
        return

    var candidates: Array = countries.keys().filter(func(x):
        return x != attacker_id and not _are_allies(attacker_id, x)
    )
    if candidates.is_empty():
        return

    var best_target := ""
    var best_score := -999.0
    for candidate in candidates:
        var target_id := str(candidate)
        var score := _war_target_score(attacker_id, target_id)
        if score > best_score:
            best_score = score
            best_target = target_id

    if best_target == "" or best_score < WAR_SCORE_THRESHOLD:
        return

    _mark_activity(attacker_id, ACTIVITY_WAR, 6)
    _mark_activity(best_target, ACTIVITY_WAR, 6)
    _resolve_battle(attacker_id, best_target, randf_range(0.18, 0.32), true)

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
    if _are_allies(attacker_id, defender_id):
        return

    var attacker_power_before: float = _total_power(countries[attacker_id])
    var defender_power_before: float = _total_power(countries[defender_id])
    _mark_activity(attacker_id, ACTIVITY_WAR, 6)
    _mark_activity(defender_id, ACTIVITY_WAR, 6)
    super._resolve_battle(attacker_id, defender_id, attack_fraction, silent_bot)

    var attacker_loss_share: float = 1.0 - _total_power(countries[attacker_id]) / maxf(1.0, attacker_power_before)
    var defender_loss_share: float = 1.0 - _total_power(countries[defender_id]) / maxf(1.0, defender_power_before)
    var attacker_rest: int = WAR_BASE_COOLDOWN_TICKS + randi_range(0, WAR_EXTRA_COOLDOWN_TICKS)
    var defender_rest: int = WAR_BASE_COOLDOWN_TICKS + randi_range(0, WAR_EXTRA_COOLDOWN_TICKS)

    if attacker_loss_share > defender_loss_share + 0.03:
        attacker_rest += WAR_LOSER_EXTRA_COOLDOWN_TICKS
        countries[attacker_id].war_fatigue = minf(100.0, float(countries[attacker_id].war_fatigue) + 8.0)
    elif defender_loss_share > attacker_loss_share + 0.03:
        defender_rest += WAR_LOSER_EXTRA_COOLDOWN_TICKS
        countries[defender_id].war_fatigue = minf(100.0, float(countries[defender_id].war_fatigue) + 8.0)

    attacker_rest += int(float(countries[attacker_id].war_fatigue) * 0.20)
    defender_rest += int(float(countries[defender_id].war_fatigue) * 0.20)
    countries[attacker_id]["war_cooldown"] = maxi(int(countries[attacker_id].get("war_cooldown", 0)), attacker_rest)
    countries[defender_id]["war_cooldown"] = maxi(int(countries[defender_id].get("war_cooldown", 0)), defender_rest)

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
