extends RefCounted

const PATH := "res://game_config.json"

static func load_config() -> Dictionary:
    if not FileAccess.file_exists(PATH):
        push_error("Missing game configuration: " + PATH)
        return {}
    var file := FileAccess.open(PATH, FileAccess.READ)
    if file == null:
        push_error("Cannot open game configuration: " + PATH)
        return {}
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("Invalid game configuration JSON: " + PATH)
        return {}
    return Dictionary(parsed)

static func active_ids(config: Dictionary) -> Array:
    var result: Array = []
    for raw in config.get("active_countries", []):
        if typeof(raw) == TYPE_DICTIONARY:
            result.append(str(raw.get("iso", "")))
    return result

static func country_names(config: Dictionary) -> Dictionary:
    var result := {}
    for raw in config.get("active_countries", []):
        if typeof(raw) == TYPE_DICTIONARY:
            result[str(raw.get("iso", ""))] = str(raw.get("name", ""))
    return result

static func country_flags(config: Dictionary) -> Dictionary:
    var result := {}
    for raw in config.get("active_countries", []):
        if typeof(raw) == TYPE_DICTIONARY:
            result[str(raw.get("iso", ""))] = str(raw.get("flag", ""))
    return result

static func country_colors(config: Dictionary) -> Dictionary:
    var result := {}
    for raw in config.get("active_countries", []):
        if typeof(raw) != TYPE_DICTIONARY:
            continue
        var values: Array = Array(raw.get("color", []))
        if values.size() == 3:
            result[str(raw.get("iso", ""))] = Color(float(values[0]), float(values[1]), float(values[2]))
    return result

static func playable_ids(config: Dictionary) -> Array:
    return active_ids(config) + Array(config.get("neutral_countries", []))

static func map_ids(config: Dictionary) -> Array:
    return playable_ids(config) + Array(config.get("background_countries", []))

static func difficulty_ids(config: Dictionary) -> Array:
    var result: Array = []
    for raw in config.get("difficulties", []):
        if typeof(raw) == TYPE_DICTIONARY:
            result.append(str(raw.get("id", "")))
    return result

static func difficulty_names(config: Dictionary) -> Dictionary:
    var result := {}
    for raw in config.get("difficulties", []):
        if typeof(raw) == TYPE_DICTIONARY:
            result[str(raw.get("id", ""))] = str(raw.get("name", ""))
    return result

static func difficulty(config: Dictionary, difficulty_id: String) -> Dictionary:
    for raw in config.get("difficulties", []):
        if typeof(raw) == TYPE_DICTIONARY and str(raw.get("id", "")) == difficulty_id:
            return Dictionary(raw)
    var fallback := str(config.get("default_difficulty", "easy"))
    for raw in config.get("difficulties", []):
        if typeof(raw) == TYPE_DICTIONARY and str(raw.get("id", "")) == fallback:
            return Dictionary(raw)
    return {}
