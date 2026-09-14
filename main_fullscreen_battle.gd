extends "res://main_world_ui.gd"

const BATTLE_FLAG := {
    "RU":"🇷🇺","US":"🇺🇸","UA":"🇺🇦","PL":"🇵🇱","CN":"🇨🇳","DE":"🇩🇪","FR":"🇫🇷","GB":"🇬🇧","IN":"🇮🇳","IR":"🇮🇷","TR":"🇹🇷","JP":"🇯🇵","BR":"🇧🇷"
}
const BATTLE_ICON := {"army":"🪖","air":"✈️","navy":"🚢","def":"🛡️","missile":"🚀"}
const BATTLE_PHASES := [
    {"key":"army", "title":"СУХОПУТНЫЙ БОЙ", "effect":"💥"},
    {"key":"air", "title":"АВИАЦИОННЫЙ УДАР", "effect":"✦"},
    {"key":"navy", "title":"УДАР ФЛОТА", "effect":"💥"},
    {"key":"def", "title":"ПВО / ПРО", "effect":"⚡"},
    {"key":"missile", "title":"РАКЕТНЫЙ ЗАЛП", "effect":"🔥"}
]

func _panel_style(bg: Color, border: Color, width: int = 2, radius: int = 10) -> StyleBoxFlat:
    var s := StyleBoxFlat.new()
    s.bg_color = bg
    s.border_color = border
    s.set_border_width_all(width)
    s.set_corner_radius_all(radius)
    s.content_margin_left = 12
    s.content_margin_right = 12
    s.content_margin_top = 8
    s.content_margin_bottom = 8
    return s

func _visual_unit_count(amount: float, key: String) -> int:
    if amount <= 0.0:
        return 0
    var baseline := 100000.0
    if key == "missile":
        baseline = 1000.0
    var scaled := 2.0 + 6.0 * sqrt(amount / baseline)
    return clampi(int(round(scaled)), 2, 18)

func _unit_cloud(icon: String, count: int) -> String:
    if count <= 0:
        return "—"
    var parts: Array[String] = []
    for i in range(count):
        parts.append(icon)
    return " ".join(parts)

func _phase_amount(before: Dictionary, losses: Dictionary, key: String, progress: float) -> float:
    return maxf(0.0, float(before.get(key, 0.0)) - float(losses.get(key, 0.0)) * progress)

func _resolve_battle(attacker_id: String, defender_id: String, attack_fraction: float, silent_bot: bool = false) -> void:
    if _are_allies(attacker_id, defender_id):
        return

    var a: Dictionary = countries[attacker_id]
    var d: Dictionary = countries[defender_id]
    var defense_fraction := _ai_defense_fraction(d)
    var ratio := (_combat_power(a, attack_fraction, false) * randf_range(0.90, 1.10)) / maxf(1.0, _combat_power(d, defense_fraction, true) * randf_range(0.90, 1.10))

    var a_loss := 0.12
    var d_loss := 0.12
    var winner := ""
    if ratio > 1.5:
        winner = attacker_id; a_loss = randf_range(0.05,0.12); d_loss = randf_range(0.40,0.60)
    elif ratio > 1.12:
        winner = attacker_id; a_loss = randf_range(0.08,0.15); d_loss = randf_range(0.20,0.35)
    elif ratio < 0.67:
        winner = defender_id; a_loss = randf_range(0.40,0.60); d_loss = randf_range(0.05,0.12)
    elif ratio < 0.89:
        winner = defender_id; a_loss = randf_range(0.20,0.35); d_loss = randf_range(0.08,0.15)
    else:
        a_loss = randf_range(0.10,0.20); d_loss = randf_range(0.10,0.20)

    var before_a := {}
    var before_d := {}
    var alosses := {}
    var dlosses := {}
    var apeop := 0.0
    var dpeop := 0.0
    var acost := 0.0
    var dcost := 0.0

    for key in UNIT_KEYS:
        before_a[key] = float(a[key])
        before_d[key] = float(d[key])
        var al := float(a[key]) * attack_fraction * a_loss
        var dl := float(d[key]) * defense_fraction * d_loss
        alosses[key] = al
        dlosses[key] = dl
        a[key] = maxf(0.0, float(a[key]) - al)
        d[key] = maxf(0.0, float(d[key]) - dl)
        apeop += al * float(PERSONNEL_PER_POWER_M[key]) * 1000000.0
        dpeop += dl * float(PERSONNEL_PER_POWER_M[key]) * 1000000.0
        acost += al * float(UNIT_COST[key]) / 100.0
        dcost += dl * float(UNIT_COST[key]) / 100.0

    a.population = maxf(0.1, float(a.population) - apeop / 1000000.0)
    d.population = maxf(0.1, float(d.population) - dpeop / 1000000.0)
    a.war_fatigue = minf(100.0, float(a.war_fatigue) + 5.0)
    d.war_fatigue = minf(100.0, float(d.war_fatigue) + 5.0)

    a.treasury = maxf(0.0, float(a.treasury) - acost)
    d.treasury = maxf(0.0, float(d.treasury) - dcost)
    var transfer := 0.0
    var loser := ""
    if winner != "":
        loser = defender_id if winner == attacker_id else attacker_id
        var loser_country: Dictionary = countries[loser]
        var base_transfer := (dcost if loser == defender_id else acost) * 0.5
        transfer = minf(base_transfer, float(loser_country.treasury))
        loser_country.treasury -= transfer
        countries[winner].treasury += transfer

    var a_financial := -acost
    var d_financial := -dcost
    if winner == attacker_id:
        a_financial += transfer
        d_financial -= transfer
    elif winner == defender_id:
        d_financial += transfer
        a_financial -= transfer

    var result := "без решающего результата" if winner == "" else "победа %s" % countries[winner].name
    _push_news("БИТВА: %s - %s: %s." % [a.name, d.name, result])
    a.relations[defender_id] = max(-100, int(a.relations.get(defender_id,0)) - 25)
    d.relations[attacker_id] = max(-100, int(d.relations.get(attacker_id,0)) - 35)
    _mark_activity(attacker_id, ACTIVITY_WAR, 6)
    _mark_activity(defender_id, ACTIVITY_WAR, 6)
    _refresh_all()

    if attacker_id == player_id or defender_id == player_id:
        _show_fullscreen_battle(attacker_id, defender_id, winner, before_a, before_d, alosses, dlosses, apeop, dpeop, acost, dcost, transfer, a_financial, d_financial)

func _show_fullscreen_battle(attacker_id: String, defender_id: String, winner: String, before_a: Dictionary, before_d: Dictionary, alosses: Dictionary, dlosses: Dictionary, apeop: float, dpeop: float, acost: float, dcost: float, transfer: float, a_financial: float, d_financial: float) -> void:
    var previous_pause := paused
    paused = true

    var overlay := ColorRect.new()
    overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    overlay.color = Color(0.015,0.025,0.045,0.99)
    overlay.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(overlay)
    overlay.z_index = 500

    var margin := MarginContainer.new()
    margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    margin.add_theme_constant_override("margin_left", 16)
    margin.add_theme_constant_override("margin_right", 16)
    margin.add_theme_constant_override("margin_top", 12)
    margin.add_theme_constant_override("margin_bottom", 12)
    overlay.add_child(margin)

    var root := VBoxContainer.new()
    root.add_theme_constant_override("separation", 8)
    margin.add_child(root)

    var header := PanelContainer.new()
    header.add_theme_stylebox_override("panel", _panel_style(Color(0.03,0.08,0.14,1), Color(0.15,0.55,0.95,1), 2, 8))
    root.add_child(header)
    var hrow := HBoxContainer.new()
    header.add_child(hrow)
    var left_title := Label.new()
    left_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    left_title.text = "%s  %s" % [BATTLE_FLAG.get(attacker_id,"🏳️"), countries[attacker_id].name]
    left_title.add_theme_font_size_override("font_size",24)
    hrow.add_child(left_title)
    var center_title := Label.new()
    center_title.text = "ХОД БОЯ\nРАУНД 1 ИЗ 5"
    center_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    center_title.add_theme_font_size_override("font_size",21)
    hrow.add_child(center_title)
    var right_title := Label.new()
    right_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    right_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    right_title.text = "%s  %s" % [countries[defender_id].name, BATTLE_FLAG.get(defender_id,"🏳️")]
    right_title.add_theme_font_size_override("font_size",24)
    hrow.add_child(right_title)

    var battle_panel := PanelContainer.new()
    battle_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
    battle_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.02,0.045,0.075,1), Color(0.10,0.32,0.52,1), 2, 8))
    root.add_child(battle_panel)
    var battle_box := VBoxContainer.new()
    battle_box.alignment = BoxContainer.ALIGNMENT_CENTER
    battle_box.add_theme_constant_override("separation", 8)
    battle_panel.add_child(battle_box)

    var phase_title := Label.new()
    phase_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    phase_title.add_theme_font_size_override("font_size",24)
    battle_box.add_child(phase_title)

    var counts := HBoxContainer.new()
    battle_box.add_child(counts)
    var left_count := Label.new()
    left_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    left_count.add_theme_font_size_override("font_size",17)
    counts.add_child(left_count)
    var phase_status := Label.new()
    phase_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    phase_status.custom_minimum_size.x = 260
    phase_status.add_theme_font_size_override("font_size",18)
    counts.add_child(phase_status)
    var right_count := Label.new()
    right_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    right_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    right_count.add_theme_font_size_override("font_size",17)
    counts.add_child(right_count)

    var visual_row := HBoxContainer.new()
    visual_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
    visual_row.alignment = BoxContainer.ALIGNMENT_CENTER
    battle_box.add_child(visual_row)
    var left_units := Label.new()
    left_units.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    left_units.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    left_units.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    left_units.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    left_units.add_theme_font_size_override("font_size",27)
    visual_row.add_child(left_units)
    var clash := Label.new()
    clash.custom_minimum_size = Vector2(180,100)
    clash.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    clash.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    clash.add_theme_font_size_override("font_size",36)
    visual_row.add_child(clash)
    var right_units := Label.new()
    right_units.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    right_units.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
    right_units.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    right_units.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    right_units.add_theme_font_size_override("font_size",27)
    visual_row.add_child(right_units)

    var loss_line := Label.new()
    loss_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    loss_line.add_theme_font_size_override("font_size",15)
    battle_box.add_child(loss_line)

    var summary := HBoxContainer.new()
    summary.add_theme_constant_override("separation",6)
    battle_box.add_child(summary)
    var summary_labels := {}
    for key in UNIT_KEYS:
        var l := Label.new()
        l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        l.add_theme_font_size_override("font_size",14)
        summary.add_child(l)
        summary_labels[key] = l

    var result_panel := PanelContainer.new()
    result_panel.add_theme_stylebox_override("panel",_panel_style(Color(0.02,0.08,0.04,1),Color(0.15,0.85,0.35,1),2,8))
    root.add_child(result_panel)
    var result_box := VBoxContainer.new()
    result_panel.add_child(result_box)
    var result_title := Label.new()
    result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    result_title.add_theme_font_size_override("font_size",28)
    result_title.text = "БОЙ ИДЁТ..."
    result_box.add_child(result_title)

    var columns := HBoxContainer.new()
    columns.add_theme_constant_override("separation",8)
    result_box.add_child(columns)
    var left_report := VBoxContainer.new()
    left_report.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    columns.add_child(left_report)
    var finance := VBoxContainer.new()
    finance.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    columns.add_child(finance)
    var right_report := VBoxContainer.new()
    right_report.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    columns.add_child(right_report)

    var buttons := HBoxContainer.new()
    buttons.alignment = BoxContainer.ALIGNMENT_CENTER
    result_box.add_child(buttons)
    var counter_btn := Button.new()
    counter_btn.text = "ОТВЕТНЫЙ УДАР"
    counter_btn.visible = false
    counter_btn.custom_minimum_size = Vector2(240,58)
    buttons.add_child(counter_btn)
    var close_btn := Button.new()
    close_btn.text = "ЗАКРЫТЬ"
    close_btn.custom_minimum_size = Vector2(240,58)
    close_btn.disabled = true
    buttons.add_child(close_btn)

    for phase_index in range(BATTLE_PHASES.size()):
        var phase: Dictionary = BATTLE_PHASES[phase_index]
        var key: String = str(phase.key)
        var icon: String = str(BATTLE_ICON[key])
        center_title.text = "ХОД БОЯ\nРАУНД %d ИЗ 5" % (phase_index + 1)
        phase_title.text = "%s  %s  %s" % [icon, str(phase.title), icon]

        for pulse in range(4):
            var progress := float(pulse + 1) / 4.0
            var a_now := _phase_amount(before_a, alosses, key, progress)
            var d_now := _phase_amount(before_d, dlosses, key, progress)
            var a_vis := _visual_unit_count(a_now, key)
            var d_vis := _visual_unit_count(d_now, key)
            left_units.text = _unit_cloud(icon, a_vis)
            right_units.text = _unit_cloud(icon, d_vis)
            left_count.text = "%s: %.0f" % [UNIT_LABELS[key], a_now]
            right_count.text = "%.0f :%s" % [d_now, UNIT_LABELS[key]]

            if key == "air":
                clash.text = "✈️  %s  🛡️\n%s" % [str(phase.effect), "💥" if pulse % 2 == 1 else "✦"]
                phase_status.text = "Авиация под огнём ПВО"
            elif key == "def":
                clash.text = "🚀  ➜  🛡️\n%s" % ("💥" if pulse % 2 == 1 else "⚡")
                phase_status.text = "Перехват воздушных целей"
            elif key == "missile":
                clash.text = "🚀  ➜  %s  ⬅  🚀" % ("🔥" if pulse % 2 == 1 else "💥")
                phase_status.text = "Массированный ракетный залп"
            elif key == "navy":
                clash.text = "🚢  ➜  %s  ⬅  🚢" % str(phase.effect)
                phase_status.text = "Корабельная артиллерия и ракеты"
            else:
                clash.text = "🪖  ➜  %s  ⬅  🪖" % str(phase.effect)
                phase_status.text = "Сухопутные силы сходятся"

            loss_line.text = "Потери фазы: %s -%.0f   |   %s -%.0f" % [str(countries[attacker_id].name), float(alosses[key]) * progress, str(countries[defender_id].name), float(dlosses[key]) * progress]
            for summary_key in UNIT_KEYS:
                var phase_fraction := 1.0 if UNIT_KEYS.find(summary_key) < phase_index else (progress if summary_key == key else 0.0)
                var sa := _phase_amount(before_a, alosses, summary_key, phase_fraction)
                var sd := _phase_amount(before_d, dlosses, summary_key, phase_fraction)
                summary_labels[summary_key].text = "%s\n%.0f | %.0f" % [BATTLE_ICON[summary_key], sa, sd]
            await get_tree().create_timer(0.16).timeout

        clash.text = "%s   💥   %s" % [icon, icon]
        await get_tree().create_timer(0.18).timeout

    var a_name: String = str(countries[attacker_id].name)
    var d_name: String = str(countries[defender_id].name)
    result_title.text = "НИЧЬЯ / БЕЗ РЕШАЮЩЕГО РЕЗУЛЬТАТА" if winner=="" else "★ ПОБЕДА %s" % str(countries[winner].name).to_upper()

    _add_label(left_report,"%s %s" % [BATTLE_FLAG.get(attacker_id,"🏳️"),a_name],21)
    _add_label(left_report,"Население: %.3f млн  (-%d)" % [float(countries[attacker_id].population),int(apeop)],16)
    for key in UNIT_KEYS:
        _add_label(left_report,"%s: %.0f  (-%.0f)" % [UNIT_LABELS[key],float(countries[attacker_id][key]),float(alosses[key])],15)
    _add_label(left_report,"Техника и вооружение: -%.0f млн" % acost,17)

    _add_label(right_report,"%s %s" % [d_name,BATTLE_FLAG.get(defender_id,"🏳️")],21)
    _add_label(right_report,"Население: %.3f млн  (-%d)" % [float(countries[defender_id].population),int(dpeop)],16)
    for key in UNIT_KEYS:
        _add_label(right_report,"%s: %.0f  (-%.0f)" % [UNIT_LABELS[key],float(countries[defender_id][key]),float(dlosses[key])],15)
    _add_label(right_report,"Техника и вооружение: -%.0f млн" % dcost,17)

    _add_label(finance,"ФИНАНСОВЫЕ ИТОГИ",21)
    if winner != "":
        _add_label(finance,"Выплата проигравшего: %.0f млн" % transfer,16)
    _add_label(finance,"Итог %s: %+.0f млн" % [a_name,a_financial],18)
    _add_label(finance,"Итог %s: %+.0f млн" % [d_name,d_financial],18)

    close_btn.disabled = false
    if defender_id == player_id and attacker_id != player_id:
        counter_btn.visible = true

    close_btn.pressed.connect(func():
        paused = previous_pause
        overlay.queue_free()
    )
    counter_btn.pressed.connect(func():
        paused = previous_pause
        overlay.queue_free()
        selected_id = attacker_id
        _refresh_selected()
        _open_attack_dialog(attacker_id)
    )
