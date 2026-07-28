extends Control
## Turn-based battle UI.

@onready var log_box: RichTextLabel = $Safe/VBox/Log
@onready var player_hp: ProgressBar = $Safe/VBox/Battlers/PlayerCol/PHP
@onready var enemy_hp: ProgressBar = $Safe/VBox/Battlers/EnemyCol/EHP
@onready var player_name: Label = $Safe/VBox/Battlers/PlayerCol/PName
@onready var enemy_name: Label = $Safe/VBox/Battlers/EnemyCol/EName
@onready var player_view: Control = $Safe/VBox/Battlers/PlayerCol/PView
@onready var enemy_view: Control = $Safe/VBox/Battlers/EnemyCol/EView
@onready var action_row: HBoxContainer = $Safe/VBox/Actions
@onready var ability_list: VBoxContainer = $Safe/VBox/AbilityList

var player: Dictionary = {}
var enemy: Dictionary = {}
var can_flee := true
var busy := false
var is_boss := false

func _ready() -> void:
	var pending: Dictionary = GameState.pending_battle
	if pending.is_empty():
		get_tree().change_scene_to_file("res://scenes/overworld/Overworld.tscn")
		return
	player = GameState.get_companion().duplicate(true)
	enemy = pending.get("enemy", {}).duplicate(true)
	can_flee = bool(pending.get("can_flee", true))
	is_boss = bool(pending.get("is_boss", false))
	player_view.draw.connect(_draw_player_battle)
	enemy_view.draw.connect(func(): PlaceholderArt.draw_creature(enemy_view, enemy, enemy_view.size * 0.5, minf(enemy_view.size.x, enemy_view.size.y) * 0.4))
	$Safe/VBox/Actions/FightBtn.pressed.connect(_show_abilities)
	$Safe/VBox/Actions/FleeBtn.pressed.connect(_flee)
	$Safe/VBox/Actions/FleeBtn.disabled = not can_flee
	_refresh()
	_append("%s wants to battle!" % enemy.get("name", "Enemy"))

func _draw_player_battle() -> void:
	# Trainer on the left/back, companion forward as the battler.
	var mid := player_view.size * 0.5
	var scale := minf(player_view.size.x, player_view.size.y) / 48.0 * 0.7
	PlayerAvatar.draw(player_view, mid + Vector2(-player_view.size.x * 0.18, player_view.size.y * 0.08), scale * 0.85, player, "right", 0.0, false)
	PlaceholderArt.draw_creature(player_view, player, mid + Vector2(player_view.size.x * 0.16, 0), minf(player_view.size.x, player_view.size.y) * 0.32)

func _refresh() -> void:
	player_name.text = str(player.get("name", "You"))
	enemy_name.text = str(enemy.get("name", "Enemy"))
	if enemy.get("is_alpha", false):
		enemy_name.text += " ★"
	player_hp.max_value = float(player.get("max_hp", 1))
	player_hp.value = float(player.get("hp", 0))
	enemy_hp.max_value = float(enemy.get("max_hp", 1))
	enemy_hp.value = float(enemy.get("hp", 0))
	player_view.queue_redraw()
	enemy_view.queue_redraw()
	GameState.set_companion(player)
	GameState.autosave()

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
		btn.custom_minimum_size = Vector2(0, 44)
		var el = ab.get("element", null)
		var el_txt := str(el).capitalize() if el != null else "Neutral"
		btn.text = "%s  (%s · Pwr %d)" % [ab.get("name", aid), el_txt, ab.get("power", 0)]
		btn.pressed.connect(_player_act.bind(str(aid)))
		ability_list.add_child(btn)
	var cancel := Button.new()
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
				if res.get("status_applied", null) != null:
					_append("%s inflicted %s!" % [player.get("name"), res.get("status_applied")])
		else:
			await _do_enemy_action()
		_refresh()
		await get_tree().create_timer(0.35).timeout

	# End of round statuses
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
	# Testing aid: restore HP after wins so runs stay playable.
	player["hp"] = int(player.get("max_hp", player.get("hp", 1)))
	player["statuses"] = []
	GameState.set_companion(player)
	if is_boss:
		GameState.mark_boss_defeated(str(enemy.get("template_id", enemy.get("id"))))
	GameState.end_battle_victory(enemy)
	# Win condition: hive cleared — MVP stub regions don't have final boss yet.
	# If forest boss beaten and somehow hive — for MVP, beating forest unlocks desert; true win when meteor_hive cleared.
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
