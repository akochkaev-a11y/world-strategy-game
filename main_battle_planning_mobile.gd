extends "res://main_battle_planning.gd"

func _open_attack_dialog(target: String) -> void:
    if _are_allies(player_id, target):
        _show_simple_notice("СОЮЗНИК", "%s - союзник России. Сначала расторгните союз." % str(countries[target].name))
        return

    var dialog := AcceptDialog.new()
    dialog.title = "ПОДГОТОВКА ОПЕРАЦИИ - %s" % str(countries[target].name).to_upper()
    dialog.ok_button_text = ""

    var box := VBoxContainer.new()
    box.add_theme_constant_override("separation", 6)
    var sliders: Dictionary = {}
    var line_labels: Dictionary = {}
    var prefs: Dictionary = countries[player_id].get("attack_prefs", {}).duplicate(true)
    var enemy: Dictionary = countries[target]
    var player: Dictionary = countries[player_id]

    _add_label(box, "РАЗВЕДДАННЫЕ О ПРОТИВНИКЕ", 21)
    var enemy_total: float = _total_power(enemy)
    _add_label(box, "%s - общий военный потенциал: %.0f" % [str(enemy.name), enemy_total], 18)
    _add_label(box, "Ниже по каждому роду войск: потенциал противника и сколько сил вы отправляете.", 14)

    for key in UNIT_KEYS:
        var unit_box := VBoxContainer.new()
        unit_box.add_theme_constant_override("separation", 1)
        box.add_child(unit_box)

        var line := Label.new()
        line.add_theme_font_size_override("font_size", 17)
        line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        unit_box.add_child(line)
        line_labels[key] = line

        var slider := HSlider.new()
        slider.min_value = 0
        slider.max_value = 100
        slider.step = 5
        slider.value = float(prefs.get(key, 25.0))
        slider.custom_minimum_size = Vector2(560, 42)
        unit_box.add_child(slider)
        sliders[key] = slider

    var ratio_label := Label.new()
    ratio_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    ratio_label.add_theme_font_size_override("font_size", 20)
    box.add_child(ratio_label)

    var forecast := Label.new()
    forecast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    forecast.add_theme_font_size_override("font_size", 17)
    forecast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    box.add_child(forecast)

    var intel_note := Label.new()
    intel_note.text = "Разведка оценивает, что противник задействует около 60% потенциала. Подготовленная оборона имеет дополнительное преимущество."
    intel_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    intel_note.add_theme_font_size_override("font_size", 13)
    box.add_child(intel_note)

    var refresh_preview := func() -> void:
        var live_prefs: Dictionary = {}
        for k in UNIT_KEYS:
            var pct: float = float(sliders[k].value)
            var sent_amount: float = float(player[k]) * pct / 100.0
            var enemy_amount: float = float(enemy[k])
            live_prefs[k] = pct
            line_labels[k].text = "%s %s   ПРОТИВНИК: %.0f   |   ВЫ: %.0f (%.0f%%)" % [BATTLE_ICON.get(k, ""), UNIT_LABELS[k], enemy_amount, sent_amount, pct]
        var ap: float = _planning_attack_power(player, live_prefs)
        var dp: float = _planning_defense_power(enemy)
        var r: float = ap / maxf(1.0, dp)
        ratio_label.text = "СООТНОШЕНИЕ БОЕВОЙ МОЩИ: %.2f : 1" % r
        forecast.text = _forecast_text(r)

    for key in UNIT_KEYS:
        sliders[key].value_changed.connect(func(_v): refresh_preview.call())
    refresh_preview.call()

    var buttons := HBoxContainer.new()
    buttons.alignment = BoxContainer.ALIGNMENT_CENTER
    box.add_child(buttons)

    var cancel_btn := Button.new()
    cancel_btn.text = "ОТМЕНА"
    cancel_btn.custom_minimum_size = Vector2(190, 58)
    buttons.add_child(cancel_btn)

    var start_btn := Button.new()
    start_btn.text = "НАЧАТЬ ОПЕРАЦИЮ"
    start_btn.custom_minimum_size = Vector2(280, 58)
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
    dialog.popup_centered(Vector2i(700, 690))
