extends RefCounted
class_name AbilitySystem

static func add_ability(companion: Dictionary, ability_id: String) -> void:
	var abs: Array = companion.get("abilities", [])
	if abs.has(ability_id):
		return
	if abs.size() >= DataRegistry.max_abilities:
		return
	abs.append(ability_id)
	companion["abilities"] = abs

static func replace_ability(companion: Dictionary, old_id: String, new_id: String) -> void:
	var abs: Array = companion.get("abilities", [])
	var idx := abs.find(old_id)
	if idx >= 0:
		abs[idx] = new_id
	companion["abilities"] = abs

static func upgrade_ability(companion: Dictionary, from_id: String, to_id: String) -> void:
	replace_ability(companion, from_id, to_id)

static func find_upgrade(companion: Dictionary, candidate_id: String, enemy: Dictionary) -> Dictionary:
	var cand: Dictionary = DataRegistry.get_ability(candidate_id)
	if cand.is_empty():
		return {}
	var chain := str(cand.get("chain", ""))
	var cand_tier := int(cand.get("tier", 1))
	# If companion already has same ability, try next in chain.
	for owned_id in companion.get("abilities", []):
		var owned: Dictionary = DataRegistry.get_ability(str(owned_id))
		if owned.is_empty():
			continue
		if str(owned.get("chain", "")) == chain:
			var next_id := _next_in_chain(chain, int(owned.get("tier", 1)))
			if next_id != "":
				return {"from": owned_id, "to": next_id}
			return {}
		# Similar DNA: shared family + same chain affinity via enemy families.
	# Also: if candidate is higher tier of an owned chain, upgrade toward it.
	for owned_id in companion.get("abilities", []):
		var owned2: Dictionary = DataRegistry.get_ability(str(owned_id))
		if str(owned2.get("chain", "")) == chain and cand_tier > int(owned2.get("tier", 1)):
			return {"from": owned_id, "to": candidate_id}
	# Repeated similar DNA: enemy shares family with an owned ability's families → nudge upgrade
	for owned_id in companion.get("abilities", []):
		var owned3: Dictionary = DataRegistry.get_ability(str(owned_id))
		var shared := false
		for f in owned3.get("families", []):
			if enemy.get("families", []).has(f):
				shared = true
				break
		if shared and str(owned3.get("chain", "")) != "" and str(owned3.get("chain", "")) == chain:
			var nxt := _next_in_chain(chain, int(owned3.get("tier", 1)))
			if nxt != "":
				return {"from": owned_id, "to": nxt}
	return {}

static func _next_in_chain(chain: String, current_tier: int) -> String:
	var best_id := ""
	var best_tier := 999
	for id in DataRegistry.abilities.keys():
		var a: Dictionary = DataRegistry.abilities[id]
		if str(a.get("chain", "")) != chain:
			continue
		var t := int(a.get("tier", 1))
		if t > current_tier and t < best_tier:
			best_tier = t
			best_id = str(id)
	return best_id
