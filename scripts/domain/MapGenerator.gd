extends RefCounted
class_name MapGenerator
## Builds a simple Pokémon-style grid: paths, grass, camp, boss tile, walls.

const TILE_EMPTY := 0
const TILE_PATH := 1
const TILE_GRASS := 2
const TILE_WALL := 3
const TILE_CAMP := 4
const TILE_BOSS := 5
const TILE_EXIT := 6

static func generate(region: Dictionary) -> Dictionary:
	var w := int(region.get("map_width", 12))
	var h := int(region.get("map_height", 16))
	var tiles: Array = []
	for y in h:
		var row: Array = []
		for x in w:
			if x == 0 or y == 0 or x == w - 1 or y == h - 1:
				row.append(TILE_WALL)
			else:
				row.append(TILE_GRASS)
		tiles.append(row)

	# Main path from camp (bottom) to boss (top).
	var camp: Dictionary = region.get("camp_cell", {"x": 1, "y": h - 2})
	var boss: Dictionary = region.get("boss_cell", {"x": int(w / 2.0), "y": 1})
	var cx := int(camp.get("x", 1))
	var cy := int(camp.get("y", h - 2))
	var bx := int(boss.get("x", int(w / 2.0)))
	var by := int(boss.get("y", 1))

	# Vertical corridor then horizontal.
	var x := cx
	var y := cy
	while y > by:
		tiles[y][x] = TILE_PATH
		# Side grass already default; carve a wider path occasionally.
		if x + 1 < w - 1:
			tiles[y][x + 1] = TILE_PATH if (y % 3 == 0) else tiles[y][x + 1]
		y -= 1
	while x != bx:
		tiles[y][x] = TILE_PATH
		x += 1 if bx > x else -1
	tiles[by][bx] = TILE_BOSS
	tiles[cy][cx] = TILE_CAMP

	# Exit tile near camp right side if region has next and is cleared later handled in overworld.
	if cx + 2 < w - 1:
		tiles[cy][cx + 2] = TILE_EXIT

	# A few open clearings.
	for i in 5:
		var rx := randi_range(2, w - 3)
		var ry := randi_range(2, h - 3)
		tiles[ry][rx] = TILE_PATH
		tiles[ry][mini(rx + 1, w - 2)] = TILE_PATH

	return {
		"width": w,
		"height": h,
		"tiles": tiles,
		"camp": Vector2i(cx, cy),
		"boss": Vector2i(bx, by)
	}

static func is_walkable(tile: int) -> bool:
	return tile != TILE_WALL

static func tile_name(tile: int) -> String:
	match tile:
		TILE_PATH: return "path"
		TILE_GRASS: return "grass"
		TILE_WALL: return "wall"
		TILE_CAMP: return "camp"
		TILE_BOSS: return "boss"
		TILE_EXIT: return "exit"
		_: return "empty"
