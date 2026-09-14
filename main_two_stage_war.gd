extends "res://main_battle_planning.gd"

const INVASION_TREASURY_SHARE := 0.10
var battle_stage := "border"
var pending_counter_target := ""

func _resolve_battle(attacker_id: String, defender_id: String, attack_fraction: float, silent_bot: bool = false) -> void:
    if _are_allies(attacker_id, defender_id):
        return

    var a: Dictionary = countries[attacker_id]
    var d: Dictionary = countries[defender_id]
    var defense_fraction: float = 1.0 if battle_stage == "invasion" else _ai_defense_fraction(d)
    var ratio: float = (_combat_power(a, attack_fraction, false) * randf_range(0.90, 1.10)) / maxf(1.0, _combat_power(d, defense_fraction, true) * randf_range(0.90, 1.10))

    var a_loss := 0.16
    var d_loss := 0.12
    var winner := defender_id
    if ratio >= 4.0:
        winner=attacker_id; a_loss=randf_range(0.03,0.08); d_loss=randf_range(0.45,0.65)
    elif ratio >= 3.0:
        winner=attacker_id; a_loss=randf_range(0.05,0.12); d_loss=randf_range(0.30,0.50)
    elif ratio >= 2.0 and randf() < 0.55:
        winner=attacker_id; a_loss=randf_range(0.12,0.22); d_loss=randf_range(0.20,0.35)
    elif ratio >= 1.5 and randf() < 0.25:
        winner=attacker_id; a_loss=randf_range(0.15,0.25); d_loss=randf_range(0.18,0.30)
    elif ratio < 0.75:
        a_loss=randf_range(0.35,0.55); d_loss=randf_range(0.05,0.12)
    else:
        a_loss=randf_range(0.20,0.35); d_loss=randf_range(0.08,0.18)

    var before_a := {}; var before_d := {}; var alosses := {}; var dlosses := {}
    var apeop := 0.0; var dpeop := 0.0; var acost := 0.0; var dcost := 0.0
    for key in UNIT_KEYS:
        before_a[key]=float(a[key]); before_d[key]=float(d[key])
        var al: float=float(a[key])*attack_fraction*a_loss
        var dl: float=float(d[key])*defense_fraction*d_loss
        alosses[key]=al; dlosses[key]=dl
        a[key]=maxf(0.0,float(a[key])-al); d[key]=maxf(0.0,float(d[key])-dl)
        apeop += al*float(PERSONNEL_PER_POWER_M[key])*1000000.0
        dpeop += dl*float(PERSONNEL_PER_POWER_M[key])*1000000.0
        acost += al*float(UNIT_COST[key])/100.0; dcost += dl*float(UNIT_COST[key])/100.0
    a.population=maxf(0.1,float(a.population)-apeop/1000000.0); d.population=maxf(0.1,float(d.population)-dpeop/1000000.0)
    a.war_fatigue=minf(100.0,float(a.war_fatigue)+5.0); d.war_fatigue=minf(100.0,float(d.war_fatigue)+5.0)
    a.treasury=maxf(0.0,float(a.treasury)-acost); d.treasury=maxf(0.0,float(d.treasury)-dcost)

    var loser: String = defender_id if winner==attacker_id else attacker_id
    var loser_loss_cost: float = dcost if loser==defender_id else acost
    var loser_country: Dictionary = countries[loser]
    var transfer: float = minf(loser_loss_cost*0.5,float(loser_country.treasury))
    loser_country.treasury -= transfer; countries[winner].treasury += transfer
    var treasury_reparation := 0.0
    if battle_stage == "invasion":
        treasury_reparation = float(loser_country.treasury)*INVASION_TREASURY_SHARE
        loser_country.treasury -= treasury_reparation; countries[winner].treasury += treasury_reparation
        transfer += treasury_reparation

    var a_financial := -acost; var d_financial := -dcost
    if winner==attacker_id: a_financial+=transfer; d_financial-=transfer
    else: d_financial+=transfer; a_financial-=transfer

    var stage_name := "ВТОРЖЕНИЕ" if battle_stage=="invasion" else "ОБОРОНИТЕЛЬНЫЙ БОЙ"
    _push_news("БИТВА: %s - %s: победа %s (%s)." % [a.name,d.name,countries[winner].name,stage_name])
    a.relations[defender_id]=-100; d.relations[attacker_id]=-100
    _mark_activity(attacker_id,ACTIVITY_WAR,6); _mark_activity(defender_id,ACTIVITY_WAR,6); _refresh_all()

    if attacker_id==player_id or defender_id==player_id:
        pending_counter_target = attacker_id if defender_id==player_id and winner==player_id and battle_stage=="border" else ""
        _show_fullscreen_battle(attacker_id,defender_id,winner,before_a,before_d,alosses,dlosses,apeop,dpeop,acost,dcost,transfer,a_financial,d_financial)

func _open_attack_dialog(target: String) -> void:
    battle_stage="border"
    super._open_attack_dialog(target)

func _open_invasion_dialog(target: String) -> void:
    battle_stage="invasion"
    countries[player_id]["attack_prefs"]={"army":100.0,"air":100.0,"navy":100.0,"def":100.0,"missile":100.0}
    _resolve_battle(player_id,target,1.0,false)

func _add_treasury_to_battle_report(overlay: Control, attacker_id: String, defender_id: String, winner: String, transfer: float) -> void:
    var equipment_labels: Array[Label] = []
    var stack: Array[Node] = [overlay]
    while not stack.is_empty():
        var node: Node = stack.pop_back()
        for child in node.get_children():
            stack.push_back(child)
            if child is Label and str(child.text).begins_with("Техника и вооружение:"):
                equipment_labels.append(child as Label)
    if equipment_labels.size() < 2:
        return

    var countries_order := [attacker_id, defender_id]
    for i in range(2):
        var country_id: String = countries_order[i]
        var is_winner := winner != "" and country_id == winner
        var sign := "+" if is_winner and transfer > 0.0 else "-"
        var amount := transfer if transfer > 0.0 else 0.0
        var treasury_label := Label.new()
        treasury_label.add_theme_font_size_override("font_size", 15)
        treasury_label.text = "Казна: %.0f млн  (%s%.0f млн)" % [float(countries[country_id].treasury), sign, amount]
        if not is_winner and transfer > 0.0:
            treasury_label.add_theme_color_override("font_color", Color(0.95, 0.25, 0.25, 1.0))
        elif is_winner and transfer > 0.0:
            treasury_label.add_theme_color_override("font_color", Color(0.35, 0.95, 0.45, 1.0))
        equipment_labels[i].get_parent().add_child(treasury_label)

func _show_fullscreen_battle(attacker_id: String, defender_id: String, winner: String, before_a: Dictionary, before_d: Dictionary, alosses: Dictionary, dlosses: Dictionary, apeop: float, dpeop: float, acost: float, dcost: float, transfer: float, a_financial: float, d_financial: float) -> void:
    var overlay_before: Array[Node] = get_children()
    await super._show_fullscreen_battle(attacker_id,defender_id,winner,before_a,before_d,alosses,dlosses,apeop,dpeop,acost,dcost,transfer,a_financial,d_financial)
    for node in get_children():
        if node not in overlay_before and node is ColorRect:
            _add_treasury_to_battle_report(node as Control, attacker_id, defender_id, winner, transfer)
            break
    if pending_counter_target != "":
        var target := pending_counter_target
        pending_counter_target=""
        _show_counteroffensive_choice(target)

func _show_counteroffensive_choice(target: String) -> void:
    var dialog:=ConfirmationDialog.new()
    dialog.title="ПРОТИВНИК ОТБРОШЕН"
    dialog.dialog_text="Россия отразила нападение %s.\n\nЗавершить конфликт или перейти в контрнаступление?\nВторжение - бой ВСЕМИ оставшимися войсками.\nПобеда: 50%% стоимости потерь противника + 10%% его оставшейся казны." % str(countries[target].name)
    dialog.ok_button_text="ВТОРЖЕНИЕ"
    dialog.cancel_button_text="ЗАВЕРШИТЬ КОНФЛИКТ"
    add_child(dialog)
    dialog.confirmed.connect(func(): dialog.queue_free(); _open_invasion_dialog(target))
    dialog.canceled.connect(dialog.queue_free)
    dialog.popup_centered(Vector2i(720,420))
