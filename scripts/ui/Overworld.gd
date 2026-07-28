extends Control
## Continuous overworld movement with virtual joystick.

const TILE := 48.0
const MOVE_SPEED := 4.2 ## tiles per second at full stick
const PLAYER_RADIUS := 0.28 ## collision radius in tile units
const ENCOUNTER_DISTANCE := 0.85 ## tiles walked in grass between rolls
const SAVE_INTERVAL := 1.25

@onready var map_draw: Control = $MapArea/MapDraw
@onready var hud: Label = $HUD/Top/Info
@onready var hp_bar: ProgressBar = $HUD/Top/HPBar
@onready var message: Label = $HUD/Message
@onready var region_panel: PanelContainer = $RegionPanel
@onready var region_list: VBoxContainer = $RegionPanel/Margin/VBox/List
@onready var joystick: VirtualJoystick = $HUD/Joystick

var _map: Dictionary = {}
var _pos: Vector2 = Vector2(1.5, 14.5)
var _stick: Vector2 = Vector2.ZERO
var _keyboard: Vector2 = Vector2.ZERO
var _intro_shown := false
var _busy := false
var _grass_travel := 0.0
var _last_tile: Vector2i = Vector2i(-999, -999)
var _save_cooldown := 0.0
var _bob_t := 0.0

func _ready() -> void:
	if GameState.run.is_empty():
		get_tree().change_scene_to_file("res://scenes/menu/MainMenu.tscn")
		return
	region_panel.visible = false
	_load_region()
	map_draw.draw.connect(_draw_map)
	joystick.direction_changed.connect(_on_stick)
	$HUD/Buttons/ABtn.pressed.connect(_on_a)
	$HUD/Buttons/BBtn.pressed.connect(_on_b)
	$HUD/Buttons/MenuBtn.pressed.connect(_toggle_regions)
	$RegionPanel/Margin/VBox/CloseBtn.pressed.connect(func(): region_panel.visible = false)
	_refresh_hud()
	_show_intro_once()

func _on_stick(dir: Vector2) -> void:
	_stick = dir

func _load_region() -> void:
	var region := GameState.current_region()
	_map = MapGenerator.generate(region)
	_pos = _read_saved_pos()
	_pos.x = clampf(_pos.x, 1.2, float(_map.width) - 1.2)
	_pos.y = clampf(_pos.y, 1.2, float(_map.height) - 1.2)
	_persist_pos(false)
	_last_tile = _tile_at(_pos)
	_grass_travel = 0.0
	map_draw.queue_redraw()

func _read_saved_pos() -> Vector2:
	var p: Dictionary = GameState.run.get("player_pos", {"x": 1.5, "y": 14.5})
	var x := float(p.get("x", 1.5))
	var y := float(p.get("y", 14.5))
	# Legacy integer cell saves → stand in tile center.
	if absf(x - roundf(x)) < 0.001 and absf(y - roundf(y)) < 0.001:
		return Vector2(x + 0.5, y + 0.5)
	return Vector2(x, y)

func _persist_pos(count_step: bool) -> void:
	GameState.run["player_pos"] = {"x": _pos.x, "y": _pos.y}
	if count_step:
		GameState.run["steps"] = int(GameState.run.get("steps", 0)) + 1

func _show_intro_once() -> void:
	if _intro_shown:
		return
	_intro_shown = true
	var region := GameState.current_region()
	message.text = "%s\n%s" % [region.get("name"), region.get("intro", "")]
	await get_tree().create_timer(2.0).timeout
	if is_inside_tree():
		message.text = "Drag the joystick to move. Grass hides wild DNA."

func _refresh_hud() -> void:
	var c: Dictionary = GameState.get_companion()
	var region := GameState.current_region()
	hud.text = "%s  |  %s  HP %d/%d" % [
		region.get("name", "?"),
		c.get("name", "?"),
		c.get("hp", 0),
		c.get("max_hp", 1)
	]
	hp_bar.max_value = float(c.get("max_hp", 1))
	hp_bar.value = float(c.get("hp", 0))

func _process(delta: float) -> void:
	if _map.is_empty() or _busy or region_panel.visible:
		return
	_update_keyboard()
	var input_vec := _stick
	if input_vec.length() < 0.01:
		input_vec = _keyboard
	if input_vec.length() > 0.01:
		var before := _pos
		_move_with_collision(input_vec.normalized() * MOVE_SPEED * input_vec.length() * delta)
		var dist := before.distance_to(_pos)
		if dist > 0.0001:
			_bob_t += delta * (6.0 + input_vec.length() * 8.0)
			_persist_pos(true)
			_save_cooldown -= delta
			if _save_cooldown <= 0.0:
				_save_cooldown = SAVE_INTERVAL
				GameState.autosave()
			var tile := _tile_at(_pos)
			if tile != _last_tile:
				_last_tile = tile
				_on_enter_tile(_tile_type(tile))
			elif _tile_type(tile) == MapGenerator.TILE_GRASS:
				_grass_travel += dist
				if _grass_travel >= ENCOUNTER_DISTANCE:
					_grass_travel = 0.0
					_try_grass_encounter()
			map_draw.queue_redraw()
	else:
		_bob_t = move_toward(_bob_t, roundf(_bob_t / TAU) * TAU, delta * 8.0)
		map_draw.queue_redraw()

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
	# Separate axes for smooth wall sliding.
	var next := _pos + Vector2(motion.x, 0.0)
	if _can_occupy(next):
		_pos = next
	next = _pos + Vector2(0.0, motion.y)
	if _can_occupy(next):
		_pos = next

func _can_occupy(p: Vector2) -> bool:
	# Sample corners of the player circle against tile walkability.
	var offsets := [
		Vector2(-PLAYER_RADIUS, -PLAYER_RADIUS),
		Vector2(PLAYER_RADIUS, -PLAYER_RADIUS),
		Vector2(-PLAYER_RADIUS, PLAYER_RADIUS),
		Vector2(PLAYER_RADIUS, PLAYER_RADIUS),
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
	var ground := Color.html(str(region.get("ground_color", "#1b4332")))
	var grass := Color.html(str(region.get("grass_color", "#2d6a4f")))
	var path := Color.html(str(region.get("path_color", "#52796f")))
	var tiles: Array = _map.tiles
	var w: int = _map.width
	var h: int = _map.height
	var origin := Vector2(
		map_draw.size.x * 0.5 - _pos.x * TILE,
		map_draw.size.y * 0.45 - _pos.y * TILE
	)
	for y in h:
		for x in w:
			var t: int = tiles[y][x]
			var rect := Rect2(origin + Vector2(x, y) * TILE, Vector2(TILE - 1, TILE - 1))
			var col := ground
			match t:
				MapGenerator.TILE_GRASS: col = grass
				MapGenerator.TILE_PATH: col = path
				MapGenerator.TILE_WALL: col = Color(0.05, 0.07, 0.06)
				MapGenerator.TILE_CAMP: col = Color(0.85, 0.7, 0.35)
				MapGenerator.TILE_BOSS: col = Color(0.65, 0.15, 0.2)
				MapGenerator.TILE_EXIT: col = Color(0.3, 0.55, 0.85)
			map_draw.draw_rect(rect, col)
	var bob := sin(_bob_t) * 2.5
	var center := origin + _pos * TILE + Vector2(0.0, bob)
	map_draw.draw_circle(center + Vector2(0, 10), 9.0, Color(0, 0, 0, 0.25))
	map_draw.draw_circle(center, 12.0, Color(0.95, 0.95, 0.9))
	var companion: Dictionary = GameState.get_companion()
	PlaceholderArt.draw_creature(map_draw, companion, center, 11.0)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("confirm"):
		_on_a()
	elif event.is_action_pressed("cancel"):
		_on_b()

func _on_enter_tile(tile: int) -> void:
	match tile:
		MapGenerator.TILE_CAMP:
			GameState.heal_companion_full()
			message.text = "Camp rest. Companion fully healed."
			_refresh_hud()
			GameState.autosave()
		MapGenerator.TILE_BOSS:
			_trigger_boss()
		MapGenerator.TILE_EXIT:
			_open_region_travel()
		MapGenerator.TILE_GRASS:
			_grass_travel = 0.0
		_:
			_grass_travel = 0.0

func _try_grass_encounter() -> void:
	if _busy:
		return
	var region := GameState.current_region()
	if not EncounterSystem.should_trigger_encounter(region, true):
		return
	if region.get("stub", false):
		message.text = "Strange echoes... no stable DNA signatures here yet."
		return
	var wild := EncounterSystem.roll_wild(str(region.get("id")), GameState.account)
	if wild.is_empty():
		return
	_busy = true
	_stick = Vector2.ZERO
	message.text = "A wild %s appears!" % wild.get("name")
	GameState.autosave()
	await get_tree().create_timer(0.3).timeout
	GameState.begin_battle(wild, false)
	get_tree().change_scene_to_file("res://scenes/battle/Battle.tscn")

func _trigger_boss() -> void:
	if _busy:
		return
	var region := GameState.current_region()
	if region.get("stub", false) or region.get("boss_id", null) == null:
		message.text = "A sealed gate. This region is not yet open."
		return
	if GameState.run.get("bosses_defeated", []).has(region.get("boss_id")):
		message.text = "The boss falls silent. Path onward awaits."
		return
	_busy = true
	_stick = Vector2.ZERO
	message.text = "Boss presence detected..."
	GameState.autosave()
	await get_tree().create_timer(0.35).timeout
	var boss := EncounterSystem.create_boss(region)
	if not boss.is_empty():
		GameState.begin_battle(boss, true)
		get_tree().change_scene_to_file("res://scenes/battle/Battle.tscn")
	else:
		_busy = false

func _on_a() -> void:
	if _busy:
		return
	_on_enter_tile(_tile_type(_tile_at(_pos)))

func _on_b() -> void:
	message.text = "Companion: %s | Mutations: %d | Elements: %s" % [
		GameState.get_companion().get("name"),
		GameState.get_companion().get("mutations", []).size(),
		", ".join(PackedStringArray(GameState.get_companion().get("elements", [])))
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
		if r.get("stub", false):
			btn.text += " (stub)"
		if lock:
			btn.text += " — Locked"
			btn.disabled = true
		else:
			btn.pressed.connect(_travel.bind(str(rid)))
		region_list.add_child(btn)

func _travel(region_id: String) -> void:
	GameState.change_region(region_id)
	# Start at tile centers for smooth movement.
	var region := DataRegistry.get_region(region_id)
	var start: Dictionary = region.get("start_cell", {"x": 1, "y": 14})
	GameState.run["player_pos"] = {
		"x": float(start.get("x", 1)) + 0.5,
		"y": float(start.get("y", 14)) + 0.5
	}
	GameState.autosave()
	region_panel.visible = false
	_intro_shown = false
	_busy = false
	_load_region()
	_refresh_hud()
	_show_intro_once()
