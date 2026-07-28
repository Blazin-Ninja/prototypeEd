extends RefCounted
class_name AbsorptionSystem
## Independent absorption rolls after victory.

static func preview_chances(enemy: Dictionary, account: Dictionary) -> Dictionary:
	var table: Dictionary = enemy.get("absorption", {})
	var bonus := _absorb_multiplier(account)
	if enemy.get("is_alpha", false):
		bonus *= float(DataRegistry.alpha_config.get("absorb_bonus", 1.5))
	return {
		"stat": _pct(table.get("stat_chance", 0), bonus),
		"ability": _pct(table.get("ability_chance", 0), bonus),
		"element": _pct(table.get("element_chance", 0), bonus),
		"mutation": _pct(table.get("mutation_chance", 0), bonus),
		"rare_passive": _pct(table.get("rare_passive_chance", 0), bonus),
		"special_mutation": _pct(table.get("special_mutation_chance", 0), bonus)
	}

static func roll_all(companion: Dictionary, enemy: Dictionary, account: Dictionary) -> Array:
	var table: Dictionary = enemy.get("absorption", {})
	var bonus := _absorb_multiplier(account)
	if enemy.get("is_alpha", false):
		bonus *= float(DataRegistry.alpha_config.get("absorb_bonus", 1.5))
	var results: Array = []

	# Stat gain
	if _roll(table.get("stat_chance", 0), bonus):
		var gains: Dictionary = table.get("stat_gains", {})
		if not gains.is_empty():
			var keys: Array = gains.keys()
			var stat_key := str(keys[randi() % keys.size()])
			var rng: Array = gains[stat_key]
			var amount := int(rng[0])
			if rng.size() > 1:
				amount = randi_range(int(rng[0]), int(rng[1]))
			results.append({
				"type": "stat",
				"stat": stat_key,
				"amount": amount,
				"label": "+%d %s" % [amount, stat_key.replace("_", " ").capitalize()],
				"needs_choice": false
			})

	# Ability / upgrade
	if _roll(table.get("ability_chance", 0), bonus):
		var pool: Array = table.get("ability_pool", [])
		if not pool.is_empty():
			var pick := str(pool[randi() % pool.size()])
			var upgrade := AbilitySystem.find_upgrade(companion, pick, enemy)
			if not upgrade.is_empty():
				results.append({
					"type": "ability_upgrade",
					"from": upgrade.get("from"),
					"to": upgrade.get("to"),
					"label": "Ability evolves: %s → %s" % [
						DataRegistry.get_ability(str(upgrade.get("from"))).get("name", upgrade.get("from")),
						DataRegistry.get_ability(str(upgrade.get("to"))).get("name", upgrade.get("to"))
					],
					"needs_choice": false
				})
			else:
				var abdef: Dictionary = DataRegistry.get_ability(pick)
				var el = abdef.get("element", null)
				var el_txt := str(el).capitalize() if el != null else "Neutral"
				results.append({
					"type": "ability",
					"ability_id": pick,
					"label": "New ability: %s (Pwr %d · %s)" % [
						abdef.get("name", pick),
						int(abdef.get("power", 0)),
						el_txt
					],
					"needs_choice": companion.get("abilities", []).size() >= DataRegistry.max_abilities,
					"full": companion.get("abilities", []).size() >= DataRegistry.max_abilities
				})

	# Element
	if _roll(table.get("element_chance", 0), bonus):
		var epool: Array = table.get("element_pool", [])
		# Prefer enemy elements if pool empty.
		if epool.is_empty():
			epool = enemy.get("elements", [])
		if not epool.is_empty():
			var el := str(epool[randi() % epool.size()])
			var current: Array = companion.get("elements", [])
			if current.has(el):
				results.append({
					"type": "element_fail_dup",
					"element": el,
					"label": "Already has %s element" % el.capitalize(),
					"needs_choice": false,
					"skip": true
				})
			else:
				results.append({
					"type": "element",
					"element": el,
					"label": "Element: %s" % el.capitalize(),
					"needs_choice": current.size() >= DataRegistry.max_elements,
					"full": current.size() >= DataRegistry.max_elements
				})

	# Visual mutation
	if _roll(table.get("mutation_chance", 0), bonus):
		var mpool: Array = table.get("mutation_pool", [])
		var mid := _pick_mutation(mpool, companion, enemy)
		if mid != "":
			results.append({
				"type": "mutation",
				"mutation_id": mid,
				"label": "Mutation: %s" % DataRegistry.get_mutation(mid).get("name", mid),
				"needs_choice": false
			})

	# Rare passive
	if _roll(table.get("rare_passive_chance", 0), bonus):
		var stats := ["attack", "defense", "speed", "special_attack", "special_defense", "hp"]
		var sk := str(stats[randi() % stats.size()])
		results.append({
			"type": "rare_passive",
			"stat": sk,
			"amount": 2,
			"label": "Rare passive: +2 %s" % sk.replace("_", " ").capitalize(),
			"needs_choice": false
		})

	# Special mutation
	if _roll(table.get("special_mutation_chance", 0), bonus):
		var spool: Array = table.get("special_mutation_pool", [])
		var sid := _pick_mutation(spool, companion, enemy)
		if sid != "":
			results.append({
				"type": "special_mutation",
				"mutation_id": sid,
				"label": "Special mutation: %s" % DataRegistry.get_mutation(sid).get("name", sid),
				"needs_choice": false
			})

	return results

static func apply_result(companion: Dictionary, result: Dictionary, choice: Dictionary = {}) -> Dictionary:
	if result.get("skip", false):
		return {"applied": false, "message": result.get("label", "Skipped")}

	match str(result.get("type", "")):
		"stat", "rare_passive":
			var stat := str(result.get("stat"))
			var amount := int(result.get("amount", 1))
			var stats: Dictionary = companion.get("stats", {})
			stats[stat] = int(stats.get(stat, 0)) + amount
			companion["stats"] = stats
			if stat == "hp":
				companion["max_hp"] = int(stats["hp"])
				companion["hp"] = mini(int(companion.get("hp", 0)) + amount, int(companion["max_hp"]))
			CreatureFactory.apply_stat_cap(companion)
			return {"applied": true, "message": result.get("label")}
		"ability_upgrade":
			AbilitySystem.upgrade_ability(companion, str(result.get("from")), str(result.get("to")))
			return {"applied": true, "message": result.get("label")}
		"ability":
			var aid := str(result.get("ability_id"))
			if companion.get("abilities", []).has(aid):
				return {"applied": false, "message": "Already knows ability"}
			if companion.get("abilities", []).size() >= DataRegistry.max_abilities:
				var replace := str(choice.get("replace_ability", ""))
				if replace == "" or not companion.get("abilities", []).has(replace):
					return {"applied": false, "message": "Skipped ability (slot full)"}
				AbilitySystem.replace_ability(companion, replace, aid)
				return {"applied": true, "message": "Replaced ability with %s" % DataRegistry.get_ability(aid).get("name", aid)}
			AbilitySystem.add_ability(companion, aid)
			return {"applied": true, "message": result.get("label")}
		"element":
			var el := str(result.get("element"))
			var els: Array = companion.get("elements", [])
			if els.has(el):
				return {"applied": false, "message": "Duplicate element"}
			if els.size() >= DataRegistry.max_elements:
				var replace_el := str(choice.get("replace_element", ""))
				if replace_el == "" or not els.has(replace_el):
					return {"applied": false, "message": "Skipped element (slot full)"}
				els.erase(replace_el)
			els.append(el)
			companion["elements"] = els
			return {"applied": true, "message": result.get("label")}
		"mutation", "special_mutation":
			var mid := str(result.get("mutation_id"))
			MutationSystem.apply_mutation(companion, mid)
			return {"applied": true, "message": result.get("label")}
		_:
			return {"applied": false, "message": "Unknown result"}

static func _pick_mutation(pool: Array, companion: Dictionary, enemy: Dictionary) -> String:
	var owned: Array = companion.get("mutations", [])
	var candidates: Array = []
	for mid in pool:
		if owned.has(mid):
			continue
		var m: Dictionary = DataRegistry.get_mutation(str(mid))
		if m.is_empty():
			continue
		var fams: Array = m.get("families", [])
		if fams.is_empty():
			candidates.append(mid)
			continue
		var ok := false
		for f in enemy.get("families", []):
			if fams.has(f):
				ok = true
				break
		for f in companion.get("families", []):
			if fams.has(f):
				ok = true
				break
		if ok:
			candidates.append(mid)
	if candidates.is_empty():
		return ""
	return str(candidates[randi() % candidates.size()])

static func _absorb_multiplier(account: Dictionary) -> float:
	var mult := 1.0
	for uid in account.get("owned_unlocks", []):
		for u in DataRegistry.progression.get("unlocks", []):
			if u.get("id") == uid and u.get("type") == "absorb_bonus":
				mult *= float(u.get("payload", {}).get("multiplier", 1.0))
	return mult

static func _pct(base, bonus: float) -> int:
	return int(clampf(float(base) * bonus, 0.0, 100.0))

static func _roll(base, bonus: float) -> bool:
	return randi() % 100 < _pct(base, bonus)
