extends RefCounted
class_name BossSprites
## Loads and draws name-matched boss sprites.

const BOSS_DIR := "res://assets/bosses/"
static var _cache: Dictionary = {}
static var _loaded := false

static func ensure_loaded() -> void:
	if _loaded:
		return
	for id in ["elder_treant", "solar_colossus", "glacier_titan", "prime_chimera", "hive_heart"]:
		var path: String = BOSS_DIR + id + ".png"
		if ResourceLoader.exists(path):
			_cache[id] = load(path)
	_loaded = true

static func has_sprite(creature: Dictionary) -> bool:
	ensure_loaded()
	var tid := str(creature.get("template_id", creature.get("id", "")))
	return _cache.has(tid)

static func draw(canvas: CanvasItem, creature: Dictionary, center: Vector2, radius: float, pulse: float = 0.0) -> bool:
	ensure_loaded()
	var tid := str(creature.get("template_id", creature.get("id", "")))
	if not _cache.has(tid):
		return false
	var tex: Texture2D = _cache[tid]
	var scale_boost := 1.0 + 0.04 * sin(pulse)
	var size := Vector2(radius * 2.4, radius * 2.4) * scale_boost
	# Glow ring matching boss theme
	var glow := _theme_color(tid)
	glow.a = 0.28
	canvas.draw_circle(center + Vector2(0, radius * 0.15), radius * 1.35 * scale_boost, glow)
	glow.a = 0.5
	canvas.draw_arc(center, radius * 1.45 * scale_boost, 0.0, TAU, 40, glow, 3.0, true)
	var dst := Rect2(center - size * 0.5, size)
	canvas.draw_texture_rect(tex, dst, false)
	# Nameplate slash under sprite
	canvas.draw_rect(Rect2(center + Vector2(-radius * 1.1, radius * 1.15), Vector2(radius * 2.2, 4)), Color(glow.r, glow.g, glow.b, 0.55))
	return true

static func _theme_color(tid: String) -> Color:
	match tid:
		"elder_treant":
			return Color(0.25, 0.7, 0.35)
		"solar_colossus":
			return Color(1.0, 0.65, 0.15)
		"glacier_titan":
			return Color(0.45, 0.8, 0.95)
		"prime_chimera":
			return Color(0.7, 0.25, 0.9)
		"hive_heart":
			return Color(0.95, 0.2, 0.45)
		_:
			return Color(0.8, 0.3, 0.3)
