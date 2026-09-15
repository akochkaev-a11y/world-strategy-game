extends "res://main_interactive_battle.gd"

var world_map: Control
var map_action_bar: HBoxContainer
var conquest_clock: float=0.0

func _seed_countries()->void:
    countries={"RU":_c("Россия",4200,25,1000,0,0,0,0,"рациональный"),"UA":_c("Украина",1200,7,1000,0,0,0,0,"агрессивный"),"PL":_c("Польша",1800,15,1000,0,0,0,0,"осторожный"),"FR":_c("Франция",3000,24,1000,0,0,0,0,"дипломатический"),"DE":_c("Германия",3200,35,1000,0,0,0,0,"осторожный"),"GB":_c("Великобритания",3100,24,1000,0,0,0,0,"дипломатический"),"CN":_c("Китай",7600,75,1000,0,0,0,0,"экономический"),"IN":_c("Индия",3500,30,1000,0,0,0,0,"авантюрный"),"IR":_c("Иран",1500,10,1000,0,0,0,0,"агрессивный"),"JP":_c("Япония",3000,32,1000,0,0,0,0,"осторожный")}
    for id in countries.keys():countries[id]["population"]=100.0;countries[id]["relations"]={}

func _build_ui()->void:
    super._build_ui()
    var left_scroll:=countries_box.get_parent();if left_scroll is Control:left_scroll.hide()
    for i in range(tabs.get_tab_count()):
        if tabs.get_tab_title(i)!="Карта":tabs.set_tab_hidden(i,true)
    var world:VBoxContainer=tabs.get_node("Карта")
    for child in world.get_children():child.queue_free()
    var header:=Label.new();header.text="ЗАХВАТ ТЕРРИТОРИЙ";header.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;header.add_theme_font_size_override("font_size",20);world.add_child(header)
    var hint:=Label.new();hint.text="Нажмите свою территорию, затем цель. Отправляется половина войск. Щипок двумя пальцами - масштаб.";hint.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;world.add_child(hint)
    world_map=preload("res://world_map.gd").new();world_map.name="WorldMap";world_map.size_flags_horizontal=Control.SIZE_EXPAND_FILL;world_map.size_flags_vertical=Control.SIZE_EXPAND_FILL;world.add_child(world_map);world_map.country_clicked.connect(_on_map_country_clicked);world_map.attack_requested.connect(_on_attack_requested)

func _ready()->void:
    super._ready()
    if world_map:world_map.setup(countries,selected_id)

func _on_map_country_clicked(id:String)->void:
    selected_id=id

func _on_attack_requested(from_id:String,to_id:String)->void:
    if not world_map.territories.has(from_id) or not world_map.territories.has(to_id):return
    var src:Dictionary=world_map.territories[from_id];var dst:Dictionary=world_map.territories[to_id]
    if str(src.owner)!="RU":return
    var sent:float=floor(float(src.army)*0.5);if sent<1.0:return
    src.army=float(src.army)-sent
    var defender:float=float(dst.army)
    if str(dst.owner)=="RU":dst.army=defender+sent;_push_news("Переброшено %d солдат."%int(sent))
    elif sent>defender:
        dst.army=sent-defender;dst.owner="RU";_push_news("Территория захвачена. Осталось %d солдат."%int(dst.army))
    else:
        dst.army=defender-sent;_push_news("Атака отбита. У противника осталось %d солдат."%int(dst.army))
    world_map.queue_redraw()

func _process(delta:float)->void:
    if paused:return
    conquest_clock+=delta
    while conquest_clock>=1.0:
        conquest_clock-=1.0
        if world_map and is_instance_valid(world_map):world_map.grow_armies(1.0)
