extends Node
## Headless domain tests via scene so autoloads resolve.
## godot --headless --path . res://tests/TestRunner.tscn

const LevelSystem = preload("res://scripts/domain/LevelSystem.gd")
const CreatureFactory = preload("res://scripts/domain/CreatureFactory.gd")
const EncounterSystem = preload("res://scripts/domain/EncounterSystem.gd")
const EvolutionSystem = preload("res://scripts/domain/EvolutionSystem.gd")
const CombatSystem = preload("res://scripts/domain/CombatSystem.gd")
const AbsorptionSystem = preload("res://scripts/domain/AbsorptionSystem.gd")
const AbilitySystem = preload("res://scripts/domain/AbilitySystem.gd")
const MutationSystem = preload("res://scripts/domain/MutationSystem.gd")
const DifficultySystem = preload("res://scripts/domain/DifficultySystem.gd")
const MapGenerator = preload("res://scripts/domain/MapGenerator.gd")
const ProgressionSystem = preload("res://scripts/domain/ProgressionSystem.gd")
const RunTimer = preload("res://scripts/util/RunTimer.gd")
const AppTheme = preload("res://scripts/ui/AppTheme.gd")

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
	failed += _test_bond_shards()
	failed += _test_level_up()
	failed += _test_bond_retry()
	failed += _test_difficulty_modes()
	failed += _test_minimap_fog()
	failed += _test_wild_respawn()
	failed += _test_wild_elements_and_boss_scaling()
	failed += _test_graphics_assets()
	failed += _test_run_timer_board()
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
	f += _ok("6 starters configured", DataRegistry.starters.size() == 6)
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
	var map := MapGenerator.generate(region, 1)
	var camp: Vector2i = map.camp
	var tile: int = map.tiles[camp.y][camp.x]
	var failed := 0
	failed += _ok("camp walkable", MapGenerator.is_walkable(tile))
	failed += _ok("camp tile type", tile == MapGenerator.TILE_CAMP)
	failed += _ok("map is large", int(map.width) >= 30 and int(map.height) >= 40)
	failed += _ok("floor1 is not boss floor", not bool(map.get("is_boss_floor", true)))
	var stairs: Vector2i = map.get("stairs_down", Vector2i(-1, -1))
	failed += _ok("floor1 has stairs down", stairs.x >= 0 and int(map.tiles[stairs.y][stairs.x]) == MapGenerator.TILE_EXIT)
	var boss_floor := MapGenerator.generate(region, 5)
	var boss: Vector2i = boss_floor.boss
	failed += _ok("floor5 is boss floor", bool(boss_floor.get("is_boss_floor", false)))
	failed += _ok("boss walkable", boss.x >= 0 and MapGenerator.is_walkable(int(boss_floor.tiles[boss.y][boss.x])))
	failed += _ok("five floors per region", MapGenerator.floors_per_region() == 5)
	var has_bridge := false
	var has_hazard := false
	for y in int(map.height):
		for x in int(map.width):
			var t: int = map.tiles[y][x]
			if t == MapGenerator.TILE_BRIDGE:
				has_bridge = true
			if MapGenerator.is_hazard(t):
				has_hazard = true
	failed += _ok("has bridges or hazards", has_bridge or has_hazard)
	# Path-driven floors: clearings + corridors, not open seas of walkable grass.
	var total := 0
	var hazard_n := 0
	var path_n := 0
	var walk_n := 0
	var empty_n := 0
	for y2 in int(map.height):
		for x2 in int(map.width):
			var tt: int = map.tiles[y2][x2]
			if tt == MapGenerator.TILE_WALL:
				continue
			total += 1
			if MapGenerator.is_hazard(tt):
				hazard_n += 1
			if tt == MapGenerator.TILE_PATH or tt == MapGenerator.TILE_BRIDGE:
				path_n += 1
			if tt == MapGenerator.TILE_EMPTY:
				empty_n += 1
			if MapGenerator.is_walkable(tt):
				walk_n += 1
	failed += _ok("hazards are minority", total > 0 and float(hazard_n) / float(total) < 0.22)
	failed += _ok("has path network", path_n >= 20)
	failed += _ok("underbrush surrounds paths", empty_n > path_n)
	failed += _ok("walkable is not the whole map", total > 0 and float(walk_n) / float(total) < 0.72)
	failed += _ok("has obelisks", map.get("obelisks", []).size() >= 2)
	var exit_cell: Vector2i = map.get("exit", Vector2i(-1, -1))
	failed += _ok("has exit hub", exit_cell.x >= 0 and MapGenerator.is_walkable(int(map.tiles[exit_cell.y][exit_cell.x])))
	failed += _ok("exit is not camp", exit_cell != camp)
	return failed

func _test_obelisks() -> int:
	GameState.start_new_run("ember_pup")
	var cell := Vector2i(3, 4)
	var f := 0
	f += _ok("obelisk starts uncleared", not GameState.is_obelisk_cleared("forest", cell))
	var state := GameState.ensure_obelisk_state("forest", cell, "brush_rat")
	f += _ok("obelisk starts stage 1", int(state.get("stage", 0)) == 1)
	f += _ok("obelisk starts cyan", str(state.get("hue", "")) == "cyan")
	f += _ok("obelisk persists template", str(state.get("template_id", "")) == "brush_rat")
	var adv1 := GameState.advance_obelisk("forest", cell)
	f += _ok("stage1 win upgrades in place", not bool(adv1.get("cleared", true)) and int(adv1.get("stage", 0)) == 2)
	f += _ok("stage2 is amber", str(adv1.get("hue", "")) == "amber")
	f += _ok("still not path after stage1", not GameState.is_obelisk_cleared("forest", cell))
	var adv2 := GameState.advance_obelisk("forest", cell)
	f += _ok("stage2 win goes violet", int(adv2.get("stage", 0)) == 3 and str(adv2.get("hue", "")) == "violet")
	var adv3 := GameState.advance_obelisk("forest", cell)
	f += _ok("stage3 win clears to path", bool(adv3.get("cleared", false)) and bool(adv3.get("bonus", false)))
	f += _ok("cleared stays path", GameState.is_obelisk_cleared("forest", cell))
	# Legacy cleared_obelisks entry with no progress must stay path (no surprise stage-2).
	var legacy := Vector2i(9, 9)
	GameState.mark_obelisk_cleared("forest", legacy)
	f += _ok("legacy cleared is path", GameState.is_obelisk_cleared("forest", legacy))
	f += _ok("legacy ensure stays empty", GameState.ensure_obelisk_state("forest", legacy, "brush_rat").is_empty())
	var g1 := EncounterSystem.create_obelisk_guardian("forest", "brush_rat", 1, 0)
	var g2 := EncounterSystem.create_obelisk_guardian("forest", "brush_rat", 2, 0)
	var g3 := EncounterSystem.create_obelisk_guardian("forest", "brush_rat", 3, 0)
	f += _ok("obelisk guardian created", not g1.is_empty() and bool(g1.get("is_obelisk_guardian", false)))
	f += _ok("obelisk not full alpha", not bool(g1.get("is_alpha", true)))
	f += _ok("stage hues set", str(g1.get("obelisk_hue")) == "cyan" and str(g3.get("obelisk_hue")) == "violet")
	var base := CreatureFactory.create_from_template("brush_rat", {})
	var g1_atk := int(g1.get("stats", {}).get("attack", 0))
	var g2_atk := int(g2.get("stats", {}).get("attack", 0))
	var g3_atk := int(g3.get("stats", {}).get("attack", 0))
	var base_atk := int(base.get("stats", {}).get("attack", 1))
	f += _ok("stage1 stronger than base", g1_atk > base_atk)
	f += _ok("stage2 stronger than stage1", g2_atk > g1_atk)
	f += _ok("stage3 stronger than stage2", g3_atk > g2_atk)
	f += _ok("stage1 near 1.22x", g1_atk == int(round(float(base_atk) * 1.22)))
	f += _ok("stage3 near 1.60x", g3_atk == int(round(float(base_atk) * 1.60)))
	# Wild roster persistence
	GameState.set_wild_roster("forest", [{
		"instance_id": "w1",
		"creature": {"instance_id": "w1", "name": "Test"},
		"x": 3.5, "y": 4.5, "alive": true
	}])
	GameState.mark_wild_defeated("forest", "w1")
	var roster := GameState.get_wild_roster("forest")
	f += _ok("wild marked defeated", roster.size() == 1 and not bool(roster[0].get("alive", true)))
	f += _ok("wild has respawn timer", float(roster[0].get("respawn_at", 0)) > Time.get_unix_time_from_system())
	return f

func _test_bond_shards() -> int:
	var f := 0
	GameState.start_new_run("ember_pup")
	f += _ok("new run starts with 1 shard", GameState.get_bond_shards() == 1)
	f += _ok("can use starting shard", GameState.can_use_bond_shard())

	var pup := CreatureFactory.create_from_template("ember_pup", {"is_player": true})
	var max_hp := int(pup.get("max_hp", 1))
	pup["hp"] = maxi(1, max_hp / 4)
	pup["statuses"] = [
		{"id": "burn", "turns": 2},
		{"id": "stun", "turns": 1},
		{"id": "poison", "turns": 2}
	]
	var before := int(pup.get("hp", 0))
	var res := CombatSystem.use_bond_shard(pup)
	f += _ok("shard heal ok", bool(res.get("ok", false)))
	f += _ok("shard healed some hp", int(res.get("healed", 0)) > 0 and int(pup.get("hp", 0)) > before)
	var band := CombatSystem.bond_shard_heal_range(pup)
	var min_heal := maxi(1, int(round(float(max_hp) * band.x)))
	var max_heal := maxi(1, int(round(float(max_hp) * band.y)))
	var healed := int(res.get("healed", 0))
	f += _ok("heal in 35-55% band", healed >= min_heal - 1 and healed <= max_heal)
	f += _ok("cleanses stun first", str(res.get("cleansed", "")) == "stun")
	var left: Array = pup.get("statuses", [])
	var has_stun := false
	for s in left:
		if str(s.get("id", "")) == "stun":
			has_stun = true
	f += _ok("stun removed from statuses", not has_stun)

	# Priority: poison over burn when stun gone
	pup["statuses"] = [{"id": "burn", "turns": 2}, {"id": "poison", "turns": 2}]
	pup["hp"] = maxi(1, max_hp / 4)
	res = CombatSystem.use_bond_shard(pup)
	f += _ok("cleanses poison before burn", str(res.get("cleansed", "")) == "poison")

	# Cap
	GameState.set_bond_shards(GameState.BOND_SHARD_CAP)
	f += _ok("cap is 5", GameState.get_bond_shards() == 5)
	GameState.set_bond_shards(99)
	f += _ok("set clamps to cap", GameState.get_bond_shards() == GameState.BOND_SHARD_CAP)
	var drop := GameState.try_grant_bond_shard_drop({"is_obelisk_guardian": true}, false)
	f += _ok("no drop at cap", not bool(drop.get("granted", true)))

	GameState.set_bond_shards(1)
	f += _ok("consume works", GameState.consume_bond_shard() and GameState.get_bond_shards() == 0)
	f += _ok("cannot consume at zero", not GameState.consume_bond_shard())

	# Full HP rejects
	pup["hp"] = max_hp
	pup["statuses"] = []
	res = CombatSystem.use_bond_shard(pup)
	f += _ok("rejects full hp", not bool(res.get("ok", true)))

	# Mutation boost hook
	var boosted := CreatureFactory.create_from_template("ember_pup", {"is_player": true})
	boosted["passives"] = ["vital_bond"]
	var boosted_band := CombatSystem.bond_shard_heal_range(boosted)
	f += _ok("vital_bond raises heal band", is_equal_approx(boosted_band.x, 0.50) and is_equal_approx(boosted_band.y, 0.75))
	return f

func _test_level_up() -> int:
	var f := 0
	var pup := CreatureFactory.create_from_template("ember_pup", {"is_player": true})
	LevelSystem.ensure_fields(pup)
	f += _ok("starts at level 1", int(pup.get("level", 0)) == 1)
	var enemy := CreatureFactory.create_from_template("brush_rat", {})
	var before_atk := int(pup.get("stats", {}).get("attack", 0))
	var before_hp := int(pup.get("max_hp", 0))
	pup["xp"] = LevelSystem.xp_to_next(1) - 1
	var res := LevelSystem.grant_battle_xp(pup, enemy, false)
	f += _ok("grants xp", int(res.get("xp_gained", 0)) > 0)
	f += _ok("levels up from battle xp", int(res.get("levels_gained", 0)) >= 1 and int(pup.get("level", 1)) >= 2)
	f += _ok("level raises attack", int(pup.get("stats", {}).get("attack", 0)) > before_atk)
	f += _ok("level raises max hp", int(pup.get("max_hp", 0)) > before_hp)
	f += _ok("boss xp > wild xp", LevelSystem.battle_xp_reward(enemy, true) > LevelSystem.battle_xp_reward(enemy, false))
	var ob1 := EncounterSystem.create_obelisk_guardian("forest", "brush_rat", 1, 0)
	var ob3 := EncounterSystem.create_obelisk_guardian("forest", "brush_rat", 3, 0)
	f += _ok("obelisk xp > wild xp", LevelSystem.battle_xp_reward(ob1, false) > LevelSystem.battle_xp_reward(enemy, false))
	f += _ok("stage3 obelisk xp > stage1", LevelSystem.battle_xp_reward(ob3, false) > LevelSystem.battle_xp_reward(ob1, false))
	# +5% XP per boss already defeated (stacks)
	var base_xp := LevelSystem.battle_xp_reward(enemy, false, 0)
	var xp1 := LevelSystem.battle_xp_reward(enemy, false, 1)
	var xp2 := LevelSystem.battle_xp_reward(enemy, false, 2)
	f += _ok("0 bosses keeps base xp", base_xp == LevelSystem.battle_xp_reward(enemy, false))
	f += _ok("1 boss adds ~5% xp", xp1 == maxi(1, int(round(float(base_xp) * 1.05))))
	f += _ok("2 bosses add ~10% xp", xp2 == maxi(1, int(round(float(base_xp) * 1.10))))
	f += _ok("boss fight xp uses prior clears only", LevelSystem.battle_xp_reward(enemy, true, 0) == LevelSystem.battle_xp_reward(enemy, true))
	# Basilisk evolves at Lv 8
	var basilisk := CreatureFactory.create_from_template("basilisk", {"is_player": true})
	LevelSystem.ensure_fields(basilisk)
	f += _ok("basilisk template loads", not basilisk.is_empty())
	f += _ok("basilisk has evolves_to", str(DataRegistry.get_creature("basilisk").get("evolves_to", "")) == "dread_basilisk")
	basilisk["level"] = 7
	var evo_early := EvolutionSystem.try_evolve(basilisk)
	f += _ok("basilisk does not evolve early", not bool(evo_early.get("evolved", true)))
	basilisk["level"] = 8
	var evo := EvolutionSystem.try_evolve(basilisk)
	f += _ok("basilisk evolves at 8", bool(evo.get("evolved", false)))
	f += _ok("becomes dread basilisk", str(basilisk.get("template_id", "")) == "dread_basilisk")
	f += _ok("keeps level after evo", int(basilisk.get("level", 0)) == 8)
	# Encounter levels progress by floor
	var forest := DataRegistry.get_region("forest")
	f += _ok("floor1 encounter level", LevelSystem.encounter_level(forest, 1, 0) == 1)
	f += _ok("floor5 encounter level higher", LevelSystem.encounter_level(forest, 5, 0) > LevelSystem.encounter_level(forest, 1, 0))
	return f

func _test_bond_retry() -> int:
	var f := 0
	GameState.start_new_run("basilisk")
	var companion: Dictionary = GameState.get_companion()
	var base_atk := int(companion.get("stats", {}).get("attack", 0))
	var base_hp := int(companion.get("max_hp", 0))
	MutationSystem.apply_mutation(companion, "scales_green")
	companion["abilities"] = ["vine_lash", "sting", "toxin_spray"]
	companion["elements"] = ["poison", "nature"]
	# Simulate leveling so stats diverge hard from base.
	for _i in range(9):
		LevelSystem._apply_level_bonus(companion)
		companion["level"] = int(companion.get("level", 1)) + 1
	companion["xp"] = 12
	GameState.set_companion(companion)
	f += _ok("pre-death level high", int(companion.get("level", 1)) >= 10)
	f += _ok("pre-death stats raised", int(companion.get("stats", {}).get("attack", 0)) > base_atk)
	# Force evolve mid-run then die.
	var evo := EvolutionSystem.try_evolve(companion)
	f += _ok("retry setup evolved", bool(evo.get("evolved", false)))
	GameState.set_companion(companion)
	var leveled_atk := int(companion.get("stats", {}).get("attack", 0))
	var report := GameState.end_run(false)
	f += _ok("loss report allows retry", bool(report.get("can_retry", false)))
	f += _ok("pending retry snapshot kept", GameState.has_pending_retry_companion())
	f += _ok("run cleared after death", GameState.run.is_empty())
	f += _ok("dead run not continuable", not GameState.has_continue())
	# DNA snapshot must not carry level/power fields.
	var snap: Dictionary = GameState.pending_retry_companion
	f += _ok("snap has no level", not snap.has("level"))
	f += _ok("snap has no stats", not snap.has("stats"))
	f += _ok("snap has no xp", not snap.has("xp"))
	# Persist across account reload (simulates app restart on Bond Lost).
	GameState.pending_retry_companion = {}
	GameState.refresh_account()
	f += _ok("retry survives account reload", GameState.has_pending_retry_companion())
	f += _ok("retry start ok", GameState.start_new_run_from_pending_companion())
	var again: Dictionary = GameState.get_companion()
	f += _ok("retry keeps evolved form", str(again.get("template_id", "")) == "dread_basilisk")
	f += _ok("retry resets to level 1", int(again.get("level", 0)) == 1)
	f += _ok("retry xp cleared", int(again.get("xp", -1)) == 0)
	# Stats must match a fresh template of the retry species + DNA mutations — not leveled power.
	var expected := CreatureFactory.create_from_template("dread_basilisk", {"is_player": true})
	MutationSystem.apply_mutation(expected, "scales_green")
	ProgressionSystem.apply_starting_passives(expected, GameState.account)
	f += _ok("retry attack reset", int(again.get("stats", {}).get("attack", 0)) == int(expected.get("stats", {}).get("attack", -1)))
	f += _ok("retry hp reset", int(again.get("max_hp", 0)) == int(expected.get("max_hp", -1)))
	f += _ok("retry weaker than leveled", int(again.get("stats", {}).get("attack", 0)) < leveled_atk)
	f += _ok("retry keeps mutations", (again.get("mutations", []) as Array).has("scales_green"))
	f += _ok("retry keeps abilities", (again.get("abilities", []) as Array).has("toxin_spray"))
	f += _ok("retry starts in forest", str(GameState.run.get("region_id", "")) == "forest")
	f += _ok("retry consumes pending snap", not GameState.has_pending_retry_companion())
	# Victory should not offer retry.
	GameState.start_new_run("ember_pup")
	var win_report := GameState.end_run(true)
	f += _ok("win has no retry", not bool(win_report.get("can_retry", true)))
	f += _ok("win clears pending", not GameState.has_pending_retry_companion())
	return f

func _test_difficulty_modes() -> int:
	var f := 0
	var forest := DataRegistry.get_region("forest")
	var p_easy := EncounterSystem.compute_wild_pressure(forest, 2, 3, "easy")
	var p_norm := EncounterSystem.compute_wild_pressure(forest, 2, 3, "normal")
	var p_hard := EncounterSystem.compute_wild_pressure(forest, 2, 3, "hard")
	f += _ok("easy pressure < normal", p_easy < p_norm)
	f += _ok("hard pressure > normal", p_hard > p_norm)
	f += _ok("normal pressure unchanged formula", is_equal_approx(p_norm, 0.7 + 1.0))
	var lvl_e := LevelSystem.encounter_level(forest, 3, 0, "easy")
	var lvl_n := LevelSystem.encounter_level(forest, 3, 0, "normal")
	var lvl_h := LevelSystem.encounter_level(forest, 3, 0, "hard")
	f += _ok("easy encounter level lower", lvl_e < lvl_n)
	f += _ok("hard encounter level higher", lvl_h > lvl_n)
	var base := CreatureFactory.create_from_template("brush_rat", {})
	var easy_c := CreatureFactory.create_from_template("brush_rat", {})
	var hard_c := CreatureFactory.create_from_template("brush_rat", {})
	EncounterSystem.apply_wild_pressure(easy_c, 4.0, "easy")
	EncounterSystem.apply_wild_pressure(hard_c, 4.0, "hard")
	f += _ok("easy wild weaker than hard", int(easy_c.get("stats", {}).get("attack", 0)) < int(hard_c.get("stats", {}).get("attack", 0)))
	f += _ok("easy hp softer", int(easy_c.get("max_hp", 0)) < int(hard_c.get("max_hp", 0)))
	var b_easy := EncounterSystem.create_boss(forest, 0, 5, "easy")
	var b_hard := EncounterSystem.create_boss(forest, 0, 5, "hard")
	f += _ok("easy boss less hp", int(b_easy.get("max_hp", 0)) < int(b_hard.get("max_hp", 0)))
	GameState.start_new_run("ember_pup", "hard")
	f += _ok("run stores hard", GameState.get_difficulty() == "hard")
	f += _ok("hard starts with 1 shard", GameState.get_bond_shards() == 1)
	GameState.start_new_run("ember_pup", "easy")
	f += _ok("easy starts with 2 shards", GameState.get_bond_shards() == 2)
	f += _ok("preferred difficulty saved", GameState.get_preferred_difficulty() == "easy")
	f += _ok("normalize junk to normal", DifficultySystem.normalize("nonsense") == "normal")
	f += _ok("base still loads", not base.is_empty())
	return f

func _test_minimap_fog() -> int:
	var f := 0
	GameState.start_new_run("ember_pup", "normal")
	f += _ok("explored maps start empty", GameState.get_explored_cells().is_empty())
	f += _ok("cell starts fogged", not GameState.is_cell_explored(Vector2i(8, 42)))
	var changed := GameState.reveal_exploration_around(Vector2(8.5, 42.5), 2)
	f += _ok("reveal marks cells", changed and GameState.is_cell_explored(Vector2i(8, 42)))
	f += _ok("reveal covers radius", GameState.is_cell_explored(Vector2i(10, 42)))
	f += _ok("outside radius stays fogged", not GameState.is_cell_explored(Vector2i(20, 20)))
	var again := GameState.reveal_exploration_around(Vector2(8.5, 42.5), 2)
	f += _ok("repeat reveal no change", not again)
	# Floor keys are separate.
	GameState.run["region_floor"] = 2
	f += _ok("other floor fogged", GameState.get_explored_cells().is_empty())
	GameState.reveal_exploration_around(Vector2(3.2, 4.1), 1)
	f += _ok("floor2 explores independently", GameState.is_cell_explored(Vector2i(3, 4)))
	GameState.run["region_floor"] = 1
	f += _ok("floor1 still remembered", GameState.is_cell_explored(Vector2i(8, 42)))
	return f

func _test_wild_respawn() -> int:
	var f := 0
	GameState.start_new_run("ember_pup")
	GameState.set_wild_roster("forest", [{
		"instance_id": "r1",
		"creature": {"instance_id": "r1", "name": "Rat", "max_hp": 10, "hp": 1, "statuses": [{"id": "burn", "turns": 1}]},
		"x": 3.5, "y": 4.5, "alive": true
	}])
	GameState.mark_wild_defeated("forest", "r1")
	var roster := GameState.get_wild_roster("forest")
	f += _ok("defeated schedules respawn", not bool(roster[0].get("alive", true)) and roster[0].has("respawn_at"))
	f += _ok("defeated heals creature for return", int(roster[0].get("creature", {}).get("hp", 0)) == 10)
	# Simulate due respawn by backdating.
	roster[0]["respawn_at"] = Time.get_unix_time_from_system() - 1.0
	GameState.set_wild_roster("forest", roster)
	GameState.migrate_wild_respawns("forest")
	# Migration should not clear an existing due timer.
	roster = GameState.get_wild_roster("forest")
	f += _ok("due timer preserved", float(roster[0].get("respawn_at", 0)) <= Time.get_unix_time_from_system())
	# Old save without timer gets one.
	GameState.set_wild_roster("forest", [{
		"instance_id": "old",
		"creature": {"instance_id": "old", "name": "Old", "max_hp": 5, "hp": 5},
		"x": 1.5, "y": 1.5, "alive": false
	}])
	GameState.migrate_wild_respawns("forest")
	roster = GameState.get_wild_roster("forest")
	f += _ok("old dead wilds get respawn timer", roster[0].has("respawn_at"))
	return f

func _test_wild_elements_and_boss_scaling() -> int:
	var f := 0
	var pool := EncounterSystem.wild_element_pool()
	f += _ok("wild pool has 7 types", pool.size() == 7)
	f += _ok("normal element exists", DataRegistry.elements.has("normal"))
	f += _ok("nature displays as Grass", str(DataRegistry.elements["nature"].get("name")) == "Grass")
	f += _ok("wind displays as Flying", str(DataRegistry.elements["wind"].get("name")) == "Flying")
	var seen := {}
	for _i in 40:
		var w := EncounterSystem.roll_wild("forest", {})
		for e in w.get("elements", []):
			seen[str(e)] = true
		f += _ok("wild has elements", not w.get("elements", []).is_empty())
		break
	# Diversity across many rolls
	seen.clear()
	for _i in 60:
		var w2 := EncounterSystem.roll_wild("forest", {})
		for e2 in w2.get("elements", []):
			seen[str(e2)] = true
	f += _ok("wild types vary", seen.size() >= 4)
	for e3 in seen.keys():
		f += _ok("rolled type in pool", pool.has(e3))
		break
	var region := DataRegistry.get_region("forest")
	var b0 := EncounterSystem.create_boss(region, 0)
	var b3 := EncounterSystem.create_boss(region, 3)
	var hp0 := int(b0.get("max_hp", 1))
	var hp3 := int(b3.get("max_hp", 1))
	var atk0 := int(b0.get("stats", {}).get("attack", 1))
	var atk3 := int(b3.get("stats", {}).get("attack", 1))
	f += _ok("later boss has more hp", hp3 > hp0)
	f += _ok("later boss hits harder", atk3 > atk0)
	f += _ok("boss has elements", not b0.get("elements", []).is_empty())
	# Hybrid wild pressure: region floor + 0.35 * bosses_defeated
	var forest := DataRegistry.get_region("forest")
	var hive := DataRegistry.get_region("meteor_hive")
	f += _ok("forest pressure floor 0", is_equal_approx(EncounterSystem.compute_wild_pressure(forest, 0, 1), 0.0))
	f += _ok("hive pressure floor 4", is_equal_approx(EncounterSystem.compute_wild_pressure(hive, 0, 1), 4.0))
	f += _ok("forest+2 bosses pressure 0.7", is_equal_approx(EncounterSystem.compute_wild_pressure(forest, 2, 1), 0.7))
	f += _ok("deeper floor raises pressure", EncounterSystem.compute_wild_pressure(forest, 0, 5) > EncounterSystem.compute_wild_pressure(forest, 0, 1))
	f += _ok("pressure clamps to 8", is_equal_approx(EncounterSystem.compute_wild_pressure(hive, 20, 5), 8.0))
	var base_rat := CreatureFactory.create_from_template("brush_rat", {})
	var wild0 := CreatureFactory.create_from_template("brush_rat", {})
	EncounterSystem.apply_wild_pressure(wild0, 0.0)
	var wild4 := CreatureFactory.create_from_template("brush_rat", {})
	EncounterSystem.apply_wild_pressure(wild4, 4.0)
	f += _ok("pressure0 keeps base atk", int(wild0.get("stats", {}).get("attack", 0)) == int(base_rat.get("stats", {}).get("attack", 1)))
	f += _ok("pressure4 raises atk", int(wild4.get("stats", {}).get("attack", 0)) > int(base_rat.get("stats", {}).get("attack", 1)))
	f += _ok("pressure4 raises hp harder", int(wild4.get("max_hp", 0)) > int(wild0.get("max_hp", 0)))
	# Re-apply does not stack
	var atk_before := int(wild4.get("stats", {}).get("attack", 0))
	EncounterSystem.apply_wild_pressure(wild4, 4.0)
	f += _ok("reapply pressure does not stack", int(wild4.get("stats", {}).get("attack", 0)) == atk_before)
	# Obelisk mult sits on regional wild base
	var g_press := EncounterSystem.create_obelisk_guardian("meteor_hive", "brush_rat", 1, 0)
	f += _ok("obelisk uses regional wild base", int(g_press.get("stats", {}).get("attack", 0)) > int(round(float(base_rat.get("stats", {}).get("attack", 1)) * 1.22)))
	return f

func _test_graphics_assets() -> int:
	var f := 0
	f += _ok("display font present", ResourceLoader.exists("res://assets/fonts/Fredoka-Variable.ttf"))
	f += _ok("body font present", ResourceLoader.exists("res://assets/fonts/Karla-Regular.ttf"))
	f += _ok("grass tile present", ResourceLoader.exists("res://assets/tiles/grass.png"))
	f += _ok("grass variants present", ResourceLoader.exists("res://assets/tiles/grass_1.png") and ResourceLoader.exists("res://assets/tiles/grass_2.png") and ResourceLoader.exists("res://assets/tiles/grass_3.png"))
	f += _ok("tree variants present", ResourceLoader.exists("res://assets/tiles/tree_1.png") and ResourceLoader.exists("res://assets/tiles/tree_2.png") and ResourceLoader.exists("res://assets/tiles/tree_3.png"))
	f += _ok("dune variants present", ResourceLoader.exists("res://assets/tiles/dune.png") and ResourceLoader.exists("res://assets/tiles/dune_1.png") and ResourceLoader.exists("res://assets/tiles/dune_2.png"))
	f += _ok("cliff tile present", ResourceLoader.exists("res://assets/tiles/cliff.png") and ResourceLoader.exists("res://assets/tiles/cliff_2.png"))
	f += _ok("forest cobble path present", ResourceLoader.exists("res://assets/tiles/path_forest_0.png") and ResourceLoader.exists("res://assets/tiles/path_forest_2.png"))
	f += _ok("desert plank path present", ResourceLoader.exists("res://assets/tiles/path_desert_0.png"))
	f += _ok("frozen black plank path present", ResourceLoader.exists("res://assets/tiles/path_frozen_mountains_0.png"))
	f += _ok("alien marble path present", ResourceLoader.exists("res://assets/tiles/path_alien_lab_0.png"))
	f += _ok("meteor lava-rock path present", ResourceLoader.exists("res://assets/tiles/path_meteor_hive_0.png"))
	var grass_tex = load("res://assets/tiles/grass.png")
	f += _ok("grass hi-res terrain", grass_tex != null and grass_tex.get_width() >= 256)
	f += _ok("water anim present", ResourceLoader.exists("res://assets/tiles/water_0.png"))
	f += _ok("ui button chrome present", ResourceLoader.exists("res://assets/ui/btn_normal.png"))
	f += _ok("boot splash art present", ResourceLoader.exists("res://assets/ui/boot_bg.png"))
	f += _ok("joystick art present", ResourceLoader.exists("res://assets/ui/stick_base.png"))
	f += _ok("forest arena present", ResourceLoader.exists("res://assets/arenas/forest.png"))
	f += _ok("desert arena present", ResourceLoader.exists("res://assets/arenas/desert.png"))
	f += _ok("slash fx present", ResourceLoader.exists("res://assets/fx/slash.png"))
	f += _ok("impact fx present", ResourceLoader.exists("res://assets/fx/impact.png"))
	f += _ok("player walk sheet present", ResourceLoader.exists("res://assets/player/human_walk_x2.png"))
	f += _ok("ember pup sprite present", ResourceLoader.exists("res://assets/creatures/ember_pup.png"))
	var ember_tex = load("res://assets/creatures/ember_pup.png")
	f += _ok("ember pup hi-res", ember_tex != null and ember_tex.get_width() >= 416)
	f += _ok("mutation horns present", ResourceLoader.exists("res://assets/mutations/horns/horns_small.png"))
	var theme = AppTheme.get_theme()
	f += _ok("app theme builds", theme != null)
	return f

func _test_run_timer_board() -> int:
	var f := 0
	f += _ok("format under an hour", RunTimer.format_run_time(125000) == "2:05")
	f += _ok("format with hours", RunTimer.format_run_time(3723000) == "1:02:03")
	f += _ok("elapsed non-negative", RunTimer.elapsed_ms(1000, 500) == 0)
	f += _ok("elapsed basic", RunTimer.elapsed_ms(1000, 3500) == 2500)
	# Fresh account board.
	var account := {
		"fastest_runs": {}
	}
	RunTimer.ensure_board(account)
	f += _ok("board has three diffs", (account["fastest_runs"] as Dictionary).has("easy") and (account["fastest_runs"] as Dictionary).has("hard"))
	# Losses must not write the board — only victories.
	GameState.account = SaveService.load_account()
	GameState.account["fastest_runs"] = RunTimer.empty_board()
	GameState.start_new_run("ember_pup", "normal")
	f += _ok("run stamps started_at", int(GameState.run.get("started_at_ms", 0)) > 0)
	# Force a known start so elapsed is deterministic.
	GameState.run["started_at_ms"] = RunTimer.now_ms() - 45000
	var loss := GameState.end_run(false)
	f += _ok("loss reports elapsed", int(loss.get("elapsed_ms", 0)) >= 40000)
	f += _ok("loss reports run_time string", str(loss.get("run_time", "")) != "")
	f += _ok("loss does not record fastest", RunTimer.get_fastest(GameState.account, "normal").is_empty())
	# Four wins — keep only the three fastest.
	for ms_ago in [90000, 60000, 120000, 30000]:
		GameState.start_new_run("ember_pup", "hard")
		GameState.run["started_at_ms"] = RunTimer.now_ms() - ms_ago
		GameState.end_run(true)
	var hard_board: Array = RunTimer.get_fastest(GameState.account, "hard")
	f += _ok("hard board capped at 3", hard_board.size() == 3)
	f += _ok("hard board sorted fastest first", int(hard_board[0].get("elapsed_ms", 999999)) <= int(hard_board[1].get("elapsed_ms", 0)))
	f += _ok("hard board excludes slowest", int(hard_board[2].get("elapsed_ms", 0)) <= 90000)
	f += _ok("normal board still empty", RunTimer.get_fastest(GameState.account, "normal").is_empty())
	var lines := RunTimer.format_board_lines(GameState.account, "hard")
	f += _ok("board lines mention clears", lines.contains("Fastest clears"))
	return f

func _test_progression_starters() -> int:
	var account := SaveService.load_account()
	var starters := ProgressionSystem.available_starters(account)
	var f := 0
	f += _ok("at least 2 starters unlocked by default", starters.size() >= 2)
	f += _ok("ember available", starters.has("ember_pup"))
	f += _ok("basilisk available", starters.has("basilisk"))
	f += _ok("basilisk sprite present", ResourceLoader.exists("res://assets/creatures/basilisk.png"))
	f += _ok("dread basilisk sprite present", ResourceLoader.exists("res://assets/creatures/dread_basilisk.png"))
	return f
