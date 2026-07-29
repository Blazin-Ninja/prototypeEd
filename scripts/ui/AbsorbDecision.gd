extends Control
## Post-battle absorb flow with independent rolls and Replace/Skip choices.

signal choice_made(choice: Dictionary)

@onready var title: Label = $Safe/VBox/Title
@onready var chances: Label = $Safe/VBox/Chances
@onready var enemy_view: Control = $Safe/VBox/EnemyView
@onready var results_box: VBoxContainer = $Safe/VBox/Results
@onready var choice_panel: PanelContainer = $ChoicePanel
@onready var choice_list: VBoxContainer = $ChoicePanel/Margin/VBox/Scroll/List
@onready var choice_title: Label = $ChoicePanel/Margin/VBox/Title
@onready var absorb_btn: Button = $BottomBar/BottomMargin/Buttons/AbsorbBtn
@onready var leave_btn: Button = $BottomBar/BottomMargin/Buttons/LeaveBtn

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
	absorb_btn.pressed.connect(_absorb)
	leave_btn.pressed.connect(_leave)

func _leave() -> void:
	GameState.skip_absorb()
	_return_overworld()

func _absorb() -> void:
	absorb_btn.disabled = true
	leave_btn.disabled = true
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
		var new_id := str(result.get("ability_id", ""))
		var new_ab: Dictionary = DataRegistry.get_ability(new_id)
		var new_el = new_ab.get("element", null)
		var new_el_txt := str(new_el).capitalize() if new_el != null else "Neutral"
		choice_title.text = "NEW ATTACK\n%s\nPower %d · %s · %s\nAccuracy %d%%\n\nSlots full — choose an attack to replace, or skip." % [
			new_ab.get("name", new_id),
			int(new_ab.get("power", 0)),
			str(new_ab.get("category", "physical")).capitalize(),
			new_el_txt,
			int(new_ab.get("accuracy", 100))
		]
		# Header comparing current moves
		var header := Label.new()
		header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		header.text = "Your current attacks:"
		choice_list.add_child(header)
		for aid in companion.get("abilities", []):
			var old_ab: Dictionary = DataRegistry.get_ability(str(aid))
			var old_el = old_ab.get("element", null)
			var old_el_txt := str(old_el).capitalize() if old_el != null else "Neutral"
			var btn := Button.new()
			btn.custom_minimum_size = Vector2(0, 56)
			btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			var power_delta := int(new_ab.get("power", 0)) - int(old_ab.get("power", 0))
			var delta_txt := "+%d pwr" % power_delta if power_delta >= 0 else "%d pwr" % power_delta
			btn.text = "Replace %s  (Pwr %d · %s)\n→ with %s  (Pwr %d · %s)  [%s]" % [
				old_ab.get("name", aid),
				int(old_ab.get("power", 0)),
				old_el_txt,
				new_ab.get("name", new_id),
				int(new_ab.get("power", 0)),
				new_el_txt,
				delta_txt
			]
			btn.pressed.connect(_resolve_choice.bind({"replace_ability": str(aid)}))
			choice_list.add_child(btn)
	elif typed == "element":
		choice_title.text = "Element slots full (max 3). Replace one or skip.\nNew element: %s" % str(result.get("element", "?")).capitalize()
		for el in companion.get("elements", []):
			var btn2 := Button.new()
			btn2.custom_minimum_size = Vector2(0, 48)
			btn2.text = "Replace %s" % str(el).capitalize()
			btn2.pressed.connect(_resolve_choice.bind({"replace_element": str(el)}))
			choice_list.add_child(btn2)
	var skip := Button.new()
	skip.custom_minimum_size = Vector2(0, 48)
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
