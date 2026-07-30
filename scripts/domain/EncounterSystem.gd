extends RefCounted
class_name EncounterSystem

const CreatureFactory = preload("res://scripts/domain/CreatureFactory.gd")
const ProgressionSystem = preload("res://scripts/domain/ProgressionSystem.gd")
const LevelSystem = preload("res://scripts/domain/LevelSystem.gd")
const DifficultySystem = preload("res://scripts/domain/DifficultySystem.gd")

const WILD_ELEMENT_POOL := ["nature", "fire", "water", "normal", "ice", "wind", "poison"]
const OBELISK_STAGE_MULTS := [1.22, 1.40, 1.60]
const OBELISK_STAGE_HUES := ["cyan", "amber", "violet"]
const FLOORS_PER_REGION := 5

static func floors_per_region() -> int:
	return FLOORS_PER_REGION

static func roll_wild(
	region_id: String,
	account: Dictionary,
	bosses_defeated: int = 0,
	floor: int = 1,
	difficulty: String = "normal"
) -> Dictionary:
	var wilds := DataRegistry.get_wilds_for_region(region_id)
	if wilds.is_empty():
		return {}
	# On deep floors, prefer evolved basilisk forms when present in the pool.
	wilds = _weight_wilds_for_floor(wilds, floor)
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
	var region := DataRegistry.get_region(region_id)
	var lvl := LevelSystem.encounter_level(region, floor, bosses_defeated, difficulty)
	LevelSystem.apply_encounter_level(creature, lvl)
	# Snapshot after level so pressure scales the leveled base without stacking later.
	creature.erase("unscaled_stats")
	apply_wild_pressure(creature, compute_wild_pressure(region, bosses_defeated, floor, difficulty), difficulty)
	return creature

static func _weight_wilds_for_floor(wilds: Array, floor: int) -> Array:
	## Deep floors tilt toward evolved forms (dread_basilisk).
	var out: Array = []
	for w in wilds:
		var entry: Dictionary = (w as Dictionary).duplicate(true)
		var id := str(entry.get("id", ""))
		if floor >= 4 and id == "dread_basilisk":
			entry["encounter_weight"] = int(entry.get("encounter_weight", 1)) + 10
		elif floor <= 2 and id == "dread_basilisk":
			entry["encounter_weight"] = maxi(1, int(entry.get("encounter_weight", 1)) - 6)
		elif floor >= 4 and id == "basilisk":
			entry["encounter_weight"] = maxi(2, int(entry.get("encounter_weight", 1)) - 4)
		out.append(entry)
	return out

static func wild_element_pool() -> Array:
	return WILD_ELEMENT_POOL.duplicate()

static func compute_wild_pressure(
	region: Dictionary,
	bosses_defeated: int,
	floor: int = 1,
	difficulty: String = "normal"
) -> float:
	## Hybrid: region sets the floor; deeper dungeon floors + bosses push harder.
	var region_tier := float(int(region.get("index", 1)) - 1)
	var floor_tier := 0.5 * float(clampi(floor, 1, FLOORS_PER_REGION) - 1)
	var global := 0.35 * float(maxi(0, bosses_defeated))
	var raw := region_tier + floor_tier + global
	raw *= DifficultySystem.pressure_mult(difficulty)
	return clampf(raw, 0.0, 8.0)

static func snapshot_unscaled_stats(creature: Dictionary) -> void:
	if creature.is_empty():
		return
	if creature.has("unscaled_stats"):
		return
	creature["unscaled_stats"] = (creature.get("stats", {}) as Dictionary).duplicate(true)

static func apply_wild_pressure(
	creature: Dictionary,
	pressure: float,
	difficulty: String = "normal"
) -> void:
	## Stats ≈ 1.0 + 0.10 * pressure · HP ≈ 1.0 + 0.12 * pressure (from unscaled base).
	if creature.is_empty():
		return
	snapshot_unscaled_stats(creature)
	var base: Dictionary = creature.get("unscaled_stats", creature.get("stats", {}))
	var p := clampf(pressure, 0.0, 8.0)
	var stat_m := (1.0 + 0.10 * p) * DifficultySystem.enemy_stat_mult(difficulty)
	var hp_m := (1.0 + 0.12 * p) * DifficultySystem.enemy_hp_mult(difficulty)
	var stats: Dictionary = {}
	for key in ["attack", "defense", "special_attack", "special_defense", "speed"]:
		stats[key] = maxi(1, int(round(float(base.get(key, 10)) * stat_m)))
	stats["hp"] = maxi(1, int(round(float(base.get("hp", 10)) * hp_m)))
	creature["stats"] = stats
	creature["max_hp"] = int(stats["hp"])
	creature["hp"] = int(stats["hp"])
	creature["wild_pressure"] = p
	creature["difficulty"] = DifficultySystem.normalize(difficulty)

static func refresh_wild_pressure(
	creature: Dictionary,
	region: Dictionary,
	bosses_defeated: int,
	floor: int = 1,
	difficulty: String = "normal"
) -> void:
	## Re-apply current hybrid pressure without stacking (uses unscaled snapshot).
	if creature.is_empty():
		return
	apply_wild_pressure(creature, compute_wild_pressure(region, bosses_defeated, floor, difficulty), difficulty)

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

static func obelisk_stage_mult(stage: int) -> float:
	var idx := clampi(stage, 1, OBELISK_STAGE_MULTS.size()) - 1
	return float(OBELISK_STAGE_MULTS[idx])

static func obelisk_stage_hue(stage: int) -> String:
	var idx := clampi(stage, 1, OBELISK_STAGE_HUES.size()) - 1
	return str(OBELISK_STAGE_HUES[idx])

static func obelisk_hue_color(hue: String) -> Color:
	match hue:
		"amber":
			return Color(1.0, 0.72, 0.28, 1.0)
		"violet":
			return Color(0.72, 0.45, 1.0, 1.0)
		_:
			return Color(0.35, 0.92, 1.0, 1.0) # cyan

static func create_obelisk_guardian(
	region_id: String,
	template_id: String = "",
	stage: int = 1,
	bosses_defeated: int = 0,
	floor: int = 1,
	difficulty: String = "normal"
) -> Dictionary:
	## In-place stages on regional wild base: ~1.22 / 1.40 / 1.60 (cyan/amber/violet).
	var tid := template_id
	if tid == "":
		var wilds := DataRegistry.get_wilds_for_region(region_id)
		if wilds.is_empty():
			return {}
		tid = str(wilds[randi() % wilds.size()].get("id", ""))
	if tid == "":
		return {}
	var stage_n := clampi(stage, 1, 3)
	var guardian := CreatureFactory.create_from_template(tid, {
		"is_alpha": false,
		"is_legendary": false
	})
	apply_random_wild_elements(guardian)
	var region := DataRegistry.get_region(region_id)
	var lvl := LevelSystem.encounter_level(region, floor, bosses_defeated, difficulty)
	LevelSystem.apply_encounter_level(guardian, lvl)
	guardian.erase("unscaled_stats")
	apply_wild_pressure(guardian, compute_wild_pressure(region, bosses_defeated, floor, difficulty), difficulty)
	var stage_mult := obelisk_stage_mult(stage_n) * DifficultySystem.obelisk_stage_mult_scale(difficulty)
	var stats: Dictionary = guardian.get("stats", {})
	for key in ["hp", "attack", "defense", "special_attack", "special_defense", "speed"]:
		stats[key] = maxi(1, int(round(float(stats.get(key, 10)) * stage_mult)))
	guardian["stats"] = stats
	guardian["max_hp"] = int(stats.get("hp", guardian.get("max_hp", 1)))
	guardian["hp"] = int(guardian["max_hp"])
	guardian["name"] = "%s Obelisk" % str(guardian.get("name", "Guardian"))
	guardian["is_obelisk_guardian"] = true
	guardian["is_alpha"] = false
	guardian["obelisk_stage"] = stage_n
	guardian["obelisk_hue"] = obelisk_stage_hue(stage_n)
	return guardian

static func create_boss(
	region: Dictionary,
	bosses_already_defeated: int = 0,
	floor: int = 5,
	difficulty: String = "normal"
) -> Dictionary:
	var boss_id = region.get("boss_id", null)
	if boss_id == null:
		return {}
	var boss := CreatureFactory.create_from_template(str(boss_id), {})
	if boss.is_empty():
		return {}
	_scale_boss_for_progress(boss, bosses_already_defeated, difficulty)
	_randomize_boss_elements(boss)
	var lvl := LevelSystem.encounter_level(
		region,
		clampi(floor, 1, FLOORS_PER_REGION),
		bosses_already_defeated,
		difficulty
	)
	boss["level"] = maxi(lvl, int(boss.get("level", 1)))
	boss["difficulty"] = DifficultySystem.normalize(difficulty)
	return boss

static func _scale_boss_for_progress(boss: Dictionary, tier: int, difficulty: String = "normal") -> void:
	## Stronger the more main bosses you've already beaten this run.
	## Keep existing bosses_defeated curve only — no extra stack with wild pressure.
	tier = clampi(tier, 0, 8)
	var jitter := randf_range(-0.03, 0.03)
	var mult := (1.0 + 0.12 * float(tier) + jitter) * DifficultySystem.boss_stat_mult(difficulty)
	var hp_mult := (1.0 + 0.15 * float(tier)) * DifficultySystem.boss_hp_mult(difficulty)
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
