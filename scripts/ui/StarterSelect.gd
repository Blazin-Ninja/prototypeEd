extends Control

const AppTheme = preload("res://scripts/ui/AppTheme.gd")
const DifficultySystem = preload("res://scripts/domain/DifficultySystem.gd")
const RunTimer = preload("res://scripts/util/RunTimer.gd")

@onready var list: VBoxContainer = $Safe/VBox/Scroll/List
@onready var detail: Label = $Safe/VBox/Detail
@onready var preview: Control = $Safe/VBox/Preview
@onready var confirm_btn: Button = $Safe/VBox/ConfirmBtn
@onready var diff_hint: Label = $Safe/VBox/DiffHint
@onready var fastest_label: Label = $Safe/VBox/FastestLabel
@onready var easy_btn: Button = $Safe/VBox/DiffRow/EasyBtn
@onready var normal_btn: Button = $Safe/VBox/DiffRow/NormalBtn
@onready var hard_btn: Button = $Safe/VBox/DiffRow/HardBtn

var _selected: String = ""
var _difficulty: String = DifficultySystem.ID_NORMAL
var _preview_creature: Dictionary = {}
var _preview_t := 0.0
var _diff_buttons: Dictionary = {}

func _ready() -> void:
	AppTheme.apply_to(self)
	PlayerAvatar.ensure_loaded()
	confirm_btn.disabled = true
	confirm_btn.pressed.connect(_confirm)
	$Safe/VBox/BackBtn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/menu/MainMenu.tscn"))
	_diff_buttons = {
		DifficultySystem.ID_EASY: easy_btn,
		DifficultySystem.ID_NORMAL: normal_btn,
		DifficultySystem.ID_HARD: hard_btn
	}
	easy_btn.pressed.connect(_set_difficulty.bind(DifficultySystem.ID_EASY))
	normal_btn.pressed.connect(_set_difficulty.bind(DifficultySystem.ID_NORMAL))
	hard_btn.pressed.connect(_set_difficulty.bind(DifficultySystem.ID_HARD))
	_set_difficulty(GameState.get_preferred_difficulty())
	_build_list()
	preview.draw.connect(_on_preview_draw)

func _process(delta: float) -> void:
	_preview_t += delta * 6.0
	if not _preview_creature.is_empty():
		preview.queue_redraw()

func _set_difficulty(diff_id: String) -> void:
	_difficulty = DifficultySystem.normalize(diff_id)
	for id in _diff_buttons.keys():
		var btn: Button = _diff_buttons[id]
		btn.set_pressed_no_signal(id == _difficulty)
	diff_hint.text = "%s — %s" % [
		DifficultySystem.label(_difficulty),
		DifficultySystem.description(_difficulty)
	]
	fastest_label.text = RunTimer.format_board_lines(GameState.account, _difficulty)
	GameState.set_preferred_difficulty(_difficulty)

func _build_list() -> void:
	for c in list.get_children():
		c.queue_free()
	var available := GameState.available_starters()
	# Show all starters; locked ones disabled with unlock hint.
	for sid in DataRegistry.get_starters():
		var template: Dictionary = DataRegistry.get_creature(str(sid))
		var unlocked := available.has(sid)
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(0, 52)
		var els: Array = template.get("elements", [])
		var el_txt := ", ".join(PackedStringArray(els))
		btn.text = "%s [%s]" % [template.get("name", sid), el_txt.capitalize()]
		if not unlocked:
			btn.text += "  (Locked)"
			btn.disabled = true
		btn.pressed.connect(_select.bind(str(sid)))
		list.add_child(btn)
	# Auto-select first available
	if not available.is_empty():
		_select(str(available[0]))

func _select(starter_id: String) -> void:
	_selected = starter_id
	confirm_btn.disabled = false
	var t: Dictionary = DataRegistry.get_creature(starter_id)
	var stats: Dictionary = t.get("base_stats", {})
	detail.text = "%s\n%s\nHP %d  ATK %d  DEF %d  SPD %d\nSpA %d  SpD %d\nAbilities: %s" % [
		t.get("name"),
		t.get("description"),
		stats.get("hp"), stats.get("attack"), stats.get("defense"), stats.get("speed"),
		stats.get("special_attack"), stats.get("special_defense"),
		", ".join(PackedStringArray(t.get("abilities", [])))
	]
	_preview_creature = {
		"id": starter_id,
		"template_id": starter_id,
		"name": t.get("name"),
		"color": t.get("color"),
		"shape": t.get("shape"),
		"elements": t.get("elements", []),
		"abilities": t.get("abilities", []),
		"mutations": [],
		"is_alpha": false,
		"is_boss": false
	}
	preview.queue_redraw()

func _on_preview_draw() -> void:
	if _preview_creature.is_empty():
		return
	var s := minf(preview.size.x, preview.size.y) / 48.0 * 0.95
	PlayerAvatar.draw(preview, preview.size * 0.5, s, _preview_creature, "down", _preview_t, true)

func _confirm() -> void:
	if _selected == "":
		return
	GameState.start_new_run(_selected, _difficulty)
	get_tree().change_scene_to_file("res://scenes/overworld/Overworld.tscn")
