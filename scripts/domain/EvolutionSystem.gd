extends RefCounted
class_name EvolutionSystem
## Species evolution for companions (and display helpers for wilds).

const CreatureFactory = preload("res://scripts/domain/CreatureFactory.gd")

static func can_evolve(creature: Dictionary) -> bool:
	if creature.is_empty():
		return false
	var template := DataRegistry.get_creature(str(creature.get("template_id", creature.get("id", ""))))
	var evo_id := str(template.get("evolves_to", ""))
	if evo_id == "":
		return false
	if DataRegistry.get_creature(evo_id).is_empty():
		return false
	var need := int(template.get("evolve_level", 99))
	return int(creature.get("level", 1)) >= need

static func try_evolve(creature: Dictionary) -> Dictionary:
	## Morph into evolves_to when level threshold is met. Preserves bond progress.
	if not can_evolve(creature):
		return {"evolved": false, "log": ""}
	var from_id := str(creature.get("template_id", creature.get("id", "")))
	var from_template := DataRegistry.get_creature(from_id)
	var to_id := str(from_template.get("evolves_to", ""))
	var to_template := DataRegistry.get_creature(to_id)
	var from_name := str(creature.get("name", from_template.get("name", from_id)))
	var level := int(creature.get("level", 1))
	var xp := int(creature.get("xp", 0))
	var mutations: Array = (creature.get("mutations", []) as Array).duplicate()
	var visual_loadout: Dictionary = (creature.get("visual_loadout", {}) as Dictionary).duplicate(true)
	var abilities: Array = (creature.get("abilities", []) as Array).duplicate()
	var elements: Array = (creature.get("elements", []) as Array).duplicate()
	var families: Array = (creature.get("families", []) as Array).duplicate()
	var passives: Array = (creature.get("passives", []) as Array).duplicate()
	var instance_id := str(creature.get("instance_id", ""))
	var is_player := bool(creature.get("is_player", false))

	var evolved := CreatureFactory.create_from_template(to_id, {
		"is_player": is_player,
		"is_alpha": false,
		"is_legendary": false
	})
	if evolved.is_empty():
		return {"evolved": false, "log": ""}
	# Replay level bonuses from 1 → current level on the new base form.
	evolved["level"] = 1
	evolved["xp"] = 0
	for _i in range(1, level):
		_apply_level_bonus(evolved)
		evolved["level"] = int(evolved["level"]) + 1
	evolved["level"] = level
	evolved["xp"] = xp
	evolved["instance_id"] = instance_id if instance_id != "" else evolved.get("instance_id", "")
	evolved["mutations"] = mutations
	evolved["visual_loadout"] = visual_loadout
	evolved["passives"] = passives
	evolved["is_player"] = is_player
	# Merge ability/element identity — keep what the bond already earned.
	for ab in abilities:
		var aid := str(ab)
		if aid != "" and not evolved["abilities"].has(aid):
			evolved["abilities"].append(aid)
	while evolved["abilities"].size() > DataRegistry.max_abilities:
		evolved["abilities"].pop_back()
	for el in elements:
		var eid := str(el)
		if eid != "" and not evolved["elements"].has(eid):
			evolved["elements"].append(eid)
	while evolved["elements"].size() > DataRegistry.max_elements:
		evolved["elements"].pop_back()
	for fam in families:
		var fid := str(fam)
		if fid != "" and not evolved["families"].has(fid):
			evolved["families"].append(fid)
	CreatureFactory.apply_stat_cap(evolved)
	evolved["hp"] = int(evolved.get("max_hp", evolved.get("hp", 1)))
	var to_name := str(evolved.get("name", to_template.get("name", to_id)))
	# Copy evolved fields back onto the live dictionary reference.
	creature.clear()
	for k in evolved.keys():
		creature[k] = evolved[k]
	return {
		"evolved": true,
		"from": from_id,
		"to": to_id,
		"log": "%s evolved into %s!" % [from_name, to_name]
	}

static func _apply_level_bonus(creature: Dictionary) -> void:
	var stats: Dictionary = creature.get("stats", {})
	var old_hp_stat := int(stats.get("hp", 10))
	var hp_gain := maxi(2, int(round(float(old_hp_stat) * 0.06)))
	stats["hp"] = old_hp_stat + hp_gain
	stats["attack"] = int(stats.get("attack", 5)) + 2
	stats["special_attack"] = int(stats.get("special_attack", 5)) + 2
	stats["defense"] = int(stats.get("defense", 5)) + 1
	stats["special_defense"] = int(stats.get("special_defense", 5)) + 1
	stats["speed"] = int(stats.get("speed", 5)) + 1
	creature["stats"] = stats
	var new_max := int(stats["hp"])
	var cur := int(creature.get("hp", new_max))
	creature["max_hp"] = new_max
	creature["hp"] = mini(new_max, cur + hp_gain)
