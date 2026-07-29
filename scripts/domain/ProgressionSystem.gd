extends RefCounted
class_name ProgressionSystem

static func available_starters(account: Dictionary) -> Array:
	var owned: Array = account.get("owned_unlocks", [])
	var out: Array = []
	# Map unlock ids to starter creature ids; always include defaults from unlock list.
	for u in DataRegistry.progression.get("unlocks", []):
		if u.get("type") != "starter":
			continue
		var sid := str(u.get("payload", {}).get("starter_id", ""))
		if sid == "":
			continue
		if u.get("default_owned", false) or owned.has(u.get("id")):
			if not out.has(sid):
				out.append(sid)
	# Safety: at least ember + tide
	if out.is_empty():
		out = ["ember_pup", "tide_fin"]
	return out

static func alpha_bonus(account: Dictionary) -> float:
	var bonus := 0.0
	var owned: Array = account.get("owned_unlocks", [])
	for u in DataRegistry.progression.get("unlocks", []):
		if owned.has(u.get("id")) and u.get("type") == "alpha_rate":
			bonus += float(u.get("payload", {}).get("bonus", 0.0))
	return bonus

static func apply_starting_passives(companion: Dictionary, account: Dictionary) -> void:
	var owned: Array = account.get("owned_unlocks", [])
	for u in DataRegistry.progression.get("unlocks", []):
		if not owned.has(u.get("id")):
			continue
		if u.get("type") != "starting_passive":
			continue
		var payload: Dictionary = u.get("payload", {})
		var stat := str(payload.get("stat", ""))
		var bonus := int(payload.get("bonus", 0))
		if stat == "":
			continue
		var stats: Dictionary = companion.get("stats", {})
		stats[stat] = int(stats.get(stat, 0)) + bonus
		companion["stats"] = stats
		if stat == "hp":
			companion["max_hp"] = int(stats["hp"])
			companion["hp"] = int(stats["hp"])
	CreatureFactory.apply_stat_cap(companion)

static func grant_tokens(account: Dictionary, run: Dictionary, won: bool) -> int:
	var cfg: Dictionary = DataRegistry.progression.get("tokens", {})
	var tokens := int(cfg.get("on_lose", 1))
	if won:
		tokens = int(cfg.get("on_win", 5))
	tokens += int(cfg.get("per_region_cleared", 1)) * int(run.get("regions_cleared", []).size())
	account["evolution_tokens"] = int(account.get("evolution_tokens", 0)) + tokens
	return tokens

static func purchase(account: Dictionary, unlock_id: String) -> Dictionary:
	var unlock: Dictionary = {}
	for u in DataRegistry.progression.get("unlocks", []):
		if u.get("id") == unlock_id:
			unlock = u
			break
	if unlock.is_empty():
		return {"ok": false, "message": "Unknown unlock"}
	var owned: Array = account.get("owned_unlocks", [])
	if owned.has(unlock_id) or unlock.get("default_owned", false):
		return {"ok": false, "message": "Already owned"}
	var cost := int(unlock.get("cost", 0))
	var tokens := int(account.get("evolution_tokens", 0))
	if tokens < cost:
		return {"ok": false, "message": "Not enough tokens"}
	account["evolution_tokens"] = tokens - cost
	owned.append(unlock_id)
	account["owned_unlocks"] = owned
	SaveService.save_account(account)
	return {"ok": true, "message": "Unlocked %s" % unlock.get("name", unlock_id)}

static func shop_entries(account: Dictionary) -> Array:
	var owned: Array = account.get("owned_unlocks", [])
	var out: Array = []
	for u in DataRegistry.progression.get("unlocks", []):
		if typeof(u) != TYPE_DICTIONARY:
			continue
		var unlock: Dictionary = u
		if unlock.get("default_owned", false):
			continue
		var entry: Dictionary = unlock.duplicate(true)
		entry["owned"] = owned.has(unlock.get("id"))
		out.append(entry)
	return out
