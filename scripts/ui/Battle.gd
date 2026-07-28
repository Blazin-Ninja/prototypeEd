extends Control
## Turn-based battle UI — large portrait layout.

@onready var log_box: RichTextLabel = $Safe/VBox/LogPanel/LogMargin/Log
@onready var player_hp: ProgressBar = $Safe/VBox/PlayerPanel/PlayerMargin/PlayerCol/PHP
@onready var enemy_hp: ProgressBar = $Safe/VBox/EnemyPanel/EnemyMargin/EnemyCol/EHP
@onready var player_hp_text: Label = $Safe/VBox/PlayerPanel/PlayerMargin/PlayerCol/PHPText
@onready var enemy_hp_text: Label = $Safe/VBox/EnemyPanel/EnemyMargin/EnemyCol/EHPText
@onready var player_name: Label = $Safe/VBox/PlayerPanel/PlayerMargin/PlayerCol/PName
@onready var enemy_name: Label = $Safe/VBox/EnemyPanel/EnemyMargin/EnemyCol/EName
@onready var enemy_meta: Label = $Safe/VBox/EnemyPanel/EnemyMargin/EnemyCol/EMeta
@onready var player_view: Control = $Safe/VBox/PlayerPanel/PlayerMargin/PlayerCol/PView
@onready var enemy_view: Control = $Safe/VBox/EnemyPanel/EnemyMargin/EnemyCol/EView
@onready var action_row: HBoxContainer = $Safe/VBox/Actions
@onready var ability_list: VBoxContainer = $Safe/VBox/AbilityList
@onready var bg_accent: ColorRect = $BGAccent
@onready var enemy_panel: PanelContainer = $Safe/VBox/EnemyPanel
@onready var player_panel: PanelContainer = $Safe/VBox/PlayerPanel

var player: Dictionary = {}
var enemy: Dictionary = {}
var can_flee := true
var busy := false
var is_boss := false
var _anim_t := 0.0
var _hit_flash := 0.0

func _ready() -> void:
	var pending: Dictionary = GameState.pending_battle
	if pending.is_empty():
		get_tree().change_scene_to_file("res://scenes/overworld/Overworld.tscn")
		return
	BossSprites.ensure_loaded()
	PlayerAvatar.ensure_loaded()
	player = GameState.get_companion().duplicate(true)
	enemy = pending.get("enemy", {}).duplicate(true)
	can_flee = bool(pending.get("can_flee", true))
	is_boss = bool(pending.get("is_boss", false))
	_style_panels()
	player_view.draw.connect(_draw_player_battle)
	enemy_view.draw.connect(_draw_enemy_battle)
	$Safe/VBox/Actions/FightBtn.pressed.connect(_show_abilities)
	$Safe/VBox/Actions/FleeBtn.pressed.connect(_flee)
	$Safe/VBox/Actions/FleeBtn.disabled = not can_flee
	_refresh()
	var intro := "%s wants to battle!" % enemy.get("name", "Enemy")
	if is_boss:
		intro = "[b]BOSS[/b] — %s blocks the path!" % enemy.get("name", "Enemy")
	_append(intro)

func _process(delta: float) -> void:
	_anim_t += delta
	if _hit_flash > 0.0:
		_hit_flash = maxf(0.0, _hit_flash - delta * 3.0)
	enemy_view.queue_redraw()
	player_view.queue_redraw()

func _style_panels() -> void:
	# Tint the top stage by enemy element / boss theme.
	var accent := Color(0.14, 0.12, 0.2, 0.65)
	if is_boss:
		var tid := str(enemy.get("template_id", enemy.get("id", "")))
		accent = BossSprites._theme_color(tid)
		accent = Color(accent.r * 0.25, accent.g * 0.2, accent.b * 0.3, 0.7)
	elif not enemy.get("elements", []).is_empty():
		var eid := str(enemy.get("elements", [])[0])
		if DataRegistry.elements.has(eid):
			accent = Color.html(str(DataRegistry.elements[eid].get("color", "#333333")))
			accent = Color(accent.r * 0.2, accent.g * 0.18, accent.b * 0.25, 0.65)
	bg_accent.color = accent

func _draw_player_battle() -> void:
	var mid := player_view.size * 0.5
	var scale := minf(player_view.size.x, player_view.size.y) / 48.0 * 0.85
	# Soft stage floor
	player_view.draw_circle(mid + Vector2(0, player_view.size.y * 0.32), minf(player_view.size.x, player_view.size.y) * 0.28, Color(0, 0, 0, 0.25))
	PlayerAvatar.draw(player_view, mid + Vector2(-player_view.size.x * 0.22, player_view.size.y * 0.1), scale * 0.9, player, "right", 0.0, false)
	PlaceholderArt.draw_creature(player_view, player, mid + Vector2(player_view.size.x * 0.18, 0), minf(player_view.size.x, player_view.size.y) * 0.36, _anim_t)

func _draw_enemy_battle() -> void:
	var mid := enemy_view.size * 0.5
	var radius := minf(enemy_view.size.x, enemy_view.size.y) * (0.42 if is_boss else 0.36)
	# Stage plate
	enemy_view.draw_circle(mid + Vector2(0, radius * 0.85), radius * 0.85, Color(0, 0, 0, 0.28))
	var shake := Vector2.ZERO
	if _hit_flash > 0.0:
		shake = Vector2(sin(_anim_t * 60.0) * 4.0 * _hit_flash, 0)
		enemy_view.modulate = Color(1, 1.0 - _hit_flash * 0.3, 1.0 - _hit_flash * 0.3, 1)
	else:
		enemy_view.modulate = Color.WHITE
	PlaceholderArt.draw_creature(enemy_view, enemy, mid + shake + Vector2(0, -8), radius, _anim_t)

func _refresh() -> void:
	player_name.text = str(player.get("name", "You"))
	enemy_name.text = str(enemy.get("name", "Enemy"))
	var tags: Array = []
	if is_boss:
		tags.append("BOSS")
	if enemy.get("is_alpha", false):
		tags.append("ALPHA")
	if enemy.get("is_legendary", false):
		tags.append("LEGENDARY")
	var els: Array = enemy.get("elements", [])
	if not els.is_empty():
		tags.append(", ".join(PackedStringArray(els)).capitalize())
	enemy_meta.text = " · ".join(PackedStringArray(tags))
	player_hp.max_value = float(player.get("max_hp", 1))
	player_hp.value = float(player.get("hp", 0))
	enemy_hp.max_value = float(enemy.get("max_hp", 1))
	enemy_hp.value = float(enemy.get("hp", 0))
	player_hp_text.text = "HP %d / %d" % [int(player.get("hp", 0)), int(player.get("max_hp", 1))]
	enemy_hp_text.text = "HP %d / %d" % [int(enemy.get("hp", 0)), int(enemy.get("max_hp", 1))]
	_tint_hp_bar(player_hp, float(player.get("hp", 0)) / maxf(float(player.get("max_hp", 1)), 1.0))
	_tint_hp_bar(enemy_hp, float(enemy.get("hp", 0)) / maxf(float(enemy.get("max_hp", 1)), 1.0))
	player_view.queue_redraw()
	enemy_view.queue_redraw()
	GameState.set_companion(player)
	GameState.autosave()

func _tint_hp_bar(bar: ProgressBar, ratio: float) -> void:
	var col := Color(0.3, 0.85, 0.45)
	if ratio < 0.5:
		col = Color(0.95, 0.75, 0.25)
	if ratio < 0.25:
		col = Color(0.95, 0.3, 0.3)
	bar.modulate = col

func _append(text: String) -> void:
	log_box.append_text(text + "\n")

func _set_actions_enabled(on: bool) -> void:
	for c in action_row.get_children():
		if c is Button:
			c.disabled = not on
	if on:
		$Safe/VBox/Actions/FleeBtn.disabled = not can_flee

func _show_abilities() -> void:
	if busy:
		return
	for c in ability_list.get_children():
		c.queue_free()
	ability_list.visible = true
	for aid in player.get("abilities", []):
		var ab: Dictionary = DataRegistry.get_ability(str(aid))
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(0, 56)
		var el = ab.get("element", null)
		var el_txt := str(el).capitalize() if el != null else "Neutral"
		btn.text = "%s   ·   %s   ·   Pwr %d" % [ab.get("name", aid), el_txt, ab.get("power", 0)]
		btn.pressed.connect(_player_act.bind(str(aid)))
		ability_list.add_child(btn)
	var cancel := Button.new()
	cancel.custom_minimum_size = Vector2(0, 48)
	cancel.text = "Cancel"
	cancel.pressed.connect(func(): ability_list.visible = false)
	ability_list.add_child(cancel)

func _player_act(ability_id: String) -> void:
	if busy:
		return
	busy = true
	ability_list.visible = false
	_set_actions_enabled(false)
	await _resolve_turn(ability_id)
	busy = false

func _flee() -> void:
	if busy or not can_flee:
		return
	busy = true
	_set_actions_enabled(false)
	if CombatSystem.attempt_flee(player, enemy):
		_append("Got away safely!")
		GameState.set_companion(player)
		GameState.autosave()
		await get_tree().create_timer(0.6).timeout
		get_tree().change_scene_to_file("res://scenes/overworld/Overworld.tscn")
	else:
		_append("Couldn't escape!")
		await _enemy_turn_only()
		busy = false
		_set_actions_enabled(true)

func _resolve_turn(player_ability: String) -> void:
	var order := CombatSystem.initiative_order(player, enemy)
	for actor in order:
		if int(player.get("hp", 0)) <= 0 or int(enemy.get("hp", 0)) <= 0:
			break
		if actor.get("instance_id") == player.get("instance_id"):
			if not CombatSystem.can_act(player):
				_append("%s is stunned and can't move!" % player.get("name"))
				CombatSystem.clear_stun(player)
			else:
				var res := CombatSystem.execute_ability(player, enemy, player_ability)
				_append(str(res.get("log", "")))
				if bool(res.get("hit", false)):
					_hit_flash = 1.0
				if res.get("status_applied", null) != null:
					_append("%s inflicted %s!" % [player.get("name"), res.get("status_applied")])
		else:
			await _do_enemy_action()
		_refresh()
		await get_tree().create_timer(0.35).timeout

	for log in CombatSystem.apply_end_of_turn_statuses(player):
		_append(str(log))
	for log in CombatSystem.apply_end_of_turn_statuses(enemy):
		_append(str(log))
	_refresh()

	if int(enemy.get("hp", 0)) <= 0:
		await _victory()
		return
	if int(player.get("hp", 0)) <= 0:
		await _defeat()
		return
	_set_actions_enabled(true)

func _enemy_turn_only() -> void:
	await _do_enemy_action()
	for log in CombatSystem.apply_end_of_turn_statuses(player):
		_append(str(log))
	for log in CombatSystem.apply_end_of_turn_statuses(enemy):
		_append(str(log))
	_refresh()
	if int(player.get("hp", 0)) <= 0:
		await _defeat()

func _do_enemy_action() -> void:
	if not CombatSystem.can_act(enemy):
		_append("%s is stunned and can't move!" % enemy.get("name"))
		CombatSystem.clear_stun(enemy)
		return
	var aid := CombatSystem.choose_enemy_ability(enemy)
	if aid == "":
		return
	var res := CombatSystem.execute_ability(enemy, player, aid)
	_append(str(res.get("log", "")))
	if res.get("status_applied", null) != null:
		_append("%s inflicted %s!" % [enemy.get("name"), res.get("status_applied")])

func _victory() -> void:
	_append("%s was defeated!" % enemy.get("name"))
	player["hp"] = int(player.get("max_hp", player.get("hp", 1)))
	player["statuses"] = []
	GameState.set_companion(player)
	if is_boss:
		GameState.mark_boss_defeated(str(enemy.get("template_id", enemy.get("id"))))
	GameState.end_battle_victory(enemy)
	var region := GameState.current_region()
	if str(region.get("id")) == "meteor_hive" and is_boss:
		GameState.last_run_report = GameState.end_run(true)
		await get_tree().create_timer(0.8).timeout
		get_tree().change_scene_to_file("res://scenes/run_end/RunEnd.tscn")
		return
	await get_tree().create_timer(0.7).timeout
	get_tree().change_scene_to_file("res://scenes/absorb/AbsorbDecision.tscn")

func _defeat() -> void:
	_append("%s has fallen... The bond is broken." % player.get("name"))
	GameState.set_companion(player)
	GameState.last_run_report = GameState.end_run(false)
	await get_tree().create_timer(1.0).timeout
	get_tree().change_scene_to_file("res://scenes/run_end/RunEnd.tscn")
