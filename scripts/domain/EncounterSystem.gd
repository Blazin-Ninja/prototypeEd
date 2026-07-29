extends RefCounted
class_name EncounterSystem

const CreatureFactory = preload("res://scripts/domain/CreatureFactory.gd")
const ProgressionSystem = preload("res://scripts/domain/ProgressionSystem.gd")

const WILD_ELEMENT_POOL := ["nature", "fire", "water", "normal", "ice", "wind", "poison"]

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
	var creature := CreatureFactory.create_from_template(str(chosen.get("id")), {
		"is_alpha": is_alpha and not is_legendary,
		"is_legendary": is_legendary
	})
	apply_random_wild_elements(creature)
	return creature

static func wild_element_pool() -> Array:
	return WILD_ELEMENT_POOL.duplicate()

static func apply_random_wild_elements(creature: Dictionary) -> void:
	## Grass/Fire/Water/Normal/Ice/Flying/Poison — 1 primary, sometimes a second.
	if creature.is_empty():
		return
	var pool: Array = WILD_ELEMENT_POOL.duplicate()
	pool.shuffle()
	var rolled: Array = [str(pool[0])]
	if randf() < 0.18 and pool.size() > 1:
		rolled.append(str(pool[1]))
	creature["elements"] = rolled
	# Keep absorb pool aligned with what you fought.
	var absorption: Dictionary = creature.get("absorption", {})
	absorption["element_pool"] = rolled.duplicate()
	creature["absorption"] = absorption

static func should_trigger_encounter(region: Dictionary, on_grass: bool) -> bool:
	if not on_grass:
		return false
	return randf() < float(region.get("grass_encounter_chance", 0.15))

static func create_obelisk_guardian(region_id: String, template_id: String = "") -> Dictionary:
	## Optional side fight: one mild guardian tier (~1.22×), not alpha double-dip.
	var tid := template_id
	if tid == "":
		var wilds := DataRegistry.get_wilds_for_region(region_id)
		if wilds.is_empty():
			return {}
		tid = str(wilds[randi() % wilds.size()].get("id", ""))
	if tid == "":
		return {}
	var guardian := CreatureFactory.create_from_template(tid, {
		"is_alpha": false,
		"is_legendary": false
	})
	apply_random_wild_elements(guardian)
	var stats: Dictionary = guardian.get("stats", {})
	for key in ["hp", "attack", "defense", "special_attack", "special_defense", "speed"]:
		stats[key] = int(round(float(stats.get(key, 10)) * 1.22))
	guardian["stats"] = stats
	guardian["max_hp"] = int(stats.get("hp", guardian.get("max_hp", 1)))
	guardian["hp"] = int(guardian["max_hp"])
	guardian["name"] = "%s Obelisk" % str(guardian.get("name", "Guardian"))
	guardian["is_obelisk_guardian"] = true
	guardian["is_alpha"] = false
	return guardian

static func create_boss(region: Dictionary, bosses_already_defeated: int = 0) -> Dictionary:
	var boss_id = region.get("boss_id", null)
	if boss_id == null:
		return {}
	var boss := CreatureFactory.create_from_template(str(boss_id), {})
	if boss.is_empty():
		return {}
	_scale_boss_for_progress(boss, bosses_already_defeated)
	_randomize_boss_elements(boss)
	return boss

static func _scale_boss_for_progress(boss: Dictionary, tier: int) -> void:
	## Stronger the more main bosses you've already beaten this run.
	tier = clampi(tier, 0, 8)
	var jitter := randf_range(-0.03, 0.03)
	var mult := 1.0 + 0.12 * float(tier) + jitter
	var hp_mult := 1.0 + 0.15 * float(tier)
	var stats: Dictionary = boss.get("stats", {})
	for key in ["attack", "defense", "special_attack", "special_defense", "speed"]:
		stats[key] = maxi(1, int(round(float(stats.get(key, 10)) * mult)))
	stats["hp"] = maxi(1, int(round(float(stats.get("hp", 10)) * hp_mult)))
	boss["stats"] = stats
	boss["max_hp"] = int(stats["hp"])
	boss["hp"] = int(stats["hp"])
	boss["boss_tier"] = tier

static func _randomize_boss_elements(boss: Dictionary) -> void:
	var original: Array = boss.get("elements", []).duplicate()
	var pool: Array = WILD_ELEMENT_POOL.duplicate()
	pool.shuffle()
	var rolled: Array = []
	# Keep at least one original type when possible so the boss still reads as itself.
	if not original.is_empty() and randf() < 0.7:
		rolled.append(str(original[0]))
	while rolled.size() < 2 and not pool.is_empty():
		var nxt := str(pool.pop_back())
		if rolled.has(nxt):
			continue
		rolled.append(nxt)
	if rolled.is_empty():
		rolled = [str(WILD_ELEMENT_POOL[randi() % WILD_ELEMENT_POOL.size()])]
	boss["elements"] = rolled
	var absorption: Dictionary = boss.get("absorption", {})
	absorption["element_pool"] = rolled.duplicate()
	boss["absorption"] = absorption
