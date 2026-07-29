extends RefCounted
class_name PlayerAvatar
## Draws the human trainer + companion perched on the shoulder.

const SHEET_PATH := "res://assets/player/human_walk.png"
const SHEET_X2_PATH := "res://assets/player/human_walk_x2.png"
const FRAME := 48
const DIRS := ["down", "left", "right", "up"]

static var _sheet: Texture2D = null
static var _frame_px := 48
static var _ready := false

static func ensure_loaded() -> void:
	if _ready:
		return
	if ResourceLoader.exists(SHEET_X2_PATH):
		_sheet = load(SHEET_X2_PATH) as Texture2D
		_frame_px = 96
	elif ResourceLoader.exists(SHEET_PATH):
		_sheet = load(SHEET_PATH) as Texture2D
		_frame_px = FRAME
	_ready = true

static func facing_from_vector(v: Vector2) -> String:
	if v.length() < 0.01:
		return "down"
	if absf(v.x) > absf(v.y):
		return "right" if v.x > 0.0 else "left"
	return "down" if v.y > 0.0 else "up"

static func draw(
	canvas: CanvasItem,
	center: Vector2,
	scale: float,
	companion: Dictionary,
	facing: String,
	walk_phase: float,
	moving: bool
) -> void:
	ensure_loaded()
	var dir := facing if facing in DIRS else "down"
	var frame := 0
	if moving:
		frame = int(floor(walk_phase)) % 4
		if frame < 0:
			frame = 0
	else:
		frame = 0

	var draw_scale := scale
	# Display size stays based on the logical 48px frame so scale feels consistent.
	var human_size := Vector2(FRAME, FRAME) * draw_scale

	canvas.draw_circle(center + Vector2(0, human_size.y * 0.42), human_size.x * 0.22, Color(0, 0, 0, 0.28))
	_draw_ability_aura(canvas, center, human_size.x * 0.55, companion, walk_phase)

	# When facing away, perch companion first so it sits behind the trainer.
	if dir == "up":
		_draw_shoulder_companion(canvas, center, human_size, companion, dir, walk_phase, moving)

	if _sheet != null:
		var row := DIRS.find(dir)
		var src := Rect2(frame * _frame_px, row * _frame_px, _frame_px, _frame_px)
		var dst := Rect2(center - human_size * 0.5 + Vector2(0, human_size.y * 0.05), human_size)
		canvas.draw_texture_rect_region(_sheet, dst, src)
	else:
		_draw_fallback_human(canvas, center, human_size.x * 0.5, dir, frame)

	if dir != "up":
		_draw_shoulder_companion(canvas, center, human_size, companion, dir, walk_phase, moving)

static func _draw_ability_aura(canvas: CanvasItem, center: Vector2, radius: float, companion: Dictionary, phase: float) -> void:
	var els: Array = companion.get("elements", [])
	if els.is_empty() and companion.get("abilities", []):
		# Infer from first ability element if any.
		var ab: Dictionary = DataRegistry.get_ability(str(companion.get("abilities", [])[0]))
		if ab.get("element", null) != null:
			els = [ab.get("element")]
	var col := Color(0.4, 0.7, 0.9, 0.18)
	if not els.is_empty():
		var eid := str(els[0])
		var edef: Dictionary = DataRegistry.elements.get(eid, {})
		if edef.has("color"):
			col = Color.html(str(edef["color"]))
			col.a = 0.22
	var pulse := 1.0 + 0.08 * sin(phase * 0.9)
	canvas.draw_circle(center + Vector2(0, radius * 0.1), radius * pulse, col)
	# Ability motif particles near feet/shoulders
	_draw_ability_motifs(canvas, center, radius, companion, phase)

static func _draw_ability_motifs(canvas: CanvasItem, center: Vector2, radius: float, companion: Dictionary, phase: float) -> void:
	var abs: Array = companion.get("abilities", [])
	for i in mini(abs.size(), 3):
		var ab: Dictionary = DataRegistry.get_ability(str(abs[i]))
		var el = ab.get("element", null)
		var c := Color(0.9, 0.9, 0.9, 0.55)
		if el != null and DataRegistry.elements.has(str(el)):
			c = Color.html(str(DataRegistry.elements[str(el)].get("color", "#ffffff")))
			c.a = 0.65
		var ang := phase * 0.7 + float(i) * TAU / 3.0
		var p := center + Vector2(cos(ang), sin(ang) * 0.55) * radius * 0.85 + Vector2(0, -radius * 0.1)
		match str(ab.get("category", "physical")):
			"special":
				canvas.draw_circle(p, radius * 0.08, c)
			_:
				canvas.draw_colored_polygon(PackedVector2Array([
					p + Vector2(0, -radius * 0.1),
					p + Vector2(radius * 0.08, radius * 0.06),
					p + Vector2(-radius * 0.08, radius * 0.06)
				]), c)

static func _draw_shoulder_companion(
	canvas: CanvasItem,
	center: Vector2,
	human_size: Vector2,
	companion: Dictionary,
	dir: String,
	phase: float,
	moving: bool
) -> void:
	if companion.is_empty():
		return
	var bob := sin(phase * 1.3) * (2.2 if moving else 1.0)
	var shoulder := Vector2.ZERO
	var companion_r := human_size.x * 0.28
	# Layer order: when facing up, companion is behind (drawn before human already handled by skip)
	# We draw companion after human for down/left/right; for up draw slightly behind shoulder.
	match dir:
		"left":
			shoulder = center + Vector2(-human_size.x * 0.18, -human_size.y * 0.28) + Vector2(0, bob)
		"right":
			shoulder = center + Vector2(human_size.x * 0.20, -human_size.y * 0.28) + Vector2(0, bob)
		"up":
			shoulder = center + Vector2(human_size.x * 0.14, -human_size.y * 0.30) + Vector2(0, bob)
		_:
			shoulder = center + Vector2(human_size.x * 0.22, -human_size.y * 0.26) + Vector2(0, bob)

	# Tiny perch shadow on shoulder
	canvas.draw_circle(shoulder + Vector2(0, companion_r * 0.55), companion_r * 0.35, Color(0, 0, 0, 0.2))
	PlaceholderArt.draw_creature(canvas, companion, shoulder, companion_r)

	# Ability-colored collar glow under companion
	var els: Array = companion.get("elements", [])
	if not els.is_empty():
		var ec := Color.html(str(DataRegistry.elements.get(str(els[0]), {}).get("color", "#ffffff")))
		ec.a = 0.35
		canvas.draw_arc(shoulder, companion_r * 1.15, 0.0, TAU, 20, ec, 2.0, true)

static func _draw_fallback_human(canvas: CanvasItem, center: Vector2, radius: float, dir: String, frame: int) -> void:
	var bob := -1.0 if frame in [1, 3] else 0.0
	var c := center + Vector2(0, bob)
	canvas.draw_circle(c + Vector2(0, radius * 0.85), radius * 0.35, Color(0, 0, 0, 0.2))
	# legs
	var swing := 0.0
	if frame == 1:
		swing = -3.0
	elif frame == 3:
		swing = 3.0
	canvas.draw_rect(Rect2(c + Vector2(-radius * 0.25 + swing * 0.15, radius * 0.15), Vector2(radius * 0.2, radius * 0.55)), Color(0.2, 0.22, 0.3))
	canvas.draw_rect(Rect2(c + Vector2(radius * 0.05 - swing * 0.15, radius * 0.15), Vector2(radius * 0.2, radius * 0.55)), Color(0.2, 0.22, 0.3))
	# torso
	canvas.draw_rect(Rect2(c + Vector2(-radius * 0.35, -radius * 0.15), Vector2(radius * 0.7, radius * 0.55)), Color(0.25, 0.45, 0.55))
	# head
	canvas.draw_circle(c + Vector2(0, -radius * 0.45), radius * 0.32, Color(0.9, 0.74, 0.58))
	canvas.draw_circle(c + Vector2(0, -radius * 0.55), radius * 0.28, Color(0.2, 0.14, 0.1))
	if dir != "up":
		var eye_x := 0.0
		if dir == "left":
			eye_x = -0.12
		elif dir == "right":
			eye_x = 0.12
		canvas.draw_circle(c + Vector2((-0.1 + eye_x) * radius, -radius * 0.45), radius * 0.05, Color(0.1, 0.1, 0.12))
		canvas.draw_circle(c + Vector2((0.1 + eye_x) * radius, -radius * 0.45), radius * 0.05, Color(0.1, 0.1, 0.12))
