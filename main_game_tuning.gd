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
    await super._show_fullscreen_battle(attacker_id, defender_id, winner, before_a, before_d, alosses, dlosses, apeop, dpeop, acost, dcost, transfer, a_financial, d_financial)
    Engine.time_scale = old_scale
