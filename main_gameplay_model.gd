extends "res://main_game_tuning.gd"

const MIN_ANNUAL_POP_GROWTH := -0.030
const MAX_ANNUAL_POP_GROWTH := 0.025
const ECONOMY_GROWTH_COEFFICIENT := 0.00008
const WAR_SCORE_THRESHOLD := 60.0

func _ensure_population_data() -> void:
    super._ensure_population_data()
    for id in countries.keys():
        var c: Dictionary = countries[id]
        if not c.has("starting_population"):
            c["starting_population"] = maxf(0.1, float(c.get("population", 100.0)))
        if not c.has("war_cooldown"):
            c["war_cooldown"] = 0

func _annual_population_growth(id: String) -> float:
    var c: Dictionary = countries[id]
    var base_growth: float = float(POP_GROWTH_ANNUAL.get(id, 0.003))
    var economy_modifier: float = (float(c.economy) - 100.0) * ECONOMY_GROWTH_COEFFICIENT
    var fatigue_modifier: float = -float(c.war_fatigue) * 0.00004
    return clampf(base_growth + economy_modifier + fatigue_modifier, MIN_ANNUAL_POP_GROWTH, MAX_ANNUAL_POP_GROWTH)

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
    var starting_population: float = maxf(0.1, float(c.get("starting_population", population)))
    var population_factor: float = pow(population / starting_population, 0.65)
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

func _bot_tick() -> void:
    for id in countries.keys():
        if id == player_id:
            continue

        var c: Dictionary = countries[id]
        c.war_cooldown = maxi(0, int(c.get("war_cooldown", 0)) - 1)
        var roll: float = randf()

        if roll < 0.46 and c.treasury > 150.0:
            var key: String = UNIT_KEYS.pick_random()
            var price: float = _unit_price(id, key)
            if c.treasury >= price and _can_recruit(c, key, 100.0):
                c.treasury -= price
                c[key] += 100.0
                _push_news("%s наращивает вооружение: %s +100." % [c.name, UNIT_LABELS[key]])
        elif roll < 0.72 and c.treasury >= 250.0:
            c.treasury -= 250.0
            c.economy += 1.0
            c.income *= 1.01
            _push_news("%s инвестирует 250 млн в экономику." % c.name)
        elif roll < 0.82:
            _bot_diplomacy(id)
        elif roll > 0.97:
            _bot_may_attack(id)

    _refresh_all()

func _allied_power(country_id: String) -> float:
    var total: float = 0.0
    for ally_id in countries[country_id].get("allies", []):
        if countries.has(ally_id):
            total += _total_power(countries[ally_id])
    return total

func _war_desire_score(attacker_id: String, defender_id: String) -> float:
    var a: Dictionary = countries[attacker_id]
    var d: Dictionary = countries[defender_id]
    var score: float = 10.0
    var relations: int = int(a.relations.get(defender_id, 0))
    var strength_ratio: float = _total_power(a) / maxf(1.0, _total_power(d))

    if relations <= -50:
        score += 25.0
    elif relations <= -20:
        score += 15.0
    elif relations >= 40:
        score -= 35.0
    elif relations >= 20:
        score -= 20.0

    if strength_ratio >= 1.50:
        score += 25.0
    elif strength_ratio >= 1.25:
        score += 15.0
    elif strength_ratio < 0.80:
        score -= 40.0
    elif strength_ratio < 1.00:
        score -= 25.0

    match str(a.ai):
        "агрессивный": score += 18.0
        "авантюрный": score += 10.0
        "осторожный": score -= 15.0
        "дипломатический": score -= 18.0
        "экономический": score -= 12.0
        _: pass

    score -= float(a.war_fatigue) * 0.45

    var income: float = maxf(1.0, _effective_income(a))
    if float(a.treasury) < income * 3.0:
        score -= 25.0
    elif float(a.treasury) > income * 10.0:
        score += 8.0

    if float(a.economy) < 80.0:
        score -= 15.0
    elif float(a.economy) > 120.0:
        score += 5.0

    var defender_allies: float = _allied_power(defender_id)
    if defender_allies > _total_power(d) * 0.50:
        score -= 10.0
    if defender_allies > _total_power(a):
        score -= 25.0

    if float(d.treasury) > float(a.treasury) * 1.5:
        score += 5.0

    return score

func _bot_may_attack(attacker_id: String) -> void:
    if int(countries[attacker_id].get("war_cooldown", 0)) > 0:
        return

    var best_target: String = ""
    var best_score: float = -999.0
    for target_id in countries.keys():
        if target_id == attacker_id or _are_allies(attacker_id, target_id):
            continue
        var score: float = _war_desire_score(attacker_id, target_id)
        if score > best_score:
            best_score = score
            best_target = target_id

    if best_target == "" or best_score < WAR_SCORE_THRESHOLD:
        return

    var attack_fraction: float = clampf(0.20 + (best_score - WAR_SCORE_THRESHOLD) * 0.004, 0.20, 0.42)
    if str(countries[attacker_id].ai) == "агрессивный":
        attack_fraction = minf(0.48, attack_fraction + 0.05)
    _resolve_battle(attacker_id, best_target, attack_fraction, true)

func _resolve_battle(attacker_id: String, defender_id: String, attack_fraction: float, silent_bot: bool = false) -> void:
    if _are_allies(attacker_id, defender_id):
        return

    var attacker_power_before: float = _total_power(countries[attacker_id])
    var defender_power_before: float = _total_power(countries[defender_id])
    super._resolve_battle(attacker_id, defender_id, attack_fraction, silent_bot)

    if not countries.has(attacker_id) or not countries.has(defender_id):
        return

    var attacker_loss_share: float = 1.0 - _total_power(countries[attacker_id]) / maxf(1.0, attacker_power_before)
    var defender_loss_share: float = 1.0 - _total_power(countries[defender_id]) / maxf(1.0, defender_power_before)

    if attacker_loss_share > defender_loss_share + 0.03:
        countries[attacker_id].war_cooldown = randi_range(10, 16)
        countries[attacker_id].war_fatigue = minf(100.0, float(countries[attacker_id].war_fatigue) + 10.0)
    else:
        countries[attacker_id].war_cooldown = randi_range(6, 10)
        countries[attacker_id].war_fatigue = minf(100.0, float(countries[attacker_id].war_fatigue) + 4.0)

    countries[defender_id].war_cooldown = maxi(int(countries[defender_id].get("war_cooldown", 0)), randi_range(4, 8))

func _refresh_selected() -> void:
    super._refresh_selected()
    if countries.has(selected_id):
        var c: Dictionary = countries[selected_id]
        var growth_percent: float = _annual_population_growth(selected_id) * 100.0
        var military_share_percent: float = 100.0 * _military_population(c) / maxf(0.1, float(c.population))
        _add_label(selected_panel, "Демография: %+.2f%% в год" % growth_percent)
        _add_label(selected_panel, "Население в армии: %.2f%%" % military_share_percent)
        _add_label(selected_panel, "Влияние армии на доход: %.1f%%" % ((_military_labor_factor(c) - 1.0) * 100.0))
        _style_all_buttons(selected_panel)
