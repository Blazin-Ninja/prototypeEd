extends Control

const AppTheme = preload("res://scripts/ui/AppTheme.gd")
const DifficultySystem = preload("res://scripts/domain/DifficultySystem.gd")
const RunTimer = preload("res://scripts/util/RunTimer.gd")

@onready var title: Label = $Safe/VBox/Title
@onready var body: Label = $Safe/VBox/Body
@onready var eddie: Label = $Safe/VBox/EddieLine
@onready var retry_btn: Button = $Safe/VBox/RetryBtn
@onready var menu_btn: Button = $Safe/VBox/MenuBtn

func _ready() -> void:
	AppTheme.apply_to(self)
	var report: Dictionary = GameState.last_run_report
	if report.is_empty():
		report = GameState.account.get("last_run_summary", {})
	var won := bool(report.get("won", false))
	var can_retry := not won and (
		bool(report.get("can_retry", false)) or GameState.has_pending_retry_companion()
	)
	title.text = "VICTORY" if won else "BOND LOST"
	AppTheme.style_title(title, 40)
	title.modulate = Color(0.7, 0.95, 0.75) if won else Color(0.95, 0.55, 0.55)
	eddie.visible = not won
	eddie.text = "Do better than Eddie did."
	var loss_blurb := "Your companion reached zero HP.\nThe bond is broken — but the DNA remains."
	if can_retry:
		loss_blurb += "\nStart a new run with the same companion, or return to the menu."
	body.text = "%s\n\nCompanion: %s\nDifficulty: %s\nRun time: %s\nBattles won: %d\nAbsorptions: %d\nRegions cleared: %s\n\nEvolution Tokens earned: +%d\nTotal tokens: %d" % [
		"The hive falls. Humanity endures — for now." if won else loss_blurb,
		report.get("companion_name", "?"),
		DifficultySystem.label(str(report.get("difficulty", GameState.pending_retry_difficulty))),
		str(report.get("run_time", RunTimer.format_run_time(int(report.get("elapsed_ms", 0))))),
		int(report.get("battles_won", 0)),
		int(report.get("absorptions", 0)),
		", ".join(PackedStringArray(report.get("regions_cleared", []))),
		int(report.get("tokens", 0)),
		int(GameState.account.get("evolution_tokens", 0))
	]
	retry_btn.visible = can_retry
	if can_retry:
		var cname := str(report.get("companion_name", "Companion"))
		retry_btn.text = "New Run — Same Companion (%s)" % cname
	retry_btn.pressed.connect(_on_retry)
	menu_btn.pressed.connect(_on_menu)

func _on_retry() -> void:
	if not GameState.start_new_run_from_pending_companion():
		GameState.clear_pending_retry_companion()
		get_tree().change_scene_to_file("res://scenes/menu/MainMenu.tscn")
		return
	get_tree().change_scene_to_file("res://scenes/overworld/Overworld.tscn")

func _on_menu() -> void:
	GameState.clear_pending_retry_companion()
	get_tree().change_scene_to_file("res://scenes/menu/MainMenu.tscn")
