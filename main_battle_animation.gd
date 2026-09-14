extends "res://main_world_ui.gd"

const FLAG := {
    "RU": "🇷🇺", "US": "🇺🇸", "CN": "🇨🇳", "DE": "🇩🇪", "FR": "🇫🇷",
    "GB": "🇬🇧", "IN": "🇮🇳", "TR": "🇹🇷", "JP": "🇯🇵", "BR": "🇧🇷"
}

const UNIT_ICON := {
    "army": "🪖",
    "air": "✈️",
    "navy": "🚢",
    "def": "🛡️",
    "missile": "🚀"
}

func _show_detailed_report(target: String, winner: String, our_dead: float, enemy_dead: float, our_loss: Dictionary, enemy_loss: Dictionary, our_cost: float, enemy_cost: float, reward: float) -> void:
    _play_battle_animation(target, winner, our_dead, enemy_dead, our_loss, enemy_loss, our_cost, enemy_cost, reward)

func _play_battle_animation(target: String, winner: String, our_dead: float, enemy_dead: float, our_loss: Dictionary, enemy_loss: Dictionary, our_cost: float, enemy_cost: float, reward: float) -> void:
    var old_pause := paused
    paused = true

    var dialog := AcceptDialog.new()
    dialog.title = "ХОД БОЯ"
    dialog.ok_button_text = ""
    dialog.exclusive = true

    var root := VBoxContainer.new()
    root.add_theme_constant_override("separation", 8)

    var title_row := HBoxContainer.new()
    title_row.alignment = BoxContainer.ALIGNMENT_CENTER
    root.add_child(title_row)

    var our_total_before := 0.0
    var enemy_total_before := 0.0
    for key in UNIT_KEYS:
        our_total_before += float(countries[player_id][key]) + float(our_loss.get(key, 0.0))
        enemy_total_before += float(countries[target][key]) + float(enemy_loss.get(key, 0.0))

    var left_head := Label.new()
    left_head.text = "%s  РОССИЯ\nВсего: %.0f" % [FLAG.get(player_id, "🏳️"), our_total_before]
    left_head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    left_head.custom_minimum_size.x = 240
    left_head.add_theme_font_size_override("font_size", 22)
    title_row.add_child(left_head)

    var vs := Label.new()
    vs.text = "  ⚔️  "
    vs.add_theme_font_size_override("font_size", 28)
    title_row.add_child(vs)

    var right_head := Label.new()
    right_head.text = "%s  %s\nВсего: %.0f" % [FLAG.get(target, "🏳️"), countries[target].name, enemy_total_before]
    right_head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    right_head.custom_minimum_size.x = 260
    right_head.add_theme_font_size_override("font_size", 22)
    title_row.add_child(right_head)

    var rows: Dictionary = {}
    for key in UNIT_KEYS:
        var row := HBoxContainer.new()
        row.alignment = BoxContainer.ALIGNMENT_CENTER
        root.add_child(row)

        var left := Label.new()
        left.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
        left.custom_minimum_size.x = 220
        left.add_theme_font_size_override("font_size", 20)
        row.add_child(left)

        var icon := Label.new()
        icon.text = "   %s   ⚔️   %s   " % [UNIT_ICON.get(key, "•"), UNIT_ICON.get(key, "•")]
        icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        icon.custom_minimum_size.x = 160
        icon.add_theme_font_size_override("font_size", 24)
        row.add_child(icon)

        var right := Label.new()
        right.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
        right.custom_minimum_size.x = 220
        right.add_theme_font_size_override("font_size", 20)
        row.add_child(right)

        rows[key] = {"left": left, "right": right}

    var status := Label.new()
    status.text = "БОЙ ИДЁТ..."
    status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    status.add_theme_font_size_override("font_size", 24)
    root.add_child(status)

    dialog.add_child(root)
    add_child(dialog)
    _style_all_buttons(dialog)
    dialog.popup_centered(Vector2i(760, 600))

    var steps := 14
    for step in range(steps + 1):
        var t := float(step) / float(steps)
        for key in UNIT_KEYS:
            var our_after := float(countries[player_id][key])
            var enemy_after := float(countries[target][key])
            var our_before := our_after + float(our_loss.get(key, 0.0))
            var enemy_before := enemy_after + float(enemy_loss.get(key, 0.0))
            var our_now := lerpf(our_before, our_after, t)
            var enemy_now := lerpf(enemy_before, enemy_after, t)
            rows[key]["left"].text = "%s  %.0f" % [UNIT_LABELS[key], our_now]
            rows[key]["right"].text = "%.0f  %s" % [enemy_now, UNIT_LABELS[key]]
        await get_tree().create_timer(0.10).timeout

    var our_total_after := 0.0
    var enemy_total_after := 0.0
    for key in UNIT_KEYS:
        our_total_after += float(countries[player_id][key])
        enemy_total_after += float(countries[target][key])

    left_head.text = "%s  РОССИЯ\nОсталось: %.0f (-%.0f)" % [FLAG.get(player_id, "🏳️"), our_total_after, our_total_before - our_total_after]
    right_head.text = "%s  %s\nОсталось: %.0f (-%.0f)" % [FLAG.get(target, "🏳️"), countries[target].name, enemy_total_after, enemy_total_before - enemy_total_after]

    if winner == player_id:
        status.text = "🏆 ПОБЕДА РОССИИ"
    elif winner == target:
        status.text = "ПОБЕДА %s" % countries[target].name
    else:
        status.text = "БОЙ БЕЗ РЕШАЮЩЕГО РЕЗУЛЬТАТА"

    await get_tree().create_timer(1.2).timeout
    dialog.queue_free()
    paused = old_pause
    super._show_detailed_report(target, winner, our_dead, enemy_dead, our_loss, enemy_loss, our_cost, enemy_cost, reward)
