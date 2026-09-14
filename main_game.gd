extends "res://main_fixed.gd"

# More active geopolitics: bots are now much more willing to attack,
# and Russia is deliberately included as a meaningful target instead of
# being lost in a purely random target roll.
func _bot_may_attack(attacker_id: String) -> void:
    var candidates: Array = countries.keys().filter(func(x): return x != attacker_id)
    if candidates.is_empty():
        return

    var defender_id: String
    # About one third of bot attack attempts are aimed at the player.
    # The remaining attempts still create wars between AI countries.
    if player_id != attacker_id and randf() < 0.35:
        defender_id = player_id
    else:
        defender_id = candidates.pick_random()

    var a: Dictionary = countries[attacker_id]
    var d: Dictionary = countries[defender_id]
    var strength_ratio: float = _total_power(a) / maxf(1.0, _total_power(d))
    var relations: int = int(a.relations.get(defender_id, 0))

    var threshold: float = 1.15
    if a.ai == "агрессивный":
        threshold = 0.82
    elif a.ai == "осторожный":
        threshold = 1.35

    # Bad relations make a risky attack more likely.
    if relations <= -50:
        threshold -= 0.20
    elif relations <= -20:
        threshold -= 0.10

    if strength_ratio > threshold:
        _resolve_battle(attacker_id, defender_id, randf_range(0.18, 0.35), true)

func _resolve_battle(attacker_id: String, defender_id: String, attack_fraction: float, silent_bot: bool = false) -> void:
    var a: Dictionary = countries[attacker_id]
    var d: Dictionary = countries[defender_id]

    if defender_id == player_id and attacker_id != player_id:
        _push_news("ВНИМАНИЕ: %s атакует Россию!" % a.name)

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

    var attacker_people_lost: float = 0.0
    var defender_people_lost: float = 0.0
    var attacker_economic_loss: float = 0.0
    var defender_economic_loss: float = 0.0

    for key in UNIT_KEYS:
        var av: float = float(a[key]) * attack_fraction
        var dv: float = float(d[key]) * defense_fraction
        var al: float = av * a_loss
        var dl: float = dv * d_loss

        a[key] = maxf(0.0, float(a[key]) - al)
        d[key] = maxf(0.0, float(d[key]) - dl)

        attacker_people_lost += al * float(PERSONNEL_PER_POWER_M[key]) * 1000000.0
        defender_people_lost += dl * float(PERSONNEL_PER_POWER_M[key]) * 1000000.0
        attacker_economic_loss += al * float(UNIT_COST[key]) / 100.0
        defender_economic_loss += dl * float(UNIT_COST[key]) / 100.0

    a.war_fatigue = minf(100.0, float(a.war_fatigue) + 5.0)
    d.war_fatigue = minf(100.0, float(d.war_fatigue) + 5.0)

    var reward: float = 0.0
    if winner != "":
        reward = defender_economic_loss * 0.5 if winner == attacker_id else attacker_economic_loss * 0.5
        countries[winner].treasury += reward

    var result_text := "без решающего результата"
    if winner == attacker_id:
        result_text = "победа %s" % a.name
    elif winner == defender_id:
        result_text = "победа %s" % d.name

    # Every battle goes into world news, including AI-vs-AI wars.
    _push_news("БИТВА: %s - %s: %s. Потери: %s - ~%d чел., %.0f млн; %s - ~%d чел., %.0f млн." % [
        a.name, d.name, result_text,
        a.name, int(attacker_people_lost), attacker_economic_loss,
        d.name, int(defender_people_lost), defender_economic_loss
    ])

    a.relations[defender_id] = max(-100, int(a.relations.get(defender_id, 0)) - 25)
    d.relations[attacker_id] = max(-100, int(d.relations.get(attacker_id, 0)) - 35)

    if not silent_bot or attacker_id == player_id or defender_id == player_id:
        selected_id = defender_id

    _refresh_all()

    if attacker_id == player_id:
        _show_operation_report(defender_id, winner, attacker_people_lost, defender_people_lost, attacker_economic_loss, defender_economic_loss, reward)
    elif defender_id == player_id:
        _show_attack_alert(attacker_id, winner)

func _show_operation_report(target_id: String, winner: String, our_people_lost: float, enemy_people_lost: float, our_economic_loss: float, enemy_economic_loss: float, reward: float) -> void:
    var was_paused := paused
    paused = true

    var dialog := AcceptDialog.new()
    dialog.title = "ИТОГИ ОПЕРАЦИИ"
    dialog.ok_button_text = "ЗАКРЫТЬ"

    var box := VBoxContainer.new()
    var result_text := "Операция завершилась без решающего результата."
    if winner == player_id:
        result_text = "ПОБЕДА РОССИИ"
    elif winner == target_id:
        result_text = "ОПЕРАЦИЯ НЕУДАЧНА"

    _add_label(box, result_text, 24)
    _add_label(box, "Противник: %s" % countries[target_id].name, 19)
    _add_label(box, "Наши потери: ~%d человек" % int(our_people_lost), 19)
    _add_label(box, "Экономические потери: %.0f млн" % our_economic_loss, 19)
    _add_label(box, "Потери противника: ~%d человек" % int(enemy_people_lost), 19)
    _add_label(box, "Ущерб противнику: %.0f млн" % enemy_economic_loss, 19)
    _add_label(box, "Получено: +%.0f млн" % reward, 19)
    _add_label(box, "Финансовый итог: %+.0f млн" % (reward - our_economic_loss), 20)

    dialog.add_child(box)
    add_child(dialog)
    _style_all_buttons(dialog)
    dialog.confirmed.connect(func():
        paused = was_paused
        dialog.queue_free()
    )
    dialog.canceled.connect(func():
        paused = was_paused
        dialog.queue_free()
    )
    dialog.popup_centered(Vector2i(720, 500))
