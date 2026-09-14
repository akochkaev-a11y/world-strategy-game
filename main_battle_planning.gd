extends "res://main_fullscreen_battle.gd"

# Classical assault balance: the defender has a strong positional advantage.
# In practice this moves an ordinary attacking victory to about 2:1 and a
# decisive victory to about 3:1, while keeping the existing battle randomness.
const DEFENDER_POSITIONAL_MULTIPLIER := 1.80
const INTEL_DEFENSE_ESTIMATE := 0.60

func _combat_power(c: Dictionary, fraction: float, defender: bool) -> float:
    var total: float
    # For Russia on attack, the five sliders affect combat power separately.
    if not defender and str(c.get("name", "")) == str(countries[player_id].get("name", "")):
        var prefs: Dictionary = countries[player_id].get("attack_prefs", {})
        var ground: float = float(c.army) * float(prefs.get("army", fraction * 100.0)) / 100.0
        var air: float = float(c.air) * float(prefs.get("air", fraction * 100.0)) / 100.0
        var navy: float = float(c.navy) * float(prefs.get("navy", fraction * 100.0)) / 100.0
        var defense: float = float(c.def) * float(prefs.get("def", fraction * 100.0)) / 100.0
        var missile: float = float(c.missile) * float(prefs.get("missile", fraction * 100.0)) / 100.0
        # Own air defense supports the operation; it must never suppress our own aviation.
        var air_support: float = air
        total = ground + air_support * 0.9 + navy * 0.45 + missile * 0.65 + defense * 0.25
        total *= 1.0 - float(c.war_fatigue) / 250.0
    else:
        total = super._combat_power(c, fraction, defender)

    if defender:
        total *= DEFENDER_POSITIONAL_MULTIPLIER
    return total

func _planning_attack_power(c: Dictionary, prefs: Dictionary) -> float:
    var ground: float = float(c.army) * float(prefs.get("army", 25.0)) / 100.0
    var air: float = float(c.air) * float(prefs.get("air", 25.0)) / 100.0
    var navy: float = float(c.navy) * float(prefs.get("navy", 25.0)) / 100.0
    var defense: float = float(c.def) * float(prefs.get("def", 25.0)) / 100.0
    var missile: float = float(c.missile) * float(prefs.get("missile", 25.0)) / 100.0
    # Increasing our own PVO/PRO must only increase attacking power.
    var air_support: float = air
    var total := ground + air_support * 0.9 + navy * 0.45 + missile * 0.65 + defense * 0.25
    return total * (1.0 - float(c.war_fatigue) / 250.0)

func _planning_defense_power(c: Dictionary) -> float:
    return super._combat_power(c, INTEL_DEFENSE_ESTIMATE, true) * DEFENDER_POSITIONAL_MULTIPLIER

func _forecast_text(ratio: float) -> String:
    if ratio >= 3.0:
        return "ВЫСОКАЯ ВЕРОЯТНОСТЬ ПОБЕДЫ - классическое превосходство 3:1+"
    if ratio >= 2.0:
        return "ПРЕИМУЩЕСТВО - наступление имеет хорошие шансы"
    if ratio >= 1.5:
        return "РИСКОВАННО - оборона всё ещё очень сильна"
    return "ВЫСОКИЙ РИСК ПОРАЖЕНИЯ - сил для наступления недостаточно"

func _open_attack_dialog(target: String) -> void:
    if _are_allies(player_id, target):
        _show_simple_notice("СОЮЗНИК", "%s - союзник России. Сначала расторгните союз." % str(countries[target].name))
        return

    var dialog := AcceptDialog.new()
    dialog.title = "ПОДГОТОВКА ОПЕРАЦИИ - %s" % str(countries[target].name).to_upper()
    dialog.ok_button_text = ""

    var box := VBoxContainer.new()
    box.add_theme_constant_override("separation", 5)
    var sliders: Dictionary = {}
    var sent_labels: Dictionary = {}
    var prefs: Dictionary = countries[player_id].get("attack_prefs", {}).duplicate(true)
    var enemy: Dictionary = countries[target]
    var player: Dictionary = countries[player_id]

    _add_label(box, "РАЗВЕДДАННЫЕ И РАСПРЕДЕЛЕНИЕ СИЛ", 22)
    _add_label(box, "Слева - ваши силы в операции. Справа - полный военный потенциал противника.", 15)

    for key in UNIT_KEYS:
        var row := HBoxContainer.new()
        box.add_child(row)

        var name_label := Label.new()
        name_label.text = "%s %s" % [BATTLE_ICON.get(key, ""), UNIT_LABELS[key]]
        name_label.custom_minimum_size.x = 155
        name_label.add_theme_font_size_override("font_size", 17)
        row.add_child(name_label)

        var sent := Label.new()
        sent.custom_minimum_size.x = 105
        sent.add_theme_font_size_override("font_size", 17)
        row.add_child(sent)
        sent_labels[key] = sent

        var slider := HSlider.new()
        slider.min_value = 0
        slider.max_value = 100
        slider.step = 5
        slider.value = float(prefs.get(key, 25.0))
        slider.custom_minimum_size = Vector2(230, 48)
        row.add_child(slider)
        sliders[key] = slider

        var enemy_label := Label.new()
        enemy_label.text = "противник: %.0f" % float(enemy[key])
        enemy_label.custom_minimum_size.x = 155
        enemy_label.add_theme_font_size_override("font_size", 17)
        row.add_child(enemy_label)

    var ratio_label := Label.new()
    ratio_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    ratio_label.add_theme_font_size_override("font_size", 21)
    box.add_child(ratio_label)

    var forecast := Label.new()
    forecast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    forecast.add_theme_font_size_override("font_size", 18)
    forecast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    box.add_child(forecast)

    var intel_note := Label.new()
    intel_note.text = "Оценка обороны разведки: около 60% потенциала + преимущество подготовленной обороны. Точный состав противник определит в момент боя."
    intel_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    intel_note.add_theme_font_size_override("font_size", 14)
    box.add_child(intel_note)

    var refresh_preview := func() -> void:
        var live_prefs: Dictionary = {}
        for k in UNIT_KEYS:
            var pct: float = float(sliders[k].value)
            live_prefs[k] = pct
            sent_labels[k].text = "%.0f (%.0f%%)" % [float(player[k]) * pct / 100.0, pct]
        var ap: float = _planning_attack_power(player, live_prefs)
        var dp: float = _planning_defense_power(enemy)
        var r: float = ap / maxf(1.0, dp)
        ratio_label.text = "СООТНОШЕНИЕ БОЕВОЙ МОЩИ:  %.2f : 1" % r
        forecast.text = _forecast_text(r)

    for key in UNIT_KEYS:
        sliders[key].value_changed.connect(func(_v): refresh_preview.call())
    refresh_preview.call()

    var buttons := HBoxContainer.new()
    buttons.alignment = BoxContainer.ALIGNMENT_CENTER
    box.add_child(buttons)
    var cancel_btn := Button.new()
    cancel_btn.text = "ОТМЕНА"
    cancel_btn.custom_minimum_size = Vector2(220, 60)
    buttons.add_child(cancel_btn)
    var start_btn := Button.new()
    start_btn.text = "НАЧАТЬ ОПЕРАЦИЮ"
    start_btn.custom_minimum_size = Vector2(300, 60)
    buttons.add_child(start_btn)

    dialog.add_child(box)
    add_child(dialog)
    _style_all_buttons(dialog)

    start_btn.pressed.connect(func():
        var new_prefs: Dictionary = {}
        var weighted: float = 0.0
        for key in UNIT_KEYS:
            var chosen: float = float(sliders[key].value)
            new_prefs[key] = chosen
            weighted += chosen / 100.0
        countries[player_id]["attack_prefs"] = new_prefs
        var avg_fraction: float = clampf(weighted / float(UNIT_KEYS.size()), 0.05, 1.0)
        dialog.queue_free()
        _resolve_battle(player_id, target, avg_fraction, false)
    )
    cancel_btn.pressed.connect(dialog.queue_free)
    dialog.canceled.connect(dialog.queue_free)
    dialog.popup_centered(Vector2i(820, 610))
