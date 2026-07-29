extends Control

const AppTheme = preload("res://scripts/ui/AppTheme.gd")

@onready var list: VBoxContainer = $Safe/VBox/Scroll/List
@onready var detail: Label = $Safe/VBox/Detail
@onready var preview: Control = $Safe/VBox/Preview
@onready var confirm_btn: Button = $Safe/VBox/ConfirmBtn

var _selected: String = ""
var _preview_creature: Dictionary = {}
var _preview_t := 0.0

func _ready() -> void:
	AppTheme.apply_to(self)
	PlayerAvatar.ensure_loaded()
	confirm_btn.disabled = true
	confirm_btn.pressed.connect(_confirm)
	$Safe/VBox/BackBtn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/menu/MainMenu.tscn"))
	_build_list()
	preview.draw.connect(_on_preview_draw)

func _process(delta: float) -> void:
	_preview_t += delta * 6.0
	if not _preview_creature.is_empty():
		preview.queue_redraw()

func _build_list() -> void:
	for c in list.get_children():
		c.queue_free()
	var available := GameState.available_starters()
	# Show all 5 starters; locked ones disabled with unlock hint.
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
	GameState.start_new_run(_selected)
	get_tree().change_scene_to_file("res://scenes/overworld/Overworld.tscn")
