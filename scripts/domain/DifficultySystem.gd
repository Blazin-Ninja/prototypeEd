extends RefCounted
class_name DifficultySystem
## Run difficulty: easy / normal / hard. Normal matches legacy balance.

const ID_EASY := "easy"
const ID_NORMAL := "normal"
const ID_HARD := "hard"

const LABELS := {
	"easy": "Easy",
	"normal": "Normal",
	"hard": "Hard"
}

const DESCRIPTIONS := {
	"easy": "Softer enemies and bosses. Good for learning the bond.",
	"normal": "Standard difficulty — the original balance.",
	"hard": "Tougher wilds, guardians, and bosses."
}

static func normalize(id: String) -> String:
	var key := id.strip_edges().to_lower()
	if key == ID_EASY or key == ID_HARD or key == ID_NORMAL:
		return key
	return ID_NORMAL

static func label(id: String) -> String:
	return str(LABELS.get(normalize(id), "Normal"))

static func description(id: String) -> String:
	return str(DESCRIPTIONS.get(normalize(id), DESCRIPTIONS[ID_NORMAL]))

static func all_ids() -> Array:
	return [ID_EASY, ID_NORMAL, ID_HARD]

static func pressure_mult(id: String) -> float:
	match normalize(id):
		ID_EASY:
			return 0.70
		ID_HARD:
			return 1.30
		_:
			return 1.0

static func encounter_level_offset(id: String) -> int:
	match normalize(id):
		ID_EASY:
			return -1
		ID_HARD:
			return 1
		_:
			return 0

static func enemy_stat_mult(id: String) -> float:
	## Extra ATK/SpA/DEF/SpD/SPD after pressure (Normal = 1.0).
	match normalize(id):
		ID_EASY:
			return 0.90
		ID_HARD:
			return 1.12
		_:
			return 1.0

static func enemy_hp_mult(id: String) -> float:
	match normalize(id):
		ID_EASY:
			return 0.90
		ID_HARD:
			return 1.15
		_:
			return 1.0

static func boss_stat_mult(id: String) -> float:
	match normalize(id):
		ID_EASY:
			return 0.90
		ID_HARD:
			return 1.15
		_:
			return 1.0

static func boss_hp_mult(id: String) -> float:
	match normalize(id):
		ID_EASY:
			return 0.85
		ID_HARD:
			return 1.20
		_:
			return 1.0

static func obelisk_stage_mult_scale(id: String) -> float:
	## Scales the 1.22 / 1.40 / 1.60 stage chain.
	match normalize(id):
		ID_EASY:
			return 0.92
		ID_HARD:
			return 1.12
		_:
			return 1.0

static func starting_bond_shards(id: String) -> int:
	match normalize(id):
		ID_EASY:
			return 2
		_:
			return 1
