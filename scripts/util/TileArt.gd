extends RefCounted
class_name TileArt
## Phase B overworld tile textures with region tinting + biome props.

const MapGenerator = preload("res://scripts/domain/MapGenerator.gd")
const TILE_SIZE := 83 ## ~64 * 1.3 source resolution

static var _cache: Dictionary = {}
static var _anim: Dictionary = {}

static func draw_tile(
	ci: CanvasItem,
	tile: int,
	rect: Rect2,
	grass_tint: Color,
	path_tint: Color,
	ambient_t: float,
	obelisk_tint: Color = Color(1, 1, 1, 1),
	biome: String = "forest",
	cell: Vector2i = Vector2i.ZERO
) -> void:
	match tile:
		MapGenerator.TILE_GRASS:
			_blit(ci, "grass", rect, grass_tint)
			_maybe_blit_prop(ci, rect, biome, cell, true)
		MapGenerator.TILE_PATH:
			_blit(ci, "path", rect, path_tint)
			if biome == "desert" and _prop_seed(cell, 17) % 7 == 0:
				_blit(ci, "dune", rect, Color(1, 1, 1, 0.85))
		MapGenerator.TILE_WALL:
			_blit(ci, "cliff", rect, Color(1, 1, 1, 1))
		MapGenerator.TILE_ROCK:
			# Rock sits on grass/path base with a small cliff shelf.
			_blit(ci, "grass", rect, grass_tint)
			_blit(ci, "rock", rect, Color(1, 1, 1, 1))
			if _prop_seed(cell, 3) % 2 == 0:
				_blit(ci, "cliff", rect, Color(1, 1, 1, 0.55))
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
			_blit_empty_biome(ci, rect, grass_tint, biome, cell)
		_:
			ci.draw_rect(rect, Color(0.1, 0.12, 0.11, 1))

static func _blit_empty_biome(
	ci: CanvasItem,
	rect: Rect2,
	grass_tint: Color,
	biome: String,
	cell: Vector2i
) -> void:
	match biome:
		"desert":
			_blit(ci, "dune", rect, Color(1, 1, 1, 1))
		"frozen_mountains":
			_blit(ci, "cliff", rect, Color(0.85, 0.92, 1.0, 1.0))
		"alien_lab", "meteor_hive":
			_blit(ci, "empty", rect, Color(0.75, 0.55, 0.95, 1.0))
			if _prop_seed(cell, 9) % 3 == 0:
				_blit(ci, "tree", rect, Color(0.7, 0.45, 0.95, 0.75))
		_:
			# Forest / default: dense trees over underbrush.
			_blit(ci, "empty", rect, grass_tint)
			_blit(ci, "tree", rect, Color(1, 1, 1, 1))

static func _maybe_blit_prop(
	ci: CanvasItem,
	rect: Rect2,
	biome: String,
	cell: Vector2i,
	on_grass: bool
) -> void:
	var roll := _prop_seed(cell, 41) % 10
	match biome:
		"desert":
			if roll < 4:
				_blit(ci, "dune", rect, Color(1, 1, 1, 0.9))
		"frozen_mountains":
			if roll < 3:
				_blit(ci, "cliff", rect, Color(0.9, 0.95, 1.0, 0.7))
		"forest":
			if on_grass and roll < 2:
				_blit(ci, "tree", rect, Color(1, 1, 1, 0.85))
		_:
			if on_grass and roll == 0:
				_blit(ci, "tree", rect, Color(1, 1, 1, 0.7))

static func _prop_seed(cell: Vector2i, salt: int) -> int:
	return absi(cell.x * 73856093 ^ cell.y * 19349663 ^ salt)

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
