extends "res://main_game.gd"

const POP_GROWTH_ANNUAL := {
    "RU": -0.005, "US": 0.005, "CN": -0.002, "DE": -0.002,
    "FR": 0.002, "GB": 0.004, "IN": 0.008, "TR": 0.006,
    "JP": -0.005, "BR": 0.004
}

func _ensure_population_data() -> void:
    super._ensure_population_data()
    for id in countries.keys():
        if not countries[id].has("allies"):
            countries[id]["allies"] = []

func _economic_tick() -> void:
    super._economic_tick()
    # One economic tick is one game minute; 525600 minutes per year.
    for id in countries.keys():
        var annual: float = float(POP_GROWTH_ANNUAL.get(id, 0.003))
        countries[id].population = maxf(0.1, float(countries[id].population) * (1.0 + annual / 525600.0))

func _bot_tick() -> void:
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
                _push_news("%s наращивает вооружение: %s +100." % [c.name, UNIT_LABELS[key]])
        elif roll < 0.70 and c.treasury >= 250:
            c.treasury -= 250
            c.economy += 1.0
            c.income *= 1.01
            _push_news("%s инвестирует 250 млн в экономику. Экономический потенциал растёт." % c.name)
        elif roll < 0.78:
            _bot_diplomacy(id)
        elif roll > 0.90:
            _bot_may_attack(id)
    _refresh_all()

func _bot_diplomacy(id: String) -> void:
    var candidates: Array = countries.keys().filter(func(x): return x != id and x != player_id)
    if candidates.is_empty(): return
    var other: String = candidates.pick_random()
    if int(countries[id].relations.get(other, 0)) >= 35 and not _are_allies(id, other) and randf() < 0.20:
        _set_alliance(id, other, true)
        _push_news("СОЮЗ: %s и %s заключили союз." % [countries[id].name, countries[other].name])

func _are_allies(a_id: String, b_id: String) -> bool:
    return b_id in countries[a_id].get("allies", [])

func _set_alliance(a_id: String, b_id: String, enabled: bool) -> void:
    var aa: Array = countries[a_id].get("allies", [])
    var ba: Array = countries[b_id].get("allies", [])
    if enabled:
        if b_id not in aa: aa.append(b_id)
        if a_id not in ba: ba.append(a_id)
    else:
        aa.erase(b_id); ba.erase(a_id)
    countries[a_id]["allies"] = aa
    countries[b_id]["allies"] = ba

func _refresh_selected() -> void:
    super._refresh_selected()
    if selected_id == player_id or not countries.has(selected_id): return
    var allied := _are_allies(player_id, selected_id)
    _add_label(selected_panel, "Статус: %s" % ("СОЮЗНИК" if allied else "союза нет"), 18)
    var alliance_btn := Button.new()
    alliance_btn.text = "РАСТОРГНУТЬ СОЮЗ" if allied else "ПРЕДЛОЖИТЬ СОЮЗ"
    alliance_btn.pressed.connect(_toggle_alliance_with.bind(selected_id))
    selected_panel.add_child(alliance_btn)
    if allied:
        var money_btn := Button.new(); money_btn.text = "ПОМОЩЬ СОЮЗНИКУ: 100 МЛН"; money_btn.pressed.connect(_send_aid.bind(selected_id)); selected_panel.add_child(money_btn)
        var arms_btn := Button.new(); arms_btn.text = "ПЕРЕДАТЬ ВООРУЖЕНИЕ"; arms_btn.pressed.connect(_send_arms.bind(selected_id)); selected_panel.add_child(arms_btn)
        var request_money := Button.new(); request_money.text = "ЗАПРОСИТЬ 100 МЛН"; request_money.pressed.connect(_request_aid.bind(selected_id)); selected_panel.add_child(request_money)
        var request_arms := Button.new(); request_arms.text = "ЗАПРОСИТЬ ВООРУЖЕНИЕ"; request_arms.pressed.connect(_request_arms.bind(selected_id)); selected_panel.add_child(request_arms)
    _style_all_buttons(selected_panel)

func _toggle_alliance_with(target: String) -> void:
    if _are_allies(player_id, target):
        _set_alliance(player_id, target, false)
        _push_news("Россия и %s расторгли союз." % countries[target].name)
    else:
        var rel := int(countries[player_id].relations.get(target, 0))
        var chance := clampf(0.35 + float(rel) / 200.0, 0.10, 0.90)
        if randf() <= chance:
            _set_alliance(player_id, target, true)
            _push_news("СОЮЗ: Россия и %s заключили союз." % countries[target].name)
        else:
            _push_news("%s отклоняет предложение России о союзе." % countries[target].name)
    _refresh_all()

func _send_arms(target: String) -> void:
    var key: String = UNIT_KEYS.pick_random()
    var amount := minf(100.0, float(countries[player_id][key]))
    if amount <= 0: return
    countries[player_id][key] -= amount; countries[target][key] += amount
    _push_news("Россия передала союзнику %s вооружение: %s %.0f." % [countries[target].name, UNIT_LABELS[key], amount])
    _refresh_all()

func _request_aid(target: String) -> void:
    if float(countries[target].treasury) >= 100.0 and randf() < 0.65:
        countries[target].treasury -= 100.0; countries[player_id].treasury += 100.0
        _push_news("%s предоставила России союзную финансовую помощь: 100 млн." % countries[target].name)
    else: _push_news("%s отклонила запрос России о финансовой помощи." % countries[target].name)
    _refresh_all()

func _request_arms(target: String) -> void:
    var key: String = UNIT_KEYS.pick_random()
    if float(countries[target][key]) >= 100.0 and randf() < 0.60:
        countries[target][key] -= 100.0; countries[player_id][key] += 100.0
        _push_news("%s передала России вооружение: %s 100." % [countries[target].name, UNIT_LABELS[key]])
    else: _push_news("%s отклонила запрос России на поставку вооружения." % countries[target].name)
    _refresh_all()

func _resolve_battle(attacker_id: String, defender_id: String, attack_fraction: float, silent_bot: bool = false) -> void:
    var a: Dictionary = countries[attacker_id]; var d: Dictionary = countries[defender_id]
    if defender_id == player_id and attacker_id != player_id: _push_news("ВНИМАНИЕ: %s атакует Россию!" % a.name)
    var defense_fraction := _ai_defense_fraction(d)
    var ratio := (_combat_power(a, attack_fraction, false) * randf_range(0.90,1.10)) / maxf(1.0, _combat_power(d, defense_fraction, true) * randf_range(0.90,1.10))
    var a_loss := 0.12; var d_loss := 0.12; var winner := ""
    if ratio > 1.5: winner=attacker_id; a_loss=randf_range(.05,.12); d_loss=randf_range(.40,.60)
    elif ratio > 1.12: winner=attacker_id; a_loss=randf_range(.08,.15); d_loss=randf_range(.20,.35)
    elif ratio < .67: winner=defender_id; a_loss=randf_range(.40,.60); d_loss=randf_range(.05,.12)
    elif ratio < .89: winner=defender_id; a_loss=randf_range(.20,.35); d_loss=randf_range(.08,.15)
    else: a_loss=randf_range(.10,.20); d_loss=randf_range(.10,.20)
    var alosses := {}; var dlosses := {}; var apeop:=0.0; var dpeop:=0.0; var acost:=0.0; var dcost:=0.0
    for key in UNIT_KEYS:
        var al := float(a[key])*attack_fraction*a_loss; var dl := float(d[key])*defense_fraction*d_loss
        alosses[key]=al; dlosses[key]=dl; a[key]=maxf(0,float(a[key])-al); d[key]=maxf(0,float(d[key])-dl)
        apeop += al*float(PERSONNEL_PER_POWER_M[key])*1000000.0; dpeop += dl*float(PERSONNEL_PER_POWER_M[key])*1000000.0
        acost += al*float(UNIT_COST[key])/100.0; dcost += dl*float(UNIT_COST[key])/100.0
    a.population=maxf(.1,float(a.population)-apeop/1000000.0); d.population=maxf(.1,float(d.population)-dpeop/1000000.0)
    a.war_fatigue=minf(100,float(a.war_fatigue)+5); d.war_fatigue=minf(100,float(d.war_fatigue)+5)
    var reward:=0.0
    if winner!="": reward=dcost*.5 if winner==attacker_id else acost*.5; countries[winner].treasury+=reward
    var result := "без решающего результата" if winner=="" else "победа %s" % countries[winner].name
    _push_news("БИТВА: %s - %s: %s. Погибло: %s ~%d, %s ~%d. Потери вооружения: %.0f / %.0f млн." % [a.name,d.name,result,a.name,int(apeop),d.name,int(dpeop),acost,dcost])
    a.relations[defender_id]=max(-100,int(a.relations.get(defender_id,0))-25); d.relations[attacker_id]=max(-100,int(d.relations.get(attacker_id,0))-35)
    _refresh_all()
    if attacker_id==player_id: _show_detailed_report(defender_id,winner,apeop,dpeop,alosses,dlosses,acost,dcost,reward)
    elif defender_id==player_id: _show_attack_alert(attacker_id,winner)

func _show_detailed_report(target: String, winner: String, our_dead: float, enemy_dead: float, our_loss: Dictionary, enemy_loss: Dictionary, our_cost: float, enemy_cost: float, reward: float) -> void:
    var old_pause:=paused; paused=true
    var dialog:=AcceptDialog.new(); dialog.title="ИТОГИ ОПЕРАЦИИ"; dialog.ok_button_text="ЗАКРЫТЬ"
    var box:=VBoxContainer.new(); var result:="БЕЗ РЕШАЮЩЕГО РЕЗУЛЬТАТА"
    if winner==player_id: result="ПОБЕДА РОССИИ"
    elif winner==target: result="ОПЕРАЦИЯ НЕУДАЧНА"
    _add_label(box,result,24)
    _add_label(box,"РОССИЯ - население %.3f млн (-%d)" % [float(countries[player_id].population),int(our_dead)],19)
    for key in UNIT_KEYS: _add_label(box,"%s: %.0f (-%.0f)" % [UNIT_LABELS[key],float(countries[player_id][key]),float(our_loss[key])],18)
    _add_label(box,"Потери техники и вооружения: %.0f млн" % our_cost,19)
    _add_label(box,"%s - население %.3f млн (-%d)" % [countries[target].name,float(countries[target].population),int(enemy_dead)],19)
    for key in UNIT_KEYS: _add_label(box,"%s: %.0f (-%.0f)" % [UNIT_LABELS[key],float(countries[target][key]),float(enemy_loss[key])],18)
    _add_label(box,"Ущерб противнику: %.0f млн" % enemy_cost,19)
    _add_label(box,"Получено: +%.0f млн" % reward,19)
    _add_label(box,"Финансовый итог: %+.0f млн" % (reward-our_cost),20)
    dialog.add_child(box); add_child(dialog); _style_all_buttons(dialog)
    dialog.confirmed.connect(func(): paused=old_pause; dialog.queue_free())
    dialog.canceled.connect(func(): paused=old_pause; dialog.queue_free())
    dialog.popup_centered(Vector2i(760,780))
