extends Control
## Boot splash → main menu.

@onready var label: Label = $Center/VBox/Label
@onready var sub: Label = $Center/VBox/Sub

func _ready() -> void:
	label.text = "CHIMERA BOND"
	sub.text = "One companion. Endless mutation."
	await get_tree().create_timer(1.2).timeout
	get_tree().change_scene_to_file("res://scenes/menu/MainMenu.tscn")
