extends RefCounted
class_name TileArt
## Ultra terrain tiles — high-res variants + biome props.

const MapGenerator = preload("res://scripts/domain/MapGenerator.gd")
const TILE_SIZE := 256

static var _cache: Dictionary = {}

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
	var v := _variant(cell)
	match tile:
		MapGenerator.TILE_GRASS:
			_blit(ci, _pick(["grass", "grass_1", "grass_2", "grass_3"], v), rect, grass_tint)
			_maybe_blit_prop(ci, rect, biome, cell, true)
		MapGenerator.TILE_PATH:
			_blit(ci, _pick(["path", "path_1", "path_2"], v), rect, path_tint)
			if biome == "desert" and _prop_seed(cell, 17) % 5 == 0:
				_blit(ci, _pick(["dune", "dune_1", "dune_2"], v), rect, Color(1, 1, 1, 0.88))
		MapGenerator.TILE_WALL:
			_blit(ci, _pick(["cliff", "cliff_1", "cliff_2"], v), rect, Color(1, 1, 1, 1))
		MapGenerator.TILE_ROCK:
			_blit(ci, _pick(["grass", "grass_1", "grass_2"], v), rect, grass_tint)
			_blit(ci, _pick(["rock", "rock_1"], v), rect, Color(1, 1, 1, 1))
			if _prop_seed(cell, 3) % 2 == 0:
				_blit(ci, _pick(["cliff", "cliff_1"], v), rect, Color(1, 1, 1, 0.5))
		MapGenerator.TILE_BRIDGE:
			_blit(ci, "bridge", rect, Color(1, 1, 1, 1))
		MapGenerator.TILE_CAMP:
			_blit(ci, "camp", rect, Color(1, 1, 1, 1))
		MapGenerator.TILE_EXIT:
			_blit(ci, "exit", rect, Color(1, 1, 1, 1))
		MapGenerator.TILE_BOSS:
			_blit(ci, "boss", rect, Color(1, 1, 1, 1))
		MapGenerator.TILE_OBELISK:
			_blit(ci, _pick(["path", "path_1", "path_2"], v), rect, path_tint)
			_blit(ci, "obelisk", rect, obelisk_tint)
		MapGenerator.TILE_WATER:
			_blit(ci, _frame("water", ambient_t, 2.6), rect, Color(1, 1, 1, 1))
		MapGenerator.TILE_LAVA:
			_blit(ci, _frame("lava", ambient_t, 3.4), rect, Color(1, 1, 1, 1))
		MapGenerator.TILE_VOID:
			_blit(ci, _frame("void", ambient_t, 2.0), rect, Color(1, 1, 1, 1))
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
	var v := _variant(cell)
	match biome:
		"desert":
			_blit(ci, _pick(["dune", "dune_1", "dune_2"], v), rect, Color(1, 1, 1, 1))
		"frozen_mountains":
			_blit(ci, _pick(["cliff", "cliff_1", "cliff_2"], v), rect, Color(0.88, 0.94, 1.0, 1.0))
		"alien_lab", "meteor_hive":
			_blit(ci, "empty", rect, Color(0.78, 0.55, 0.95, 1.0))
			if _prop_seed(cell, 9) % 2 == 0:
				_blit(ci, _pick(["tree", "tree_1", "tree_2", "tree_3"], v), rect, Color(0.72, 0.48, 0.95, 0.8))
		_:
			_blit(ci, "empty", rect, grass_tint)
			_blit(ci, _pick(["tree", "tree_1", "tree_2", "tree_3"], v), rect, Color(1, 1, 1, 1))

static func _maybe_blit_prop(
	ci: CanvasItem,
	rect: Rect2,
	biome: String,
	cell: Vector2i,
	on_grass: bool
) -> void:
	var roll := _prop_seed(cell, 41) % 10
	var v := _variant(cell)
	match biome:
		"desert":
			if roll < 5:
				_blit(ci, _pick(["dune", "dune_1", "dune_2"], v), rect, Color(1, 1, 1, 0.92))
		"frozen_mountains":
			if roll < 4:
				_blit(ci, _pick(["cliff", "cliff_1", "cliff_2"], v), rect, Color(0.92, 0.96, 1.0, 0.72))
		"forest":
			if on_grass and roll < 5:
				_blit(ci, _pick(["tree", "tree_1", "tree_2", "tree_3"], v), rect, Color(1, 1, 1, 1.0))
		_:
			if on_grass and roll < 2:
				_blit(ci, _pick(["tree", "tree_1"], v), rect, Color(1, 1, 1, 0.75))

static func _pick(keys: Array, variant: int) -> String:
	if keys.is_empty():
		return "grass"
	return str(keys[variant % keys.size()])

static func _variant(cell: Vector2i) -> int:
	return _prop_seed(cell, 91) % 4

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
