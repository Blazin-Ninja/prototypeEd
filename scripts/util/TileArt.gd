extends RefCounted
class_name TileArt
## Phase B overworld tile textures with region tinting + simple anim frames.

const MapGenerator = preload("res://scripts/domain/MapGenerator.gd")
const TILE_SIZE := 48

static var _cache: Dictionary = {}
static var _anim: Dictionary = {}

static func draw_tile(
	ci: CanvasItem,
	tile: int,
	rect: Rect2,
	grass_tint: Color,
	path_tint: Color,
	ambient_t: float,
	obelisk_tint: Color = Color(1, 1, 1, 1)
) -> void:
	match tile:
		MapGenerator.TILE_GRASS:
			_blit(ci, "grass", rect, grass_tint)
		MapGenerator.TILE_PATH:
			_blit(ci, "path", rect, path_tint)
		MapGenerator.TILE_WALL:
			_blit(ci, "wall", rect, Color(1, 1, 1, 1))
		MapGenerator.TILE_ROCK:
			# Rock sits on grass/path base.
			_blit(ci, "grass", rect, grass_tint)
			_blit(ci, "rock", rect, Color(1, 1, 1, 1))
		MapGenerator.TILE_BRIDGE:
			_blit(ci, "bridge", rect, Color(1, 1, 1, 1))
		MapGenerator.TILE_CAMP:
			_blit(ci, "camp", rect, Color(1, 1, 1, 1))
		MapGenerator.TILE_EXIT:
			_blit(ci, "exit", rect, Color(1, 1, 1, 1))
		MapGenerator.TILE_BOSS:
			_blit(ci, "boss", rect, Color(1, 1, 1, 1))
		MapGenerator.TILE_OBELISK:
			_blit(ci, "path", rect, path_tint)
			_blit(ci, "obelisk", rect, obelisk_tint)
		MapGenerator.TILE_WATER:
			_blit(ci, _frame("water", ambient_t, 3.0), rect, Color(1, 1, 1, 1))
		MapGenerator.TILE_LAVA:
			_blit(ci, _frame("lava", ambient_t, 4.0), rect, Color(1, 1, 1, 1))
		MapGenerator.TILE_VOID:
			_blit(ci, _frame("void", ambient_t, 2.2), rect, Color(1, 1, 1, 1))
		MapGenerator.TILE_EMPTY:
			_blit(ci, "empty", rect, Color(1, 1, 1, 1))
		_:
			ci.draw_rect(rect, Color(0.1, 0.12, 0.11, 1))

static func _frame(prefix: String, ambient_t: float, speed: float) -> String:
	var idx := int(floor(ambient_t * speed)) % 4
	return "%s_%d" % [prefix, idx]

static func _blit(ci: CanvasItem, key: String, rect: Rect2, modulate: Color) -> void:
	var tex := _tex(key)
	if tex == null:
		ci.draw_rect(rect, modulate)
		return
	ci.draw_texture_rect(tex, rect, false, modulate)

static func _tex(key: String) -> Texture2D:
	if _cache.has(key):
		return _cache[key]
	var path := "res://assets/tiles/%s.png" % key
	if not ResourceLoader.exists(path):
		_cache[key] = null
		return null
	var tex = load(path)
	if tex is Texture2D:
		_cache[key] = tex
		return tex
	_cache[key] = null
	return null
