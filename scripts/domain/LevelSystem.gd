extends RefCounted
class_name LevelSystem
## In-run companion XP and level-ups from battle victories. No gold.

const CreatureFactory = preload("res://scripts/domain/CreatureFactory.gd")
const EvolutionSystem = preload("res://scripts/domain/EvolutionSystem.gd")
const DifficultySystem = preload("res://scripts/domain/DifficultySystem.gd")
const MAX_LEVEL := 20

static func ensure_fields(companion: Dictionary) -> void:
	if not companion.has("level"):
		companion["level"] = 1
	if not companion.has("xp"):
		companion["xp"] = 0
	companion["level"] = clampi(int(companion.get("level", 1)), 1, MAX_LEVEL)
	companion["xp"] = maxi(0, int(companion.get("xp", 0)))

static func xp_to_next(level: int) -> int:
	var lv := clampi(level, 1, MAX_LEVEL)
	return 10 + lv * 8

static func battle_xp_reward(enemy: Dictionary, is_boss: bool) -> int:
	var base := 8
	if is_boss:
		base = 28
	elif bool(enemy.get("is_obelisk_guardian", false)):
		# Stage 1/2/3: 14 / 18 / 24 — violet is best XP of the chain.
		var stage := clampi(int(enemy.get("obelisk_stage", 1)), 1, 3)
		base = 10 + stage * 4
	elif bool(enemy.get("is_legendary", false)):
		base = 22
	elif bool(enemy.get("is_alpha", false)):
		base = 12
	base += clampi(int(enemy.get("max_hp", 20)) / 40, 0, 8)
	# Deeper floors / higher enemy levels grant a bit more XP.
	base += clampi(int(enemy.get("level", 1)) / 3, 0, 6)
	return maxi(1, base)

static func grant_battle_xp(companion: Dictionary, enemy: Dictionary, is_boss: bool) -> Dictionary:
	## Returns {xp_gained, levels_gained, logs, level, xp, evolved, evolve_log}
	ensure_fields(companion)
	var gained := battle_xp_reward(enemy, is_boss)
	if int(companion.get("level", 1)) >= MAX_LEVEL:
		var evo_capped := EvolutionSystem.try_evolve(companion)
		return {
			"xp_gained": 0,
			"levels_gained": 0,
			"logs": [],
			"level": int(companion.get("level", MAX_LEVEL)),
			"xp": int(companion.get("xp", 0)),
			"evolved": bool(evo_capped.get("evolved", false)),
			"evolve_log": str(evo_capped.get("log", ""))
		}
	companion["xp"] = int(companion.get("xp", 0)) + gained
	var levels := 0
	var logs: Array = []
	while int(companion.get("level", 1)) < MAX_LEVEL \
			and int(companion.get("xp", 0)) >= xp_to_next(int(companion.get("level", 1))):
		companion["xp"] = int(companion["xp"]) - xp_to_next(int(companion["level"]))
		companion["level"] = int(companion["level"]) + 1
		levels += 1
		_apply_level_bonus(companion)
		logs.append("%s reached Lv %d!" % [str(companion.get("name", "Companion")), int(companion["level"])])
	if int(companion.get("level", 1)) >= MAX_LEVEL:
		companion["xp"] = 0
	CreatureFactory.apply_stat_cap(companion)
	var evo := EvolutionSystem.try_evolve(companion)
	if bool(evo.get("evolved", false)):
		logs.append(str(evo.get("log", "Evolution!")))
	return {
		"xp_gained": gained,
		"levels_gained": levels,
		"logs": logs,
		"level": int(companion.get("level", 1)),
		"xp": int(companion.get("xp", 0)),
		"evolved": bool(evo.get("evolved", false)),
		"evolve_log": str(evo.get("log", ""))
	}

static func _apply_level_bonus(companion: Dictionary) -> void:
	var stats: Dictionary = companion.get("stats", {})
	var old_hp_stat := int(stats.get("hp", 10))
	var hp_gain := maxi(2, int(round(float(old_hp_stat) * 0.06)))
	stats["hp"] = old_hp_stat + hp_gain
	stats["attack"] = int(stats.get("attack", 5)) + 2
	stats["special_attack"] = int(stats.get("special_attack", 5)) + 2
	stats["defense"] = int(stats.get("defense", 5)) + 1
	stats["special_defense"] = int(stats.get("special_defense", 5)) + 1
	stats["speed"] = int(stats.get("speed", 5)) + 1
	companion["stats"] = stats
	var new_max := int(stats["hp"])
	var cur := int(companion.get("hp", new_max))
	companion["max_hp"] = new_max
	companion["hp"] = mini(new_max, cur + hp_gain)

static func encounter_level(
	region: Dictionary,
	floor: int,
	bosses_defeated: int,
	difficulty: String = "normal"
) -> int:
	## Progressing encounter level across region floors (1..20).
	var region_tier := maxi(0, int(region.get("index", 1)) - 1)
	var floor_n := clampi(floor, 1, 5)
	var lvl := 1 + region_tier * 3 + (floor_n - 1) + int(floor(float(maxi(0, bosses_defeated)) * 0.5))
	lvl += DifficultySystem.encounter_level_offset(difficulty)
	return clampi(lvl, 1, MAX_LEVEL)

static func apply_encounter_level(creature: Dictionary, level: int) -> void:
	## Raise a freshly created enemy from Lv1 base up to the encounter level.
	if creature.is_empty():
		return
	ensure_fields(creature)
	var target := clampi(level, 1, MAX_LEVEL)
	var current := clampi(int(creature.get("level", 1)), 1, MAX_LEVEL)
	while current < target:
		_apply_level_bonus(creature)
		current += 1
		creature["level"] = current
	creature["level"] = target
	creature["xp"] = 0
	CreatureFactory.apply_stat_cap(creature)
	creature["hp"] = int(creature.get("max_hp", creature.get("hp", 1)))
