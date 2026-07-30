extends Control
## Continuous overworld with virtual joystick, visible wilds, and test heal.

const TILE := 72.8 ## 56 * 1.3 — larger overworld tiles / props
const GFX_SCALE := 1.3
const MOVE_SPEED := 4.2
const PLAYER_RADIUS := 0.28
const WILD_RADIUS := 0.35
const CONTACT_DIST := 0.85
const SAVE_INTERVAL := 1.25
const WILD_SPEED := 1.05
const DEFAULT_WILD_COUNT := 6
const TEST_MODE := true ## Infinite heal + easier testing aids.
const MINIMAP_REVEAL_RADIUS := 3
const FOG_PURPLE := Color(0.28, 0.08, 0.42, 0.92)
const FOG_PURPLE_EDGE := Color(0.42, 0.16, 0.58, 0.55)
const AppTheme = preload("res://scripts/ui/AppTheme.gd")
const TileArt = preload("res://scripts/util/TileArt.gd")
const DifficultySystem = preload("res://scripts/domain/DifficultySystem.gd")

@onready var map_draw: MapCanvas = $MapArea/MapDraw
@onready var minimap: MapCanvas = $HUD/Minimap
@onready var hud: Label = $HUD/Top/Strip/Info
@onready var hp_bar: ProgressBar = $HUD/Top/Strip/HPBar
@onready var message: Label = $HUD/Message
@onready var region_panel: PanelContainer = $RegionPanel
@onready var region_list: VBoxContainer = $RegionPanel/Margin/VBox/List
@onready var joystick: VirtualJoystick = $HUD/Joystick
@onready var heal_btn: Button = $HUD/Buttons/HealBtn

var _map: Dictionary = {}
var _pos: Vector2 = Vector2(1.5, 14.5)
var _stick: Vector2 = Vector2.ZERO
var _keyboard: Vector2 = Vector2.ZERO
var _intro_shown := false
var _busy := false
var _last_tile: Vector2i = Vector2i(-999, -999)
var _save_cooldown := 0.0
var _bob_t := 0.0
var _ambient_t := 0.0
var _wilds: Array = [] ## {creature, pos, vel, bob, roster_id}
var _boss_marker: Dictionary = {} ## visible boss on map if undefeated
var _obelisk_state: Dictionary = {} ## "x,y" -> {template_id, stage, hue}
var _facing: String = "down"
var _walk_phase: float = 0.0
var _moving := false
var _contact_grace := 0.0
var _explored: Dictionary = {} ## "x,y" -> true cache for current floor
var _minimap_dirty := true

func _ready() -> void:
	if GameState.run.is_empty():
		get_tree().change_scene_to_file("res://scenes/menu/MainMenu.tscn")
		return
	AppTheme.apply_to(self)
	AppTheme.style_muted(message, 15)
	PlayerAvatar.ensure_loaded()
	CreatureSprites.ensure_loaded()
	BossSprites.ensure_loaded()
	region_panel.visible = false
	heal_btn.visible = TEST_MODE
	heal_btn.pressed.connect(_test_heal)
	# Paint via MapCanvas._draw — never rely on external draw-signal painting.
	map_draw.paint = Callable(self, "_paint_world")
	minimap.paint = Callable(self, "_paint_minimap")
	_load_region()
	joystick.direction_changed.connect(_on_stick)
	$HUD/Buttons/ABtn.pressed.connect(_on_a)
	$HUD/Buttons/BBtn.pressed.connect(_on_b)
	$HUD/Buttons/MenuBtn.pressed.connect(_toggle_regions)
	$RegionPanel/Margin/VBox/CloseBtn.pressed.connect(_close_region_travel)
	_refresh_hud()
	_show_intro_once()
	call_deferred("_maybe_prompt_travel")
	call_deferred("_force_redraw")

func _force_redraw() -> void:
	if is_instance_valid(map_draw):
		map_draw.queue_redraw()
	if is_instance_valid(minimap):
		minimap.queue_redraw()

func _on_stick(dir: Vector2) -> void:
	_stick = dir

func _maybe_prompt_travel() -> void:
	var next_id = GameState.run.get("pending_travel_prompt", null)
	if next_id == null or str(next_id) == "":
		return
	GameState.run["pending_travel_prompt"] = null
	GameState.autosave()
	var next_region := DataRegistry.get_region(str(next_id))
	message.text = "Region cleared! %s is now open — travel when ready." % next_region.get("name", next_id)
	await get_tree().create_timer(0.7).timeout
	if is_inside_tree():
		_open_region_travel()

func _test_heal() -> void:
	GameState.heal_companion_full()
	_refresh_hud()
	message.text = "TEST HEAL — companion fully restored."
	GameState.autosave()

func _load_region() -> void:
	var region := GameState.current_region()
	var floor := GameState.current_floor()
	# Stable floor layout within a run so obelisks stay put after battles.
	var floor_seed := int(GameState.run.get("seed", 1)) ^ str(region.get("id", "")).hash() ^ (floor * 7919)
	seed(floor_seed)
	_map = MapGenerator.generate(region, floor)
	_apply_obelisk_state()
	_pos = _read_saved_pos()
	_pos.x = clampf(_pos.x, 1.2, float(_map.width) - 1.2)
	_pos.y = clampf(_pos.y, 1.2, float(_map.height) - 1.2)
	# If a prior save left us inside a hazard on a newly generated floor, snap to camp.
	if not _can_occupy_radius(_pos, PLAYER_RADIUS):
		var camp: Vector2i = _map.camp
		_pos = Vector2(float(camp.x) + 0.5, float(camp.y) + 0.5)
	_persist_pos(false)
	_last_tile = _tile_at(_pos)
	_spawn_wilds()
	_setup_boss_marker()
	_contact_grace = 1.25
	_reload_explored_cache()
	_reveal_at_player(true)
	map_draw.queue_redraw()
	_queue_minimap_redraw()

func _reload_explored_cache() -> void:
	_explored = GameState.get_explored_cells().duplicate(true)
	_minimap_dirty = true

func _reveal_at_player(force_save: bool = false) -> void:
	var changed := GameState.reveal_exploration_around(_pos, MINIMAP_REVEAL_RADIUS)
	if changed:
		_explored = GameState.get_explored_cells().duplicate(true)
		_minimap_dirty = true
		_queue_minimap_redraw()
		if force_save:
			GameState.autosave()
	elif force_save and _explored.is_empty():
		# Ensure first load still paints fog even with empty explore set.
		_queue_minimap_redraw()

func _queue_minimap_redraw() -> void:
	if is_instance_valid(minimap):
		minimap.queue_redraw()

func _apply_obelisk_state() -> void:
	_obelisk_state.clear()
	var region_id := str(GameState.run.get("region_id", ""))
	var obelisks: Array = _map.get("obelisks", [])
	for o in obelisks:
		var cell := Vector2i(int(o.get("x", 0)), int(o.get("y", 0)))
		if cell.y < 0 or cell.y >= int(_map.height) or cell.x < 0 or cell.x >= int(_map.width):
			continue
		# Legacy cleared_obelisks (and stage-3 completes) stay path — no surprise revive.
		if GameState.is_obelisk_cleared(region_id, cell):
			_map.tiles[cell.y][cell.x] = MapGenerator.TILE_PATH
			continue
		var template_id := str(o.get("template_id", ""))
		var state := GameState.ensure_obelisk_state(region_id, cell, template_id)
		if state.is_empty():
			_map.tiles[cell.y][cell.x] = MapGenerator.TILE_PATH
			continue
		_obelisk_state["%d,%d" % [cell.x, cell.y]] = {
			"template_id": str(state.get("template_id", template_id)),
			"stage": clampi(int(state.get("stage", 1)), 1, 3),
			"hue": str(state.get("hue", "cyan"))
		}
		_map.tiles[cell.y][cell.x] = MapGenerator.TILE_OBELISK

func _read_saved_pos() -> Vector2:
	var p: Dictionary = GameState.run.get("player_pos", {"x": 1.5, "y": 14.5})
	var x := float(p.get("x", 1.5))
	var y := float(p.get("y", 14.5))
	if absf(x - roundf(x)) < 0.001 and absf(y - roundf(y)) < 0.001:
		return Vector2(x + 0.5, y + 0.5)
	return Vector2(x, y)

func _persist_pos(count_step: bool) -> void:
	GameState.run["player_pos"] = {"x": _pos.x, "y": _pos.y}
	if count_step:
		GameState.run["steps"] = int(GameState.run.get("steps", 0)) + 1

func _habitat_cells() -> Array:
	## Grass clearings first; fall back to path tiles so wilds always spawn.
	var cells: Array = []
	var paths: Array = []
	var w: int = _map.width
	var h: int = _map.height
	for y in h:
		for x in w:
			var t: int = int(_map.tiles[y][x])
			if t == MapGenerator.TILE_GRASS:
				cells.append(Vector2i(x, y))
			elif t == MapGenerator.TILE_PATH:
				paths.append(Vector2i(x, y))
	if cells.size() >= 8:
		return cells
	cells.append_array(paths)
	return cells

func _grass_cells() -> Array:
	return _habitat_cells()

func _is_wild_tile(tile: int) -> bool:
	return tile == MapGenerator.TILE_GRASS or tile == MapGenerator.TILE_PATH or tile == MapGenerator.TILE_BRIDGE

func _spawn_wilds() -> void:
	_wilds.clear()
	var region := GameState.current_region()
	var region_id := str(region.get("id", ""))
	var floor := GameState.current_floor()
	if region.get("stub", false):
		return
	GameState.migrate_wild_respawns(region_id, floor)
	var roster: Array = GameState.get_wild_roster(region_id, floor)
	if roster.is_empty():
		roster = _build_wild_roster(region)
		GameState.set_wild_roster(region_id, roster, floor)
	else:
		# Re-apply hybrid pressure so backtracking reflects bosses cleared.
		_refresh_roster_pressure(roster, region)
		GameState.set_wild_roster(region_id, roster, floor)
	for entry in roster:
		if not bool(entry.get("alive", true)):
			continue
		_add_live_wild(entry)

func _refresh_roster_pressure(roster: Array, region: Dictionary) -> void:
	var bosses := GameState.bosses_defeated_count()
	var floor := GameState.current_floor()
	for entry in roster:
		var creature: Dictionary = entry.get("creature", {})
		if creature.is_empty():
			continue
		var hp := int(creature.get("hp", 0))
		var max_hp := int(creature.get("max_hp", 1))
		var ratio := 1.0
		if max_hp > 0:
			ratio = clampf(float(hp) / float(max_hp), 0.0, 1.0)
		EncounterSystem.refresh_wild_pressure(creature, region, bosses, floor, GameState.get_difficulty())
		if bool(entry.get("alive", true)):
			creature["hp"] = maxi(1, int(round(float(creature.get("max_hp", 1)) * ratio)))
		else:
			creature["hp"] = int(creature.get("max_hp", 1))
		entry["creature"] = creature

func _add_live_wild(entry: Dictionary) -> void:
	var creature: Dictionary = entry.get("creature", {})
	if creature.is_empty():
		return
	var rid := str(entry.get("instance_id", creature.get("instance_id", "")))
	for w in _wilds:
		if str(w.get("roster_id", "")) == rid:
			return
	var ang := randf() * TAU
	_wilds.append({
		"creature": creature,
		"pos": Vector2(float(entry.get("x", 1.5)), float(entry.get("y", 1.5))),
		"vel": Vector2(cos(ang), sin(ang)) * WILD_SPEED,
		"bob": randf() * TAU,
		"retarget": randf_range(1.2, 2.8),
		"roster_id": rid
	})

func _pick_respawn_cell() -> Vector2i:
	var cells := _grass_cells()
	if cells.is_empty():
		var camp: Vector2i = _map.camp
		return Vector2i(camp.x + 2, camp.y + 2)
	var camp2: Vector2i = _map.camp
	var filtered: Array = []
	for cell in cells:
		var c: Vector2i = cell
		if absi(c.x - camp2.x) + absi(c.y - camp2.y) < 7:
			continue
		var world := Vector2(float(c.x) + 0.5, float(c.y) + 0.5)
		if world.distance_to(_pos) < 3.5:
			continue
		filtered.append(c)
	if filtered.is_empty():
		filtered = cells
	return filtered[randi() % filtered.size()]

func _tick_wild_respawns() -> void:
	if _map.is_empty() or _busy:
		return
	var region_id := str(GameState.run.get("region_id", ""))
	var floor := GameState.current_floor()
	var roster: Array = GameState.get_wild_roster(region_id, floor)
	if roster.is_empty():
		return
	var now := Time.get_unix_time_from_system()
	var changed := false
	var respawned := 0
	for entry in roster:
		if bool(entry.get("alive", true)):
			continue
		if not entry.has("respawn_at"):
			continue
		if now < float(entry.get("respawn_at", now + 999)):
			continue
		var cell := _pick_respawn_cell()
		entry["alive"] = true
		entry.erase("respawn_at")
		entry["x"] = float(cell.x) + 0.5
		entry["y"] = float(cell.y) + 0.5
		var creature: Dictionary = entry.get("creature", {})
		if not creature.is_empty():
			creature["statuses"] = []
			EncounterSystem.apply_random_wild_elements(creature)
			EncounterSystem.refresh_wild_pressure(
				creature,
				GameState.current_region(),
				GameState.bosses_defeated_count(),
				floor,
				GameState.get_difficulty()
			)
			creature["hp"] = int(creature.get("max_hp", 1))
			entry["creature"] = creature
		_add_live_wild(entry)
		changed = true
		respawned += 1
	if changed:
		GameState.set_wild_roster(region_id, roster, floor)
		if respawned > 0 and not region_panel.visible:
			message.text = "Wild monsters have returned to the area."
		map_draw.queue_redraw()

func _build_wild_roster(region: Dictionary) -> Array:
	var cells := _grass_cells()
	if cells.is_empty():
		return []
	var camp: Vector2i = _map.camp
	var filtered: Array = []
	for cell in cells:
		var c: Vector2i = cell
		if absi(c.x - camp.x) + absi(c.y - camp.y) < 7:
			continue
		filtered.append(c)
	if filtered.is_empty():
		filtered = cells
	var want := int(region.get("wild_count", DEFAULT_WILD_COUNT))
	want = clampi(want, 2, 10)
	var count := mini(want, filtered.size())
	filtered.shuffle()
	var roster: Array = []
	for i in count:
		var cell: Vector2i = filtered[i]
		var wild := EncounterSystem.roll_wild(
			str(region.get("id")),
			GameState.account,
			GameState.bosses_defeated_count(),
			GameState.current_floor(),
			GameState.get_difficulty()
		)
		if wild.is_empty():
			continue
		roster.append({
			"instance_id": str(wild.get("instance_id", "")),
			"creature": wild,
			"x": float(cell.x) + 0.5,
			"y": float(cell.y) + 0.5,
			"alive": true
		})
	return roster

func _persist_wild_positions() -> void:
	var region_id := str(GameState.run.get("region_id", ""))
	var floor := GameState.current_floor()
	var roster: Array = GameState.get_wild_roster(region_id, floor)
	if roster.is_empty():
		return
	var by_id := {}
	for w in _wilds:
		by_id[str(w.get("roster_id", ""))] = w
	for entry in roster:
		if not bool(entry.get("alive", true)):
			continue
		var wid := str(entry.get("instance_id", ""))
		if by_id.has(wid):
			var live: Dictionary = by_id[wid]
			var p: Vector2 = live["pos"]
			entry["x"] = p.x
			entry["y"] = p.y
	GameState.set_wild_roster(region_id, roster, floor)

func _setup_boss_marker() -> void:
	_boss_marker = {}
	var region := GameState.current_region()
	if region.get("stub", false) or region.get("boss_id", null) == null:
		return
	if not bool(_map.get("is_boss_floor", true)):
		return
	if GameState.run.get("bosses_defeated", []).has(region.get("boss_id")):
		return
	var tier := int(GameState.run.get("bosses_defeated", []).size())
	var boss := EncounterSystem.create_boss(region, tier, GameState.current_floor(), GameState.get_difficulty())
	if boss.is_empty():
		return
	var bc: Vector2i = _map.get("boss", Vector2i(-1, -1))
	if bc.x < 0:
		return
	_boss_marker = {
		"creature": boss,
		"pos": Vector2(float(bc.x) + 0.5, float(bc.y) + 0.5)
	}

func _show_intro_once() -> void:
	if _intro_shown:
		return
	_intro_shown = true
	var region := GameState.current_region()
	message.text = "%s\n%s" % [region.get("name"), region.get("intro", "")]
	await get_tree().create_timer(1.6).timeout
	if is_inside_tree():
		message.text = "Explore 5 dungeon floors. Stairs go deeper; Floor 5 holds the boss. Bond Shards heal in battle (costs a turn)."

func _refresh_hud() -> void:
	var c: Dictionary = GameState.get_companion()
	var region := GameState.current_region()
	hud.text = "%s F%d/%d · %s · %s Lv%d · HP %d/%d · Shards %d/%d" % [
		region.get("name", "?"),
		GameState.current_floor(),
		GameState.floors_per_region(),
		DifficultySystem.label(GameState.get_difficulty()),
		c.get("name", "?"),
		int(c.get("level", 1)),
		c.get("hp", 0),
		c.get("max_hp", 1),
		GameState.get_bond_shards(),
		GameState.BOND_SHARD_CAP
	]
	hp_bar.max_value = float(c.get("max_hp", 1))
	hp_bar.value = float(c.get("hp", 0))
	AppTheme.style_title(hud, 15)

func _process(delta: float) -> void:
	if _map.is_empty() or _busy or region_panel.visible:
		_moving = false
		return
	_ambient_t += delta
	_tick_wild_respawns()
	if _contact_grace > 0.0:
		_contact_grace = maxf(0.0, _contact_grace - delta)
	_update_keyboard()
	_update_wilds(delta)
	var input_vec := _stick
	if input_vec.length() < 0.01:
		input_vec = _keyboard
	if input_vec.length() > 0.01:
		_facing = PlayerAvatar.facing_from_vector(input_vec)
		var before := _pos
		_move_with_collision(input_vec.normalized() * MOVE_SPEED * input_vec.length() * delta)
		var dist := before.distance_to(_pos)
		_moving = dist > 0.0001
		if _moving:
			_walk_phase += delta * (8.0 + input_vec.length() * 6.0)
			_bob_t = _walk_phase
			_persist_pos(true)
			_save_cooldown -= delta
			if _save_cooldown <= 0.0:
				_save_cooldown = SAVE_INTERVAL
				_persist_wild_positions()
				GameState.autosave()
			var tile := _tile_at(_pos)
			if tile != _last_tile:
				_last_tile = tile
				_reveal_at_player()
				_on_enter_tile(_tile_type(tile))
			_check_contacts()
	else:
		_moving = false
		_walk_phase = move_toward(_walk_phase, floorf(_walk_phase / 4.0) * 4.0, delta * 10.0)
		_check_contacts()
	map_draw.queue_redraw()
	if _minimap_dirty or _moving:
		_queue_minimap_redraw()
		_minimap_dirty = false

func _update_wilds(delta: float) -> void:
	for w in _wilds:
		w["retarget"] = float(w.get("retarget", 0.0)) - delta
		w["bob"] = float(w.get("bob", 0.0)) + delta * 5.0
		if float(w["retarget"]) <= 0.0:
			var ang := randf() * TAU
			w["vel"] = Vector2(cos(ang), sin(ang)) * WILD_SPEED * randf_range(0.7, 1.2)
			w["retarget"] = randf_range(1.0, 2.6)
		var pos: Vector2 = w["pos"]
		var vel: Vector2 = w["vel"]
		var next := pos + vel * delta
		if _can_occupy_radius(next, WILD_RADIUS) and _is_wild_tile(_tile_type(_tile_at(next))):
			w["pos"] = next
		else:
			# Bounce / pick new heading
			var ang2 := randf() * TAU
			w["vel"] = Vector2(cos(ang2), sin(ang2)) * WILD_SPEED
			w["retarget"] = randf_range(0.6, 1.4)

func _check_contacts() -> void:
	if _busy or _contact_grace > 0.0:
		return
	if not _boss_marker.is_empty():
		var bp: Vector2 = _boss_marker["pos"]
		if _pos.distance_to(bp) <= CONTACT_DIST + 0.15:
			_start_battle(_boss_marker["creature"], true)
			return
	for i in range(_wilds.size()):
		var w: Dictionary = _wilds[i]
		var wp: Vector2 = w["pos"]
		if _pos.distance_to(wp) <= CONTACT_DIST:
			var creature: Dictionary = w["creature"]
			var rid := str(w.get("roster_id", creature.get("instance_id", "")))
			_wilds.remove_at(i)
			_start_battle(creature, false, rid)
			return

func _start_battle(creature: Dictionary, is_boss: bool, roster_id: String = "", obelisk_cell: Vector2i = Vector2i(-1, -1)) -> void:
	if _busy:
		return
	_busy = true
	_stick = Vector2.ZERO
	_persist_wild_positions()
	message.text = "%s blocks your path!" % creature.get("name", "Enemy")
	GameState.autosave()
	await get_tree().create_timer(0.25).timeout
	GameState.begin_battle(creature, is_boss, roster_id, obelisk_cell)
	get_tree().change_scene_to_file("res://scenes/battle/Battle.tscn")

func _update_keyboard() -> void:
	var v := Vector2.ZERO
	if Input.is_action_pressed("move_up"):
		v.y -= 1.0
	if Input.is_action_pressed("move_down"):
		v.y += 1.0
	if Input.is_action_pressed("move_left"):
		v.x -= 1.0
	if Input.is_action_pressed("move_right"):
		v.x += 1.0
	_keyboard = v.normalized() if v.length() > 0.0 else Vector2.ZERO

func _move_with_collision(motion: Vector2) -> void:
	if motion == Vector2.ZERO:
		return
	var next := _pos + Vector2(motion.x, 0.0)
	if _can_occupy_radius(next, PLAYER_RADIUS):
		_pos = next
	next = _pos + Vector2(0.0, motion.y)
	if _can_occupy_radius(next, PLAYER_RADIUS):
		_pos = next

func _can_occupy_radius(p: Vector2, radius: float) -> bool:
	var offsets := [
		Vector2(-radius, -radius),
		Vector2(radius, -radius),
		Vector2(-radius, radius),
		Vector2(radius, radius),
		Vector2.ZERO
	]
	for off in offsets:
		var sample: Vector2 = p + off
		var t := _tile_at(sample)
		if t.x < 0 or t.y < 0 or t.x >= int(_map.width) or t.y >= int(_map.height):
			return false
		if not MapGenerator.is_walkable(_tile_type(t)):
			return false
	return true

func _tile_at(p: Vector2) -> Vector2i:
	return Vector2i(int(floor(p.x)), int(floor(p.y)))

func _tile_type(t: Vector2i) -> int:
	if t.y < 0 or t.x < 0 or t.y >= int(_map.height) or t.x >= int(_map.width):
		return MapGenerator.TILE_WALL
	return int(_map.tiles[t.y][t.x])

func _paint_minimap(canvas: CanvasItem) -> void:
	if _map.is_empty() or canvas == null:
		return
	var sz: Vector2 = canvas.get_size()
	if sz.x < 8.0 or sz.y < 8.0:
		return
	var map_w: int = int(_map.width)
	var map_h: int = int(_map.height)
	if map_w < 1 or map_h < 1:
		return
	var pad := 4.0
	var inner := Rect2(Vector2(pad, pad), sz - Vector2(pad * 2.0, pad * 2.0))
	var cell := minf(inner.size.x / float(map_w), inner.size.y / float(map_h))
	var draw_w := cell * float(map_w)
	var draw_h := cell * float(map_h)
	var origin := inner.position + Vector2((inner.size.x - draw_w) * 0.5, (inner.size.y - draw_h) * 0.5)
	var region := GameState.current_region()
	var grass := Color.html(str(region.get("grass_color", "#2d6a4f")))
	var pathc := Color.html(str(region.get("path_color", "#52796f")))
	# Frame + full purple fog base (unexplored).
	canvas.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.05, 0.03, 0.08, 0.92), true)
	canvas.draw_rect(Rect2(origin, Vector2(draw_w, draw_h)), FOG_PURPLE, true)
	var tiles: Array = _map.tiles
	for y in map_h:
		for x in map_w:
			var ck := "%d,%d" % [x, y]
			if not _explored.has(ck):
				continue
			var t: int = int(tiles[y][x])
			var col := _minimap_tile_color(t, grass, pathc)
			var r := Rect2(origin + Vector2(float(x) * cell, float(y) * cell), Vector2(cell, cell))
			canvas.draw_rect(r, col, true)
	# Soft purple veil over explored edges for atmosphere.
	for y2 in map_h:
		for x2 in map_w:
			var ck2 := "%d,%d" % [x2, y2]
			if not _explored.has(ck2):
				continue
			if _explored_neighbor_fogged(x2, y2, map_w, map_h):
				var er := Rect2(origin + Vector2(float(x2) * cell, float(y2) * cell), Vector2(cell, cell))
				canvas.draw_rect(er, FOG_PURPLE_EDGE, true)
	# Player blip.
	var px := origin.x + _pos.x * cell
	var py := origin.y + _pos.y * cell
	canvas.draw_circle(Vector2(px, py), maxf(2.2, cell * 0.55), Color(1.0, 0.92, 0.35, 1.0))
	canvas.draw_arc(Vector2(px, py), maxf(3.0, cell * 0.85), 0.0, TAU, 16, Color(1.0, 0.95, 0.55, 0.9), 1.2, true)
	# Border
	canvas.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.55, 0.35, 0.75, 0.95), false, 2.0)
	canvas.draw_string(
		AppTheme.body_font(),
		Vector2(8, 14),
		"Map",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		12,
		Color(0.92, 0.82, 1.0, 0.9)
	)

func _explored_neighbor_fogged(x: int, y: int, map_w: int, map_h: int) -> bool:
	for oy in range(-1, 2):
		for ox in range(-1, 2):
			if ox == 0 and oy == 0:
				continue
			var nx := x + ox
			var ny := y + oy
			if nx < 0 or ny < 0 or nx >= map_w or ny >= map_h:
				return true
			if not _explored.has("%d,%d" % [nx, ny]):
				return true
	return false

func _minimap_tile_color(tile: int, grass: Color, pathc: Color) -> Color:
	match tile:
		MapGenerator.TILE_PATH, MapGenerator.TILE_BRIDGE:
			return pathc.lightened(0.1)
		MapGenerator.TILE_GRASS:
			return grass
		MapGenerator.TILE_CAMP:
			return Color(0.95, 0.85, 0.35, 1.0)
		MapGenerator.TILE_BOSS:
			return Color(0.9, 0.25, 0.28, 1.0)
		MapGenerator.TILE_EXIT:
			return Color(0.45, 0.75, 1.0, 1.0)
		MapGenerator.TILE_OBELISK:
			return Color(0.55, 0.9, 1.0, 1.0)
		MapGenerator.TILE_WATER:
			return Color(0.25, 0.45, 0.75, 1.0)
		MapGenerator.TILE_LAVA:
			return Color(0.85, 0.35, 0.15, 1.0)
		MapGenerator.TILE_VOID:
			return Color(0.12, 0.05, 0.2, 1.0)
		MapGenerator.TILE_ROCK, MapGenerator.TILE_WALL:
			return Color(0.28, 0.28, 0.32, 1.0)
		_:
			return Color(0.1, 0.12, 0.11, 1.0)

func _paint_world(canvas: CanvasItem) -> void:
	if _map.is_empty() or canvas == null:
		return
	var sz: Vector2 = canvas.get_size()
	if sz.x < 8.0 or sz.y < 8.0:
		return
	var region := GameState.current_region()
	var biome := str(region.get("id", "forest"))
	var grass := Color.html(str(region.get("grass_color", "#2d6a4f")))
	var pathc := Color.html(str(region.get("path_color", "#52796f")))
	var tiles: Array = _map.tiles
	var map_w: int = _map.width
	var map_h: int = _map.height
	var origin := Vector2(sz.x * 0.5 - _pos.x * TILE, sz.y * 0.48 - _pos.y * TILE)
	# Cull to visible viewport for large dungeon floors.
	var pad := 2
	var min_x := clampi(int((-origin.x) / TILE) - pad, 0, map_w - 1)
	var min_y := clampi(int((-origin.y) / TILE) - pad, 0, map_h - 1)
	var max_x := clampi(int((sz.x - origin.x) / TILE) + pad, 0, map_w - 1)
	var max_y := clampi(int((sz.y - origin.y) / TILE) + pad, 0, map_h - 1)
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var t: int = tiles[y][x]
			var rect := Rect2(origin + Vector2(x, y) * TILE, Vector2(TILE, TILE))
			var obelisk_tint := Color(1, 1, 1, 1)
			if t == MapGenerator.TILE_OBELISK:
				var ostate: Dictionary = _obelisk_state.get("%d,%d" % [x, y], {})
				obelisk_tint = EncounterSystem.obelisk_hue_color(str(ostate.get("hue", "cyan")))
			TileArt.draw_tile(canvas, t, rect, grass, pathc, _ambient_t, obelisk_tint, biome, Vector2i(x, y))

	# Visible wild creatures — large, ringed, labeled so they never blend into tiles.
	var view := Rect2(Vector2.ZERO, sz).grow(96.0 * GFX_SCALE)
	var name_font := AppTheme.body_font()
	for wild in _wilds:
		var wp: Vector2 = wild["pos"]
		var bob := sin(float(wild.get("bob", 0.0))) * 3.0 * GFX_SCALE
		var cpos := origin + wp * TILE + Vector2(0.0, bob)
		if not view.has_point(cpos):
			continue
		var ecol := _element_color(wild["creature"])
		canvas.draw_circle(cpos + Vector2(0, 16 * GFX_SCALE), 14.0 * GFX_SCALE, Color(0, 0, 0, 0.38))
		canvas.draw_circle(cpos, 28.0 * GFX_SCALE, Color(ecol.r, ecol.g, ecol.b, 0.22))
		canvas.draw_arc(cpos, 26.0 * GFX_SCALE, 0.0, TAU, 36, ecol, 3.0 * GFX_SCALE, true)
		PlaceholderArt.draw_creature(canvas, wild["creature"], cpos, 22.0 * GFX_SCALE, float(wild.get("bob", 0.0)))
		var n := str(wild["creature"].get("name", "?"))
		var type_txt := _element_label(wild["creature"])
		canvas.draw_string(name_font, cpos + Vector2(-42 * GFX_SCALE, -36 * GFX_SCALE), n, HORIZONTAL_ALIGNMENT_LEFT, int(90 * GFX_SCALE), int(14 * GFX_SCALE), Color(1, 1, 1, 0.96))
		if type_txt != "":
			canvas.draw_string(name_font, cpos + Vector2(-42 * GFX_SCALE, -20 * GFX_SCALE), type_txt, HORIZONTAL_ALIGNMENT_LEFT, int(100 * GFX_SCALE), int(12 * GFX_SCALE), ecol)

	# Boss marker
	if not _boss_marker.is_empty():
		var bp: Vector2 = _boss_marker["pos"]
		var bpos := origin + bp * TILE
		if view.has_point(bpos):
			canvas.draw_circle(bpos + Vector2(0, 18 * GFX_SCALE), 16.0 * GFX_SCALE, Color(0.2, 0.02, 0.04, 0.4))
			canvas.draw_circle(bpos, 36.0 * GFX_SCALE, Color(0.85, 0.15, 0.2, 0.24))
			canvas.draw_arc(bpos, 34.0 * GFX_SCALE, 0.0, TAU, 40, Color(1.0, 0.45, 0.4, 0.9), 3.5 * GFX_SCALE, true)
			PlaceholderArt.draw_creature(canvas, _boss_marker["creature"], bpos, 28.0 * GFX_SCALE, _ambient_t)
			canvas.draw_string(name_font, bpos + Vector2(-56 * GFX_SCALE, -46 * GFX_SCALE), str(_boss_marker["creature"].get("name", "Boss")), HORIZONTAL_ALIGNMENT_LEFT, int(120 * GFX_SCALE), int(15 * GFX_SCALE), Color(1, 0.82, 0.82, 1))
			canvas.draw_string(name_font, bpos + Vector2(-56 * GFX_SCALE, -28 * GFX_SCALE), _element_label(_boss_marker["creature"]), HORIZONTAL_ALIGNMENT_LEFT, int(120 * GFX_SCALE), int(12 * GFX_SCALE), _element_color(_boss_marker["creature"]))

	# Player: human trainer with companion — oversized gold ring so YOU are always visible.
	var center := origin + _pos * TILE
	canvas.draw_circle(center + Vector2(0, 22 * GFX_SCALE), 13.0 * GFX_SCALE, Color(0, 0, 0, 0.42))
	canvas.draw_circle(center, 32.0 * GFX_SCALE, Color(0.98, 0.95, 0.55, 0.18))
	canvas.draw_arc(center, 30.0 * GFX_SCALE, 0.0, TAU, 40, Color(1.0, 0.92, 0.35, 0.95), 3.5 * GFX_SCALE, true)
	PlayerAvatar.draw(
		canvas,
		center,
		2.05 * GFX_SCALE,
		GameState.get_companion(),
		_facing,
		_walk_phase,
		_moving
	)
	canvas.draw_string(name_font, center + Vector2(-20 * GFX_SCALE, -42 * GFX_SCALE), "YOU", HORIZONTAL_ALIGNMENT_LEFT, int(50 * GFX_SCALE), int(14 * GFX_SCALE), Color(1, 0.95, 0.55, 0.98))

func _element_label(creature: Dictionary) -> String:
	var els: Array = creature.get("elements", [])
	if els.is_empty():
		return ""
	var names: PackedStringArray = []
	for e in els:
		var id := str(e)
		if DataRegistry.elements.has(id):
			names.append(str(DataRegistry.elements[id].get("name", id)).capitalize())
		else:
			names.append(id.capitalize())
	return " · ".join(names)

func _element_color(creature: Dictionary) -> Color:
	var els: Array = creature.get("elements", [])
	if els.is_empty():
		return Color(0.8, 0.85, 0.82, 0.85)
	var id := str(els[0])
	if DataRegistry.elements.has(id):
		return Color.html(str(DataRegistry.elements[id].get("color", "#cfcfcf")))
	return Color(0.8, 0.85, 0.82, 0.9)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("confirm"):
		_on_a()
	elif event.is_action_pressed("cancel"):
		_on_b()

func _draw_obelisk(center: Vector2) -> void:
	var glow := 0.45 + 0.25 * sin(_ambient_t * 2.0 + center.x * 0.02)
	map_draw.draw_circle(center + Vector2(0, 6), 16.0, Color(0.35, 0.55, 0.95, 0.2 + glow * 0.15))
	# Stone pillar
	map_draw.draw_rect(Rect2(center - Vector2(8, 22), Vector2(16, 36)), Color(0.42, 0.44, 0.5))
	map_draw.draw_rect(Rect2(center - Vector2(10, 26), Vector2(20, 8)), Color(0.5, 0.52, 0.58))
	# Pointed tip
	map_draw.draw_colored_polygon(PackedVector2Array([
		center + Vector2(0, -34),
		center + Vector2(-10, -18),
		center + Vector2(10, -18)
	]), Color(0.55, 0.58, 0.66))
	# Rune glow
	map_draw.draw_rect(Rect2(center - Vector2(3, 8), Vector2(6, 14)), Color(0.45, 0.85, 1.0, 0.55 + glow * 0.35))
	map_draw.draw_circle(center + Vector2(0, -10), 3.0, Color(0.7, 0.95, 1.0, 0.7 + glow * 0.3))

func _on_enter_tile(tile: int) -> void:
	match tile:
		MapGenerator.TILE_CAMP:
			GameState.heal_companion_full()
			message.text = "Camp rest. Companion fully healed."
			_refresh_hud()
			GameState.autosave()
		MapGenerator.TILE_EXIT:
			_handle_exit_tile(_tile_at(_pos))
		MapGenerator.TILE_OBELISK:
			_try_activate_obelisk(_tile_at(_pos))
		_:
			pass

func _handle_exit_tile(cell: Vector2i) -> void:
	var stairs_down: Vector2i = _map.get("stairs_down", Vector2i(-1, -1))
	var stairs_up: Vector2i = _map.get("stairs_up", Vector2i(-1, -1))
	if cell == stairs_down:
		message.text = "Stairs deeper. Press A to descend (Floor %d → %d)." % [
			GameState.current_floor(), mini(GameState.current_floor() + 1, GameState.floors_per_region())
		]
	elif cell == stairs_up:
		message.text = "Stairs upward. Press A to climb (Floor %d → %d)." % [
			GameState.current_floor(), maxi(GameState.current_floor() - 1, 1)
		]
	else:
		message.text = "Travel hub. Open Regions (or press A) to travel."

func _try_use_stairs(cell: Vector2i) -> bool:
	if _busy:
		return false
	if _tile_type(cell) != MapGenerator.TILE_EXIT:
		return false
	var stairs_down: Vector2i = _map.get("stairs_down", Vector2i(-1, -1))
	var stairs_up: Vector2i = _map.get("stairs_up", Vector2i(-1, -1))
	if cell == stairs_down:
		if GameState.advance_floor():
			message.text = "Descending to Floor %d/%d..." % [
				GameState.current_floor(), GameState.floors_per_region()
			]
			_load_region()
			_refresh_hud()
			return true
		message.text = "This is the deepest floor."
		return true
	if cell == stairs_up:
		if GameState.retreat_floor():
			message.text = "Climbing to Floor %d/%d..." % [
				GameState.current_floor(), GameState.floors_per_region()
			]
			_load_region()
			_refresh_hud()
			return true
		message.text = "Already on Floor 1 — open Regions to leave."
		return true
	return false

func _try_activate_obelisk(cell: Vector2i) -> bool:
	if _busy:
		return false
	if _tile_type(cell) != MapGenerator.TILE_OBELISK:
		return false
	var region_id := str(GameState.run.get("region_id", ""))
	if GameState.is_obelisk_cleared(region_id, cell):
		return false
	var key := "%d,%d" % [cell.x, cell.y]
	var state: Dictionary = _obelisk_state.get(key, {})
	if state.is_empty():
		state = GameState.ensure_obelisk_state(region_id, cell, "")
	var template_id := str(state.get("template_id", ""))
	var stage := clampi(int(state.get("stage", 1)), 1, 3)
	var guardian := EncounterSystem.create_obelisk_guardian(
		region_id,
		template_id,
		stage,
		GameState.bosses_defeated_count(),
		GameState.current_floor(),
		GameState.get_difficulty()
	)
	if guardian.is_empty():
		message.text = "The obelisk stays silent."
		return false
	var hue := str(guardian.get("obelisk_hue", state.get("hue", "cyan"))).capitalize()
	message.text = "Obelisk %d/3 (%s) awakens — %s emerges!" % [
		stage, hue, guardian.get("name", "Guardian")
	]
	_start_battle(guardian, false, "", cell)
	return true

func _on_a() -> void:
	if _busy or region_panel.visible:
		return
	# Prefer activating an obelisk underfoot / adjacent.
	var here := _tile_at(_pos)
	if _try_activate_obelisk(here):
		return
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if _try_activate_obelisk(here + d):
			return
	# Stairs before wilds so floor transitions stay reliable.
	if _try_use_stairs(here):
		return
	# Prefer interacting with nearest wild within reach.
	var nearest_i := -1
	var nearest_d := 1.1
	for i in range(_wilds.size()):
		var d := _pos.distance_to(_wilds[i]["pos"])
		if d < nearest_d:
			nearest_d = d
			nearest_i = i
	if nearest_i >= 0:
		var nearest: Dictionary = _wilds[nearest_i]
		var creature: Dictionary = nearest["creature"]
		var rid := str(nearest.get("roster_id", creature.get("instance_id", "")))
		_wilds.remove_at(nearest_i)
		_start_battle(creature, false, rid)
		return
	if not _boss_marker.is_empty() and _pos.distance_to(_boss_marker["pos"]) < 1.2:
		_start_battle(_boss_marker["creature"], true)
		return
	if _tile_type(_tile_at(_pos)) == MapGenerator.TILE_EXIT:
		_open_region_travel()
		return
	_on_enter_tile(_tile_type(_tile_at(_pos)))

func _on_b() -> void:
	if region_panel.visible:
		_close_region_travel()
		return
	message.text = "Companion: %s | Mutations: %d | Shards: %d | Wilds: %d" % [
		GameState.get_companion().get("name"),
		GameState.get_companion().get("mutations", []).size(),
		GameState.get_bond_shards(),
		_wilds.size()
	]

func _toggle_regions() -> void:
	if region_panel.visible:
		_close_region_travel()
		return
	_open_region_travel()

func _close_region_travel() -> void:
	region_panel.visible = false
	_stick = Vector2.ZERO
	if str(message.text).begins_with("Choose a region"):
		message.text = "Travel closed. Cross bridges to explore — open Regions when you want to leave."

func _open_region_travel() -> void:
	_stick = Vector2.ZERO
	region_panel.visible = true
	_rebuild_regions()
	message.text = "Choose a region to travel."

func _rebuild_regions() -> void:
	for c in region_list.get_children():
		c.queue_free()
	var unlocked: Array = GameState.run.get("unlocked_regions", [])
	for rid in DataRegistry.region_order:
		var r: Dictionary = DataRegistry.get_region(str(rid))
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(0, 48)
		var lock := not unlocked.has(rid)
		btn.text = str(r.get("name"))
		if lock:
			btn.text += " — Locked"
			btn.disabled = true
		else:
			if str(GameState.run.get("region_id", "")) == str(rid):
				btn.text += " (here)"
			btn.pressed.connect(_travel.bind(str(rid)))
		region_list.add_child(btn)

func _travel(region_id: String) -> void:
	GameState.change_region(region_id)
	# Position is resolved after generate() using the live camp cell.
	GameState.run["player_pos"] = {"x": 1.5, "y": 1.5}
	GameState.autosave()
	region_panel.visible = false
	_intro_shown = false
	_busy = false
	_load_region()
	var camp: Vector2i = _map.camp
	_pos = Vector2(float(camp.x) + 0.5, float(camp.y) + 0.5)
	_persist_pos(false)
	GameState.autosave()
	_refresh_hud()
	_show_intro_once()
	map_draw.queue_redraw()
