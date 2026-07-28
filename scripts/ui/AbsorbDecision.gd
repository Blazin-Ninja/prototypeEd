extends Control
## Post-battle absorb flow with independent rolls and Replace/Skip choices.

signal choice_made(choice: Dictionary)

@onready var title: Label = $Safe/VBox/Title
@onready var chances: Label = $Safe/VBox/Chances
@onready var enemy_view: Control = $Safe/VBox/EnemyView
@onready var results_box: VBoxContainer = $Safe/VBox/Results
@onready var choice_panel: PanelContainer = $Safe/ChoicePanel
@onready var choice_list: VBoxContainer = $Safe/ChoicePanel/Margin/VBox/List
@onready var choice_title: Label = $Safe/ChoicePanel/Margin/VBox/Title

var enemy: Dictionary = {}
var companion: Dictionary = {}
var pending_results: Array = []
var index := 0

func _ready() -> void:
	choice_panel.visible = false
	var pending: Dictionary = GameState.pending_absorb
	if pending.is_empty():
		get_tree().change_scene_to_file("res://scenes/overworld/Overworld.tscn")
		return
	enemy = pending.get("enemy", {})
	companion = GameState.get_companion().duplicate(true)
	title.text = "Absorb %s?" % enemy.get("name", "DNA")
	var ch := AbsorptionSystem.preview_chances(enemy, GameState.account)
	chances.text = "Odds — Stat %d%% · Ability %d%% · Element %d%%\nMutation %d%% · Rare passive %d%% · Special %d%%" % [
		ch.stat, ch.ability, ch.element, ch.mutation, ch.rare_passive, ch.special_mutation
	]
	enemy_view.draw.connect(func(): PlaceholderArt.draw_creature(enemy_view, enemy, enemy_view.size * 0.5, minf(enemy_view.size.x, enemy_view.size.y) * 0.4))
	enemy_view.queue_redraw()
	$Safe/VBox/Buttons/AbsorbBtn.pressed.connect(_absorb)
	$Safe/VBox/Buttons/LeaveBtn.pressed.connect(_leave)

func _leave() -> void:
	GameState.skip_absorb()
	_return_overworld()

func _absorb() -> void:
	$Safe/VBox/Buttons/AbsorbBtn.disabled = true
	$Safe/VBox/Buttons/LeaveBtn.disabled = true
	pending_results = AbsorptionSystem.roll_all(companion, enemy, GameState.account)
	GameState.run["absorptions"] = int(GameState.run.get("absorptions", 0)) + 1
	if pending_results.is_empty():
		_add_result_label("The DNA rejected fusion. Nothing gained.")
		await get_tree().create_timer(1.0).timeout
		GameState.set_companion(companion)
		GameState.skip_absorb()
		_return_overworld()
		return
	index = 0
	await _process_next()

func _process_next() -> void:
	while index < pending_results.size():
		var result: Dictionary = pending_results[index]
		index += 1
		if result.get("skip", false):
			_add_result_label(str(result.get("label")))
			continue
		if result.get("needs_choice", false):
			var choice: Dictionary = await _ask_choice(result)
			var applied := AbsorptionSystem.apply_result(companion, result, choice)
			_add_result_label(str(applied.get("message", result.get("label"))))
		else:
			var applied2 := AbsorptionSystem.apply_result(companion, result, {})
			_add_result_label(str(applied2.get("message", result.get("label"))))
		await get_tree().create_timer(0.35).timeout
	GameState.set_companion(companion)
	GameState.last_absorb_results = pending_results
	GameState.skip_absorb()
	GameState.autosave()
	EventBus.absorption_complete.emit(pending_results)
	await get_tree().create_timer(0.8).timeout
	_return_overworld()

func _ask_choice(result: Dictionary) -> Dictionary:
	choice_panel.visible = true
	for c in choice_list.get_children():
		c.queue_free()
	var typed := str(result.get("type"))
	if typed == "ability":
		choice_title.text = "Ability slots full. Replace one or skip."
		for aid in companion.get("abilities", []):
			var btn := Button.new()
			btn.text = "Replace %s" % DataRegistry.get_ability(str(aid)).get("name", aid)
			btn.pressed.connect(_resolve_choice.bind({"replace_ability": str(aid)}))
			choice_list.add_child(btn)
	elif typed == "element":
		choice_title.text = "Element slots full (max 3). Replace one or skip."
		for el in companion.get("elements", []):
			var btn2 := Button.new()
			btn2.text = "Replace %s" % str(el).capitalize()
			btn2.pressed.connect(_resolve_choice.bind({"replace_element": str(el)}))
			choice_list.add_child(btn2)
	var skip := Button.new()
	skip.text = "Skip this reward"
	skip.pressed.connect(_resolve_choice.bind({}))
	choice_list.add_child(skip)
	var choice: Dictionary = await choice_made
	choice_panel.visible = false
	return choice

func _resolve_choice(choice: Dictionary) -> void:
	choice_made.emit(choice)

func _add_result_label(text: String) -> void:
	var lbl := Label.new()
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.text = "• " + text
	results_box.add_child(lbl)

func _return_overworld() -> void:
	get_tree().change_scene_to_file("res://scenes/overworld/Overworld.tscn")
