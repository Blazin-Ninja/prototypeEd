extends Node
## Signals for loose UI coupling.

signal battle_started(enemy_data: Dictionary)
signal battle_ended(result: String)
signal run_ended(won: bool, tokens: int)
signal absorption_complete(results: Array)
signal region_changed(region_id: String)
signal companion_mutated(mutation_id: String)
