extends "res://main_diplomacy.gd"

const ECONOMY_POP_SENSITIVITY := 0.00008
const MIN_ANNUAL_POP_GROWTH := -0.03
const MAX_ANNUAL_POP_GROWTH := 0.025
const POPULATION_INCOME_EXPONENT := 0.65

# Baseline demographic trend used by the 10 playable countries.
# Economy and war fatigue modify these values dynamically during the game.
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

func _annual_population_growth(id: String) -> float:
    var c: Dictionary = countries[id]
    var natural: float = float(PLAYABLE_BASE_GROWTH.get(id, POP_GROWTH_ANNUAL.get(id, 0.003)))
    var economy_modifier: float = (float(c.economy) - 100.0) * ECONOMY_POP_SENSITIVITY
    var fatigue_modifier: float = -float(c.war_fatigue) * 0.00004
    return clampf(natural + economy_modifier + fatigue_modifier, MIN_ANNUAL_POP_GROWTH, MAX_ANNUAL_POP_GROWTH)

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

func _economic_tick() -> void:
    for id in countries.keys():
        var c: Dictionary = countries[id]
        var upkeep: float = _total_power(c) * 0.00008
        c.treasury += maxf(0.0, _effective_income(c) - upkeep)
        c.war_fatigue = maxf(0.0, float(c.war_fatigue) - 0.02)

        var annual_growth: float = _annual_population_growth(id)
        c.population = maxf(0.1, float(c.population) * (1.0 + annual_growth / 525600.0))

    _refresh_top()

func _refresh_selected() -> void:
    super._refresh_selected()
    if countries.has(selected_id):
        var c: Dictionary = countries[selected_id]
        var annual_growth: float = _annual_population_growth(selected_id) * 100.0
        var population: float = maxf(0.1, float(c.get("population", 100.0)))
        var military_share: float = 100.0 * _military_population(c) / population
        _add_label(selected_panel, "Демография: %+.2f%% в год" % annual_growth)
        _add_label(selected_panel, "Доля населения в армии: %.2f%%" % military_share)
        _add_label(selected_panel, "Влияние армии на доход: %.1f%%" % ((_military_labor_factor(c) - 1.0) * 100.0))
    _style_all_buttons(selected_panel)
