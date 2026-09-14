extends Control

const SAVE_PATH := "user://geostrategy_save.json"
const UNIT_KEYS := ["army", "air", "navy", "def", "missile"]
const UNIT_LABELS := {"army":"Сухопутные","air":"Авиация","navy":"Флот","def":"ПВО/ПРО","missile":"Ракеты"}
const UNIT_COST := {"army":20.0,"air":50.0,"navy":70.0,"def":45.0,"missile":55.0}

var countries: Dictionary = {}
var player_id: String = "RU"
var selected_id: String = "DE"
var speed: int = 1
var paused: bool = false
var minute_accum: float = 0.0
var bot_accum: float = 0.0
var news: Array[String] = []
var treasury_label: Label
var income_label: Label
var military_label: Label
var selected_panel: VBoxContainer
var countries_box: VBoxContainer
var army_box: VBoxContainer
var economy_box: VBoxContainer
var news_box: VBoxContainer
var tabs: TabContainer
var speed_buttons: Dictionary = {}

func _ready() -> void:
    _seed_countries(); _build_ui(); _push_news("Новая партия началась. Мир развивается самостоятельно."); _refresh_all()

func _process(delta: float) -> void:
    if paused: return
    minute_accum += delta * speed; bot_accum += delta * speed
    while minute_accum >= 1.0: minute_accum -= 1.0; _economic_tick()
    while bot_accum >= 5.0: bot_accum -= 5.0; _bot_tick()

func _seed_countries() -> void:
    countries = {
        "RU": _c("Россия",4200,25,7500,6200,3600,7000,6500,"рациональный"),
        "CN": _c("Китай",7600,75,9000,8500,7800,7600,8100,"экономический"),
        "DE": _c("Германия",3200,35,4200,4100,1700,3600,1600,"осторожный"),
        "FR": _c("Франция",3000,24,4300,4700,4000,3900,3100,"дипломатический"),
        "GB": _c("Великобритания",3100,24,3900,5200,5200,3500,3000,"дипломатический"),
        "IN": _c("Индия",3500,30,6500,5200,4200,3900,4500,"авантюрный"),
        "TR": _c("Турция",1800,14,4700,3600,2100,3000,2500,"агрессивный"),
        "JP": _c("Япония",3000,32,3600,5200,5500,4300,2000,"осторожный"),
        "IT": _c("Италия",2100,19,3300,3100,2600,2600,1500,"дипломатический"),
        "ES": _c("Испания",1800,17,2600,2500,2200,2100,1200,"осторожный"),
        "PL": _c("Польша",1500,13,3500,2200,900,2500,1400,"осторожный"),
        "UA": _c("Украина",900,8,4200,1900,500,2100,1700,"агрессивный"),
        "BY": _c("Беларусь",650,5,2100,900,200,1700,900,"рациональный"),
        "KZ": _c("Казахстан",1100,10,2300,1300,500,1400,900,"рациональный"),
        "IR": _c("Иран",1600,12,4700,2600,1500,3500,4200,"агрессивный"),
        "SA": _c("Саудовская Аравия",4200,30,3100,3900,2500,3400,2300,"рациональный"),
        "PK": _c("Пакистан",900,7,4200,2300,1300,1900,2700,"авантюрный"),
        "KR": _c("Южная Корея",2900,28,4200,5100,4200,4800,3000,"осторожный"),
        "KP": _c("КНДР",500,3,4800,1800,900,2500,4300,"агрессивный")
    }
    var relations: Dictionary = {}
    for a in countries.keys():
        relations[a] = {}
        for b in countries.keys():
            if a != b: relations[a][b] = randi_range(-20,30)
    for id in countries.keys(): countries[id]["relations"] = relations[id]

func _c(name:String, treasury:float, income:float, army:float, air:float, navy:float, def:float, missile:float, ai:String) -> Dictionary:
    return {"name":name,"treasury":treasury,"income":income,"economy":100.0,"army":army,"air":air,"navy":navy,"def":def,"missile":missile,"ai":ai,"war_fatigue":0.0,"relations":{}}

func _build_ui() -> void:
    var root:=VBoxContainer.new(); root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); root.add_theme_constant_override("separation",6); add_child(root)
    var top:=HBoxContainer.new(); top.custom_minimum_size.y=72; root.add_child(top)
    var title:=Label.new(); title.text="ГЕОСТРАТЕГИЯ v0.1"; title.add_theme_font_size_override("font_size",24); title.custom_minimum_size.x=250; top.add_child(title)
    treasury_label=Label.new(); treasury_label.custom_minimum_size.x=180; top.add_child(treasury_label)
    income_label=Label.new(); income_label.custom_minimum_size.x=180; top.add_child(income_label)
    military_label=Label.new(); military_label.custom_minimum_size.x=220; top.add_child(military_label)
    var spacer:=Control.new(); spacer.size_flags_horizontal=Control.SIZE_EXPAND_FILL; top.add_child(spacer)
    var pause_btn:=Button.new(); pause_btn.text="Пауза"; pause_btn.pressed.connect(_toggle_pause); top.add_child(pause_btn)
    for s in [1,2,5,10]:
        var b:=Button.new(); b.text="x%d"%s; b.pressed.connect(_set_speed.bind(s)); top.add_child(b); speed_buttons[s]=b
    var body:=HBoxContainer.new(); body.size_flags_vertical=Control.SIZE_EXPAND_FILL; root.add_child(body)
    countries_box=VBoxContainer.new(); countries_box.custom_minimum_size.x=260
    var left_scroll:=ScrollContainer.new(); left_scroll.custom_minimum_size.x=280; left_scroll.add_child(countries_box); body.add_child(left_scroll)
    tabs=TabContainer.new(); tabs.size_flags_horizontal=Control.SIZE_EXPAND_FILL; tabs.size_flags_vertical=Control.SIZE_EXPAND_FILL; body.add_child(tabs)
    var world:=VBoxContainer.new(); world.name="Карта"; tabs.add_child(world)
    var info:=Label.new(); info.text="МИР"; info.size_flags_vertical=Control.SIZE_EXPAND_FILL; world.add_child(info)
    army_box=VBoxContainer.new(); army_box.name="Армия"; tabs.add_child(army_box)
    economy_box=VBoxContainer.new(); economy_box.name="Экономика"; tabs.add_child(economy_box)
    selected_panel=VBoxContainer.new(); selected_panel.name="Страна"; tabs.add_child(selected_panel)
    news_box=VBoxContainer.new(); news_box.name="Новости"; tabs.add_child(news_box)

func _add_label(parent:Node, text:String, font_size:int=18) -> Label:
    var l:=Label.new(); l.text=text; l.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; l.add_theme_font_size_override("font_size",font_size); parent.add_child(l); return l

func _refresh_all() -> void:
    _refresh_top(); _refresh_country_list(); _refresh_selected(); _refresh_army(); _refresh_economy(); _refresh_news()
func _refresh_top() -> void:
    var p:Dictionary=countries[player_id]; treasury_label.text="Казна\n%.1f млн"%p.treasury; income_label.text="Доход\n+%.1f млн/мин"%p.income; military_label.text="Потенциал\n%d"%int(_total_power(p))
    for s in speed_buttons.keys(): speed_buttons[s].disabled=(s==speed)
func _refresh_country_list() -> void:
    for n in countries_box.get_children(): n.queue_free()
    for id in countries.keys():
        var b:=Button.new(); b.text=str(countries[id].name); b.pressed.connect(func(): selected_id=id; _refresh_selected()); countries_box.add_child(b)
func _refresh_selected() -> void:
    for n in selected_panel.get_children(): n.queue_free()
    if not countries.has(selected_id): return
    var c:Dictionary=countries[selected_id]; var p:Dictionary=countries[player_id]
    _add_label(selected_panel,c.name,26); _add_label(selected_panel,"Экономика: %.0f"%c.economy); _add_label(selected_panel,"Доход: %.1f млн/мин"%c.income); _add_label(selected_panel,"Казна: %.1f млн"%c.treasury); _add_label(selected_panel,"Военный потенциал: %d"%int(_total_power(c))); _add_label(selected_panel,"Характер ИИ: %s"%c.ai)
    if selected_id!=player_id:
        _add_label(selected_panel,"Отношения: %d"%int(p.relations.get(selected_id,0)))
        var help:=Button.new(); help.text="Помощь: 100 млн"; help.pressed.connect(_send_aid.bind(selected_id)); selected_panel.add_child(help)
        var improve:=Button.new(); improve.text="Улучшить отношения (-50 млн)"; improve.pressed.connect(_improve_relations.bind(selected_id)); selected_panel.add_child(improve)
        var attack:=Button.new(); attack.text="ВОЕННАЯ ОПЕРАЦИЯ"; attack.pressed.connect(_open_attack_dialog.bind(selected_id)); selected_panel.add_child(attack)
    else: _add_label(selected_panel,"Это ваша страна.")
func _refresh_army() -> void:
    for n in army_box.get_children(): n.queue_free()
    _add_label(army_box,"АРМИЯ - %s"%countries[player_id].name,24)
    for key in UNIT_KEYS:
        var row:=HBoxContainer.new(); army_box.add_child(row); var l:=Label.new(); l.text="%s: %d"%[UNIT_LABELS[key],int(countries[player_id][key])]; l.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.add_child(l); var b:=Button.new(); b.text="+100 за %.0f млн"%_unit_price(player_id,key); b.pressed.connect(_buy_unit.bind(key)); row.add_child(b)
func _refresh_economy() -> void:
    for n in economy_box.get_children(): n.queue_free()
    var p:Dictionary=countries[player_id]; _add_label(economy_box,"ЭКОНОМИКА",24); _add_label(economy_box,"Уровень: %.1f"%p.economy); _add_label(economy_box,"Доход: %.1f млн/мин"%p.income); _add_label(economy_box,"Казна: %.1f млн"%p.treasury)
    for amount in [100.0,500.0,1000.0]:
        var b:=Button.new(); b.text="Инвестировать %.0f млн"%amount; b.pressed.connect(_invest.bind(amount)); economy_box.add_child(b)
func _refresh_news() -> void:
    for n in news_box.get_children(): n.queue_free()
    for item in news: _add_label(news_box,item,16)
func _push_news(text:String) -> void:
    news.push_front(text); if news.size()>30: news.pop_back(); _refresh_news()
func _toggle_pause() -> void: paused=!paused
func _set_speed(s:int) -> void: speed=s; _refresh_top()
func _total_power(c:Dictionary) -> float: return float(c.army)+float(c.air)*0.9+float(c.navy)*0.45+float(c.missile)*0.65+float(c.def)*0.7
func _unit_price(id:String,key:String) -> float: return float(UNIT_COST[key])*(1.0+float(countries[id].economy)/500.0)
func _economic_tick() -> void:
    for id in countries.keys(): countries[id].treasury+=maxf(0.0,float(countries[id].income)-_total_power(countries[id])*0.00008)
    _refresh_top()
func _buy_unit(key:String) -> void:
    var p:Dictionary=countries[player_id]; var price:=_unit_price(player_id,key); if p.treasury<price: return; p.treasury-=price; p[key]+=100.0; _refresh_all()
func _invest(amount:float) -> void:
    var p:Dictionary=countries[player_id]; if p.treasury<amount: return; p.treasury-=amount; p.economy+=amount/250.0; p.income*=1.0+amount/25000.0; _refresh_all()
func _send_aid(target:String) -> void:
    var p:Dictionary=countries[player_id]; if p.treasury<100: return; p.treasury-=100; countries[target].treasury+=100; p.relations[target]=int(p.relations.get(target,0))+8; _refresh_all()
func _improve_relations(target:String) -> void:
    var p:Dictionary=countries[player_id]; if p.treasury<50: return; p.treasury-=50; p.relations[target]=int(p.relations.get(target,0))+10; _refresh_all()
func _buy_unit_for_bot(id:String,key:String) -> void: pass
func _bot_tick() -> void: pass
func _bot_may_attack(id:String) -> void: pass
func _open_attack_dialog(target:String) -> void: pass
func _combat_power(c:Dictionary,fraction:float,defender:bool) -> float:
    var total:=float(c.army)*fraction+float(c.air)*fraction*0.9+float(c.navy)*fraction*0.45+float(c.missile)*fraction*0.65+float(c.def)*fraction*(0.7 if defender else 0.25); if defender: total*=1.15; return total*(1.0-float(c.war_fatigue)/250.0)
