extends Control
class_name MapCanvas
## Owns the overworld draw pass so entities always paint inside a real _draw().

var paint: Callable

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()

func _draw() -> void:
	if paint.is_valid():
		paint.call(self)
