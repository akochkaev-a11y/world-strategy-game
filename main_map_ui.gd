extends Control

const ACTIVE_ORDER := ["RU","UA","PL","FR","DE","GB","CN","IN","IR","JP"]
const ACTIVE_COUNTRIES := {
    "RU":"Россия", "UA":"Украина", "PL":"Польша", "FR":"Франция", "DE":"Германия",
    "GB":"Великобритания", "CN":"Китай", "IN":"Индия", "IR":"Иран", "JP":"Япония"
}
const FLAGS := {"RU":"🇷🇺","UA":"🇺🇦","PL":"🇵🇱","FR":"🇫🇷","DE":"🇩🇪","GB":"🇬🇧","CN":"🇨🇳","IN":"🇮🇳","IR":"🇮🇷","JP":"🇯🇵"}

var world_map: Control
var military_balance: Control
var army_clock: float = 0.0
var match_time: float = 0.0
var started: bool = false
var chooser: Control
var timer_label: Label

var multiplayer_client: Node
var multiplayer_panel: Control
var lobby_panel: Control
var server_field: LineEdit
var room_field: LineEdit
var name_field: LineEdit
var lobby_status: Label
var room_title: Label
var start_button: Button
var selected_country: String = ""
var room_state: Dictionary = {}
var multiplayer_game: bool = false

func _ready() -> void:
    _show_mode_chooser()

func _clear_frontend() -> void:
    if is_instance_valid(chooser):
        chooser.queue_free()
    if is_instance_valid(multiplayer_panel):
        multiplayer_panel.queue_free()
    if is_instance_valid(lobby_panel):
        lobby_panel.queue_free()

func _make_full_panel() -> PanelContainer:
    var panel := PanelContainer.new()
    panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(panel)
    return panel

func _show_mode_chooser() -> void:
    _clear_frontend()
    chooser = _make_full_panel()
    var center := CenterContainer.new()
    center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    chooser.add_child(center)
    var box := VBoxContainer.new()
    box.custom_minimum_size = Vector2(560,340)
    box.alignment = BoxContainer.ALIGNMENT_CENTER
    box.add_theme_constant_override("separation",22)
    center.add_child(box)
    var title := Label.new()
    title.text = "WORLD STRATEGY"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.add_theme_font_size_override("font_size",34)
    box.add_child(title)
    var solo := Button.new()
    solo.text = "ОДИНОЧНАЯ ИГРА"
    solo.custom_minimum_size = Vector2(420,70)
    solo.add_theme_font_size_override("font_size",22)
    solo.pressed.connect(_show_country_chooser)
    box.add_child(solo)
    var multi := Button.new()
    multi.text = "МУЛЬТИПЛЕЕР"
    multi.custom_minimum_size = Vector2(420,70)
    multi.add_theme_font_size_override("font_size",22)
    multi.pressed.connect(_show_multiplayer_menu)
    box.add_child(multi)

func _show_country_chooser() -> void:
    _clear_frontend()
    chooser = _make_full_panel()
    var center := CenterContainer.new()
    center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    chooser.add_child(center)
    var box := VBoxContainer.new()
    box.custom_minimum_size = Vector2(760,560)
    box.alignment = BoxContainer.ALIGNMENT_CENTER
    box.add_theme_constant_override("separation",18)
    center.add_child(box)
    var title := Label.new()
    title.text = "ВЫБЕРИТЕ ДЕРЖАВУ"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.add_theme_font_size_override("font_size",34)
    box.add_child(title)
    var subtitle := Label.new()
    subtitle.text = "Ведите страну к господству на карте Евразии"
    subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    subtitle.modulate = Color(0.72,0.80,0.88)
    subtitle.add_theme_font_size_override("font_size",17)
    box.add_child(subtitle)
    var grid := GridContainer.new()
    grid.columns = 5
    grid.add_theme_constant_override("h_separation",12)
    grid.add_theme_constant_override("v_separation",12)
    box.add_child(grid)
    for iso in ACTIVE_ORDER:
        var b := Button.new()
        b.text = "%s\n%s" % [str(FLAGS.get(iso,"")),str(ACTIVE_COUNTRIES.get(iso,iso))]
        b.custom_minimum_size = Vector2(138,145)
        b.add_theme_font_size_override("font_size",19)
        b.pressed.connect(_start_game.bind(str(iso)))
        grid.add_child(b)
    var back := Button.new()
    back.text = "НАЗАД"
    back.pressed.connect(_show_mode_chooser)
    box.add_child(back)

func _show_multiplayer_menu() -> void:
    _clear_frontend()
    _ensure_multiplayer_client()
    multiplayer_panel = _make_full_panel()
    var center := CenterContainer.new()
    center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    multiplayer_panel.add_child(center)
    var box := VBoxContainer.new()
    box.custom_minimum_size = Vector2(620,500)
    box.alignment = BoxContainer.ALIGNMENT_CENTER
    box.add_theme_constant_override("separation",14)
    center.add_child(box)
    var title := Label.new()
    title.text = "МУЛЬТИПЛЕЕР"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.add_theme_font_size_override("font_size",32)
    box.add_child(title)
    name_field = LineEdit.new()
    name_field.placeholder_text = "Имя игрока"
    name_field.text = "Игрок"
    name_field.custom_minimum_size = Vector2(560,50)
    box.add_child(name_field)
    server_field = LineEdit.new()
    server_field.placeholder_text = "wss://адрес-сервера"
    server_field.text = "ws://87.228.13.236:8080"
    server_field.custom_minimum_size = Vector2(560,50)
    box.add_child(server_field)
    if multiplayer_client.has_saved_session():
        var resume := Button.new()
        resume.text = "ВЕРНУТЬСЯ В ПАРТИЮ"
        resume.custom_minimum_size = Vector2(560,58)
        resume.pressed.connect(_resume_multiplayer_room)
        box.add_child(resume)
    var create := Button.new()
    create.text = "СОЗДАТЬ КОМНАТУ"
    create.custom_minimum_size = Vector2(560,58)
    create.pressed.connect(_create_room)
    box.add_child(create)
    room_field = LineEdit.new()
    room_field.placeholder_text = "Код комнаты"
    room_field.max_length = 6
    room_field.custom_minimum_size = Vector2(560,50)
    box.add_child(room_field)
    var join := Button.new()
    join.text = "ВОЙТИ В КОМНАТУ"
    join.custom_minimum_size = Vector2(560,58)
    join.pressed.connect(_join_room)
    box.add_child(join)
    lobby_status = Label.new()
    lobby_status.text = "Для игры через интернет нужен запущенный WebSocket-сервер."
    lobby_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    lobby_status.modulate = Color(0.68,0.76,0.84)
    box.add_child(lobby_status)
    var back := Button.new()
    back.text = "НАЗАД"
    back.pressed.connect(_show_mode_chooser)
    box.add_child(back)

func _ensure_multiplayer_client() -> void:
    if is_instance_valid(multiplayer_client):
        return
    multiplayer_client = preload("res://multiplayer_client.gd").new()
    add_child(multiplayer_client)
    multiplayer_client.room_state_changed.connect(_on_room_state_changed)
    multiplayer_client.game_started.connect(_on_multiplayer_game_started)
    multiplayer_client.army_started.connect(_on_multiplayer_army_started)
    multiplayer_client.game_snapshot.connect(_on_multiplayer_snapshot)
    multiplayer_client.game_result.connect(_on_multiplayer_result)
    multiplayer_client.status_changed.connect(_on_multiplayer_status)

func _resume_multiplayer_room() -> void:
    _ensure_multiplayer_client()
    lobby_status.text = "Возвращаюсь в комнату..."
    multiplayer_client.resume_saved_session()

func _create_room() -> void:
    _ensure_multiplayer_client()
    lobby_status.text = "Подключение..."
    multiplayer_client.create_room(server_field.text.strip_edges(),name_field.text.strip_edges())

func _join_room() -> void:
    _ensure_multiplayer_client()
    lobby_status.text = "Подключение..."
    multiplayer_client.join_room(server_field.text.strip_edges(),room_field.text.strip_edges().to_upper(),name_field.text.strip_edges())

func _on_multiplayer_status(text: String) -> void:
    if is_instance_valid(lobby_status):
        lobby_status.text = text

func _on_room_state_changed(state: Dictionary) -> void:
    room_state = state.duplicate(true)
    selected_country = ""
    var players:Array = room_state.get("players",[])
    for p_raw in players:
        if typeof(p_raw) != TYPE_DICTIONARY:
            continue
        var p:Dictionary = p_raw
        if str(p.get("id","")) == str(multiplayer_client.player_id):
            selected_country = str(p.get("country",""))
            break
    _show_lobby()

func _show_lobby() -> void:
    if is_instance_valid(multiplayer_panel):
        multiplayer_panel.queue_free()
    if is_instance_valid(lobby_panel):
        lobby_panel.queue_free()
    lobby_panel = _make_full_panel()
    var center := CenterContainer.new()
    center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    lobby_panel.add_child(center)
    var box := VBoxContainer.new()
    box.custom_minimum_size = Vector2(900,620)
    box.alignment = BoxContainer.ALIGNMENT_CENTER
    box.add_theme_constant_override("separation",12)
    center.add_child(box)
    room_title = Label.new()
    room_title.text = "КОМНАТА %s" % str(room_state.get("code",""))
    room_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    room_title.add_theme_font_size_override("font_size",30)
    box.add_child(room_title)
    var subtitle := Label.new()
    subtitle.text = "Выберите свободную страну. Незанятые страны после старта остаются под ИИ."
    subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    subtitle.modulate = Color(0.68,0.76,0.84)
    box.add_child(subtitle)
    var taken: Dictionary = {}
    var players: Array = room_state.get("players",[])
    for p_raw in players:
        if typeof(p_raw) != TYPE_DICTIONARY:
            continue
        var p: Dictionary = p_raw
        var country: String = str(p.get("country",""))
        if country != "":
            taken[country] = str(p.get("name","Игрок"))
    var grid := GridContainer.new()
    grid.columns = 5
    grid.add_theme_constant_override("h_separation",10)
    grid.add_theme_constant_override("v_separation",10)
    box.add_child(grid)
    for iso_raw in ACTIVE_ORDER:
        var iso: String = str(iso_raw)
        var b := Button.new()
        b.custom_minimum_size = Vector2(165,112)
        var holder: String = str(taken.get(iso,""))
        if holder == "":
            b.text = "%s\n%s\nСвободно" % [str(FLAGS.get(iso,"")),str(ACTIVE_COUNTRIES.get(iso,iso))]
        else:
            b.text = "%s\n%s\n%s" % [str(FLAGS.get(iso,"")),str(ACTIVE_COUNTRIES.get(iso,iso)),holder]
            if iso != selected_country:
                b.disabled = true
        b.pressed.connect(_select_multiplayer_country.bind(iso))
        grid.add_child(b)
    var me_id: String = str(multiplayer_client.player_id)
    var host_id: String = str(room_state.get("host_id",""))
    start_button = Button.new()
    start_button.text = "СТАРТ"
    start_button.custom_minimum_size = Vector2(420,58)
    start_button.disabled = me_id != host_id or selected_country == ""
    start_button.pressed.connect(_start_multiplayer_room)
    box.add_child(start_button)
    var info := Label.new()
    info.text = "%d игрок(ов) в комнате" % players.size()
    info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    box.add_child(info)

func _select_multiplayer_country(iso: String) -> void:
    selected_country = iso
    multiplayer_client.select_country(iso)

func _start_multiplayer_room() -> void:
    multiplayer_client.start_room()

func _on_multiplayer_game_started(state: Dictionary) -> void:
    room_state = state.duplicate(true)
    var players: Array = room_state.get("players",[])
    selected_country = ""
    for p_raw in players:
        if typeof(p_raw) != TYPE_DICTIONARY:
            continue
        var p: Dictionary = p_raw
        if str(p.get("id","")) == str(multiplayer_client.player_id):
            selected_country = str(p.get("country",""))
            break
    if selected_country == "":
        return
    if started and multiplayer_game:
        return
    _start_game(selected_country,true)

func _start_game(selected: String, multiplayer: bool = false) -> void:
    _clear_frontend()
    world_map = preload("res://optimized_world_map.gd").new()
    add_child(world_map)
    world_map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    world_map.setup(ACTIVE_COUNTRIES,selected)
    multiplayer_game = multiplayer
    if multiplayer_game:
        world_map.set_multiplayer_mode(true)
        world_map.army_order_requested.connect(_on_multiplayer_army_order)
    military_balance = preload("res://military_balance.gd").new()
    add_child(military_balance)
    military_balance.setup(world_map,selected)
    timer_label = Label.new()
    timer_label.position = Vector2(18,16)
    timer_label.size = Vector2(150,42)
    timer_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    timer_label.add_theme_font_size_override("font_size",22)
    timer_label.add_theme_color_override("font_color",Color(0.92,0.96,0.99))
    timer_label.add_theme_color_override("font_shadow_color",Color(0,0,0,0.85))
    timer_label.add_theme_constant_override("shadow_offset_x",2)
    timer_label.add_theme_constant_override("shadow_offset_y",2)
    add_child(timer_label)
    match_time = 0.0
    army_clock = 0.0
    _update_timer()
    started = true

func _process(delta: float) -> void:
    if not started:
        return
    if multiplayer_game:
        _update_timer()
        return
    match_time += delta
    _update_timer()
    army_clock += delta
    while army_clock >= 1.0:
        army_clock -= 1.0
        if world_map and is_instance_valid(world_map):
            world_map.grow_armies()

func _update_timer() -> void:
    if not is_instance_valid(timer_label):
        return
    var total_seconds: int = int(match_time)
    var minutes: int = total_seconds / 60
    var seconds: int = total_seconds % 60
    timer_label.text = "%02d:%02d" % [minutes,seconds]


func _on_multiplayer_army_order(from_iso:String,to_iso:String,share:float)->void:
    if is_instance_valid(multiplayer_client):
        multiplayer_client.send_army(from_iso,to_iso,share)

func _on_multiplayer_army_started(army:Dictionary,_server_time:float)->void:
    if multiplayer_game and is_instance_valid(world_map):
        world_map.apply_multiplayer_army_started(army)

func _on_multiplayer_snapshot(state:Dictionary)->void:
    if not multiplayer_game or not is_instance_valid(world_map):return
    match_time=float(state.get("time",match_time))
    world_map.apply_multiplayer_state(state)
    _update_timer()

func _on_multiplayer_result(winner:String)->void:
    if multiplayer_game and is_instance_valid(world_map):
        world_map.show_multiplayer_result(winner)
