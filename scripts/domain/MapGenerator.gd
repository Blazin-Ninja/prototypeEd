extends RefCounted
class_name MapGenerator
## Dungeon-style floors: sparse rooms, walkways/bridges over hazards.

const TILE_EMPTY := 0
const TILE_PATH := 1
const TILE_GRASS := 2
const TILE_WALL := 3
const TILE_CAMP := 4
const TILE_BOSS := 5
const TILE_EXIT := 6
const TILE_LAVA := 7
const TILE_WATER := 8
const TILE_VOID := 9
const TILE_BRIDGE := 10
const TILE_ROCK := 11
const TILE_CHEST := 12

static func generate(region: Dictionary) -> Dictionary:
	var w := int(region.get("map_width", 36))
	var h := int(region.get("map_height", 48))
	w = maxi(w, 24)
	h = maxi(h, 28)
	var hazard := _hazard_tile(str(region.get("hazard", "lava")))
	var tiles: Array = _filled_grid(w, h, hazard)
	_paint_border(tiles, w, h, TILE_WALL)

	var rooms: Array = _place_rooms(region, w, h)
	# Carve room interiors as grass clearings (wild habitats).
	for room in rooms:
		_fill_rect(tiles, room, TILE_GRASS, w, h)

	# Connect rooms with walkways; cross hazards as bridges.
	_connect_rooms(tiles, rooms, w, h, hazard)

	# Sprinkle rocks in some grass for cover / winding feel.
	_scatter_rocks(tiles, rooms, w, h)

	var camp_room: Dictionary = rooms[0]
	var boss_room: Dictionary = rooms[rooms.size() - 1]
	var cx := int(camp_room.cx)
	var cy := int(camp_room.cy)
	var bx := int(boss_room.cx)
	var by := int(boss_room.cy)

	# Widen camp / boss pads as path so wilds don't sit on markers.
	_fill_rect(tiles, {
		"x": cx - 1, "y": cy - 1, "w": 3, "h": 3
	}, TILE_PATH, w, h)
	_fill_rect(tiles, {
		"x": bx - 1, "y": by - 1, "w": 3, "h": 3
	}, TILE_PATH, w, h)

	tiles[cy][cx] = TILE_CAMP
	tiles[by][bx] = TILE_BOSS

	# Exit near camp (travel hub).
	var ex := mini(cx + 2, w - 2)
	var ey := cy
	if int(tiles[ey][ex]) == TILE_WALL:
		ex = maxi(cx - 2, 1)
	tiles[ey][ex] = TILE_EXIT

	# Ensure camp/boss reachable: carve a guaranteed spine if needed.
	_ensure_path(tiles, Vector2i(cx, cy), Vector2i(bx, by), w, h, hazard)

	var chests: Array = _place_chests(tiles, region, Vector2i(cx, cy), Vector2i(bx, by), w, h)

	return {
		"width": w,
		"height": h,
		"tiles": tiles,
		"camp": Vector2i(cx, cy),
		"boss": Vector2i(bx, by),
		"exit": Vector2i(ex, ey),
		"rooms": rooms,
		"hazard": hazard,
		"chests": chests
	}

static func is_walkable(tile: int) -> bool:
	match tile:
		TILE_WALL, TILE_LAVA, TILE_WATER, TILE_VOID, TILE_ROCK, TILE_EMPTY:
			return false
		_:
			return true

static func is_hazard(tile: int) -> bool:
	return tile == TILE_LAVA or tile == TILE_WATER or tile == TILE_VOID

static func tile_name(tile: int) -> String:
	match tile:
		TILE_PATH: return "path"
		TILE_GRASS: return "grass"
		TILE_WALL: return "wall"
		TILE_CAMP: return "camp"
		TILE_BOSS: return "boss"
		TILE_EXIT: return "exit"
		TILE_LAVA: return "lava"
		TILE_WATER: return "water"
		TILE_VOID: return "void"
		TILE_BRIDGE: return "bridge"
		TILE_ROCK: return "rock"
		TILE_CHEST: return "chest"
		_: return "empty"

static func _place_chests(tiles: Array, region: Dictionary, camp: Vector2i, boss: Vector2i, w: int, h: int) -> Array:
	var want := int(region.get("chest_count", 6))
	want = clampi(want, 3, 12)
	var region_idx := int(region.get("index", 1))
	var gold_min := 8 + region_idx * 4
	var gold_max := 18 + region_idx * 10
	var candidates: Array = []
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			var t: int = int(tiles[y][x])
			if t != TILE_PATH and t != TILE_GRASS and t != TILE_BRIDGE:
				continue
			if absi(x - camp.x) + absi(y - camp.y) < 5:
				continue
			if absi(x - boss.x) + absi(y - boss.y) < 4:
				continue
			candidates.append(Vector2i(x, y))
	candidates.shuffle()
	var chests: Array = []
	var count := mini(want, candidates.size())
	for i in count:
		var cell: Vector2i = candidates[i]
		tiles[cell.y][cell.x] = TILE_CHEST
		chests.append({
			"x": cell.x,
			"y": cell.y,
			"gold": randi_range(gold_min, gold_max)
		})
	return chests

static func _hazard_tile(kind: String) -> int:
	match kind:
		"water", "ice":
			return TILE_WATER
		"void", "pit":
			return TILE_VOID
		_:
			return TILE_LAVA

static func _filled_grid(w: int, h: int, fill: int) -> Array:
	var tiles: Array = []
	for y in h:
		var row: Array = []
		row.resize(w)
		for x in w:
			row[x] = fill
		tiles.append(row)
	return tiles

static func _paint_border(tiles: Array, w: int, h: int, tile: int) -> void:
	for x in w:
		tiles[0][x] = tile
		tiles[h - 1][x] = tile
	for y in h:
		tiles[y][0] = tile
		tiles[y][w - 1] = tile

static func _place_rooms(region: Dictionary, w: int, h: int) -> Array:
	## Returns rooms ordered south(camp) → north(boss).
	var target := int(region.get("room_count", 10))
	target = clampi(target, 7, 16)
	var rooms: Array = []

	# Always seed camp (south) and boss (north) rooms first.
	var pref_camp: Dictionary = region.get("camp_cell", {"x": int(w * 0.25), "y": h - 6})
	var pref_boss: Dictionary = region.get("boss_cell", {"x": int(w * 0.6), "y": 5})
	var camp := {
		"x": clampi(int(pref_camp.get("x", 8)) - 2, 2, w - 8),
		"y": clampi(int(pref_camp.get("y", h - 6)) - 2, h - 10, h - 6),
		"w": 6, "h": 5,
		"cx": 0, "cy": 0
	}
	camp.cx = camp.x + int(camp.w / 2.0)
	camp.cy = camp.y + int(camp.h / 2.0)
	var boss := {
		"x": clampi(int(pref_boss.get("x", 18)) - 3, 2, w - 9),
		"y": clampi(int(pref_boss.get("y", 5)) - 2, 2, 6),
		"w": 7, "h": 5,
		"cx": 0, "cy": 0
	}
	boss.cx = boss.x + int(boss.w / 2.0)
	boss.cy = boss.y + int(boss.h / 2.0)
	rooms.append(camp)
	rooms.append(boss)

	var attempts := 0
	while rooms.size() < target and attempts < 260:
		attempts += 1
		var rw := randi_range(4, 8)
		var rh := randi_range(4, 7)
		var rx := randi_range(2, w - rw - 2)
		var ry := randi_range(8, h - rh - 8)
		var candidate := {
			"x": rx, "y": ry, "w": rw, "h": rh,
			"cx": rx + int(rw / 2.0), "cy": ry + int(rh / 2.0)
		}
		if _room_overlaps(candidate, rooms, 2):
			continue
		rooms.append(candidate)

	rooms.sort_custom(func(a, b): return int(a.cy) > int(b.cy))
	# Ensure camp is first (south) and boss last (north) after sort.
	# Re-assert camp/boss identity by y extremes.
	var south_i := 0
	var north_i := 0
	for i in rooms.size():
		if int(rooms[i].cy) > int(rooms[south_i].cy):
			south_i = i
		if int(rooms[i].cy) < int(rooms[north_i].cy):
			north_i = i
	var south: Dictionary = rooms[south_i]
	var north: Dictionary = rooms[north_i]
	var mid: Array = []
	for i in rooms.size():
		if i == south_i or i == north_i:
			continue
		mid.append(rooms[i])
	mid.sort_custom(func(a, b): return int(a.cy) > int(b.cy))
	rooms = [south]
	rooms.append_array(mid)
	rooms.append(north)
	return rooms

static func _room_overlaps(room: Dictionary, rooms: Array, pad: int) -> bool:
	var ax1 := int(room.x) - pad
	var ay1 := int(room.y) - pad
	var ax2 := int(room.x) + int(room.w) + pad
	var ay2 := int(room.y) + int(room.h) + pad
	for other in rooms:
		var bx1 := int(other.x)
		var by1 := int(other.y)
		var bx2 := bx1 + int(other.w)
		var by2 := by1 + int(other.h)
		if ax1 < bx2 and ax2 > bx1 and ay1 < by2 and ay2 > by1:
			return true
	return false

static func _fill_rect(tiles: Array, room: Dictionary, tile: int, w: int, h: int) -> void:
	var x0 := clampi(int(room.x), 1, w - 2)
	var y0 := clampi(int(room.y), 1, h - 2)
	var x1 := clampi(int(room.x) + int(room.w) - 1, 1, w - 2)
	var y1 := clampi(int(room.y) + int(room.h) - 1, 1, h - 2)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			tiles[y][x] = tile

static func _connect_rooms(tiles: Array, rooms: Array, w: int, h: int, hazard: int) -> void:
	# Chain adjacent rooms in south→north order, plus a few cross-links.
	for i in range(rooms.size() - 1):
		_carve_corridor(tiles, rooms[i], rooms[i + 1], w, h, hazard, 1 if randf() < 0.55 else 2)
	# Extra side paths for looping exploration.
	var extras := mini(3, rooms.size() - 2)
	for _i in extras:
		var a := randi_range(0, rooms.size() - 1)
		var b := randi_range(0, rooms.size() - 1)
		if a == b:
			continue
		_carve_corridor(tiles, rooms[a], rooms[b], w, h, hazard, 1)

static func _carve_corridor(tiles: Array, a: Dictionary, b: Dictionary, w: int, h: int, hazard: int, width: int) -> void:
	var x0 := int(a.cx)
	var y0 := int(a.cy)
	var x1 := int(b.cx)
	var y1 := int(b.cy)
	# Randomize bend order for variety.
	if randf() < 0.5:
		_hline(tiles, x0, x1, y0, w, h, hazard, width)
		_vline(tiles, y0, y1, x1, w, h, hazard, width)
	else:
		_vline(tiles, y0, y1, x0, w, h, hazard, width)
		_hline(tiles, x0, x1, y1, w, h, hazard, width)

static func _paint_walk(tiles: Array, x: int, y: int, w: int, h: int, hazard: int) -> void:
	if x <= 0 or y <= 0 or x >= w - 1 or y >= h - 1:
		return
	var cur: int = int(tiles[y][x])
	if cur == TILE_WALL:
		return
	if cur == hazard or is_hazard(cur):
		tiles[y][x] = TILE_BRIDGE
	elif cur == TILE_GRASS or cur == TILE_PATH or cur == TILE_BRIDGE:
		# Keep grass in rooms; corridors over grass become path edges.
		if cur == TILE_GRASS:
			tiles[y][x] = TILE_PATH
		# else leave path/bridge
	elif cur == TILE_CAMP or cur == TILE_BOSS or cur == TILE_EXIT:
		pass
	else:
		tiles[y][x] = TILE_PATH

static func _hline(tiles: Array, x0: int, x1: int, y: int, w: int, h: int, hazard: int, width: int) -> void:
	var step := 1 if x1 >= x0 else -1
	var x := x0
	while true:
		for dy in range(-(width - 1), width):
			_paint_walk(tiles, x, y + dy, w, h, hazard)
		if x == x1:
			break
		x += step

static func _vline(tiles: Array, y0: int, y1: int, x: int, w: int, h: int, hazard: int, width: int) -> void:
	var step := 1 if y1 >= y0 else -1
	var y := y0
	while true:
		for dx in range(-(width - 1), width):
			_paint_walk(tiles, x + dx, y, w, h, hazard)
		if y == y1:
			break
		y += step

static func _scatter_rocks(tiles: Array, rooms: Array, w: int, h: int) -> void:
	for room in rooms:
		if randf() > 0.55:
			continue
		var n: int = randi_range(1, 3)
		for _i in n:
			var rx := randi_range(int(room.x) + 1, int(room.x) + int(room.w) - 2)
			var ry := randi_range(int(room.y) + 1, int(room.y) + int(room.h) - 2)
			if rx <= 1 or ry <= 1 or rx >= w - 2 or ry >= h - 2:
				continue
			if int(tiles[ry][rx]) == TILE_GRASS:
				tiles[ry][rx] = TILE_ROCK

static func _ensure_path(tiles: Array, start: Vector2i, goal: Vector2i, w: int, h: int, hazard: int) -> void:
	## Simple BFS; if unreachable, carve a direct L bridge path.
	if _reachable(tiles, start, goal, w, h):
		return
	var a := {"cx": start.x, "cy": start.y}
	var b := {"cx": goal.x, "cy": goal.y}
	_carve_corridor(tiles, a, b, w, h, hazard, 2)

static func _reachable(tiles: Array, start: Vector2i, goal: Vector2i, w: int, h: int) -> bool:
	var q: Array = [start]
	var seen := {}
	seen["%d,%d" % [start.x, start.y]] = true
	var guard := 0
	while not q.is_empty() and guard < w * h:
		guard += 1
		var c: Vector2i = q.pop_front()
		if c == goal:
			return true
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var dvec: Vector2i = d
			var n: Vector2i = Vector2i(c.x + dvec.x, c.y + dvec.y)
			if n.x <= 0 or n.y <= 0 or n.x >= w - 1 or n.y >= h - 1:
				continue
			var key := "%d,%d" % [n.x, n.y]
			if seen.has(key):
				continue
			if not is_walkable(int(tiles[n.y][n.x])):
				continue
			seen[key] = true
			q.append(n)
	return false
