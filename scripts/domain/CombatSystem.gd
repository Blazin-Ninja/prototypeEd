extends RefCounted
class_name CombatSystem
## Pure turn-based combat resolution.

const STATUS_BURN := "burn"
const STATUS_POISON := "poison"
const STATUS_STUN := "stun"

static func initiative_order(a: Dictionary, b: Dictionary) -> Array:
	var sa := int(a.get("stats", {}).get("speed", 0))
	var sb := int(b.get("stats", {}).get("speed", 0))
	if sa > sb:
		return [a, b]
	if sb > sa:
		return [b, a]
	# Tie: player first if present, else first arg.
	if a.get("is_player", false):
		return [a, b]
	if b.get("is_player", false):
		return [b, a]
	return [a, b]

static func choose_enemy_ability(enemy: Dictionary) -> String:
	var abs: Array = enemy.get("abilities", [])
	if abs.is_empty():
		return ""
	return str(abs[randi() % abs.size()])

static func can_act(creature: Dictionary) -> bool:
	for s in creature.get("statuses", []):
		if str(s.get("id", "")) == STATUS_STUN:
			return false
	return true

static func clear_stun(creature: Dictionary) -> void:
	var kept: Array = []
	for s in creature.get("statuses", []):
		if str(s.get("id", "")) != STATUS_STUN:
			kept.append(s)
	creature["statuses"] = kept

static func execute_ability(user: Dictionary, target: Dictionary, ability_id: String) -> Dictionary:
	var ability: Dictionary = DataRegistry.get_ability(ability_id)
	if ability.is_empty():
		return {"ok": false, "log": "Unknown ability."}

	var acc := int(ability.get("accuracy", 100))
	var user_acc := int(user.get("stats", {}).get("accuracy", 100))
	var hit_chance := int(round(float(acc) * float(user_acc) / 100.0))
	if randi() % 100 >= hit_chance:
		return {
			"ok": true,
			"hit": false,
			"damage": 0,
			"critical": false,
			"ability_id": ability_id,
			"ability_name": ability.get("name", ability_id),
			"log": "%s used %s but missed!" % [user.get("name", "?"), ability.get("name", ability_id)],
			"status_applied": null
		}

	var power := float(ability.get("power", 40))
	var category := str(ability.get("category", "physical"))
	var atk := float(user.get("stats", {}).get("attack", 10))
	var defense := float(target.get("stats", {}).get("defense", 10))
	if category == "special":
		atk = float(user.get("stats", {}).get("special_attack", 10))
		defense = float(target.get("stats", {}).get("special_defense", 10))
	defense = maxf(defense, 1.0)

	var atk_elements: Array = []
	var el = ability.get("element", null)
	if el != null:
		atk_elements = [el]
	else:
		atk_elements = user.get("elements", [])
	var mult := DataRegistry.element_multiplier(atk_elements, target.get("elements", []))

	var base := power * (atk / defense) * 0.45
	var dmg := int(maxi(1, round(base * mult)))

	var crit_chance := int(user.get("stats", {}).get("critical_chance", 5)) + int(ability.get("crit_bonus", 0))
	var critical := randi() % 100 < crit_chance
	if critical:
		dmg = int(round(float(dmg) * 1.5))

	target["hp"] = maxi(0, int(target.get("hp", 0)) - dmg)

	var status_applied = null
	var status_id = ability.get("status", null)
	var status_chance := int(ability.get("status_chance", 0))
	if status_id != null and randi() % 100 < status_chance:
		status_applied = str(status_id)
		_apply_status(target, status_applied)

	var eff := ""
	if mult >= 1.75:
		eff = " It's super effective!"
	elif mult <= 0.6:
		eff = " It's not very effective..."

	var crit_txt := " Critical hit!" if critical else ""
	return {
		"ok": true,
		"hit": true,
		"damage": dmg,
		"critical": critical,
		"ability_id": ability_id,
		"ability_name": ability.get("name", ability_id),
		"element_mult": mult,
		"status_applied": status_applied,
		"log": "%s used %s! Dealt %d damage.%s%s" % [
			user.get("name", "?"), ability.get("name", ability_id), dmg, crit_txt, eff
		]
	}

static func apply_end_of_turn_statuses(creature: Dictionary) -> Array:
	var logs: Array = []
	var remaining: Array = []
	for s in creature.get("statuses", []):
		var sid := str(s.get("id", ""))
		var turns := int(s.get("turns", 1)) - 1
		if sid == STATUS_BURN:
			var burn_dmg := maxi(1, int(creature.get("max_hp", 10) * 0.06))
			creature["hp"] = maxi(0, int(creature.get("hp", 0)) - burn_dmg)
			logs.append("%s is hurt by burn! (-%d)" % [creature.get("name", "?"), burn_dmg])
		elif sid == STATUS_POISON:
			var p_dmg := maxi(1, int(creature.get("max_hp", 10) * 0.08))
			creature["hp"] = maxi(0, int(creature.get("hp", 0)) - p_dmg)
			logs.append("%s is hurt by poison! (-%d)" % [creature.get("name", "?"), p_dmg])
		if turns > 0 and sid != STATUS_STUN:
			s["turns"] = turns
			remaining.append(s)
		elif turns > 0 and sid == STATUS_STUN:
			# Stun lasts the skipped turn only; cleared after skip via clear_stun.
			remaining.append(s)
	creature["statuses"] = remaining
	return logs

static func attempt_flee(player: Dictionary, enemy: Dictionary) -> bool:
	var ps := int(player.get("stats", {}).get("speed", 1))
	var es := int(enemy.get("stats", {}).get("speed", 1))
	var chance := clampf(50.0 + float(ps - es) * 3.0, 15.0, 90.0)
	return randi() % 100 < int(chance)

static func _apply_status(target: Dictionary, status_id: String) -> void:
	for s in target.get("statuses", []):
		if str(s.get("id", "")) == status_id:
			s["turns"] = maxi(int(s.get("turns", 1)), 3)
			return
	var turns := 3
	if status_id == STATUS_STUN:
		turns = 1
	var statuses: Array = target.get("statuses", [])
	statuses.append({"id": status_id, "turns": turns})
	target["statuses"] = statuses
