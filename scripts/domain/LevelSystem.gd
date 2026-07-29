extends RefCounted
class_name LevelSystem
## In-run companion XP and level-ups from battle victories. No gold.

const CreatureFactory = preload("res://scripts/domain/CreatureFactory.gd")
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
		base = 14
	elif bool(enemy.get("is_legendary", false)):
		base = 22
	elif bool(enemy.get("is_alpha", false)):
		base = 12
	base += clampi(int(enemy.get("max_hp", 20)) / 40, 0, 8)
	return maxi(1, base)

static func grant_battle_xp(companion: Dictionary, enemy: Dictionary, is_boss: bool) -> Dictionary:
	## Returns {xp_gained, levels_gained, logs: PackedStringArray-like Array, level, xp}
	ensure_fields(companion)
	var gained := battle_xp_reward(enemy, is_boss)
	if int(companion.get("level", 1)) >= MAX_LEVEL:
		return {
			"xp_gained": 0,
			"levels_gained": 0,
			"logs": [],
			"level": int(companion.get("level", MAX_LEVEL)),
			"xp": int(companion.get("xp", 0))
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
	return {
		"xp_gained": gained,
		"levels_gained": levels,
		"logs": logs,
		"level": int(companion.get("level", 1)),
		"xp": int(companion.get("xp", 0))
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
