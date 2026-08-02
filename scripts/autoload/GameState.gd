extends Node
## Runtime orchestrator for account + active run.

const CreatureFactory = preload("res://scripts/domain/CreatureFactory.gd")
const ProgressionSystem = preload("res://scripts/domain/ProgressionSystem.gd")
const LevelSystem = preload("res://scripts/domain/LevelSystem.gd")
const EncounterSystem = preload("res://scripts/domain/EncounterSystem.gd")
const DifficultySystem = preload("res://scripts/domain/DifficultySystem.gd")
const RunTimer = preload("res://scripts/util/RunTimer.gd")
const CombatSystem = preload("res://scripts/domain/CombatSystem.gd")
const BOND_SHARD_CAP := 5
const BOND_SHARD_REVIVE_COST := 3
const BOND_SHARD_REVIVE_MAX := 3

var account: Dictionary = {}
var run: Dictionary = {}
var pending_battle: Dictionary = {}
var pending_absorb: Dictionary = {}
var last_absorb_results: Array = []
var last_run_report: Dictionary = {}
var pending_retry_companion: Dictionary = {} ## Bond DNA snapshot after a loss, for retry.
var pending_retry_difficulty: String = "normal"

func _ready() -> void:
	account = SaveService.load_account()
	_restore_pending_retry_from_account()

func refresh_account() -> void:
	account = SaveService.load_account()
	_restore_pending_retry_from_account()

func available_starters() -> Array:
	return ProgressionSystem.available_starters(account)

func has_continue() -> bool:
	if not SaveService.has_run():
		return false
	var data := SaveService.load_run()
	if data.is_empty():
		return false
	# Dead / cleared runs must never Continuable with old leveled companions.
	if not bool(data.get("alive", false)):
		SaveService.clear_run()
		return false
	return true

func continue_run() -> bool:
	if not SaveService.has_run():
		return false
	run = SaveService.load_run()
	if run.is_empty() or not bool(run.get("alive", false)):
		SaveService.clear_run()
		run = {}
		return false
	# Migrate pre–Bond Shard saves.
	if not run.has("bond_shards"):
		run["bond_shards"] = 1
		autosave()
	else:
		run["bond_shards"] = clampi(int(run.get("bond_shards", 1)), 0, BOND_SHARD_CAP)
	# Migrate pre–obelisk stage saves.
	if not run.has("obelisk_progress"):
		run["obelisk_progress"] = {}
		autosave()
	if not run.has("region_floor"):
		run["region_floor"] = 1
		autosave()
	if not run.has("difficulty"):
		run["difficulty"] = DifficultySystem.ID_NORMAL
		autosave()
	else:
		run["difficulty"] = DifficultySystem.normalize(str(run.get("difficulty", DifficultySystem.ID_NORMAL)))
	if not run.has("explored_maps"):
		run["explored_maps"] = {}
		autosave()
	if not run.has("started_at_ms") or int(run.get("started_at_ms", 0)) <= 0:
		run["started_at_ms"] = RunTimer.now_ms()
		autosave()
	if not run.has("shard_revives_used"):
		run["shard_revives_used"] = 0
		autosave()
	else:
		run["shard_revives_used"] = clampi(int(run.get("shard_revives_used", 0)), 0, BOND_SHARD_REVIVE_MAX)
	# Ensure companion power fields are sane if an old save somehow carried junk.
	var companion: Dictionary = run.get("companion", {})
	if not companion.is_empty():
		LevelSystem.ensure_fields(companion)
		run["companion"] = companion
	if not account.has("preferred_difficulty"):
		account["preferred_difficulty"] = DifficultySystem.ID_NORMAL
		SaveService.save_account(account)
	return true

func start_new_run(starter_id: String, difficulty: String = "normal") -> void:
	clear_pending_retry_companion()
	var diff := DifficultySystem.normalize(difficulty)
	set_preferred_difficulty(diff)
	var companion := CreatureFactory.create_from_template(starter_id, {"is_player": true})
	ProgressionSystem.apply_starting_passives(companion, account)
	_begin_run_with_companion(starter_id, companion, diff)

func start_new_run_from_pending_companion() -> bool:
	## Death retry: same companion DNA, fresh run at Lv 1 with base (non-leveled) stats.
	_restore_pending_retry_from_account()
	if pending_retry_companion.is_empty():
		return false
	var snap: Dictionary = pending_retry_companion.duplicate(true)
	var diff := DifficultySystem.normalize(pending_retry_difficulty)
	clear_pending_retry_companion()
	# Never resume a dead leveled run.
	SaveService.clear_run()
	run = {}
	var companion := CreatureFactory.create_retry_companion(snap)
	if companion.is_empty():
		return false
	ProgressionSystem.apply_starting_passives(companion, account)
	# Passives must not reintroduce level/xp from a bad snapshot.
	companion["level"] = 1
	companion["xp"] = 0
	companion.erase("unscaled_stats")
	companion["hp"] = int(companion.get("max_hp", companion.get("stats", {}).get("hp", 1)))
	var starter_id := str(companion.get("template_id", snap.get("template_id", "ember_pup")))
	_begin_run_with_companion(starter_id, companion, diff)
	return true

func clear_pending_retry_companion() -> void:
	pending_retry_companion = {}
	pending_retry_difficulty = DifficultySystem.ID_NORMAL
	if account.has("pending_retry_companion"):
		account.erase("pending_retry_companion")
	if account.has("pending_retry_difficulty"):
		account.erase("pending_retry_difficulty")
	SaveService.save_account(account)

func has_pending_retry_companion() -> bool:
	if pending_retry_companion.is_empty():
		_restore_pending_retry_from_account()
	return not pending_retry_companion.is_empty()

func _restore_pending_retry_from_account() -> void:
	if not pending_retry_companion.is_empty():
		return
	var snap = account.get("pending_retry_companion", {})
	if typeof(snap) == TYPE_DICTIONARY and not snap.is_empty():
		pending_retry_companion = (snap as Dictionary).duplicate(true)
		pending_retry_difficulty = DifficultySystem.normalize(
			str(account.get("pending_retry_difficulty", DifficultySystem.ID_NORMAL))
		)

func _persist_pending_retry_to_account() -> void:
	if pending_retry_companion.is_empty():
		account.erase("pending_retry_companion")
		account.erase("pending_retry_difficulty")
	else:
		account["pending_retry_companion"] = pending_retry_companion.duplicate(true)
		account["pending_retry_difficulty"] = DifficultySystem.normalize(pending_retry_difficulty)
	SaveService.save_account(account)

func get_difficulty() -> String:
	if run.is_empty():
		return get_preferred_difficulty()
	return DifficultySystem.normalize(str(run.get("difficulty", DifficultySystem.ID_NORMAL)))

func get_preferred_difficulty() -> String:
	return DifficultySystem.normalize(str(account.get("preferred_difficulty", DifficultySystem.ID_NORMAL)))

func set_preferred_difficulty(difficulty: String) -> void:
	account["preferred_difficulty"] = DifficultySystem.normalize(difficulty)
	SaveService.save_account(account)

func _begin_run_with_companion(starter_id: String, companion: Dictionary, difficulty: String = "normal") -> void:
	var forest := DataRegistry.get_region("forest")
	var start: Dictionary = forest.get("start_cell", {"x": 8, "y": 42})
	var diff := DifficultySystem.normalize(difficulty)
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
		"obelisk_progress": {},
		"wild_rosters": {},
		"bond_shards": DifficultySystem.starting_bond_shards(diff),
		"region_floor": 1,
		"difficulty": diff,
		"explored_maps": {},
		"started_at_ms": RunTimer.now_ms(),
		"shard_revives_used": 0
	}
	account["runs_played"] = int(account.get("runs_played", 0)) + 1
	RunTimer.ensure_board(account)
	SaveService.save_account(account)
	autosave()

func autosave() -> void:
	if run.is_empty() or not run.get("alive", false):
		return
	SaveService.save_run(run)

func get_companion() -> Dictionary:
	var companion: Dictionary = run.get("companion", {})
	if not companion.is_empty():
		LevelSystem.ensure_fields(companion)
	return companion

func set_companion(companion: Dictionary) -> void:
	if not companion.is_empty():
		LevelSystem.ensure_fields(companion)
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
	run["region_floor"] = 1
	var region := DataRegistry.get_region(region_id)
	var start: Dictionary = region.get("start_cell", {"x": 1, "y": 14})
	run["player_pos"] = {
		"x": float(start.get("x", 1)) + 0.5,
		"y": float(start.get("y", 14)) + 0.5
	}
	EventBus.region_changed.emit(region_id)
	autosave()

func current_floor() -> int:
	return clampi(int(run.get("region_floor", 1)), 1, EncounterSystem.floors_per_region())

func floors_per_region() -> int:
	return EncounterSystem.floors_per_region()

func advance_floor() -> bool:
	## Descend one dungeon floor. Returns false if already on the boss floor.
	var floor := current_floor()
	if floor >= floors_per_region():
		return false
	run["region_floor"] = floor + 1
	var region := current_region()
	var start: Dictionary = region.get("start_cell", {"x": 1, "y": 14})
	run["player_pos"] = {
		"x": float(start.get("x", 1)) + 0.5,
		"y": float(start.get("y", 14)) + 0.5
	}
	autosave()
	return true

func retreat_floor() -> bool:
	## Climb one dungeon floor toward the surface.
	var floor := current_floor()
	if floor <= 1:
		return false
	run["region_floor"] = floor - 1
	var region := current_region()
	var start: Dictionary = region.get("start_cell", {"x": 1, "y": 14})
	run["player_pos"] = {
		"x": float(start.get("x", 1)) + 0.5,
		"y": float(start.get("y", 14)) + 0.5
	}
	autosave()
	return true

func wild_roster_key(region_id: String = "", floor: int = -1) -> String:
	var rid := region_id if region_id != "" else str(run.get("region_id", "forest"))
	var fl := floor if floor > 0 else current_floor()
	return "%s#%d" % [rid, fl]

func explored_map_key(region_id: String = "", floor: int = -1) -> String:
	return wild_roster_key(region_id, floor)

func get_explored_cells(region_id: String = "", floor: int = -1) -> Dictionary:
	## Returns { "x,y": true, ... } for the current (or given) region floor.
	if run.is_empty():
		return {}
	var maps: Dictionary = run.get("explored_maps", {})
	var key := explored_map_key(region_id, floor)
	var cells = maps.get(key, null)
	if cells == null or not (cells is Dictionary):
		return {}
	return cells

func is_cell_explored(cell: Vector2i, region_id: String = "", floor: int = -1) -> bool:
	var cells := get_explored_cells(region_id, floor)
	return cells.has("%d,%d" % [cell.x, cell.y])

func reveal_exploration_around(center: Vector2, radius: int = 3, region_id: String = "", floor: int = -1) -> bool:
	## Reveal Chebyshev neighborhood around the player. Returns true if anything new was revealed.
	if run.is_empty():
		return false
	var maps: Dictionary = run.get("explored_maps", {})
	var key := explored_map_key(region_id, floor)
	var cells: Dictionary = {}
	if maps.has(key) and maps[key] is Dictionary:
		cells = maps[key]
	var cx := int(floor(center.x))
	var cy := int(floor(center.y))
	var r := maxi(0, radius)
	var changed := false
	for y in range(cy - r, cy + r + 1):
		for x in range(cx - r, cx + r + 1):
			if maxi(absi(x - cx), absi(y - cy)) > r:
				continue
			var ck := "%d,%d" % [x, y]
			if cells.has(ck):
				continue
			cells[ck] = true
			changed = true
	if changed:
		maps[key] = cells
		run["explored_maps"] = maps
	return changed

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
		"region_floor": current_floor(),
		"obelisk_x": obelisk_cell.x,
		"obelisk_y": obelisk_cell.y
	}
	EventBus.battle_started.emit(enemy)

func end_battle_victory(enemy: Dictionary) -> void:
	run["battles_won"] = int(run.get("battles_won", 0)) + 1
	# Remove defeated wild from the region's persistent roster (schedule respawn).
	if not bool(pending_battle.get("is_boss", false)):
		var wid := str(pending_battle.get("wild_roster_id", ""))
		var rid := str(pending_battle.get("region_id", run.get("region_id", "")))
		var fl := int(pending_battle.get("region_floor", current_floor()))
		if wid != "":
			mark_wild_defeated(rid, wid, fl)
		var ox := int(pending_battle.get("obelisk_x", -1))
		var oy := int(pending_battle.get("obelisk_y", -1))
		if ox >= 0 and oy >= 0:
			var adv := advance_obelisk(rid, Vector2i(ox, oy), fl)
			if bool(adv.get("bonus", false)):
				enemy["obelisk_final_clear"] = true
				_grant_obelisk_clear_bonus()
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
	var companion: Dictionary = get_companion()
	var tokens := ProgressionSystem.grant_tokens(account, run, won)
	var started_at := int(run.get("started_at_ms", 0))
	var elapsed := RunTimer.elapsed_ms(started_at)
	# Mark dead before wipe so a failed clear_run cannot Continue a leveled corpse.
	if not run.is_empty():
		run["alive"] = false
		SaveService.save_run(run)
	# On loss, keep bond DNA so the player can retry with the same companion at Lv 1.
	if won:
		clear_pending_retry_companion()
	else:
		pending_retry_companion = CreatureFactory.snapshot_for_retry(companion)
		pending_retry_difficulty = get_difficulty()
		_persist_pending_retry_to_account()
	var diff := get_difficulty() if not run.is_empty() else pending_retry_difficulty
	last_run_report = {
		"won": won,
		"tokens": tokens,
		"battles_won": run.get("battles_won", 0),
		"absorptions": run.get("absorptions", 0),
		"regions_cleared": run.get("regions_cleared", []),
		"companion_name": companion.get("name", "?"),
		"companion_template_id": str(companion.get("template_id", "")),
		"can_retry": not won and not pending_retry_companion.is_empty(),
		"difficulty": diff,
		"elapsed_ms": elapsed,
		"run_time": RunTimer.format_run_time(elapsed)
	}
	account["last_run_summary"] = {
		"won": won,
		"tokens": tokens,
		"battles_won": last_run_report.get("battles_won", 0),
		"absorptions": last_run_report.get("absorptions", 0),
		"regions_cleared": last_run_report.get("regions_cleared", []),
		"companion_name": last_run_report.get("companion_name", "?"),
		"can_retry": bool(last_run_report.get("can_retry", false)),
		"difficulty": last_run_report.get("difficulty", DifficultySystem.ID_NORMAL),
		"elapsed_ms": elapsed,
		"run_time": RunTimer.format_run_time(elapsed)
	}
	if won:
		account["runs_won"] = int(account.get("runs_won", 0)) + 1
		RunTimer.record_victory(
			account,
			diff,
			elapsed,
			str(companion.get("name", "?"))
		)
	var best := 0
	for rid in run.get("regions_cleared", []):
		best = maxi(best, int(DataRegistry.get_region(str(rid)).get("index", 0)))
	account["best_region"] = maxi(int(account.get("best_region", 0)), best)
	RunTimer.ensure_board(account)
	SaveService.save_account(account)
	SaveService.clear_run()
	run = {}
	EventBus.run_ended.emit(won, tokens)
	return last_run_report

func get_fastest_runs(difficulty: String = "") -> Array:
	var diff := difficulty if difficulty != "" else get_preferred_difficulty()
	return RunTimer.get_fastest(account, diff)

func obelisk_key(region_id: String, cell: Vector2i, floor: int = -1) -> String:
	var fl := floor if floor > 0 else current_floor()
	return "%s#%d:%d,%d" % [region_id, fl, cell.x, cell.y]

func is_obelisk_cleared(region_id: String, cell: Vector2i, floor: int = -1) -> bool:
	## Legacy cleared_obelisks entries stay path forever (no surprise stage-2 on old saves).
	var key := obelisk_key(region_id, cell, floor)
	var cleared: Array = run.get("cleared_obelisks", [])
	if cleared.has(key):
		return true
	# Legacy pre-floor keys ("forest:3,4") only apply on floor 1.
	var fl := floor if floor > 0 else current_floor()
	if fl == 1 and cleared.has("%s:%d,%d" % [region_id, cell.x, cell.y]):
		return true
	return false

func mark_obelisk_cleared(region_id: String, cell: Vector2i, floor: int = -1) -> void:
	var cleared: Array = run.get("cleared_obelisks", [])
	var key := obelisk_key(region_id, cell, floor)
	if not cleared.has(key):
		cleared.append(key)
		run["cleared_obelisks"] = cleared
	var progress: Dictionary = run.get("obelisk_progress", {})
	if progress.has(key):
		progress.erase(key)
		run["obelisk_progress"] = progress
	autosave()

func get_obelisk_state(region_id: String, cell: Vector2i, floor: int = -1) -> Dictionary:
	if is_obelisk_cleared(region_id, cell, floor):
		return {}
	var progress: Dictionary = run.get("obelisk_progress", {})
	var key := obelisk_key(region_id, cell, floor)
	var state = progress.get(key, null)
	if state == null or not (state is Dictionary):
		return {}
	return state

func ensure_obelisk_state(region_id: String, cell: Vector2i, template_id: String, floor: int = -1) -> Dictionary:
	## Persist stage/hue/template_id per cell. Starts at stage 1 (cyan).
	if is_obelisk_cleared(region_id, cell, floor):
		return {}
	var key := obelisk_key(region_id, cell, floor)
	var progress: Dictionary = run.get("obelisk_progress", {})
	if progress.has(key) and progress[key] is Dictionary:
		var existing: Dictionary = progress[key]
		if str(existing.get("template_id", "")) == "" and template_id != "":
			existing["template_id"] = template_id
			progress[key] = existing
			run["obelisk_progress"] = progress
			autosave()
		return existing
	var stage := 1
	var state := {
		"stage": stage,
		"hue": EncounterSystem.obelisk_stage_hue(stage),
		"template_id": template_id
	}
	progress[key] = state
	run["obelisk_progress"] = progress
	autosave()
	return state

func advance_obelisk(region_id: String, cell: Vector2i, floor: int = -1) -> Dictionary:
	## Win current stage → upgrade in place (2/3) or path + bonus (after stage 3).
	if is_obelisk_cleared(region_id, cell, floor):
		return {"cleared": true, "already": true, "bonus": false}
	var key := obelisk_key(region_id, cell, floor)
	var progress: Dictionary = run.get("obelisk_progress", {})
	var state: Dictionary = {}
	if progress.has(key) and progress[key] is Dictionary:
		state = progress[key]
	else:
		state = {"stage": 1, "hue": "cyan", "template_id": ""}
	var fought := clampi(int(state.get("stage", 1)), 1, 3)
	if fought >= 3:
		mark_obelisk_cleared(region_id, cell, floor)
		return {
			"cleared": true,
			"final": true,
			"bonus": true,
			"stage": 3,
			"hue": str(state.get("hue", "violet")),
			"template_id": str(state.get("template_id", ""))
		}
	var next_stage := fought + 1
	state["stage"] = next_stage
	state["hue"] = EncounterSystem.obelisk_stage_hue(next_stage)
	progress[key] = state
	run["obelisk_progress"] = progress
	autosave()
	return {
		"cleared": false,
		"final": false,
		"bonus": false,
		"stage": next_stage,
		"hue": str(state["hue"]),
		"template_id": str(state.get("template_id", ""))
	}

func _grant_obelisk_clear_bonus() -> void:
	## Stage-3 shatter bonus: guaranteed Bond Shard when under cap.
	var current := get_bond_shards()
	if current >= BOND_SHARD_CAP:
		run["pending_obelisk_bonus_log"] = "Obelisk shattered! The path opens."
		return
	set_bond_shards(current + 1)
	run["pending_obelisk_bonus_log"] = "Obelisk shattered! Bonus Bond Shard (%d/%d)." % [
		get_bond_shards(), BOND_SHARD_CAP
	]

func bosses_defeated_count() -> int:
	return int(run.get("bosses_defeated", []).size())

func wild_pressure_for_region(region_id: String, floor: int = -1) -> float:
	var fl := floor if floor > 0 else current_floor()
	return EncounterSystem.compute_wild_pressure(
		DataRegistry.get_region(region_id),
		bosses_defeated_count(),
		fl,
		get_difficulty()
	)

func get_wild_roster(region_id: String, floor: int = -1) -> Array:
	var rosters: Dictionary = run.get("wild_rosters", {})
	var key := wild_roster_key(region_id, floor)
	var list = rosters.get(key, null)
	if list == null:
		# Migrate legacy region-only keys onto floor 1.
		var fl := floor if floor > 0 else current_floor()
		if fl == 1 and rosters.has(region_id):
			list = rosters[region_id]
			rosters[key] = list
			rosters.erase(region_id)
			run["wild_rosters"] = rosters
			autosave()
			return list
		return []
	return list

func set_wild_roster(region_id: String, roster: Array, floor: int = -1) -> void:
	var rosters: Dictionary = run.get("wild_rosters", {})
	rosters[wild_roster_key(region_id, floor)] = roster
	run["wild_rosters"] = rosters
	autosave()

func mark_wild_defeated(region_id: String, instance_id: String, floor: int = -1) -> void:
	if instance_id == "":
		return
	var roster: Array = get_wild_roster(region_id, floor)
	var changed := false
	var delay := randf_range(45.0, 75.0)
	var at := Time.get_unix_time_from_system() + delay
	for entry in roster:
		if str(entry.get("instance_id", "")) == instance_id:
			entry["alive"] = false
			entry["respawn_at"] = at
			var creature: Dictionary = entry.get("creature", {})
			if not creature.is_empty():
				creature["hp"] = int(creature.get("max_hp", creature.get("hp", 1)))
				creature["statuses"] = []
				entry["creature"] = creature
			changed = true
			break
	if changed:
		set_wild_roster(region_id, roster, floor)

func migrate_wild_respawns(region_id: String, floor: int = -1) -> void:
	## Old saves marked wilds dead forever — give them a short respawn window.
	var roster: Array = get_wild_roster(region_id, floor)
	if roster.is_empty():
		return
	var now := Time.get_unix_time_from_system()
	var changed := false
	for entry in roster:
		if bool(entry.get("alive", true)):
			continue
		if entry.has("respawn_at"):
			continue
		entry["respawn_at"] = now + randf_range(20.0, 40.0)
		changed = true
	if changed:
		set_wild_roster(region_id, roster, floor)

func get_bond_shards() -> int:
	if run.is_empty():
		return 0
	return clampi(int(run.get("bond_shards", 1)), 0, BOND_SHARD_CAP)

func set_bond_shards(amount: int) -> void:
	if run.is_empty():
		return
	run["bond_shards"] = clampi(amount, 0, BOND_SHARD_CAP)
	autosave()

func can_use_bond_shard() -> bool:
	return get_bond_shards() > 0

func consume_bond_shard() -> bool:
	if get_bond_shards() <= 0:
		return false
	set_bond_shards(get_bond_shards() - 1)
	return true

func get_shard_revives_used() -> int:
	if run.is_empty():
		return 0
	return clampi(int(run.get("shard_revives_used", 0)), 0, BOND_SHARD_REVIVE_MAX)

func get_shard_revives_left() -> int:
	return maxi(0, BOND_SHARD_REVIVE_MAX - get_shard_revives_used())

func can_shard_revive() -> bool:
	if run.is_empty() or not bool(run.get("alive", false)):
		return false
	return get_bond_shards() >= BOND_SHARD_REVIVE_COST and get_shard_revives_left() > 0

func try_shard_revive(companion: Dictionary) -> Dictionary:
	## Spend 3 shards to fully revive. Max 3 uses per run.
	if not can_shard_revive():
		return {
			"ok": false,
			"shards": get_bond_shards(),
			"revives_left": get_shard_revives_left(),
			"log": "Cannot revive — need %d Bond Shards and remaining revive uses." % BOND_SHARD_REVIVE_COST
		}
	set_bond_shards(get_bond_shards() - BOND_SHARD_REVIVE_COST)
	run["shard_revives_used"] = get_shard_revives_used() + 1
	CombatSystem.apply_shard_revive(companion)
	autosave()
	var left := get_shard_revives_left()
	return {
		"ok": true,
		"shards": get_bond_shards(),
		"revives_left": left,
		"log": "Spent %d Bond Shards to revive! Full HP restored. (%d revive%s left this run)" % [
			BOND_SHARD_REVIVE_COST,
			left,
			"" if left == 1 else "s"
		]
	}

func try_grant_bond_shard_drop(enemy: Dictionary, is_boss_fight: bool) -> Dictionary:
	## Returns {granted: bool, shards: int, log: String}
	var current := get_bond_shards()
	if current >= BOND_SHARD_CAP:
		return {"granted": false, "shards": current, "log": ""}
	var chance := 0.12
	if is_boss_fight:
		chance = 0.30
	elif bool(enemy.get("is_obelisk_guardian", false)):
		# Stage 1/2/3: 20% / 30% / 40% — stage 3 is best of the chain.
		var stage := clampi(int(enemy.get("obelisk_stage", 1)), 1, 3)
		chance = 0.10 + 0.10 * float(stage)
	if randf() >= chance:
		return {"granted": false, "shards": current, "log": ""}
	set_bond_shards(current + 1)
	return {
		"granted": true,
		"shards": get_bond_shards(),
		"log": "Found a Bond Shard! (%d/%d)" % [get_bond_shards(), BOND_SHARD_CAP]
	}

func buy_unlock(unlock_id: String) -> Dictionary:
	return ProgressionSystem.purchase(account, unlock_id)
