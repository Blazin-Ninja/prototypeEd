extends Control
class_name VirtualJoystick
## Touch / mouse virtual joystick. Outputs a Vector2 in [-1, 1].

signal direction_changed(direction: Vector2)

@export var deadzone: float = 0.12
@export var knob_ratio: float = 0.38

var direction: Vector2 = Vector2.ZERO
var _active := false
var _touch_index := -1
var _knob_offset: Vector2 = Vector2.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed and not _active:
			_active = true
			_touch_index = st.index
			_update_from_local(st.position)
			accept_event()
		elif not st.pressed and _active and st.index == _touch_index:
			_release()
			accept_event()
	elif event is InputEventScreenDrag and _active:
		var sd := event as InputEventScreenDrag
		if sd.index == _touch_index:
			_update_from_local(sd.position)
			accept_event()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and not _active:
				_active = true
				_touch_index = -1
				_update_from_local(mb.position)
				accept_event()
			elif not mb.pressed and _active and _touch_index == -1:
				_release()
				accept_event()
	elif event is InputEventMouseMotion and _active and _touch_index == -1:
		var mm := event as InputEventMouseMotion
		if mm.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_update_from_local(mm.position)
			accept_event()

func _update_from_local(local_pos: Vector2) -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.5 * 0.92
	var delta := local_pos - center
	if delta.length() > radius:
		delta = delta.normalized() * radius
	_knob_offset = delta
	var raw := Vector2.ZERO
	if radius > 0.0:
		raw = delta / radius
	if raw.length() < deadzone:
		direction = Vector2.ZERO
	else:
		# Rescale so leaving deadzone maps smoothly to full range.
		var len := (raw.length() - deadzone) / (1.0 - deadzone)
		direction = raw.normalized() * clampf(len, 0.0, 1.0)
	direction_changed.emit(direction)
	queue_redraw()

func _release() -> void:
	_active = false
	_touch_index = -1
	_knob_offset = Vector2.ZERO
	direction = Vector2.ZERO
	direction_changed.emit(direction)
	queue_redraw()

func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.5
	# Base ring
	draw_circle(center, radius * 0.92, Color(0.12, 0.16, 0.15, 0.55))
	draw_arc(center, radius * 0.92, 0.0, TAU, 48, Color(0.75, 0.85, 0.8, 0.35), 3.0, true)
	# Inner guide
	draw_arc(center, radius * deadzone, 0.0, TAU, 24, Color(1, 1, 1, 0.12), 2.0, true)
	# Knob
	var knob_r := radius * knob_ratio
	var knob_pos := center + _knob_offset
	draw_circle(knob_pos, knob_r, Color(0.88, 0.94, 0.9, 0.9 if _active else 0.7))
	draw_arc(knob_pos, knob_r, 0.0, TAU, 32, Color(1, 1, 1, 0.35), 2.0, true)
