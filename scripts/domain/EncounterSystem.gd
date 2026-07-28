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

static func create_boss(region: Dictionary) -> Dictionary:
	var boss_id = region.get("boss_id", null)
	if boss_id == null:
		return {}
	return CreatureFactory.create_from_template(str(boss_id), {})
