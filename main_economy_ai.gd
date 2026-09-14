extends "res://main_diplomacy.gd"

const ECONOMY_POP_CENTER := 2500.0
const ECONOMY_POP_SENSITIVITY := 0.006
const MIN_ANNUAL_POP_GROWTH := -0.03
const MAX_ANNUAL_POP_GROWTH := 0.025
const MILITARY_FREE_SHARE := 0.01
const MILITARY_LABOR_PENALTY := 4.0
const MIN_LABOR_FACTOR := 0.55
const POPULATION_INCOME_EXPONENT := 0.65

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
    var natural: float = float(POP_GROWTH_ANNUAL.get(id, 0.003))
    var economy: float = float(c.economy)
    var economy_modifier: float = clampf(
        ((economy - ECONOMY_POP_CENTER) / ECONOMY_POP_CENTER) * ECONOMY_POP_SENSITIVITY,
        -0.008,
        0.012
    )
    var fatigue_modifier: float = -float(c.war_fatigue) * 0.00008
    return clampf(natural + economy_modifier + fatigue_modifier, MIN_ANNUAL_POP_GROWTH, MAX_ANNUAL_POP_GROWTH)

func _effective_income(c: Dictionary) -> float:
    var population: float = maxf(0.1, float(c.get("population", 100.0)))
    var initial_population: float = maxf(0.1, float(c.get("initial_population", population)))
    var population_factor: float = pow(population / initial_population, POPULATION_INCOME_EXPONENT)

    var military_share: float = clampf(_military_population(c) / population, 0.0, 0.20)
    var excess_military_share: float = maxf(0.0, military_share - MILITARY_FREE_SHARE)
    var labor_factor: float = clampf(1.0 - excess_military_share * MILITARY_LABOR_PENALTY, MIN_LABOR_FACTOR, 1.0)

    return maxf(0.0, float(c.income) * population_factor * labor_factor)

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
        var annual_growth: float = _annual_population_growth(selected_id) * 100.0
        _add_label(selected_panel, "Демография: %+.2f%% в год" % annual_growth)
        var c: Dictionary = countries[selected_id]
        var population: float = maxf(0.1, float(c.get("population", 100.0)))
        var military_share: float = 100.0 * _military_population(c) / population
        _add_label(selected_panel, "Доля населения в армии: %.2f%%" % military_share)
    _style_all_buttons(selected_panel)
