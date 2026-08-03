extends RefCounted
class_name RunTimer
## Wall-clock run timing + top-3 victory board helpers.

const DifficultySystem = preload("res://scripts/domain/DifficultySystem.gd")
const MAX_FASTEST := 3

static func now_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)

static func elapsed_ms(started_at_ms: int, ended_at_ms: int = -1) -> int:
	var end := ended_at_ms if ended_at_ms >= 0 else now_ms()
	if started_at_ms <= 0:
		return 0
	return maxi(0, end - started_at_ms)

static func format_run_time(ms: int) -> String:
	var total_sec := maxi(0, int(ms / 1000))
	var hours := int(total_sec / 3600)
	var minutes := int((total_sec % 3600) / 60)
	var seconds := int(total_sec % 60)
	if hours > 0:
		return "%d:%02d:%02d" % [hours, minutes, seconds]
	return "%d:%02d" % [minutes, seconds]

static func empty_board() -> Dictionary:
	return {
		DifficultySystem.ID_EASY: [],
		DifficultySystem.ID_NORMAL: [],
		DifficultySystem.ID_HARD: []
	}

static func ensure_board(account: Dictionary) -> Dictionary:
	var board: Dictionary = account.get("fastest_runs", {})
	if typeof(board) != TYPE_DICTIONARY:
		board = {}
	var out := empty_board()
	for id in DifficultySystem.all_ids():
		var rows: Array = []
		var raw = board.get(id, [])
		if typeof(raw) == TYPE_ARRAY:
			for item in raw:
				if typeof(item) == TYPE_DICTIONARY and int(item.get("elapsed_ms", 0)) > 0:
					rows.append({
						"elapsed_ms": int(item.get("elapsed_ms", 0)),
						"companion_name": str(item.get("companion_name", "?")),
						"at": int(item.get("at", 0))
					})
		rows.sort_custom(func(a, b): return int(a.get("elapsed_ms", 0)) < int(b.get("elapsed_ms", 0)))
		if rows.size() > MAX_FASTEST:
			rows = rows.slice(0, MAX_FASTEST)
		out[id] = rows
	account["fastest_runs"] = out
	return out

static func record_victory(account: Dictionary, difficulty: String, elapsed_ms_value: int, companion_name: String) -> Array:
	## Insert a winning time into the board for difficulty; keep fastest 3. Returns updated list.
	if elapsed_ms_value <= 0:
		return ensure_board(account).get(DifficultySystem.normalize(difficulty), [])
	var board := ensure_board(account)
	var diff := DifficultySystem.normalize(difficulty)
	var rows: Array = board.get(diff, []).duplicate(true)
	rows.append({
		"elapsed_ms": elapsed_ms_value,
		"companion_name": companion_name if companion_name != "" else "?",
		"at": now_ms()
	})
	rows.sort_custom(func(a, b): return int(a.get("elapsed_ms", 0)) < int(b.get("elapsed_ms", 0)))
	if rows.size() > MAX_FASTEST:
		rows = rows.slice(0, MAX_FASTEST)
	board[diff] = rows
	account["fastest_runs"] = board
	return rows

static func get_fastest(account: Dictionary, difficulty: String) -> Array:
	var board := ensure_board(account)
	return board.get(DifficultySystem.normalize(difficulty), [])

static func format_board_lines(account: Dictionary, difficulty: String) -> String:
	var rows := get_fastest(account, difficulty)
	if rows.is_empty():
		return "Fastest clears: none yet"
	var lines: PackedStringArray = ["Fastest clears:"]
	var i := 1
	for row in rows:
		lines.append("%d. %s — %s" % [
			i,
			format_run_time(int(row.get("elapsed_ms", 0))),
			str(row.get("companion_name", "?"))
		])
		i += 1
	return "\n".join(lines)
