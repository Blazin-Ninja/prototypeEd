extends RefCounted
class_name BattleArt
## Region battle arenas + attack FX textures.

const ARENA_DIR := "res://assets/arenas/"
const FX_DIR := "res://assets/fx/"

static var _arena: Dictionary = {}
static var _fx: Dictionary = {}
static var _loaded := false

static func ensure_loaded() -> void:
	if _loaded:
		return
	for id in ["forest", "desert", "frozen_mountains", "alien_lab", "meteor_hive"]:
		var path: String = ARENA_DIR + id + ".png"
		if ResourceLoader.exists(path):
			_arena[id] = load(path)
	for key in ["slash", "bolt", "impact", "miss"]:
		var fpath: String = FX_DIR + key + ".png"
		if ResourceLoader.exists(fpath):
			_fx[key] = load(fpath)
	_loaded = true

static func arena_for_region(region_id: String) -> Texture2D:
	ensure_loaded()
	if _arena.has(region_id):
		return _arena[region_id]
	return _arena.get("forest", null)

static func fx(key: String) -> Texture2D:
	ensure_loaded()
	return _fx.get(key, null)
