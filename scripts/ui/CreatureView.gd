extends Control
## Draws a placeholder creature; set `creature` and queue_redraw.

var creature: Dictionary = {}

func _draw() -> void:
	if creature.is_empty():
		return
	var r := minf(size.x, size.y) * 0.38
	PlaceholderArt.draw_creature(self, creature, size * 0.5, r)
