extends Node
## Loads and indexes all JSON game data.

var elements: Dictionary = {}
var element_chart: Dictionary = {}
var max_elements: int = 3
var families: Dictionary = {}
var abilities: Dictionary = {}
var max_abilities: int = 6
var mutations: Dictionary = {}
var creatures: Dictionary = {}
var starters: Array = []
var regions: Dictionary = {}
var region_order: Array = []
var progression: Dictionary = {}
var stat_caps: Dictionary = {}
var alpha_config: Dictionary = {}
var legendary_config: Dictionary = {}

func _ready() -> void:
	_load_all()

func _load_all() -> void:
	var el := _read_json("res://data/elements.json")
	for e in el.get("elements", []):
		elements[e["id"]] = e
	element_chart = el.get("chart", {})
	max_elements = int(el.get("max_active", 3))

	var fam := _read_json("res://data/dna_families.json")
	for f in fam.get("families", []):
		families[f["id"]] = f

	var ab := _read_json("res://data/abilities.json")
	for a in ab.get("abilities", []):
		abilities[a["id"]] = a
	max_abilities = int(ab.get("max_abilities", 6))

	var mu := _read_json("res://data/mutations.json")
	for m in mu.get("mutations", []):
		mutations[m["id"]] = m

	var cr := _read_json("res://data/creatures.json")
	for c in cr.get("creatures", []):
		creatures[c["id"]] = c
	stat_caps = cr.get("stat_caps", {})
	alpha_config = cr.get("alpha", {})
	legendary_config = cr.get("legendary", {})

	var st := _read_json("res://data/starters.json")
	starters = st.get("starters", [])

	var rg := _read_json("res://data/regions.json")
	for r in rg.get("regions", []):
		regions[r["id"]] = r
		region_order.append(r["id"])
	region_order.sort_custom(func(a, b): return int(regions[a]["index"]) < int(regions[b]["index"]))

	progression = _read_json("res://data/progression.json")

func _read_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Failed to open %s" % path)
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Invalid JSON at %s" % path)
		return {}
	return parsed

func get_creature(id: String) -> Dictionary:
	return creatures.get(id, {})

func get_ability(id: String) -> Dictionary:
	return abilities.get(id, {})

func get_mutation(id: String) -> Dictionary:
	return mutations.get(id, {})

func get_region(id: String) -> Dictionary:
	return regions.get(id, {})

func get_starters() -> Array:
	return starters.duplicate()

func get_wilds_for_region(region_id: String) -> Array:
	var out: Array = []
	for id in creatures.keys():
		var c: Dictionary = creatures[id]
		if c.get("region", "") == region_id and not c.get("is_boss", false) and not c.get("is_starter", false):
			out.append(c)
	return out

func element_multiplier(attack_elements: Array, defend_elements: Array) -> float:
	if attack_elements.is_empty():
		return 1.0
	var total := 0.0
	var count := 0
	for atk_el in attack_elements:
		var row: Dictionary = element_chart.get(str(atk_el), {})
		var best := 1.0
		if defend_elements.is_empty():
			best = 1.0
		else:
			best = 1.0
			for def_el in defend_elements:
				var m := float(row.get(str(def_el), 1.0))
				# Take the most relevant interaction per defending type, then average attackers.
				if m != 1.0:
					best *= m
		total += best
		count += 1
	var result := total / float(maxi(count, 1))
	return clampf(result, 0.25, 4.0)
