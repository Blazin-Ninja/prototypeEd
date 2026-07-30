extends RefCounted
class_name CreatureSprites
## Base creature sprite + slot mutation overlays (replace-per-slot visuals).

const CREATURE_DIR := "res://assets/creatures/"
const MUTATION_DIR := "res://assets/mutations/"
const SLOT_ORDER := [
	"body_size", "wings", "tail", "fur", "scales", "feathers", "skin_color",
	"armor", "horns", "fangs", "claws", "eyes", "particles"
]

static var _creature_tex: Dictionary = {}
static var _mutation_tex: Dictionary = {}
static var _loaded := false

static func ensure_loaded() -> void:
	if _loaded:
		return
	# Creature bases
	for id in DataRegistry.creatures.keys():
		var path := CREATURE_DIR + str(id) + ".png"
		if ResourceLoader.exists(path):
			_creature_tex[str(id)] = load(path)
	# Bosses may live under assets/bosses as well
	for id in ["elder_treant", "solar_colossus", "glacier_titan", "prime_chimera", "hive_heart"]:
		if _creature_tex.has(id):
			continue
		var bpath := "res://assets/bosses/%s.png" % id
		if ResourceLoader.exists(bpath):
			_creature_tex[id] = load(bpath)
	# Mutation overlays
	for mid in DataRegistry.mutations.keys():
		var m: Dictionary = DataRegistry.mutations[mid]
		var slot := str(m.get("slot", "particles"))
		var key := str(m.get("sprite_key", mid))
		var path2 := "%s%s/%s.png" % [MUTATION_DIR, slot, key]
		if ResourceLoader.exists(path2):
			_mutation_tex[str(mid)] = load(path2)
	_loaded = true

static func active_loadout(creature: Dictionary) -> Dictionary:
	## Prefer explicit visual_loadout; else derive latest-per-slot from history.
	var loadout: Dictionary = creature.get("visual_loadout", {})
	if not loadout.is_empty():
		return loadout.duplicate()
	var derived: Dictionary = {}
	for mid in creature.get("mutations", []):
		var m: Dictionary = DataRegistry.get_mutation(str(mid))
		if m.is_empty():
			continue
		var slot := str(m.get("slot", ""))
		if slot == "":
			continue
		derived[slot] = str(mid)
	return derived

static func has_base(creature: Dictionary) -> bool:
	ensure_loaded()
	var tid := str(creature.get("template_id", creature.get("id", "")))
	return _creature_tex.has(tid)

static func draw(canvas: CanvasItem, creature: Dictionary, center: Vector2, radius: float, anim_t: float = 0.0) -> bool:
	ensure_loaded()
	var tid := str(creature.get("template_id", creature.get("id", "")))
	if not _creature_tex.has(tid):
		return false

	var bob := sin(anim_t * 2.2) * (radius * 0.04)
	var c := center + Vector2(0, bob)
	var is_boss := bool(creature.get("is_boss", false))
	var size := Vector2(radius * 2.45, radius * 2.45)
	if is_boss:
		size *= 1.18

	# Soft shadow
	canvas.draw_circle(c + Vector2(0, radius * 0.85), radius * 0.55, Color(0, 0, 0, 0.25))

	# Element aura behind
	_draw_element_aura(canvas, creature, c, radius, anim_t)

	# Base sprite
	var tex: Texture2D = _creature_tex[tid]
	var dst := Rect2(c - size * 0.5, size)
	canvas.draw_texture_rect(tex, dst, false)

	# Slot overlays (ordered)
	var loadout := active_loadout(creature)
	for slot in SLOT_ORDER:
		if not loadout.has(slot):
			continue
		var mid: String = loadout[slot]
		if not _mutation_tex.has(mid):
			continue
		var mtex: Texture2D = _mutation_tex[mid]
		var m: Dictionary = DataRegistry.get_mutation(mid)
		var overlay_size := size
		# Scale some slots slightly
		if slot in ["particles", "body_size", "fur", "scales", "skin_color"]:
			overlay_size = size * 1.05
		elif slot in ["horns", "eyes", "fangs"]:
			overlay_size = size * 0.95
		var mdst := Rect2(c - overlay_size * 0.5, overlay_size)
		# Tint if mutation defines color
		if m.get("color", null) != null and slot in ["skin_color", "fur", "scales"]:
			canvas.draw_texture_rect(mtex, mdst, false, Color.html(str(m["color"])))
		else:
			canvas.draw_texture_rect(mtex, mdst, false)

	# Alpha / legendary rim
	if creature.get("is_alpha", false):
		canvas.draw_arc(c, radius * 1.2, 0, TAU, 32, Color(1, 0.84, 0, 0.85), 2.5, true)
	if creature.get("is_legendary", false):
		canvas.draw_arc(c, radius * 1.3, 0, TAU, 32, Color(0.7, 0.4, 1.0, 0.9), 3.0, true)
	if is_boss:
		canvas.draw_arc(c, radius * 1.35, 0, TAU, 40, Color(0.85, 0.2, 0.25, 0.75), 3.0, true)

	return true

static func _draw_element_aura(canvas: CanvasItem, creature: Dictionary, center: Vector2, radius: float, anim_t: float) -> void:
	var els: Array = creature.get("elements", [])
	if els.is_empty():
		return
	var eid := str(els[0])
	var col := Color(0.5, 0.7, 0.9, 0.16)
	if DataRegistry.elements.has(eid):
		col = Color.html(str(DataRegistry.elements[eid].get("color", "#88aaff")))
		col.a = 0.18
	var pulse := 1.0 + 0.06 * sin(anim_t * 2.5)
	canvas.draw_circle(center, radius * 1.15 * pulse, col)
