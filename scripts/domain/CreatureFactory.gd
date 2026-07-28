extends RefCounted
class_name CreatureFactory
## Builds runtime creature dictionaries from templates.

static func create_from_template(template_id: String, opts: Dictionary = {}) -> Dictionary:
	var template: Dictionary = DataRegistry.get_creature(template_id)
	if template.is_empty():
		push_error("Unknown creature template: %s" % template_id)
		return {}
	var stats: Dictionary = (template.get("base_stats", {}) as Dictionary).duplicate(true)
	var is_alpha := bool(opts.get("is_alpha", false))
	var is_legendary := bool(opts.get("is_legendary", false))
	var name := str(template.get("name", template_id))
	var abilities: Array = (template.get("abilities", []) as Array).duplicate()
	var mutations: Array = []
	var color := str(template.get("color", "#888888"))

	if is_legendary:
		var lm := float(DataRegistry.legendary_config.get("stat_multiplier", 1.75))
		_scale_stats(stats, lm)
		name = "Legendary %s" % name
	elif is_alpha:
		var am := float(DataRegistry.alpha_config.get("stat_multiplier", 1.35))
		_scale_stats(stats, am)
		name = "%s %s" % [DataRegistry.alpha_config.get("name_prefix", "Alpha"), name]
		var bonus_ab := str(DataRegistry.alpha_config.get("bonus_ability", ""))
		if bonus_ab != "" and not abilities.has(bonus_ab):
			abilities.append(bonus_ab)
		var bonus_mu := str(DataRegistry.alpha_config.get("bonus_mutation", ""))
		if bonus_mu != "":
			mutations.append(bonus_mu)
		color = _shift_color(color)

	var max_hp := int(stats.get("hp", 1))
	return {
		"id": template_id,
		"instance_id": _make_id(),
		"name": name,
		"template_id": template_id,
		"stats": stats,
		"max_hp": max_hp,
		"hp": max_hp,
		"elements": (template.get("elements", []) as Array).duplicate(),
		"families": (template.get("families", []) as Array).duplicate(),
		"abilities": abilities,
		"mutations": mutations,
		"passives": [],
		"statuses": [],
		"color": color,
		"shape": str(template.get("shape", "quad")),
		"is_player": bool(opts.get("is_player", false)),
		"is_alpha": is_alpha,
		"is_legendary": is_legendary,
		"is_boss": bool(template.get("is_boss", false)),
		"absorption": (template.get("absorption", {}) as Dictionary).duplicate(true)
	}

static func snapshot(creature: Dictionary) -> Dictionary:
	return creature.duplicate(true)

static func apply_stat_cap(creature: Dictionary) -> void:
	var caps: Dictionary = DataRegistry.stat_caps
	var stats: Dictionary = creature.get("stats", {})
	for k in stats.keys():
		if caps.has(k):
			stats[k] = mini(int(stats[k]), int(caps[k]))
	creature["stats"] = stats
	# Keep max_hp in sync with hp stat, preserving current ratio when possible.
	var old_max := int(creature.get("max_hp", stats.get("hp", 1)))
	var new_max := int(stats.get("hp", old_max))
	var old_hp := int(creature.get("hp", new_max))
	creature["max_hp"] = new_max
	if old_max > 0:
		creature["hp"] = mini(new_max, int(round(float(old_hp) / float(old_max) * float(new_max))))
	else:
		creature["hp"] = new_max

static func _scale_stats(stats: Dictionary, mult: float) -> void:
	for k in stats.keys():
		if k == "accuracy" or k == "critical_chance":
			continue
		stats[k] = int(round(float(stats[k]) * mult))

static func _shift_color(hex: String) -> String:
	# Simple gold-tint marker for alphas.
	return "#ffd60a" if hex != "#ffd60a" else "#f4a261"

static func _make_id() -> String:
	return "%d_%d" % [Time.get_unix_time_from_system(), randi() % 100000]
