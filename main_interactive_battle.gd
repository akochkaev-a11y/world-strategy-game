extends "res://main_game_tuning.gd"

# Player battles use a tactical node battlefield instead of the old passive animation.
# Bot-vs-bot battles keep the existing resolver.
const TACTICAL_KEYS := ["army", "air", "navy", "def", "missile"]
const TACTICAL_NAMES := {"army":"Сухопутные", "air":"Авиация", "navy":"Флот", "def":"ПВО/ПРО", "missile":"Ракеты"}
const TACTICAL_SYMBOLS := {"army":"■", "air":"▲", "navy":"◆", "def":"⬟", "missile":"●"}

var tactical_active := false

func _resolve_battle(attacker_id: String, defender_id: String, attack_fraction: float, silent_bot: bool = false) -> void:
    if attacker_id != player_id and defender_id != player_id:
        super._resolve_battle(attacker_id, defender_id, attack_fraction, silent_bot)
        return
    if tactical_active or _are_allies(attacker_id, defender_id):
        return
    _start_tactical_battle(attacker_id, defender_id, attack_fraction)

func _start_tactical_battle(attacker_id: String, defender_id: String, attack_fraction: float) -> void:
    tactical_active = true
    var old_paused := paused
    paused = true
    var player_side := attacker_id if attacker_id == player_id else defender_id
    var enemy_side := defender_id if attacker_id == player_id else attacker_id
    var player_force := {}
    var enemy_force := {}
    var initial_player := {}
    var initial_enemy := {}
    for key in TACTICAL_KEYS:
        var pf := float(countries[player_side][key]) * (attack_fraction if player_side == attacker_id else 1.0)
        var ef := float(countries[enemy_side][key]) * (1.0 if enemy_side == defender_id else attack_fraction)
        player_force[key] = pf; enemy_force[key] = ef
        initial_player[key] = pf; initial_enemy[key] = ef

    var deployed := {"СЕВЕР":{}, "ЦЕНТР":{}, "ЮГ":{}}
    var enemy_deployed := {"СЕВЕР":{}, "ЦЕНТР":{}, "ЮГ":{}}
    for zone in deployed.keys():
        for key in TACTICAL_KEYS:
            deployed[zone][key] = 0.0
            enemy_deployed[zone][key] = float(enemy_force[key]) / 3.0

    var overlay := ColorRect.new()
    overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    overlay.color = Color(0.025,0.035,0.05,0.995)
    overlay.mouse_filter = Control.MOUSE_FILTER_STOP
    overlay.z_index = 700
    add_child(overlay)
    var root := VBoxContainer.new()
    root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    root.add_theme_constant_override("separation", 8)
    root.offset_left=12; root.offset_right=-12; root.offset_top=10; root.offset_bottom=-10
    overlay.add_child(root)

    var title := Label.new()
    title.text = "%s   ТАКТИЧЕСКИЙ БОЙ   %s" % [countries[player_side].name, countries[enemy_side].name]
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.add_theme_font_size_override("font_size",22)
    root.add_child(title)
    var help := Label.new()
    help.text = "Выберите свой род войск слева, затем нажмите сектор поля боя. Повторное направление перебрасывает ещё 25% оставшихся сил."
    help.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
    root.add_child(help)

    var body := HBoxContainer.new(); body.size_flags_vertical=Control.SIZE_EXPAND_FILL; root.add_child(body)
    var left := VBoxContainer.new(); left.custom_minimum_size.x=210; body.add_child(left)
    var field := VBoxContainer.new(); field.size_flags_horizontal=Control.SIZE_EXPAND_FILL; body.add_child(field)
    var right := VBoxContainer.new(); right.custom_minimum_size.x=210; body.add_child(right)
    var selected_key := ["army"]
    var player_buttons := {}
    var enemy_labels := {}

    var lh:=Label.new(); lh.text="ВАШИ СИЛЫ"; lh.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; left.add_child(lh)
    var rh:=Label.new(); rh.text="ПРОТИВНИК"; rh.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; right.add_child(rh)
    for key in TACTICAL_KEYS:
        var b:=Button.new(); b.custom_minimum_size.y=58; left.add_child(b); player_buttons[key]=b
        b.pressed.connect(func(k=key): selected_key[0]=k)
        var l:=Label.new(); l.custom_minimum_size.y=58; l.vertical_alignment=VERTICAL_ALIGNMENT_CENTER; l.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; right.add_child(l); enemy_labels[key]=l

    var zone_buttons := {}
    var zone_labels := {}
    for zone in ["СЕВЕР","ЦЕНТР","ЮГ"]:
        var p:=PanelContainer.new(); p.size_flags_vertical=Control.SIZE_EXPAND_FILL; field.add_child(p)
        var vb:=VBoxContainer.new(); p.add_child(vb)
        var zb:=Button.new(); zb.text=zone; zb.custom_minimum_size.y=52; vb.add_child(zb); zone_buttons[zone]=zb
        var zl:=Label.new(); zl.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; zl.vertical_alignment=VERTICAL_ALIGNMENT_CENTER; zl.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; zl.size_flags_vertical=Control.SIZE_EXPAND_FILL; vb.add_child(zl); zone_labels[zone]=zl
        zb.pressed.connect(func(z=zone):
            var k:String=selected_key[0]
            var remaining:float=float(player_force[k])
            var send:float=maxf(0.0, remaining*0.25)
            deployed[z][k]=float(deployed[z][k])+send
            player_force[k]=remaining-send
        )

    var status:=Label.new(); status.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; status.text="Бой идёт - вы можете перебрасывать силы между направлениями"; root.add_child(status)
    var finish:=Button.new(); finish.text="ЗАВЕРШИТЬ БОЙ"; finish.custom_minimum_size.y=58; root.add_child(finish)

    var elapsed:=0.0
    var finished:=[false]
    finish.pressed.connect(func(): finished[0]=true)
    while not finished[0] and is_instance_valid(overlay):
        await get_tree().create_timer(0.35, true, false, true).timeout
        elapsed += 0.35
        _tactical_combat_step(deployed, enemy_deployed)
        # Enemy reinforces weak zones from its remaining reserve.
        if elapsed > 1.0:
            for key in TACTICAL_KEYS:
                if float(enemy_force[key]) > 0.0:
                    var z:String=["СЕВЕР","ЦЕНТР","ЮГ"].pick_random()
                    var send:float=float(enemy_force[key])*0.08
                    enemy_force[key]-=send; enemy_deployed[z][key]=float(enemy_deployed[z][key])+send
        for key in TACTICAL_KEYS:
            player_buttons[key].text="%s %s\n%.0f в резерве" % [TACTICAL_SYMBOLS[key],TACTICAL_NAMES[key],float(player_force[key])]
            var enemy_total:=float(enemy_force[key])
            for z in enemy_deployed.keys(): enemy_total += float(enemy_deployed[z][key])
            enemy_labels[key].text="%s %s\n%.0f" % [TACTICAL_SYMBOLS[key],TACTICAL_NAMES[key],enemy_total]
        for zone in zone_labels.keys():
            var ours:=0.0; var theirs:=0.0
            for key in TACTICAL_KEYS:
                ours+=float(deployed[zone][key]); theirs+=float(enemy_deployed[zone][key])
            zone_labels[zone].text="◀ %.0f      ⚔      %.0f ▶\n%s" % [ours,theirs,_tactical_zone_symbols(deployed[zone],enemy_deployed[zone])]
        if elapsed >= 45.0:
            finished[0]=true

    if is_instance_valid(overlay): overlay.queue_free()
    _finish_tactical_battle(player_side, enemy_side, attacker_id, defender_id, initial_player, initial_enemy, player_force, enemy_force, deployed, enemy_deployed)
    paused=old_paused
    tactical_active=false

func _tactical_zone_symbols(ours:Dictionary, theirs:Dictionary)->String:
    var a:=[]; var b:=[]
    for key in TACTICAL_KEYS:
        if float(ours[key])>0.5: a.append(TACTICAL_SYMBOLS[key])
        if float(theirs[key])>0.5: b.append(TACTICAL_SYMBOLS[key])
    return "%s     |     %s" % [" ".join(a)," ".join(b)]

func _tactical_combat_step(ours:Dictionary, theirs:Dictionary)->void:
    for zone in ours.keys():
        var a:Dictionary=ours[zone]; var d:Dictionary=theirs[zone]
        # Same-type clashes: ground-ground, air-air and fleet-fleet.
        for key in ["army","air","navy"]:
            var av:float=float(a[key]); var dv:float=float(d[key])
            if av>0.0 and dv>0.0:
                var al:=minf(av, dv*randf_range(0.004,0.010)); var dl:=minf(dv, av*randf_range(0.004,0.010))
                a[key]=av-al; d[key]=dv-dl
        # Air defence attacks surviving enemy aviation only; PVO never attacks PVO.
        if float(a.def)>0.0 and float(d.air)>0.0: d.air=maxf(0.0,float(d.air)-float(a.def)*randf_range(0.002,0.006))
        if float(d.def)>0.0 and float(a.air)>0.0: a.air=maxf(0.0,float(a.air)-float(d.def)*randf_range(0.002,0.006))
        # Surviving air and fleet strike ground without ground return fire.
        d.army=maxf(0.0,float(d.army)-float(a.air)*0.0015-float(a.navy)*0.0010)
        a.army=maxf(0.0,float(a.army)-float(d.air)*0.0015-float(d.navy)*0.0010)
        # PVO intercepts missiles; surviving missiles hit ground, air and fleet.
        var a_missile_pass:=maxf(0.0,float(a.missile)-float(d.def)*0.012)
        var d_missile_pass:=maxf(0.0,float(d.missile)-float(a.def)*0.012)
        if a_missile_pass>0.0:
            d.army=maxf(0.0,float(d.army)-a_missile_pass*0.8); d.air=maxf(0.0,float(d.air)-a_missile_pass*0.18); d.navy=maxf(0.0,float(d.navy)-a_missile_pass*0.12)
            a.missile=maxf(0.0,float(a.missile)-a_missile_pass*0.02)
        if d_missile_pass>0.0:
            a.army=maxf(0.0,float(a.army)-d_missile_pass*0.8); a.air=maxf(0.0,float(a.air)-d_missile_pass*0.18); a.navy=maxf(0.0,float(a.navy)-d_missile_pass*0.12)
            d.missile=maxf(0.0,float(d.missile)-d_missile_pass*0.02)
        # Surviving ground forces can destroy enemy PVO at close range.
        if float(a.army)>0.0: d.def=maxf(0.0,float(d.def)-float(a.army)*0.0007)
        if float(d.army)>0.0: a.def=maxf(0.0,float(a.def)-float(d.army)*0.0007)

func _finish_tactical_battle(player_side:String, enemy_side:String, attacker_id:String, defender_id:String, initial_player:Dictionary, initial_enemy:Dictionary, player_reserve:Dictionary, enemy_reserve:Dictionary, deployed:Dictionary, enemy_deployed:Dictionary)->void:
    var final_player:={}; var final_enemy:={}
    for key in TACTICAL_KEYS:
        final_player[key]=float(player_reserve[key]); final_enemy[key]=float(enemy_reserve[key])
        for z in deployed.keys(): final_player[key]+=float(deployed[z][key]); final_enemy[key]+=float(enemy_deployed[z][key])
        var ploss:=maxf(0.0,float(initial_player[key])-float(final_player[key])); var eloss:=maxf(0.0,float(initial_enemy[key])-float(final_enemy[key]))
        countries[player_side][key]=maxf(0.0,float(countries[player_side][key])-ploss)
        countries[enemy_side][key]=maxf(0.0,float(countries[enemy_side][key])-eloss)
        if key!="missile":
            countries[player_side].population=maxf(0.1,float(countries[player_side].population)-ploss/1000000.0)
            countries[enemy_side].population=maxf(0.1,float(countries[enemy_side].population)-eloss/1000000.0)
    var ptotal:=0.0; var etotal:=0.0
    for key in TACTICAL_KEYS: ptotal+=float(final_player[key]); etotal+=float(final_enemy[key])
    var winner:=player_side if ptotal>=etotal else enemy_side
    countries[player_side].war_fatigue=minf(100.0,float(countries[player_side].war_fatigue)+5.0)
    countries[enemy_side].war_fatigue=minf(100.0,float(countries[enemy_side].war_fatigue)+5.0)
    countries[player_side].relations[enemy_side]=-100; countries[enemy_side].relations[player_side]=-100
    _push_news("БИТВА: %s - %s: победа %s (тактический бой)." % [countries[attacker_id].name,countries[defender_id].name,countries[winner].name])
    _mark_activity(attacker_id,ACTIVITY_WAR,6); _mark_activity(defender_id,ACTIVITY_WAR,6)
    _refresh_all()
