extends Control
## Continuous overworld with virtual joystick, visible wilds, and test heal.

const TILE := 48.0
const MOVE_SPEED := 4.2
const PLAYER_RADIUS := 0.28
const WILD_RADIUS := 0.35
const CONTACT_DIST := 0.72
const SAVE_INTERVAL := 1.25
const WILD_SPEED := 1.05
const DEFAULT_WILD_COUNT := 5
const TEST_MODE := true ## Infinite heal + easier testing aids.

@onready var map_draw: Control = $MapArea/MapDraw
@onready var hud: Label = $HUD/Top/Info
@onready var gold_label: Label = $HUD/Top/GoldRow/GoldLabel
@onready var hp_bar: ProgressBar = $HUD/Top/HPBar
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
var _chest_gold: Dictionary = {} ## "x,y" -> gold amount for unopened chests
var _facing: String = "down"
var _walk_phase: float = 0.0
var _moving := false
var _contact_grace := 0.0

func _ready() -> void:
	if GameState.run.is_empty():
		get_tree().change_scene_to_file("res://scenes/menu/MainMenu.tscn")
		return
	PlayerAvatar.ensure_loaded()
	CreatureSprites.ensure_loaded()
	BossSprites.ensure_loaded()
	region_panel.visible = false
	heal_btn.visible = TEST_MODE
	heal_btn.pressed.connect(_test_heal)
	_load_region()
	map_draw.draw.connect(_draw_map)
	joystick.direction_changed.connect(_on_stick)
	$HUD/Buttons/ABtn.pressed.connect(_on_a)
	$HUD/Buttons/BBtn.pressed.connect(_on_b)
	$HUD/Buttons/MenuBtn.pressed.connect(_toggle_regions)
	$RegionPanel/Margin/VBox/CloseBtn.pressed.connect(func(): region_panel.visible = false)
	_refresh_hud()
	_show_intro_once()
	call_deferred("_maybe_prompt_travel")

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
	# Stable floor layout within a run so chests stay put after battles.
	var floor_seed := int(GameState.run.get("seed", 1)) ^ str(region.get("id", "")).hash()
	seed(floor_seed)
	_map = MapGenerator.generate(region)
	_apply_opened_chests()
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
	map_draw.queue_redraw()

func _apply_opened_chests() -> void:
	_chest_gold.clear()
	var region_id := str(GameState.run.get("region_id", ""))
	var chests: Array = _map.get("chests", [])
	for c in chests:
		var cell := Vector2i(int(c.get("x", 0)), int(c.get("y", 0)))
		if GameState.is_chest_opened(region_id, cell):
			if cell.y >= 0 and cell.y < int(_map.height) and cell.x >= 0 and cell.x < int(_map.width):
				_map.tiles[cell.y][cell.x] = MapGenerator.TILE_PATH
		else:
			_chest_gold["%d,%d" % [cell.x, cell.y]] = int(c.get("gold", 10))
			if cell.y >= 0 and cell.y < int(_map.height) and cell.x >= 0 and cell.x < int(_map.width):
				_map.tiles[cell.y][cell.x] = MapGenerator.TILE_CHEST

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

func _grass_cells() -> Array:
	var cells: Array = []
	var w: int = _map.width
	var h: int = _map.height
	for y in h:
		for x in w:
			if int(_map.tiles[y][x]) == MapGenerator.TILE_GRASS:
				cells.append(Vector2i(x, y))
	return cells

func _spawn_wilds() -> void:
	_wilds.clear()
	var region := GameState.current_region()
	var region_id := str(region.get("id", ""))
	if region.get("stub", false):
		return
	var roster: Array = GameState.get_wild_roster(region_id)
	if roster.is_empty():
		roster = _build_wild_roster(region)
		GameState.set_wild_roster(region_id, roster)
	for entry in roster:
		if not bool(entry.get("alive", true)):
			continue
		var creature: Dictionary = entry.get("creature", {})
		if creature.is_empty():
			continue
		var ang := randf() * TAU
		_wilds.append({
			"creature": creature,
			"pos": Vector2(float(entry.get("x", 1.5)), float(entry.get("y", 1.5))),
			"vel": Vector2(cos(ang), sin(ang)) * WILD_SPEED,
			"bob": randf() * TAU,
			"retarget": randf_range(1.2, 2.8),
			"roster_id": str(entry.get("instance_id", creature.get("instance_id", "")))
		})

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
		var wild := EncounterSystem.roll_wild(str(region.get("id")), GameState.account)
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
	var roster: Array = GameState.get_wild_roster(region_id)
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
	GameState.set_wild_roster(region_id, roster)

func _setup_boss_marker() -> void:
	_boss_marker = {}
	var region := GameState.current_region()
	if region.get("stub", false) or region.get("boss_id", null) == null:
		return
	if GameState.run.get("bosses_defeated", []).has(region.get("boss_id")):
		return
	var boss := EncounterSystem.create_boss(region)
	if boss.is_empty():
		return
	var bc: Vector2i = _map.get("boss", Vector2i(6, 1))
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
		message.text = "Explore the dungeon. Open chests for gold. Bridges cross hazards. Camp heals — boss waits ahead."

func _refresh_hud() -> void:
	var c: Dictionary = GameState.get_companion()
	var region := GameState.current_region()
	hud.text = "%s  |  %s  HP %d/%d" % [
		region.get("name", "?"),
		c.get("name", "?"),
		c.get("hp", 0),
		c.get("max_hp", 1)
	]
	gold_label.text = "Gold  %d" % GameState.get_gold()
	hp_bar.max_value = float(c.get("max_hp", 1))
	hp_bar.value = float(c.get("hp", 0))

func _process(delta: float) -> void:
	if _map.is_empty() or _busy or region_panel.visible:
		_moving = false
		return
	_ambient_t += delta
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
				_on_enter_tile(_tile_type(tile))
			_check_contacts()
	else:
		_moving = false
		_walk_phase = move_toward(_walk_phase, floorf(_walk_phase / 4.0) * 4.0, delta * 10.0)
		_check_contacts()
	map_draw.queue_redraw()

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
		if _can_occupy_radius(next, WILD_RADIUS) and _tile_type(_tile_at(next)) == MapGenerator.TILE_GRASS:
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

func _start_battle(creature: Dictionary, is_boss: bool, roster_id: String = "") -> void:
	if _busy:
		return
	_busy = true
	_stick = Vector2.ZERO
	_persist_wild_positions()
	message.text = "%s blocks your path!" % creature.get("name", "Enemy")
	GameState.autosave()
	await get_tree().create_timer(0.25).timeout
	GameState.begin_battle(creature, is_boss, roster_id)
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

func _draw_map() -> void:
	if _map.is_empty():
		return
	var region := GameState.current_region()
	var grass := Color.html(str(region.get("grass_color", "#2d6a4f")))
	var path := Color.html(str(region.get("path_color", "#52796f")))
	var tiles: Array = _map.tiles
	var map_w: int = _map.width
	var map_h: int = _map.height
	var origin := Vector2(
		map_draw.size.x * 0.5 - _pos.x * TILE,
		map_draw.size.y * 0.45 - _pos.y * TILE
	)
	# Cull to visible viewport for large dungeon floors.
	var pad := 2
	var min_x := clampi(int((-origin.x) / TILE) - pad, 0, map_w - 1)
	var min_y := clampi(int((-origin.y) / TILE) - pad, 0, map_h - 1)
	var max_x := clampi(int((map_draw.size.x - origin.x) / TILE) + pad, 0, map_w - 1)
	var max_y := clampi(int((map_draw.size.y - origin.y) / TILE) + pad, 0, map_h - 1)
	var pulse := 0.5 + 0.5 * sin(_ambient_t * 1.1)
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var t: int = tiles[y][x]
			var rect := Rect2(origin + Vector2(x, y) * TILE, Vector2(TILE - 1, TILE - 1))
			match t:
				MapGenerator.TILE_GRASS:
					map_draw.draw_rect(rect, grass)
				MapGenerator.TILE_PATH:
					map_draw.draw_rect(rect, path)
				MapGenerator.TILE_WALL:
					map_draw.draw_rect(rect, Color(0.05, 0.07, 0.06))
				MapGenerator.TILE_CAMP:
					map_draw.draw_rect(rect, Color(0.85, 0.7, 0.35))
				MapGenerator.TILE_BOSS:
					map_draw.draw_rect(rect, Color(0.65, 0.15, 0.2))
				MapGenerator.TILE_EXIT:
					map_draw.draw_rect(rect, Color(0.3, 0.55, 0.85))
				MapGenerator.TILE_LAVA:
					# Stable base color + tiny slow shimmer (not walk-synced).
					var lava := Color(0.78, 0.24, 0.06)
					map_draw.draw_rect(rect, lava)
					var shimmer := 0.25 + 0.2 * sin(_ambient_t * 1.4 + float(x) * 0.35 + float(y) * 0.2)
					map_draw.draw_circle(rect.get_center(), 5.0, Color(1.0, 0.65, 0.15, shimmer))
				MapGenerator.TILE_WATER:
					# Static water fill — no per-frame color flash while walking.
					var water := Color(0.12, 0.38, 0.55)
					map_draw.draw_rect(rect, water)
					var wave_y := 16.0 + sin(_ambient_t * 1.2 + float(x) * 0.4) * 2.0
					map_draw.draw_line(
						rect.position + Vector2(6, wave_y),
						rect.position + Vector2(40, wave_y - 2.0),
						Color(0.55, 0.8, 0.95, 0.28),
						2.0
					)
				MapGenerator.TILE_VOID:
					map_draw.draw_rect(rect, Color(0.08, 0.02, 0.14))
					map_draw.draw_circle(rect.get_center(), 9.0, Color(0.35, 0.05, 0.45, 0.4 + 0.15 * pulse))
				MapGenerator.TILE_BRIDGE:
					map_draw.draw_rect(rect, Color(0.35, 0.22, 0.12))
					# Plank lines
					var p0 := rect.position
					map_draw.draw_line(p0 + Vector2(4, 10), p0 + Vector2(40, 10), Color(0.55, 0.38, 0.2), 2.0)
					map_draw.draw_line(p0 + Vector2(4, 22), p0 + Vector2(40, 22), Color(0.55, 0.38, 0.2), 2.0)
					map_draw.draw_line(p0 + Vector2(4, 34), p0 + Vector2(40, 34), Color(0.55, 0.38, 0.2), 2.0)
					map_draw.draw_rect(Rect2(p0 + Vector2(1, 1), Vector2(TILE - 3, TILE - 3)), Color(0.2, 0.12, 0.06), false, 2.0)
				MapGenerator.TILE_ROCK:
					map_draw.draw_rect(rect, Color(0.22, 0.22, 0.24))
					map_draw.draw_circle(rect.get_center() + Vector2(-4, 2), 10.0, Color(0.35, 0.34, 0.36))
					map_draw.draw_circle(rect.get_center() + Vector2(6, -3), 7.0, Color(0.4, 0.38, 0.4))
				MapGenerator.TILE_CHEST:
					map_draw.draw_rect(rect, path.darkened(0.15))
					_draw_chest(rect.get_center(), true)
				_:
					map_draw.draw_rect(rect, Color(0.1, 0.1, 0.12))

	# Visible wild creatures (also culled)
	var view := Rect2(Vector2.ZERO, map_draw.size).grow(64.0)
	for wild in _wilds:
		var wp: Vector2 = wild["pos"]
		var bob := sin(float(wild.get("bob", 0.0))) * 2.0
		var cpos := origin + wp * TILE + Vector2(0.0, bob)
		if not view.has_point(cpos):
			continue
		map_draw.draw_circle(cpos + Vector2(0, 9), 8.0, Color(0, 0, 0, 0.22))
		PlaceholderArt.draw_creature(map_draw, wild["creature"], cpos, 12.0)
		var n := str(wild["creature"].get("name", "?"))
		map_draw.draw_string(ThemeDB.fallback_font, cpos + Vector2(-28, -18), n, HORIZONTAL_ALIGNMENT_LEFT, 56, 11, Color(1, 1, 1, 0.85))

	# Boss marker
	if not _boss_marker.is_empty():
		var bp: Vector2 = _boss_marker["pos"]
		var bpos := origin + bp * TILE
		if view.has_point(bpos):
			map_draw.draw_circle(bpos, 18.0, Color(0.7, 0.1, 0.15, 0.25))
			PlaceholderArt.draw_creature(map_draw, _boss_marker["creature"], bpos, 16.0)
			map_draw.draw_string(ThemeDB.fallback_font, bpos + Vector2(-40, -26), str(_boss_marker["creature"].get("name", "Boss")), HORIZONTAL_ALIGNMENT_LEFT, 80, 12, Color(1, 0.75, 0.75, 0.95))

	# Player: human trainer with companion on shoulder
	var center := origin + _pos * TILE
	PlayerAvatar.draw(
		map_draw,
		center,
		1.15,
		GameState.get_companion(),
		_facing,
		_walk_phase,
		_moving
	)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("confirm"):
		_on_a()
	elif event.is_action_pressed("cancel"):
		_on_b()

func _draw_chest(center: Vector2, closed: bool) -> void:
	var body := Rect2(center - Vector2(14, 8), Vector2(28, 18))
	if closed:
		map_draw.draw_rect(body, Color(0.55, 0.32, 0.12))
		map_draw.draw_rect(Rect2(center - Vector2(14, 14), Vector2(28, 8)), Color(0.7, 0.42, 0.16))
		map_draw.draw_rect(Rect2(center - Vector2(3, 4), Vector2(6, 8)), Color(0.95, 0.78, 0.25))
		map_draw.draw_circle(center + Vector2(0, -2), 2.5, Color(1.0, 0.9, 0.45))
		# Soft gold sparkle
		var spark := 0.55 + 0.45 * sin(_ambient_t * 2.0 + center.x * 0.01)
		map_draw.draw_circle(center + Vector2(10, -12), 2.0, Color(1.0, 0.92, 0.4, spark))
	else:
		map_draw.draw_rect(body, Color(0.28, 0.18, 0.1))
		map_draw.draw_rect(Rect2(center - Vector2(14, 16), Vector2(28, 7)), Color(0.4, 0.25, 0.12))

func _on_enter_tile(tile: int) -> void:
	match tile:
		MapGenerator.TILE_CAMP:
			GameState.heal_companion_full()
			message.text = "Camp rest. Companion fully healed."
			_refresh_hud()
			GameState.autosave()
		MapGenerator.TILE_EXIT:
			_open_region_travel()
		MapGenerator.TILE_CHEST:
			_try_open_chest(_tile_at(_pos))
		_:
			pass

func _try_open_chest(cell: Vector2i) -> bool:
	if _tile_type(cell) != MapGenerator.TILE_CHEST:
		return false
	var region_id := str(GameState.run.get("region_id", ""))
	if GameState.is_chest_opened(region_id, cell):
		return false
	var key := "%d,%d" % [cell.x, cell.y]
	var amount := int(_chest_gold.get(key, randi_range(10, 25)))
	GameState.mark_chest_opened(region_id, cell)
	GameState.add_gold(amount)
	_chest_gold.erase(key)
	_map.tiles[cell.y][cell.x] = MapGenerator.TILE_PATH
	message.text = "Chest opened! +%d gold." % amount
	_refresh_hud()
	map_draw.queue_redraw()
	return true

func _on_a() -> void:
	if _busy:
		return
	# Prefer opening a chest underfoot / adjacent.
	var here := _tile_at(_pos)
	if _try_open_chest(here):
		return
	for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if _try_open_chest(here + d):
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
	_on_enter_tile(_tile_type(_tile_at(_pos)))

func _on_b() -> void:
	message.text = "Companion: %s | Mutations: %d | Gold: %d | Wilds: %d" % [
		GameState.get_companion().get("name"),
		GameState.get_companion().get("mutations", []).size(),
		GameState.get_gold(),
		_wilds.size()
	]

func _toggle_regions() -> void:
	region_panel.visible = not region_panel.visible
	if region_panel.visible:
		_stick = Vector2.ZERO
		_rebuild_regions()

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
