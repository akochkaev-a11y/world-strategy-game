extends "res://main_diplomacy.gd"

const ECONOMY_POP_SENSITIVITY := 0.00008
const MIN_ANNUAL_POP_GROWTH := -0.03
const MAX_ANNUAL_POP_GROWTH := 0.025
const POPULATION_INCOME_EXPONENT := 0.65
const DAYS_PER_YEAR := 365.0
const MILITARY_UPKEEP_PER_PERSON := 0.000008
const BOT_SAVINGS_SHARE := 0.20
const BOT_RECOVERY_MARGIN := 0.05
const BOT_DEMOBILIZE_SHARE := 0.02

const PLAYABLE_BASE_GROWTH := {
    "RU": -0.005,
    "UA": -0.007,
    "PL": -0.002,
    "FR": 0.002,
    "DE": -0.002,
    "GB": 0.004,
    "CN": -0.002,
    "IN": 0.008,
    "IR": 0.006,
    "JP": -0.005
}

func _ensure_population_data() -> void:
    super._ensure_population_data()
    for id in countries.keys():
        var c: Dictionary = countries[id]
        if not c.has("initial_population"):
            c["initial_population"] = maxf(0.1, float(c.get("population", 100.0)))
        if not c.has("war_cooldown"):
            c["war_cooldown"] = 0
        if not c.has("protected_treasury"):
            c["protected_treasury"] = 0.0
        if not c.has("economic_recovery"):
            c["economic_recovery"] = false

func _annual_population_growth(id: String) -> float:
    var c: Dictionary = countries[id]
    var natural: float = float(PLAYABLE_BASE_GROWTH.get(id, POP_GROWTH_ANNUAL.get(id, 0.003)))
    var economy_modifier: float = (float(c.economy) - 100.0) * ECONOMY_POP_SENSITIVITY
    var fatigue_modifier: float = -float(c.war_fatigue) * 0.00004
    return clampf(natural + economy_modifier + fatigue_modifier, MIN_ANNUAL_POP_GROWTH, MAX_ANNUAL_POP_GROWTH)

func _military_population(c: Dictionary) -> float:
    var personnel: float = 0.0
    personnel += float(c.get("army", 0.0))
    personnel += float(c.get("air", 0.0))
    personnel += float(c.get("navy", 0.0))
    personnel += float(c.get("def", 0.0))
    return personnel / 1000000.0

func _can_recruit(c: Dictionary, key: String, amount: float) -> bool:
    if key == "missile":
        return true
    var population: float = maxf(0.1, float(c.get("population", 100.0)))
    var future_military: float = _military_population(c) + amount / 1000000.0
    return future_military <= population * 0.12

func _military_labor_factor(c: Dictionary) -> float:
    var population: float = maxf(0.1, float(c.get("population", 100.0)))
    var military_share: float = clampf(_military_population(c) / population, 0.0, 0.20)
    if military_share <= 0.01:
        return 1.0 - military_share * 0.25
    if military_share <= 0.03:
        return 0.9975 - (military_share - 0.01) * 4.0
    if military_share <= 0.05:
        return 0.9175 - (military_share - 0.03) * 7.0
    return maxf(0.35, 0.7775 - (military_share - 0.05) * 6.0)

func _effective_income(c: Dictionary) -> float:
    var population: float = maxf(0.1, float(c.get("population", 100.0)))
    var initial_population: float = maxf(0.1, float(c.get("initial_population", population)))
    var population_factor: float = pow(population / initial_population, POPULATION_INCOME_EXPONENT)
    return maxf(0.0, float(c.income) * population_factor * _military_labor_factor(c))

func _military_upkeep(c: Dictionary) -> float:
    var personnel_units: float = _military_population(c) * 1000000.0
    return personnel_units * MILITARY_UPKEEP_PER_PERSON + float(c.get("missile", 0.0)) * 0.00008

func _raw_net_income(c: Dictionary) -> float:
    return _effective_income(c) - _military_upkeep(c)

func _bot_needs_recovery(c: Dictionary) -> bool:
    var effective: float = _effective_income(c)
    return _raw_net_income(c) <= effective * BOT_RECOVERY_MARGIN

func _bot_demobilize_step(c: Dictionary) -> void:
    for key in ["army", "air", "navy", "def"]:
        c[key] = maxf(0.0, float(c.get(key, 0.0)) * (1.0 - BOT_DEMOBILIZE_SHARE))
    if _raw_net_income(c) <= 0.0:
        c.missile = maxf(0.0, float(c.get("missile", 0.0)) * (1.0 - BOT_DEMOBILIZE_SHARE))

func _demography_day_tick() -> void:
    for id in countries.keys():
        var c: Dictionary = countries[id]
        var annual_growth: float = _annual_population_growth(id)
        var daily_multiplier: float = pow(1.0 + annual_growth, 1.0 / DAYS_PER_YEAR)
        c.population = maxf(0.1, float(c.population) * daily_multiplier)

func _daily_population_change_people(id: String) -> float:
    if not countries.has(id):
        return 0.0
    var c: Dictionary = countries[id]
    var annual_growth: float = _annual_population_growth(id)
    var daily_multiplier: float = pow(1.0 + annual_growth, 1.0 / DAYS_PER_YEAR)
    return float(c.population) * 1000000.0 * (daily_multiplier - 1.0)

func _bot_spendable_treasury(c: Dictionary) -> float:
    return maxf(0.0, float(c.treasury) - float(c.get("protected_treasury", 0.0)))

func _economic_tick() -> void:
    for id in countries.keys():
        var c: Dictionary = countries[id]
        var raw_net: float = _raw_net_income(c)
        var net_income: float = maxf(0.0, raw_net)
        c.treasury += net_income
        if id != player_id:
            c.protected_treasury = minf(float(c.treasury), float(c.get("protected_treasury", 0.0)) + net_income * BOT_SAVINGS_SHARE)
            c.economic_recovery = _bot_needs_recovery(c)
        c.war_fatigue = maxf(0.0, float(c.war_fatigue) - 0.02)
    _refresh_top()

func _refresh_selected() -> void:
    super._refresh_selected()
    if countries.has(selected_id):
        var c: Dictionary = countries[selected_id]
        var annual_growth: float = _annual_population_growth(selected_id) * 100.0
        var population: float = maxf(0.1, float(c.get("population", 100.0)))
        var military_share: float = 100.0 * _military_population(c) / population
        var daily_people: float = _daily_population_change_people(selected_id)
        _add_label(selected_panel, "Демография: %+.2f%% в год" % annual_growth)
        _add_label(selected_panel, "Изменение населения: %+.0f чел./день" % daily_people)
        _add_label(selected_panel, "Доля населения в армии: %.2f%%" % military_share)
        _add_label(selected_panel, "Влияние армии на доход: %.1f%%" % ((_military_labor_factor(c) - 1.0) * 100.0))
    _style_all_buttons(selected_panel)
