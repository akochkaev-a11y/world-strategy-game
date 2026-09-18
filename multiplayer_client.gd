extends Node

signal room_state_changed(state: Dictionary)
signal game_started(state: Dictionary)
signal status_changed(text: String)

var socket := WebSocketPeer.new()
var pending_action: Dictionary = {}
var player_id: String = ""
var connected: bool = false

func create_room(url: String, player_name: String) -> void:
    pending_action = {"type":"create_room","name":_safe_name(player_name)}
    _connect(url)

func join_room(url: String, code: String, player_name: String) -> void:
    pending_action = {"type":"join_room","code":code,"name":_safe_name(player_name)}
    _connect(url)

func select_country(iso: String) -> void:
    _send({"type":"select_country","country":iso})

func start_room() -> void:
    _send({"type":"start_room"})

func _safe_name(value: String) -> String:
    var clean: String = value.strip_edges()
    return clean if clean != "" else "Игрок"

func _connect(url: String) -> void:
    if url == "":
        status_changed.emit("Укажите адрес сервера.")
        return
    socket = WebSocketPeer.new()
    var err: Error = socket.connect_to_url(url)
    if err != OK:
        status_changed.emit("Не удалось начать подключение.")
        return
    connected = false
    set_process(true)

func _process(_delta: float) -> void:
    socket.poll()
    var state: WebSocketPeer.State = socket.get_ready_state()
    if state == WebSocketPeer.STATE_OPEN:
        if not connected:
            connected = true
            status_changed.emit("Подключено.")
            if not pending_action.is_empty():
                _send(pending_action)
                pending_action.clear()
        while socket.get_available_packet_count() > 0:
            var text: String = socket.get_packet().get_string_from_utf8()
            _handle_message(text)
    elif state == WebSocketPeer.STATE_CLOSED:
        if connected:
            status_changed.emit("Соединение с сервером закрыто.")
        connected = false
        set_process(false)

func _send(payload: Dictionary) -> void:
    if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
        status_changed.emit("Нет соединения с сервером.")
        return
    socket.send_text(JSON.stringify(payload))

func _handle_message(text: String) -> void:
    var parsed: Variant = JSON.parse_string(text)
    if typeof(parsed) != TYPE_DICTIONARY:
        return
    var msg: Dictionary = parsed
    var msg_type: String = str(msg.get("type",""))
    if msg_type == "welcome":
        player_id = str(msg.get("player_id",""))
    elif msg_type == "room_state":
        room_state_changed.emit(Dictionary(msg.get("state",{})))
    elif msg_type == "game_started":
        game_started.emit(Dictionary(msg.get("state",{})))
    elif msg_type == "error":
        status_changed.emit(str(msg.get("message","Ошибка сервера")))
