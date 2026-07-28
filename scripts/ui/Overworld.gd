extends Control
## Pokémon-style grid overworld with virtual D-pad.

const TILE := 48.0

@onready var map_draw: Control = $MapArea/MapDraw
@onready var hud: Label = $HUD/Top/Info
@onready var hp_bar: ProgressBar = $HUD/Top/HPBar
@onready var message: Label = $HUD/Message
@onready var region_panel: PanelContainer = $RegionPanel
@onready var region_list: VBoxContainer = $RegionPanel/Margin/VBox/List

var _map: Dictionary = {}
var _cam_offset: Vector2 = Vector2.ZERO
var _moving := false
var _intro_shown := false

func _ready() -> void:
	if GameState.run.is_empty():
		get_tree().change_scene_to_file("res://scenes/menu/MainMenu.tscn")
		return
	region_panel.visible = false
	_load_region()
	map_draw.draw.connect(_draw_map)
	$HUD/Pad/Up.pressed.connect(func(): _try_move(Vector2i(0, -1)))
	$HUD/Pad/Down.pressed.connect(func(): _try_move(Vector2i(0, 1)))
	$HUD/Pad/Left.pressed.connect(func(): _try_move(Vector2i(-1, 0)))
	$HUD/Pad/Right.pressed.connect(func(): _try_move(Vector2i(1, 0)))
	$HUD/Buttons/ABtn.pressed.connect(_on_a)
	$HUD/Buttons/BBtn.pressed.connect(_on_b)
	$HUD/Buttons/MenuBtn.pressed.connect(_toggle_regions)
	$RegionPanel/Margin/VBox/CloseBtn.pressed.connect(func(): region_panel.visible = false)
	_refresh_hud()
	_show_intro_once()

func _load_region() -> void:
	var region := GameState.current_region()
	_map = MapGenerator.generate(region)
	# Clamp player into map if needed.
	var pos := _player_pos()
	pos.x = clampi(pos.x, 1, int(_map.width) - 2)
	pos.y = clampi(pos.y, 1, int(_map.height) - 2)
	GameState.run["player_pos"] = {"x": pos.x, "y": pos.y}
	map_draw.queue_redraw()

func _show_intro_once() -> void:
	if _intro_shown:
		return
	_intro_shown = true
	var region := GameState.current_region()
	message.text = "%s\n%s" % [region.get("name"), region.get("intro", "")]
	await get_tree().create_timer(2.0).timeout
	if is_inside_tree():
		message.text = "Tap D-pad to move. Grass hides wild DNA."

func _player_pos() -> Vector2i:
	var p: Dictionary = GameState.run.get("player_pos", {"x": 1, "y": 14})
	return Vector2i(int(p.get("x", 1)), int(p.get("y", 14)))

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
	var pos := _player_pos()
	# Center camera on player.
	var origin := Vector2(map_draw.size.x * 0.5 - (pos.x + 0.5) * TILE, map_draw.size.y * 0.45 - (pos.y + 0.5) * TILE)
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
	# Player marker
	var pr := Rect2(origin + Vector2(pos.x, pos.y) * TILE + Vector2(8, 8), Vector2(TILE - 16, TILE - 16))
	map_draw.draw_rect(pr, Color(0.95, 0.95, 0.9))
	var companion: Dictionary = GameState.get_companion()
	PlaceholderArt.draw_creature(map_draw, companion, pr.get_center(), 10.0)

func _unhandled_input(event: InputEvent) -> void:
	if _moving:
		return
	if event.is_action_pressed("move_up"):
		_try_move(Vector2i(0, -1))
	elif event.is_action_pressed("move_down"):
		_try_move(Vector2i(0, 1))
	elif event.is_action_pressed("move_left"):
		_try_move(Vector2i(-1, 0))
	elif event.is_action_pressed("move_right"):
		_try_move(Vector2i(1, 0))
	elif event.is_action_pressed("confirm"):
		_on_a()
	elif event.is_action_pressed("cancel"):
		_on_b()

func _try_move(dir: Vector2i) -> void:
	if _moving or region_panel.visible:
		return
	var pos := _player_pos()
	var next := pos + dir
	if next.x < 0 or next.y < 0 or next.x >= int(_map.width) or next.y >= int(_map.height):
		return
	var tile: int = _map.tiles[next.y][next.x]
	if not MapGenerator.is_walkable(tile):
		return
	_moving = true
	GameState.move_player(next)
	map_draw.queue_redraw()
	_refresh_hud()
	await _resolve_tile(tile)
	_moving = false

func _resolve_tile(tile: int) -> void:
	var region := GameState.current_region()
	match tile:
		MapGenerator.TILE_CAMP:
			GameState.heal_companion_full()
			message.text = "Camp rest. Companion fully healed."
			_refresh_hud()
		MapGenerator.TILE_BOSS:
			if region.get("stub", false) or region.get("boss_id", null) == null:
				message.text = "A sealed gate. This region is not yet open."
			elif GameState.run.get("bosses_defeated", []).has(region.get("boss_id")):
				message.text = "The boss falls silent. Path onward awaits."
			else:
				message.text = "Boss presence detected..."
				await get_tree().create_timer(0.4).timeout
				var boss := EncounterSystem.create_boss(region)
				if not boss.is_empty():
					GameState.begin_battle(boss, true)
					get_tree().change_scene_to_file("res://scenes/battle/Battle.tscn")
		MapGenerator.TILE_EXIT:
			_open_region_travel()
		MapGenerator.TILE_GRASS:
			if EncounterSystem.should_trigger_encounter(region, true):
				if region.get("stub", false):
					message.text = "Strange echoes... no stable DNA signatures here yet."
				else:
					var wild := EncounterSystem.roll_wild(str(region.get("id")), GameState.account)
					if not wild.is_empty():
						message.text = "A wild %s appears!" % wild.get("name")
						await get_tree().create_timer(0.35).timeout
						GameState.begin_battle(wild, false)
						get_tree().change_scene_to_file("res://scenes/battle/Battle.tscn")
		_:
			pass

func _on_a() -> void:
	# Interact with current tile.
	var pos := _player_pos()
	var tile: int = _map.tiles[pos.y][pos.x]
	_resolve_tile(tile)

func _on_b() -> void:
	message.text = "Companion: %s | Mutations: %d | Elements: %s" % [
		GameState.get_companion().get("name"),
		GameState.get_companion().get("mutations", []).size(),
		", ".join(PackedStringArray(GameState.get_companion().get("elements", [])))
	]

func _toggle_regions() -> void:
	region_panel.visible = not region_panel.visible
	if region_panel.visible:
		_rebuild_regions()

func _open_region_travel() -> void:
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
	region_panel.visible = false
	_intro_shown = false
	_load_region()
	_refresh_hud()
	_show_intro_once()
