extends RefCounted
class_name MutationSystem

static func apply_mutation(companion: Dictionary, mutation_id: String) -> void:
	var m: Dictionary = DataRegistry.get_mutation(mutation_id)
	if m.is_empty():
		return
	var list: Array = companion.get("mutations", [])
	if list.has(mutation_id):
		return
	list.append(mutation_id)
	companion["mutations"] = list

	# Visual loadout: latest mutation wins per slot (history still stacked forever above).
	var slot := str(m.get("slot", ""))
	if slot != "":
		var loadout: Dictionary = companion.get("visual_loadout", {})
		loadout[slot] = mutation_id
		companion["visual_loadout"] = loadout

	var passive = m.get("passive", null)
	if typeof(passive) == TYPE_DICTIONARY:
		var stat := str(passive.get("stat", ""))
		var bonus := int(passive.get("bonus", 0))
		if stat != "" and bonus != 0:
			var stats: Dictionary = companion.get("stats", {})
			stats[stat] = int(stats.get(stat, 0)) + bonus
			companion["stats"] = stats
			if stat == "hp":
				companion["max_hp"] = int(stats["hp"])
				companion["hp"] = mini(int(companion["max_hp"]), int(companion.get("hp", 0)) + bonus)
			CreatureFactory.apply_stat_cap(companion)
			var passives: Array = companion.get("passives", [])
			passives.append({"source": mutation_id, "stat": stat, "bonus": bonus})
			companion["passives"] = passives
	EventBus.companion_mutated.emit(mutation_id)

static func mutations_by_slot(companion: Dictionary) -> Dictionary:
	var by_slot: Dictionary = {}
	for mid in companion.get("mutations", []):
		var m: Dictionary = DataRegistry.get_mutation(str(mid))
		var slot := str(m.get("slot", "misc"))
		if not by_slot.has(slot):
			by_slot[slot] = []
		by_slot[slot].append(m)
	return by_slot
