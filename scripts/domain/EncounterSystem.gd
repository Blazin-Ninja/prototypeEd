extends RefCounted
class_name EncounterSystem

static func roll_wild(region_id: String, account: Dictionary) -> Dictionary:
	var wilds := DataRegistry.get_wilds_for_region(region_id)
	if wilds.is_empty():
		return {}
	var total := 0
	for w in wilds:
		total += int(w.get("encounter_weight", 1))
	var pick := randi() % maxi(total, 1)
	var acc := 0
	var chosen: Dictionary = wilds[0]
	for w in wilds:
		acc += int(w.get("encounter_weight", 1))
		if pick < acc:
			chosen = w
			break

	var alpha_chance := float(DataRegistry.alpha_config.get("base_chance", 0.01))
	alpha_chance += ProgressionSystem.alpha_bonus(account)
	var is_alpha := randf() < alpha_chance
	var is_legendary := randf() < float(DataRegistry.legendary_config.get("base_chance", 0.001))
	# Legendary supersedes alpha; still very rare.
	return CreatureFactory.create_from_template(str(chosen.get("id")), {
		"is_alpha": is_alpha and not is_legendary,
		"is_legendary": is_legendary
	})

static func should_trigger_encounter(region: Dictionary, on_grass: bool) -> bool:
	if not on_grass:
		return false
	return randf() < float(region.get("grass_encounter_chance", 0.15))

static func create_obelisk_guardian(region_id: String, template_id: String = "") -> Dictionary:
	## Special fight: alpha-tier regional guardian bound to an obelisk.
	var tid := template_id
	if tid == "":
		var wilds := DataRegistry.get_wilds_for_region(region_id)
		if wilds.is_empty():
			return {}
		tid = str(wilds[randi() % wilds.size()].get("id", ""))
	if tid == "":
		return {}
	var guardian := CreatureFactory.create_from_template(tid, {
		"is_alpha": true,
		"is_legendary": false
	})
	# Buff beyond a normal alpha for a distinct challenge.
	var stats: Dictionary = guardian.get("stats", {})
	for key in ["hp", "attack", "defense", "special_attack", "special_defense", "speed"]:
		stats[key] = int(round(float(stats.get(key, 10)) * 1.35))
	guardian["stats"] = stats
	guardian["max_hp"] = int(stats.get("hp", guardian.get("max_hp", 1)))
	guardian["hp"] = int(guardian["max_hp"])
	guardian["name"] = "%s Obelisk" % str(guardian.get("name", "Guardian"))
	guardian["is_obelisk_guardian"] = true
	return guardian

static func create_boss(region: Dictionary) -> Dictionary:
	var boss_id = region.get("boss_id", null)
	if boss_id == null:
		return {}
	return CreatureFactory.create_from_template(str(boss_id), {})
