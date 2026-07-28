extends Node
## Headless domain tests via scene so autoloads resolve.
## godot --headless --path . res://tests/TestRunner.tscn

func _ready() -> void:
	await get_tree().process_frame
	var failed := 0
	failed += _test_data_loaded()
	failed += _test_combat_damage()
	failed += _test_element_chart()
	failed += _test_absorption_apply()
	failed += _test_ability_upgrade()
	failed += _test_flee_and_initiative()
	failed += _test_map_walkable()
	failed += _test_obelisks()
	failed += _test_progression_starters()
	if failed == 0:
		print("ALL TESTS PASSED")
		get_tree().quit(0)
	else:
		print("TESTS FAILED: %d" % failed)
		get_tree().quit(1)

func _ok(name: String, cond: bool) -> int:
	if cond:
		print("PASS: ", name)
		return 0
	print("FAIL: ", name)
	return 1

func _test_data_loaded() -> int:
	var f := 0
	f += _ok("creatures loaded", DataRegistry.creatures.size() >= 15)
	f += _ok("abilities loaded", DataRegistry.abilities.size() >= 10)
	f += _ok("5 starters configured", DataRegistry.starters.size() == 5)
	f += _ok("regions loaded", DataRegistry.regions.size() == 5)
	return f

func _test_combat_damage() -> int:
	var a := CreatureFactory.create_from_template("ember_pup", {"is_player": true})
	var b := CreatureFactory.create_from_template("brush_rat", {})
	var res := CombatSystem.execute_ability(a, b, "scratch")
	return _ok("combat returns ok", bool(res.get("ok", false)))

func _test_element_chart() -> int:
	var multi := DataRegistry.element_multiplier(["fire"], ["nature"])
	var weak := DataRegistry.element_multiplier(["fire"], ["water"])
	return _ok("fire > nature", multi >= 1.5) + _ok("fire < water", weak <= 0.75)

func _test_absorption_apply() -> int:
	var companion := CreatureFactory.create_from_template("ember_pup", {"is_player": true})
	var before := int(companion.get("stats", {}).get("attack", 0))
	var result := {"type": "stat", "stat": "attack", "amount": 2, "label": "+2 Attack"}
	var applied := AbsorptionSystem.apply_result(companion, result, {})
	var after := int(companion.get("stats", {}).get("attack", 0))
	return _ok("stat absorb applied", bool(applied.get("applied", false)) and after == before + 2)

func _test_ability_upgrade() -> int:
	var companion := CreatureFactory.create_from_template("ember_pup", {"is_player": true})
	if not companion.get("abilities", []).has("scratch"):
		companion["abilities"] = ["scratch"]
	var enemy := CreatureFactory.create_from_template("pine_wolf", {})
	var upgrade := AbilitySystem.find_upgrade(companion, "slash", enemy)
	var f := _ok("finds claw chain upgrade", not upgrade.is_empty())
	if not upgrade.is_empty():
		AbilitySystem.upgrade_ability(companion, str(upgrade.get("from")), str(upgrade.get("to")))
		var abs: Array = companion.get("abilities", [])
		f += _ok("upgrade replaced ability", abs.has(upgrade.get("to")) and not abs.has(upgrade.get("from")))
	return f

func _test_flee_and_initiative() -> int:
	var fast := CreatureFactory.create_from_template("gale_hatch", {"is_player": true})
	var slow := CreatureFactory.create_from_template("mossback", {})
	var order := CombatSystem.initiative_order(fast, slow)
	return _ok("faster acts first", str(order[0].get("template_id")) == "gale_hatch")

func _test_map_walkable() -> int:
	var region := DataRegistry.get_region("forest")
	var map := MapGenerator.generate(region)
	var camp: Vector2i = map.camp
	var boss: Vector2i = map.boss
	var tile: int = map.tiles[camp.y][camp.x]
	var failed := 0
	failed += _ok("camp walkable", MapGenerator.is_walkable(tile))
	failed += _ok("camp tile type", tile == MapGenerator.TILE_CAMP)
	failed += _ok("map is large", int(map.width) >= 30 and int(map.height) >= 40)
	failed += _ok("boss walkable", MapGenerator.is_walkable(int(map.tiles[boss.y][boss.x])))
	var has_bridge := false
	var has_hazard := false
	for y in int(map.height):
		for x in int(map.width):
			var t: int = map.tiles[y][x]
			if t == MapGenerator.TILE_BRIDGE:
				has_bridge = true
			if MapGenerator.is_hazard(t):
				has_hazard = true
	failed += _ok("has bridges", has_bridge)
	failed += _ok("has hazards", has_hazard)
	failed += _ok("has obelisks", map.get("obelisks", []).size() >= 2)
	return failed

func _test_obelisks() -> int:
	GameState.start_new_run("ember_pup")
	var cell := Vector2i(3, 4)
	var f := 0
	f += _ok("obelisk starts uncleared", not GameState.is_obelisk_cleared("forest", cell))
	GameState.mark_obelisk_cleared("forest", cell)
	f += _ok("obelisk marked cleared", GameState.is_obelisk_cleared("forest", cell))
	var g := EncounterSystem.create_obelisk_guardian("forest")
	f += _ok("obelisk guardian created", not g.is_empty() and bool(g.get("is_obelisk_guardian", false)))
	# Wild roster persistence
	GameState.set_wild_roster("forest", [{
		"instance_id": "w1",
		"creature": {"instance_id": "w1", "name": "Test"},
		"x": 3.5, "y": 4.5, "alive": true
	}])
	GameState.mark_wild_defeated("forest", "w1")
	var roster := GameState.get_wild_roster("forest")
	f += _ok("wild marked defeated", roster.size() == 1 and not bool(roster[0].get("alive", true)))
	return f

func _test_progression_starters() -> int:
	var account := SaveService.load_account()
	var starters := ProgressionSystem.available_starters(account)
	return _ok("at least 2 starters unlocked by default", starters.size() >= 2) + _ok("ember available", starters.has("ember_pup"))
