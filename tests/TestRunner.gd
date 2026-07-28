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
	var tile: int = map.tiles[camp.y][camp.x]
	return _ok("camp walkable", MapGenerator.is_walkable(tile)) + _ok("camp tile type", tile == MapGenerator.TILE_CAMP)

func _test_progression_starters() -> int:
	var account := SaveService.load_account()
	var starters := ProgressionSystem.available_starters(account)
	return _ok("at least 2 starters unlocked by default", starters.size() >= 2) + _ok("ember available", starters.has("ember_pup"))
