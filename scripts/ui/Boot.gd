extends Control
## Boot splash → main menu.

const AppTheme = preload("res://scripts/ui/AppTheme.gd")

@onready var label: Label = $Center/VBox/Label
@onready var sub: Label = $Center/VBox/Sub
@onready var logo: TextureRect = $Center/VBox/Logo

func _ready() -> void:
	AppTheme.apply_to(self)
	if has_node("BG") and $BG is TextureRect:
		pass
	elif has_node("BG") and $BG is ColorRect:
		($BG as ColorRect).color = AppTheme.COL_BG
	AppTheme.style_title(label, 44)
	AppTheme.style_muted(sub, 17)
	label.text = "CHIMERA BOND"
	sub.text = "One companion. Endless mutation."
	if logo != null and ResourceLoader.exists("res://assets/icons/icon_512.png"):
		logo.texture = load("res://assets/icons/icon_512.png")
		logo.visible = true
	# Soft fade-in presence.
	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.45)
	await get_tree().create_timer(1.55).timeout
	var tw2 := create_tween()
	tw2.tween_property(self, "modulate:a", 0.0, 0.25)
	await tw2.finished
	get_tree().change_scene_to_file("res://scenes/menu/MainMenu.tscn")
