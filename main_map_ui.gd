extends "res://main_interactive_battle.gd"

var world_map: Control
var map_action_bar: HBoxContainer

func _total_power(c: Dictionary) -> float:
    return float(c.get("army", 0.0)) + float(c.get("missile", 0.0))

func _military_rating(c: Dictionary) -> int:
    return int(round(_total_power(c) / 10000.0))

func _military_population(c: Dictionary) -> float:
    return float(c.get("army", 0.0)) * 4.0 / 1000000.0

func _can_recruit(c: Dictionary, key: String, amount: float) -> bool:
    if key == "missile": return true
    var population: float=maxf(0.1,float(c.get("population",100.0)))
    return _military_population(c)+amount*4.0/1000000.0 <= population*0.12

func _military_upkeep(c: Dictionary) -> float:
    return float(c.get("army",0.0))*4.0*MILITARY_UPKEEP_PER_PERSON + float(c.get("missile",0.0))*0.00008

func _unit_price(id: String,key: String) -> float:
    var c: Dictionary=countries[id]
    var current: float=float(c.get(key,0.0))
    var base: float=float(UNIT_COST.get(key,20.0))
    return base*(1.0+current/20000.0)

func _bot_demobilize_step(c: Dictionary) -> void:
    c.army=maxf(0.0,float(c.get("army",0.0))*(1.0-BOT_DEMOBILIZE_SHARE))
    if _raw_net_income(c)<=0.0: c.missile=maxf(0.0,float(c.get("missile",0.0))*(1.0-BOT_DEMOBILIZE_SHARE))

func _bot_tick() -> void:
    _tick_activity(); _tick_war_cooldowns()
    for id in countries.keys():
        if id==player_id: continue
        var c: Dictionary=countries[id]
        if _bot_needs_recovery(c):
            c.economic_recovery=true; _bot_demobilize_step(c); _mark_activity(id,ACTIVITY_ECONOMY); continue
        c.economic_recovery=false
        var spendable: float=_bot_spendable_treasury(c)
        var effective: float=_effective_income(c)
        var net_income: float=_raw_net_income(c)
        var reserve: float=float(c.get("protected_treasury",0.0))
        var roll: float=randf()
        if roll<0.42 and spendable>150.0 and reserve>=effective*3.0 and net_income>=effective*0.20:
            var key: String=["army","missile"].pick_random()
            var price: float=_unit_price(id,key)
            if spendable>=price and _can_recruit(c,key,100.0): c.treasury-=price; c[key]+=100.0; _mark_activity(id,ACTIVITY_MILITARY)
        elif roll<0.62 and spendable>=250.0 and reserve>=effective:
            c.treasury-=250.0; c.economy+=1.0; c.income*=1.01; _mark_activity(id,ACTIVITY_ECONOMY)
        elif roll<0.78: _bot_diplomacy(id)
        elif roll>0.97 and net_income>=effective*0.20: _bot_may_attack(id)
    _refresh_all()

func _seed_countries() -> void:
    countries = {
        "RU": _c("Россия",4200,25,330000,0,0,0,6500,"рациональный"),
        "UA": _c("Украина",1200,7,225000,0,0,0,2700,"агрессивный"),
        "PL": _c("Польша",1800,15,54000,0,0,0,1600,"осторожный"),
        "FR": _c("Франция",3000,24,51250,0,0,0,3100,"дипломатический"),
        "DE": _c("Германия",3200,35,46000,0,0,0,1600,"осторожный"),
        "GB": _c("Великобритания",3100,24,35250,0,0,0,3000,"дипломатический"),
        "CN": _c("Китай",7600,75,508750,0,0,0,8100,"экономический"),
        "IN": _c("Индия",3500,30,363750,0,0,0,4500,"авантюрный"),
        "IR": _c("Иран",1500,10,152500,0,0,0,4400,"агрессивный"),
        "JP": _c("Япония",3000,32,61750,0,0,0,2000,"осторожный")
    }
    countries["RU"]["population"]=146.0; countries["UA"]["population"]=38.0; countries["PL"]["population"]=37.5
    countries["FR"]["population"]=68.6; countries["DE"]["population"]=84.5; countries["GB"]["population"]=69.5
    countries["CN"]["population"]=1408.0; countries["IN"]["population"]=1460.0; countries["IR"]["population"]=91.0; countries["JP"]["population"]=123.0
    var relations: Dictionary={}
    for a in countries.keys():
        relations[a]={}
        for b in countries.keys():
            if a!=b: relations[a][b]=randi_range(-20,30)
    for id in countries.keys(): countries[id]["relations"]=relations[id]

func _build_ui() -> void:
    super._build_ui()
    var left_scroll:=countries_box.get_parent()
    if left_scroll is Control: left_scroll.hide()
    var world: VBoxContainer=tabs.get_node("Карта")
    for child in world.get_children(): child.queue_free()
    var header:=Label.new(); header.text="ПОЛИТИЧЕСКАЯ КАРТА - ЕВРОПА И ЕВРАЗИЯ"; header.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; header.add_theme_font_size_override("font_size",20); world.add_child(header)
    world_map=preload("res://world_map.gd").new(); world_map.name="WorldMap"; world_map.size_flags_horizontal=Control.SIZE_EXPAND_FILL; world_map.size_flags_vertical=Control.SIZE_EXPAND_FILL; world.add_child(world_map); world_map.country_clicked.connect(_on_map_country_clicked)
    map_action_bar=HBoxContainer.new(); map_action_bar.alignment=BoxContainer.ALIGNMENT_CENTER; map_action_bar.add_theme_constant_override("separation",5); world.add_child(map_action_bar)
    var troop_btn:=Button.new(); troop_btn.text="АТАКОВАТЬ"; troop_btn.custom_minimum_size=Vector2(105,44); troop_btn.pressed.connect(func():
        if selected_id!=player_id: _open_attack_dialog(selected_id)
    ); map_action_bar.add_child(troop_btn)
    var diplomacy_btn:=Button.new(); diplomacy_btn.text="ДИПЛОМАТИЯ"; diplomacy_btn.custom_minimum_size=Vector2(105,44); diplomacy_btn.pressed.connect(func(): _refresh_selected()); map_action_bar.add_child(diplomacy_btn)
    var help_btn:=Button.new(); help_btn.text="ПОМОЩЬ"; help_btn.custom_minimum_size=Vector2(105,44); help_btn.pressed.connect(func():
        if selected_id!=player_id: _send_aid(selected_id)
    ); map_action_bar.add_child(help_btn)

func _ready() -> void:
    super._ready()
    if world_map: world_map.setup(countries,selected_id)

func _on_map_country_clicked(id:String)->void:
    selected_id=id
    if world_map: world_map.set_selected(id)
    _refresh_selected()

func _refresh_top()->void:
    super._refresh_top()
    if countries.has(player_id):
        var p: Dictionary=countries[player_id]
        military_label.text="Население %.1f млн\nЭкипажи %.2f млн\nПотенциал %d"%[float(p.get("population",0.0)),_military_population(p),_military_rating(p)]

func _refresh_selected()->void:
    super._refresh_selected()
    if countries.has(selected_id):
        var c: Dictionary=countries[selected_id]
        for child in selected_panel.get_children():
            if child is Label and str(child.text).begins_with("Военный потенциал:"): child.text="Военный потенциал: %d"%_military_rating(c)
        _add_label(selected_panel,"Танки: %d"%int(c.army),17); _add_label(selected_panel,"Ракеты: %d"%int(c.missile),17); _add_label(selected_panel,"Казна: %.0f млн"%float(c.treasury),19)
    _style_all_buttons(selected_panel)

func _refresh_army()->void:
    for n in army_box.get_children(): n.queue_free()
    _add_label(army_box,"АРМИЯ - %s"%countries[player_id].name,24)
    _add_label(army_box,"Два вида вооружения: танки и ракеты. Экипаж танка - 4 человека. Ракеты - без людских потерь.",16)
    for key in ["army","missile"]:
        var row:=VBoxContainer.new(); army_box.add_child(row)
        var title: String="ТАНКИ" if key=="army" else "РАКЕТЫ"
        var suffix: String="  • экипаж 4 чел." if key=="army" else "  • без экипажа"
        var l:=Label.new(); l.text="%s: %d%s"%[title,int(countries[player_id][key]),suffix]; l.add_theme_font_size_override("font_size",20); row.add_child(l)
        var buttons:=HBoxContainer.new(); buttons.add_theme_constant_override("separation",5); row.add_child(buttons)
        for amount in [100,1000,10000]:
            var b:=Button.new(); var price: float=_unit_price(player_id,key)*float(amount)/100.0; b.text="+%d\n%.0f млн"%[amount,price]; b.size_flags_horizontal=Control.SIZE_EXPAND_FILL; b.custom_minimum_size.y=54; b.pressed.connect(_buy_unit_amount.bind(key,amount)); buttons.add_child(b)

func _buy_unit_amount(key:String,amount:int)->void:
    var p: Dictionary=countries[player_id]; var price: float=_unit_price(player_id,key)*float(amount)/100.0
    if float(p.treasury)<price: _push_news("Недостаточно средств для покупки."); return
    if not _can_recruit(p,key,float(amount)): _push_news("Недостаточно свободного населения для экипажей танков."); return
    p.treasury-=price; p[key]+=float(amount)
    if key=="army": _push_news("%s покупает %d танков. Экипажи: %d человек."%[p.name,amount,amount*4])
    else: _push_news("%s покупает %d ракет. Людские ресурсы не используются."%[p.name,amount])
    _refresh_all()

func _process(delta:float)->void:
    super._process(delta)
    if world_map and is_instance_valid(world_map) and world_map.selected_id!=selected_id: world_map.set_selected(selected_id)
