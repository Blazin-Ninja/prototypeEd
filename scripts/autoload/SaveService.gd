extends Node
## Account + run persistence with frequent autosave.

const ACCOUNT_PATH := "user://account_save.json"
const RUN_PATH := "user://run_save.json"

func load_account() -> Dictionary:
	var data := _read(ACCOUNT_PATH)
	if data.is_empty():
		data = _default_account()
		save_account(data)
	var dirty := false
	if not data.has("preferred_difficulty"):
		data["preferred_difficulty"] = "normal"
		dirty = true
	if not data.has("fastest_runs") or typeof(data.get("fastest_runs")) != TYPE_DICTIONARY:
		data["fastest_runs"] = {
			"easy": [],
			"normal": [],
			"hard": []
		}
		dirty = true
	else:
		for id in ["easy", "normal", "hard"]:
			if not data["fastest_runs"].has(id):
				data["fastest_runs"][id] = []
				dirty = true
	if dirty:
		save_account(data)
	return data

func save_account(data: Dictionary) -> void:
	_write(ACCOUNT_PATH, data)

func has_run() -> bool:
	return FileAccess.file_exists(RUN_PATH)

func load_run() -> Dictionary:
	return _read(RUN_PATH)

func save_run(data: Dictionary) -> void:
	_write(RUN_PATH, data)

func clear_run() -> void:
	## Delete run save reliably (user:// needs globalize_path on some devices).
	if FileAccess.file_exists(RUN_PATH):
		var abs_path := ProjectSettings.globalize_path(RUN_PATH)
		DirAccess.remove_absolute(abs_path)
	if FileAccess.file_exists(RUN_PATH):
		# Last resort: overwrite with empty marker then remove again.
		var f := FileAccess.open(RUN_PATH, FileAccess.WRITE)
		if f != null:
			f.store_string("{}")
			f = null
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RUN_PATH))

func _default_account() -> Dictionary:
	var owned: Array = []
	for u in DataRegistry.progression.get("unlocks", []):
		if u.get("default_owned", false):
			owned.append(u["id"])
	# Always own first two starters unlocks
	if not owned.has("starter_ember_pup"):
		owned.append("starter_ember_pup")
	if not owned.has("starter_tide_fin"):
		owned.append("starter_tide_fin")
	return {
		"version": 1,
		"evolution_tokens": 0,
		"owned_unlocks": owned,
		"runs_played": 0,
		"runs_won": 0,
		"best_region": 0,
		"last_run_summary": {},
		"preferred_difficulty": "normal",
		"fastest_runs": {
			"easy": [],
			"normal": [],
			"hard": []
		}
	}

func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed

func _write(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("Cannot write save: %s" % path)
		return
	f.store_string(JSON.stringify(data, "\t"))
