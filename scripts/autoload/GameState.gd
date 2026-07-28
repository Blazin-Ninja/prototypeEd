extends Node
## Runtime orchestrator for account + active run.

const CreatureFactory = preload("res://scripts/domain/CreatureFactory.gd")
const ProgressionSystem = preload("res://scripts/domain/ProgressionSystem.gd")

var account: Dictionary = {}
var run: Dictionary = {}
var pending_battle: Dictionary = {}
var pending_absorb: Dictionary = {}
var last_absorb_results: Array = []
var last_run_report: Dictionary = {}

func _ready() -> void:
	account = SaveService.load_account()

func refresh_account() -> void:
	account = SaveService.load_account()

func available_starters() -> Array:
	return ProgressionSystem.available_starters(account)

func has_continue() -> bool:
	return SaveService.has_run()

func continue_run() -> bool:
	if not SaveService.has_run():
		return false
	run = SaveService.load_run()
	return not run.is_empty()

func start_new_run(starter_id: String) -> void:
	var companion := CreatureFactory.create_from_template(starter_id, {"is_player": true})
	ProgressionSystem.apply_starting_passives(companion, account)
	var forest := DataRegistry.get_region("forest")
	var start: Dictionary = forest.get("start_cell", {"x": 8, "y": 42})
	run = {
		"version": 1,
		"starter_id": starter_id,
		"companion": companion,
		"region_id": "forest",
		"unlocked_regions": ["forest"],
		"player_pos": {
			"x": float(start.get("x", 8)) + 0.5,
			"y": float(start.get("y", 42)) + 0.5
		},
		"regions_cleared": [],
		"battles_won": 0,
		"absorptions": 0,
		"bosses_defeated": [],
		"seed": randi(),
		"alive": true,
		"steps": 0,
		"cleared_obelisks": [],
		"wild_rosters": {}
	}
	account["runs_played"] = int(account.get("runs_played", 0)) + 1
	SaveService.save_account(account)
	autosave()

func autosave() -> void:
	if run.is_empty() or not run.get("alive", false):
		return
	SaveService.save_run(run)

func get_companion() -> Dictionary:
	return run.get("companion", {})

func set_companion(companion: Dictionary) -> void:
	run["companion"] = companion

func current_region() -> Dictionary:
	return DataRegistry.get_region(str(run.get("region_id", "forest")))

func heal_companion_full() -> void:
	var c: Dictionary = get_companion()
	c["hp"] = int(c.get("max_hp", c.get("stats", {}).get("hp", 1)))
	c["statuses"] = []
	set_companion(c)
	autosave()

func move_player(to: Vector2) -> void:
	run["player_pos"] = {"x": to.x, "y": to.y}
	run["steps"] = int(run.get("steps", 0)) + 1
	autosave()

func change_region(region_id: String) -> void:
	if not run.get("unlocked_regions", []).has(region_id):
		return
	run["region_id"] = region_id
	var region := DataRegistry.get_region(region_id)
	var start: Dictionary = region.get("start_cell", {"x": 1, "y": 14})
	run["player_pos"] = {
		"x": float(start.get("x", 1)) + 0.5,
		"y": float(start.get("y", 14)) + 0.5
	}
	EventBus.region_changed.emit(region_id)
	autosave()

func unlock_region(region_id: String) -> void:
	var unlocked: Array = run.get("unlocked_regions", [])
	if not unlocked.has(region_id):
		unlocked.append(region_id)
		run["unlocked_regions"] = unlocked
	autosave()

func begin_battle(enemy: Dictionary, is_boss: bool = false, wild_roster_id: String = "", obelisk_cell: Vector2i = Vector2i(-1, -1)) -> void:
	pending_battle = {
		"enemy": enemy,
		"is_boss": is_boss,
		"can_flee": not is_boss and not enemy.get("is_legendary", false) and not enemy.get("is_obelisk_guardian", false),
		"wild_roster_id": wild_roster_id,
		"region_id": str(run.get("region_id", "")),
		"obelisk_x": obelisk_cell.x,
		"obelisk_y": obelisk_cell.y
	}
	EventBus.battle_started.emit(enemy)

func end_battle_victory(enemy: Dictionary) -> void:
	run["battles_won"] = int(run.get("battles_won", 0)) + 1
	# Remove defeated wild from the region's persistent roster.
	if not bool(pending_battle.get("is_boss", false)):
		var wid := str(pending_battle.get("wild_roster_id", enemy.get("instance_id", "")))
		var rid := str(pending_battle.get("region_id", run.get("region_id", "")))
		if wid != "":
			mark_wild_defeated(rid, wid)
		var ox := int(pending_battle.get("obelisk_x", -1))
		var oy := int(pending_battle.get("obelisk_y", -1))
		if ox >= 0 and oy >= 0:
			mark_obelisk_cleared(rid, Vector2i(ox, oy))
	pending_absorb = {"enemy": enemy}
	autosave()
	EventBus.battle_ended.emit("win")

func skip_absorb() -> void:
	pending_absorb = {}
	autosave()

func mark_boss_defeated(boss_id: String) -> void:
	var list: Array = run.get("bosses_defeated", [])
	if not list.has(boss_id):
		list.append(boss_id)
	run["bosses_defeated"] = list
	var region := current_region()
	var cleared: Array = run.get("regions_cleared", [])
	var region_id := str(region.get("id", ""))
	if not cleared.has(region_id):
		cleared.append(region_id)
		run["regions_cleared"] = cleared
	var next_id = region.get("next_region", null)
	if next_id != null:
		unlock_region(str(next_id))
		run["pending_travel_prompt"] = str(next_id)
	autosave()

func end_run(won: bool) -> Dictionary:
	var tokens := ProgressionSystem.grant_tokens(account, run, won)
	SaveService.save_account(account)
	last_run_report = {
		"won": won,
		"tokens": tokens,
		"battles_won": run.get("battles_won", 0),
		"absorptions": run.get("absorptions", 0),
		"regions_cleared": run.get("regions_cleared", []),
		"companion_name": get_companion().get("name", "?")
	}
	account["last_run_summary"] = last_run_report
	if won:
		account["runs_won"] = int(account.get("runs_won", 0)) + 1
	var best := 0
	for rid in run.get("regions_cleared", []):
		best = maxi(best, int(DataRegistry.get_region(str(rid)).get("index", 0)))
	account["best_region"] = maxi(int(account.get("best_region", 0)), best)
	SaveService.save_account(account)
	SaveService.clear_run()
	run = {}
	EventBus.run_ended.emit(won, tokens)
	return last_run_report

func obelisk_key(region_id: String, cell: Vector2i) -> String:
	return "%s:%d,%d" % [region_id, cell.x, cell.y]

func is_obelisk_cleared(region_id: String, cell: Vector2i) -> bool:
	return run.get("cleared_obelisks", []).has(obelisk_key(region_id, cell))

func mark_obelisk_cleared(region_id: String, cell: Vector2i) -> void:
	var cleared: Array = run.get("cleared_obelisks", [])
	var key := obelisk_key(region_id, cell)
	if not cleared.has(key):
		cleared.append(key)
		run["cleared_obelisks"] = cleared
		autosave()

func get_wild_roster(region_id: String) -> Array:
	var rosters: Dictionary = run.get("wild_rosters", {})
	var list = rosters.get(region_id, null)
	if list == null:
		return []
	return list

func set_wild_roster(region_id: String, roster: Array) -> void:
	var rosters: Dictionary = run.get("wild_rosters", {})
	rosters[region_id] = roster
	run["wild_rosters"] = rosters
	autosave()

func mark_wild_defeated(region_id: String, instance_id: String) -> void:
	if instance_id == "":
		return
	var roster: Array = get_wild_roster(region_id)
	var changed := false
	for entry in roster:
		if str(entry.get("instance_id", "")) == instance_id:
			entry["alive"] = false
			changed = true
			break
	if changed:
		set_wild_roster(region_id, roster)

func buy_unlock(unlock_id: String) -> Dictionary:
	return ProgressionSystem.purchase(account, unlock_id)
