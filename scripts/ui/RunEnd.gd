extends Control

const AppTheme = preload("res://scripts/ui/AppTheme.gd")

@onready var title: Label = $Safe/VBox/Title
@onready var body: Label = $Safe/VBox/Body
@onready var eddie: Label = $Safe/VBox/EddieLine

func _ready() -> void:
	AppTheme.apply_to(self)
	var report: Dictionary = GameState.last_run_report
	if report.is_empty():
		report = GameState.account.get("last_run_summary", {})
	var won := bool(report.get("won", false))
	title.text = "VICTORY" if won else "GAME OVER"
	AppTheme.style_title(title, 40)
	title.modulate = Color(0.7, 0.95, 0.75) if won else Color(0.95, 0.55, 0.55)
	eddie.visible = not won
	eddie.text = "Do better than Eddie did."
	body.text = "%s\n\nCompanion: %s\nBattles won: %d\nAbsorptions: %d\nRegions cleared: %s\n\nEvolution Tokens earned: +%d\nTotal tokens: %d" % [
		"The hive falls. Humanity endures — for now." if won else "Your companion reached zero HP.\nThe run ends. No reloads.",
		report.get("companion_name", "?"),
		int(report.get("battles_won", 0)),
		int(report.get("absorptions", 0)),
		", ".join(PackedStringArray(report.get("regions_cleared", []))),
		int(report.get("tokens", 0)),
		int(GameState.account.get("evolution_tokens", 0))
	]
	$Safe/VBox/MenuBtn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/menu/MainMenu.tscn"))
