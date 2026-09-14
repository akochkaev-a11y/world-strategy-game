extends "res://main_two_stage_war.gd"

const ECONOMIC_TICK_SECONDS := 30.0
const BATTLE_TIME_SCALE := 0.65

func _ready() -> void:
    super._ready()
    _remove_test_time_note(self)

func _process(delta: float) -> void:
    if paused:
        return
    minute_accum += delta * speed
    bot_accum += delta * speed
    while minute_accum >= ECONOMIC_TICK_SECONDS:
        minute_accum -= ECONOMIC_TICK_SECONDS
        _economic_tick()
    while bot_accum >= 5.0:
        bot_accum -= 5.0
        _bot_tick()

func _remove_test_time_note(node: Node) -> void:
    for child in node.get_children():
        if child is Label and str(child.text).find("1 секунда = 1 игровая минута") >= 0:
            child.queue_free()
        else:
            _remove_test_time_note(child)

func _show_fullscreen_battle(attacker_id: String, defender_id: String, winner: String, before_a: Dictionary, before_d: Dictionary, alosses: Dictionary, dlosses: Dictionary, apeop: float, dpeop: float, acost: float, dcost: float, transfer: float, a_financial: float, d_financial: float) -> void:
    var old_scale := Engine.time_scale
    Engine.time_scale = BATTLE_TIME_SCALE
    super._show_fullscreen_battle(attacker_id, defender_id, winner, before_a, before_d, alosses, dlosses, apeop, dpeop, acost, dcost, transfer, a_financial, d_financial)
    await get_tree().process_frame
    _compact_battle_overlay()

    while _battle_overlay_exists():
        await get_tree().process_frame
    Engine.time_scale = old_scale

func _battle_overlay_exists() -> bool:
    for child in get_children():
        if child is ColorRect and child.z_index >= 500:
            return true
    return false

func _compact_battle_overlay() -> void:
    var overlay: Control = null
    for child in get_children():
        if child is ColorRect and child.z_index >= 500:
            overlay = child as Control
            break
    if overlay == null:
        return

    var buttons: HBoxContainer = null
    var stack: Array[Node] = [overlay]
    while not stack.is_empty():
        var node: Node = stack.pop_back()
        for child in node.get_children():
            stack.push_back(child)
            if child is Button:
                var parent := child.get_parent()
                if parent is HBoxContainer:
                    buttons = parent as HBoxContainer
                    break
        if buttons != null:
            break

    if buttons != null and buttons.get_parent() != overlay:
        var old_parent := buttons.get_parent()
        old_parent.remove_child(buttons)
        overlay.add_child(buttons)
        buttons.anchor_left = 0.0
        buttons.anchor_right = 1.0
        buttons.anchor_top = 1.0
        buttons.anchor_bottom = 1.0
        buttons.offset_left = 12.0
        buttons.offset_right = -12.0
        buttons.offset_top = -62.0
        buttons.offset_bottom = -8.0

    stack = [overlay]
    while not stack.is_empty():
        var node: Node = stack.pop_back()
        for child in node.get_children():
            stack.push_back(child)
            if child is Label:
                var label := child as Label
                var text := str(label.text)
                if text.find("ФИНАНСОВЫЕ ИТОГИ") >= 0:
                    label.add_theme_font_size_override("font_size", 17)
                elif text.find("ПОБЕДА") >= 0 or text.find("НИЧЬЯ") >= 0:
                    label.add_theme_font_size_override("font_size", 22)
                elif text.find("Население:") >= 0 or text.find("Техника и вооружение:") >= 0 or text.find("Казна:") >= 0:
                    label.add_theme_font_size_override("font_size", 13)
                elif text.find("Итог ") >= 0 or text.find("Выплата проигравшего") >= 0:
                    label.add_theme_font_size_override("font_size", 14)
