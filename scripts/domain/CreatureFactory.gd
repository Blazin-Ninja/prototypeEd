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
	var visual_loadout: Dictionary = {}
	for mid in mutations:
		var m: Dictionary = DataRegistry.get_mutation(str(mid))
		var slot := str(m.get("slot", ""))
		if slot != "":
			visual_loadout[slot] = str(mid)
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
		"visual_loadout": visual_loadout,
		"passives": [],
		"statuses": [],
		"color": color,
		"shape": str(template.get("shape", "quad")),
		"is_player": bool(opts.get("is_player", false)),
		"is_alpha": is_alpha,
		"is_legendary": is_legendary,
		"is_boss": bool(template.get("is_boss", false)),
		"level": 1,
		"xp": 0,
		"absorption": (template.get("absorption", {}) as Dictionary).duplicate(true)
	}

static func snapshot(creature: Dictionary) -> Dictionary:
	return creature.duplicate(true)

static func snapshot_for_retry(creature: Dictionary) -> Dictionary:
	## Compact bond identity for a death retry (species DNA only — never level/stats).
	if creature.is_empty():
		return {}
	return {
		"template_id": str(creature.get("template_id", creature.get("id", ""))),
		"name": str(creature.get("name", "")),
		"abilities": (creature.get("abilities", []) as Array).duplicate(),
		"elements": (creature.get("elements", []) as Array).duplicate(),
		"families": (creature.get("families", []) as Array).duplicate(),
		"mutations": (creature.get("mutations", []) as Array).duplicate(),
		"visual_loadout": (creature.get("visual_loadout", {}) as Dictionary).duplicate(true)
	}

static func create_retry_companion(snapshot: Dictionary) -> Dictionary:
	## Fresh Lv 1 companion from a defeated bond: keep DNA, discard run power.
	if snapshot.is_empty():
		return {}
	# Tolerate a full creature dict being passed by mistake — only read DNA fields.
	var tid := str(snapshot.get("template_id", snapshot.get("id", "")))
	if tid == "" or DataRegistry.get_creature(tid).is_empty():
		return {}
	var fresh := create_from_template(tid, {"is_player": true})
	if fresh.is_empty():
		return {}
	# Always start from the template's printed name / base power.
	var template_name := str(DataRegistry.get_creature(tid).get("name", tid))
	fresh["name"] = template_name
	# Bonded kit — clamp to game limits.
	var abilities: Array = []
	for ab in snapshot.get("abilities", []):
		var aid := str(ab)
		if aid != "" and DataRegistry.abilities.has(aid) and not abilities.has(aid):
			abilities.append(aid)
	if abilities.is_empty():
		abilities = (fresh.get("abilities", []) as Array).duplicate()
	while abilities.size() > DataRegistry.max_abilities:
		abilities.pop_back()
	fresh["abilities"] = abilities
	var elements: Array = []
	for el in snapshot.get("elements", []):
		var eid := str(el)
		if eid != "" and DataRegistry.elements.has(eid) and not elements.has(eid):
			elements.append(eid)
	if elements.is_empty():
		elements = (fresh.get("elements", []) as Array).duplicate()
	while elements.size() > DataRegistry.max_elements:
		elements.pop_back()
	fresh["elements"] = elements
	var families: Array = []
	for fam in snapshot.get("families", []):
		var fid := str(fam)
		if fid != "" and not families.has(fid):
			families.append(fid)
	if not families.is_empty():
		fresh["families"] = families
	# Re-apply mutations on the Lv1 base (visuals + passive DNA bonuses only).
	fresh["mutations"] = []
	fresh["visual_loadout"] = {}
	fresh["passives"] = []
	for mid in snapshot.get("mutations", []):
		MutationSystem.apply_mutation(fresh, str(mid))
	# Hard power reset — never inherit leveled stats/xp from the lost run.
	fresh["level"] = 1
	fresh["xp"] = 0
	fresh["statuses"] = []
	fresh["is_alpha"] = false
	fresh["is_legendary"] = false
	fresh["is_boss"] = false
	fresh["is_player"] = true
	fresh.erase("unscaled_stats")
	# Rebuild HP from current (base + mutation) hp stat.
	var stats: Dictionary = fresh.get("stats", {})
	var max_hp := int(stats.get("hp", fresh.get("max_hp", 1)))
	fresh["max_hp"] = max_hp
	fresh["hp"] = max_hp
	apply_stat_cap(fresh)
	fresh["hp"] = int(fresh.get("max_hp", 1))
	fresh["level"] = 1
	fresh["xp"] = 0
	return fresh

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
