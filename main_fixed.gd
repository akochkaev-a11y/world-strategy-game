extends "res://main.gd"

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

func _open_attack_dialog(target: String) -> void:
    var dialog := AcceptDialog.new()
    dialog.title = "Военная операция против %s" % countries[target].name
    dialog.ok_button_text = ""

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

    start_btn.pressed.connect(func():
        var weighted: float = 0.0
        for key in UNIT_KEYS:
            weighted += float(sliders[key].value) / 100.0
        var avg_fraction: float = clampf(weighted / float(UNIT_KEYS.size()), 0.05, 1.0)
        _resolve_battle(player_id, target, avg_fraction, false)
        dialog.queue_free()
    )

    cancel_btn.pressed.connect(dialog.queue_free)
    dialog.canceled.connect(dialog.queue_free)
    dialog.popup_centered(Vector2i(620, 360))
