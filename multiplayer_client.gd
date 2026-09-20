extends Node

signal room_state_changed(state: Dictionary)
signal game_started(state: Dictionary)
signal game_snapshot(state: Dictionary)
signal game_result(winner: String)
signal status_changed(text: String)

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

func create_room(url: String, name_value: String) -> void:
    server_url=url
    player_name=_safe_name(name_value)
    session_token=""
    room_code=""
    auto_reconnect=false
    pending_action={"type":"create_room","name":player_name}
    _connect(server_url)

func join_room(url: String, code: String, name_value: String) -> void:
    server_url=url
    player_name=_safe_name(name_value)
    room_code=code
    session_token=""
    auto_reconnect=false
    pending_action={"type":"join_room","code":room_code,"name":player_name}
    _connect(server_url)

func select_country(iso: String) -> void:
    _send({"type":"select_country","country":iso})

func start_room() -> void:
    _send({"type":"start_room"})

func send_army(from_iso:String,to_iso:String,share:float=0.5)->void:
    _send({"type":"send_army","from":from_iso,"to":to_iso,"share":share})

func _safe_name(value: String) -> String:
    var clean:String=value.strip_edges()
    return clean if clean!="" else "Игрок"

func _connect(url: String) -> void:
    if url=="":
        status_changed.emit("Укажите адрес сервера.")
        return
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
            pending_action={"type":"reconnect","code":room_code,"token":session_token}
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
        connected=false
        if auto_reconnect and session_token!="" and room_code!="":
            status_changed.emit("Связь потеряна. Переподключаюсь...")
            reconnect_wait=2.0
        else:
            status_changed.emit("Соединение с сервером закрыто.")
            set_process(false)
    elif state==WebSocketPeer.STATE_CONNECTING:
        if connection_started_msec>0 and Time.get_ticks_msec()-connection_started_msec>10000:
            status_changed.emit("Сервер не отвечает. Проверьте адрес и порт 8080.")
            socket.close()
            if auto_reconnect:
                reconnect_wait=2.0

func _send(payload: Dictionary) -> void:
    if socket.get_ready_state()!=WebSocketPeer.STATE_OPEN:
        status_changed.emit("Нет соединения с сервером.")
        return
    socket.send_text(JSON.stringify(payload))

func _handle_message(message_text: String) -> void:
    var parsed:Variant=JSON.parse_string(message_text)
    if typeof(parsed)!=TYPE_DICTIONARY:return
    var msg:Dictionary=parsed
    var msg_type:String=str(msg.get("type",""))
    if msg_type=="welcome":
        pass
    elif msg_type=="session":
        player_id=str(msg.get("player_id",""))
        session_token=str(msg.get("token",""))
        room_code=str(msg.get("code",""))
        auto_reconnect=true
    elif msg_type=="room_state":
        room_state_changed.emit(Dictionary(msg.get("state",{})))
    elif msg_type=="game_started":
        auto_reconnect=true
        game_started.emit(Dictionary(msg.get("state",{})))
    elif msg_type=="game_state":
        game_snapshot.emit(Dictionary(msg.get("state",{})))
    elif msg_type=="game_over":
        game_result.emit(str(msg.get("winner","")))
    elif msg_type=="error":
        status_changed.emit(str(msg.get("message","Ошибка сервера")))
