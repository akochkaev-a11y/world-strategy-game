extends Node

const GameConfig := preload("res://game_config.gd")

signal room_state_changed(state: Dictionary)
signal game_started(state: Dictionary)
signal army_started(army: Dictionary, server_time: float)
signal country_eliminated(country: String)
signal game_snapshot(state: Dictionary)
signal game_result(winner: String)
signal left_room
signal status_changed(text: String)

const SESSION_PATH := "user://multiplayer_session.cfg"

var socket := WebSocketPeer.new()
var pending_action: Dictionary = {}
var player_id: String = ""
var session_token: String = ""
var room_code: String = ""
var server_url: String = ""
var player_name: String = "Игрок"
var connected: bool = false
var connection_started_msec: int = 0
var reconnect_wait: float = -1.0
var auto_reconnect: bool = false
var last_game_revision: int = -1
var protocol_version: int = 0

func _ready() -> void:
    protocol_version = int(GameConfig.load_config().get("protocol_version", 0))
    _load_saved_session()

func has_saved_session() -> bool:
    return session_token != "" and room_code != "" and server_url != ""

func resume_saved_session() -> void:
    if not has_saved_session():
        status_changed.emit("Сохранённая игровая сессия не найдена.")
        return
    auto_reconnect = true
    pending_action = {"type":"reconnect","code":room_code,"session_token":session_token}
    _connect(server_url)

func create_room(url: String, name_value: String) -> void:
    _clear_saved_session()
    server_url=url
    player_name=_safe_name(name_value)
    auto_reconnect=false
    pending_action={"type":"create_room","name":player_name}
    _connect(server_url)

func join_room(url: String, code: String, name_value: String) -> void:
    _clear_saved_session()
    server_url=url
    player_name=_safe_name(name_value)
    room_code=code
    auto_reconnect=false
    pending_action={"type":"join_room","code":room_code,"name":player_name}
    _connect(server_url)

func select_country(iso: String) -> void:
    _send({"type":"select_country","country":iso})

func start_room() -> void:
    _send({"type":"start_room"})

func leave_room() -> void:
    if socket.get_ready_state()==WebSocketPeer.STATE_OPEN:
        _send({"type":"leave_room"})
    auto_reconnect=false
    pending_action.clear()
    _clear_saved_session()
    if socket.get_ready_state()==WebSocketPeer.STATE_OPEN or socket.get_ready_state()==WebSocketPeer.STATE_CONNECTING:
        socket.close(1000,"left_room")
    connected=false
    reconnect_wait=-1.0
    set_process(false)
    left_room.emit()

func send_army(from_iso:String,to_iso:String,share:float=0.5)->void:
    _send({"type":"send_army","source":from_iso,"target":to_iso,"share":share})

func _safe_name(value: String) -> String:
    var clean:String=value.strip_edges()
    return clean if clean!="" else "Игрок"

func _clear_saved_session() -> void:
    player_id=""
    session_token=""
    room_code=""
    auto_reconnect=false
    last_game_revision=-1
    var cfg:=ConfigFile.new()
    cfg.set_value("session","server_url","")
    cfg.set_value("session","player_name","")
    cfg.set_value("session","player_id","")
    cfg.set_value("session","token","")
    cfg.set_value("session","room_code","")
    cfg.save(SESSION_PATH)

func _save_session() -> void:
    var cfg:=ConfigFile.new()
    cfg.set_value("session","server_url",server_url)
    cfg.set_value("session","player_name",player_name)
    cfg.set_value("session","player_id",player_id)
    cfg.set_value("session","token",session_token)
    cfg.set_value("session","room_code",room_code)
    cfg.save(SESSION_PATH)

func _load_saved_session() -> void:
    var cfg:=ConfigFile.new()
    if cfg.load(SESSION_PATH)!=OK:
        return
    server_url=str(cfg.get_value("session","server_url",""))
    player_name=str(cfg.get_value("session","player_name","Игрок"))
    player_id=str(cfg.get_value("session","player_id",""))
    session_token=str(cfg.get_value("session","token",""))
    room_code=str(cfg.get_value("session","room_code",""))
    auto_reconnect=has_saved_session()

func _connect(url: String) -> void:
    if url=="":
        status_changed.emit("Укажите адрес сервера.")
        return
    if socket.get_ready_state()==WebSocketPeer.STATE_OPEN or socket.get_ready_state()==WebSocketPeer.STATE_CONNECTING:
        socket.close()
    socket=WebSocketPeer.new()
    var err:Error=socket.connect_to_url(url)
    if err!=OK:
        status_changed.emit("Не удалось начать подключение.")
        return
    connected=false
    connection_started_msec=Time.get_ticks_msec()
    reconnect_wait=-1.0
    status_changed.emit("Соединяюсь с сервером...")
    set_process(true)

func _process(delta: float) -> void:
    if reconnect_wait>=0.0:
        reconnect_wait-=delta
        if reconnect_wait<=0.0:
            reconnect_wait=-1.0
            pending_action={"type":"reconnect","code":room_code,"session_token":session_token}
            _connect(server_url)
        return
    socket.poll()
    var state:WebSocketPeer.State=socket.get_ready_state()
    if state==WebSocketPeer.STATE_OPEN:
        if not connected:
            connected=true
            status_changed.emit("Подключено.")
            if not pending_action.is_empty():
                _send(pending_action)
                pending_action.clear()
        while socket.get_available_packet_count()>0:
            var packet_text:String=socket.get_packet().get_string_from_utf8()
            _handle_message(packet_text)
    elif state==WebSocketPeer.STATE_CLOSED:
        var was_connected:bool=connected
        connected=false
        if auto_reconnect and has_saved_session():
            status_changed.emit("Связь потеряна. Переподключаюсь...")
            reconnect_wait=2.0
        else:
            status_changed.emit("Соединение с сервером закрыто." if was_connected else "Не удалось подключиться к серверу.")
            set_process(false)
    elif state==WebSocketPeer.STATE_CONNECTING:
        if connection_started_msec>0 and Time.get_ticks_msec()-connection_started_msec>10000:
            status_changed.emit("Сервер не отвечает. Проверьте адрес и порт 8080.")
            socket.close()
            if auto_reconnect and has_saved_session():
                reconnect_wait=2.0
            else:
                set_process(false)

func _send(payload: Dictionary) -> void:
    if socket.get_ready_state()!=WebSocketPeer.STATE_OPEN:
        status_changed.emit("Нет соединения с сервером.")
        return
    var message := payload.duplicate(true)
    message["protocol_version"] = protocol_version
    socket.send_text(JSON.stringify(message))

func _handle_message(message_text: String) -> void:
    var parsed:Variant=JSON.parse_string(message_text)
    if typeof(parsed)!=TYPE_DICTIONARY:return
    var msg:Dictionary=parsed
    var msg_type:String=str(msg.get("type",""))
    if msg_type=="welcome":
        var server_protocol:int=int(msg.get("protocol_version",0))
        if server_protocol!=protocol_version:
            auto_reconnect=false
            pending_action.clear()
            status_changed.emit("Версия игры несовместима с сервером. Обновите приложение.")
            socket.close(1002,"protocol_mismatch")
    elif msg_type=="session":
        player_id=str(msg.get("player_id",""))
        session_token=str(msg.get("session_token",msg.get("token","")))
        room_code=str(msg.get("code",""))
        auto_reconnect=true
        _save_session()
    elif msg_type=="room_state":
        room_state_changed.emit(Dictionary(msg.get("state",{})))
    elif msg_type=="game_started":
        auto_reconnect=true
        last_game_revision=-1
        var start_state:Dictionary=Dictionary(msg.get("state",{}))
        start_state["local_country"]=str(msg.get("player_country",""))
        game_started.emit(start_state)
    elif msg_type=="army_started":
        army_started.emit(Dictionary(msg.get("army",{})),float(msg.get("server_time",0.0)))
    elif msg_type=="country_eliminated":
        country_eliminated.emit(str(msg.get("country","")))
    elif msg_type=="game_state":
        var state:Dictionary=Dictionary(msg.get("state",{}))
        state["local_country"]=str(msg.get("player_country",""))
        var revision:int=int(state.get("revision",last_game_revision+1))
        if revision>=last_game_revision:
            last_game_revision=revision
            game_snapshot.emit(state)
    elif msg_type=="game_over":
        game_result.emit(str(msg.get("winner","")))
    elif msg_type=="left_room":
        auto_reconnect=false
        _clear_saved_session()
        left_room.emit()
    elif msg_type=="error":
        status_changed.emit(str(msg.get("message","Ошибка сервера")))
