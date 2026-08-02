extends Control
## Turn-based battle UI — monsters only, with simple attack FX.

const LevelSystem = preload("res://scripts/domain/LevelSystem.gd")
const AppTheme = preload("res://scripts/ui/AppTheme.gd")
const BattleArt = preload("res://scripts/util/BattleArt.gd")
const BATTLE_GFX_SCALE := 1.55

@onready var log_box: RichTextLabel = $Safe/VBox/LogPanel/LogMargin/Log
@onready var player_hp: ProgressBar = $Safe/VBox/PlayerPanel/PlayerMargin/PlayerCol/PHP
@onready var enemy_hp: ProgressBar = $Safe/VBox/EnemyPanel/EnemyMargin/EnemyCol/EHP
@onready var player_hp_text: Label = $Safe/VBox/PlayerPanel/PlayerMargin/PlayerCol/PHPText
@onready var enemy_hp_text: Label = $Safe/VBox/EnemyPanel/EnemyMargin/EnemyCol/EHPText
@onready var player_name: Label = $Safe/VBox/PlayerPanel/PlayerMargin/PlayerCol/PName
@onready var enemy_name: Label = $Safe/VBox/EnemyPanel/EnemyMargin/EnemyCol/EName
@onready var enemy_meta: Label = $Safe/VBox/EnemyPanel/EnemyMargin/EnemyCol/EMeta
@onready var player_view: Control = $Safe/VBox/PlayerPanel/PlayerMargin/PlayerCol/PView
@onready var enemy_view: Control = $Safe/VBox/EnemyPanel/EnemyMargin/EnemyCol/EView
@onready var action_row: HBoxContainer = $Safe/VBox/Actions
@onready var ability_list: VBoxContainer = $Safe/VBox/AbilityList
@onready var bg: ColorRect = $BG
@onready var bg_accent: ColorRect = $BGAccent
@onready var enemy_panel: PanelContainer = $Safe/VBox/EnemyPanel
@onready var player_panel: PanelContainer = $Safe/VBox/PlayerPanel
@onready var log_panel: PanelContainer = $Safe/VBox/LogPanel
@onready var fx_layer: Control = $FXLayer
@onready var heal_btn: Button = $Safe/VBox/Actions/HealBtn
@onready var revive_row: HBoxContainer = $Safe/VBox/ReviveRow
@onready var revive_btn: Button = $Safe/VBox/ReviveRow/ReviveBtn
@onready var give_up_btn: Button = $Safe/VBox/ReviveRow/GiveUpBtn

var player: Dictionary = {}
var enemy: Dictionary = {}
var can_flee := true
var busy := false
var is_boss := false
var _anim_t := 0.0
var _pending_shard_drop_log := ""
var _awaiting_revive_choice := false

# Motion / hit feedback
var _player_lunge := 0.0
var _enemy_lunge := 0.0
var _player_hit := 0.0
var _enemy_hit := 0.0
var _player_miss := 0.0
var _enemy_miss := 0.0

# Attack VFX state (drawn on FXLayer)
var _fx_active := false
var _fx_t := 0.0
var _fx_duration := 0.4
var _fx_from_player := true
var _fx_kind := "physical" # physical | special | miss
var _fx_color := Color(1, 0.85, 0.4, 1)
var _fx_critical := false
var _fx_impact := 0.0

func _ready() -> void:
	var pending: Dictionary = GameState.pending_battle
	if pending.is_empty():
		get_tree().change_scene_to_file("res://scenes/overworld/Overworld.tscn")
		return
	AppTheme.apply_to(self)
	BossSprites.ensure_loaded()
	BattleArt.ensure_loaded()
	player = GameState.get_companion().duplicate(true)
	enemy = pending.get("enemy", {}).duplicate(true)
	can_flee = bool(pending.get("can_flee", true))
	is_boss = bool(pending.get("is_boss", false))
	_apply_arena_backdrop()
	_style_panels()
	player_view.draw.connect(_draw_player_battle)
	enemy_view.draw.connect(_draw_enemy_battle)
	fx_layer.draw.connect(_draw_fx)
	$Safe/VBox/Actions/FightBtn.pressed.connect(_show_abilities)
	$Safe/VBox/Actions/FleeBtn.pressed.connect(_flee)
	$Safe/VBox/Actions/FleeBtn.disabled = not can_flee
	heal_btn.pressed.connect(_use_bond_shard)
	revive_btn.pressed.connect(_confirm_shard_revive)
	give_up_btn.pressed.connect(_confirm_give_up)
	revive_row.visible = false
	_refresh()
	var intro := "%s wants to battle!" % enemy.get("name", "Enemy")
	if is_boss:
		intro = "[b]BOSS[/b] — %s blocks the path!" % enemy.get("name", "Enemy")
	elif enemy.get("is_obelisk_guardian", false):
		var stage := clampi(int(enemy.get("obelisk_stage", 1)), 1, 3)
		var hue := str(enemy.get("obelisk_hue", "cyan")).capitalize()
		intro = "[b]OBELISK %d/3 · %s[/b] — %s answers the call!" % [
			stage, hue, enemy.get("name", "Guardian")
		]
	_append(intro)

func _apply_arena_backdrop() -> void:
	var region := GameState.current_region()
	var rid := str(region.get("id", "forest"))
	var tex := BattleArt.arena_for_region(rid)
	if tex == null:
		return
	var arena := TextureRect.new()
	arena.name = "ArenaBG"
	arena.set_anchors_preset(Control.PRESET_FULL_RECT)
	arena.offset_left = 0
	arena.offset_top = 0
	arena.offset_right = 0
	arena.offset_bottom = 0
	arena.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	arena.stretch_mode = TextureRect.STRETCH_SCALE
	arena.texture = tex
	arena.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(arena)
	move_child(arena, 0)
	if bg:
		bg.color = Color(0.02, 0.03, 0.05, 0.35)
	if bg_accent:
		bg_accent.color = Color(0.05, 0.05, 0.08, 0.25)

func _use_bond_shard() -> void:
	if busy:
		return
	busy = true
	ability_list.visible = false
	_set_actions_enabled(false)

	# Stunned: the attempt spends the turn, but no shard is consumed.
	if not CombatSystem.can_act(player):
		_append("%s is stunned and can't move!" % player.get("name"))
		CombatSystem.clear_stun(player)
		_refresh()
		await get_tree().create_timer(0.2).timeout
		await _finish_player_action_turn()
		return

	if not GameState.can_use_bond_shard():
		_append("No Bond Shards left.")
		busy = false
		_set_actions_enabled(true)
		return
	if int(player.get("hp", 0)) >= int(player.get("max_hp", 1)):
		_append("Already at full health.")
		busy = false
		_set_actions_enabled(true)
		return
	if not GameState.consume_bond_shard():
		_append("No Bond Shards left.")
		busy = false
		_set_actions_enabled(true)
		return
	var res := CombatSystem.use_bond_shard(player)
	if not bool(res.get("ok", false)):
		# Refund if heal somehow failed after consume.
		GameState.set_bond_shards(GameState.get_bond_shards() + 1)
		_append(str(res.get("log", "Bond Shard failed.")))
		busy = false
		_set_actions_enabled(true)
		_refresh()
		return
	_append(str(res.get("log", "Used a Bond Shard.")))
	GameState.set_companion(player)
	_refresh()
	await get_tree().create_timer(0.25).timeout
	await _finish_player_action_turn()

func _finish_player_action_turn() -> void:
	if int(player.get("hp", 0)) > 0 and int(enemy.get("hp", 0)) > 0:
		await _do_enemy_action()
	for log in CombatSystem.apply_end_of_turn_statuses(player):
		_append(str(log))
	for log in CombatSystem.apply_end_of_turn_statuses(enemy):
		_append(str(log))
	GameState.set_companion(player)
	_refresh()
	if int(enemy.get("hp", 0)) <= 0:
		await _victory()
		return
	if int(player.get("hp", 0)) <= 0:
		await _on_player_fallen()
		return
	busy = false
	_set_actions_enabled(true)

func _process(delta: float) -> void:
	_anim_t += delta
	_player_lunge = maxf(0.0, _player_lunge - delta * 4.0)
	_enemy_lunge = maxf(0.0, _enemy_lunge - delta * 4.0)
	_player_hit = maxf(0.0, _player_hit - delta * 2.8)
	_enemy_hit = maxf(0.0, _enemy_hit - delta * 2.8)
	_player_miss = maxf(0.0, _player_miss - delta * 3.0)
	_enemy_miss = maxf(0.0, _enemy_miss - delta * 3.0)
	if _fx_impact > 0.0:
		_fx_impact = maxf(0.0, _fx_impact - delta * 3.5)
	if _fx_active:
		_fx_t += delta
		if _fx_t >= _fx_duration:
			_fx_active = false
	enemy_view.queue_redraw()
	player_view.queue_redraw()
	fx_layer.queue_redraw()

func _style_panels() -> void:
	var accent := Color(0.14, 0.12, 0.2, 0.65)
	if is_boss:
		var tid := str(enemy.get("template_id", enemy.get("id", "")))
		accent = BossSprites._theme_color(tid)
		accent = Color(accent.r * 0.25, accent.g * 0.2, accent.b * 0.3, 0.7)
	elif not enemy.get("elements", []).is_empty():
		var eid := str(enemy.get("elements", [])[0])
		if DataRegistry.elements.has(eid):
			accent = Color.html(str(DataRegistry.elements[eid].get("color", "#333333")))
			accent = Color(accent.r * 0.2, accent.g * 0.18, accent.b * 0.25, 0.65)
	bg_accent.color = accent
	# Opaque log chrome above FX so combat subtitles stay readable.
	var log_style := StyleBoxFlat.new()
	log_style.bg_color = Color(0.05, 0.09, 0.08, 0.96)
	log_style.border_color = Color(0.28, 0.48, 0.40, 1.0)
	log_style.set_border_width_all(2)
	log_style.set_corner_radius_all(10)
	log_style.set_content_margin_all(8.0)
	log_panel.add_theme_stylebox_override("panel", log_style)
	log_box.add_theme_font_size_override("normal_font_size", 18)
	log_box.add_theme_color_override("default_color", AppTheme.COL_TEXT)
	player_view.clip_contents = true
	enemy_view.clip_contents = true

func _creature_offset(is_player_side: bool) -> Vector2:
	var lunge := _player_lunge if is_player_side else _enemy_lunge
	var hit := _player_hit if is_player_side else _enemy_hit
	var miss := _player_miss if is_player_side else _enemy_miss
	# Player lunges up toward enemy; enemy lunges down toward player.
	var dir := Vector2(0, -1) if is_player_side else Vector2(0, 1)
	var shake := Vector2.ZERO
	if hit > 0.0:
		shake = Vector2(sin(_anim_t * 55.0) * 12.0 * hit, cos(_anim_t * 40.0) * 5.0 * hit)
	if miss > 0.0:
		shake += Vector2(sin(_anim_t * 30.0) * 16.0 * miss, 0)
	return dir * (56.0 * lunge) + shake

func _draw_player_battle() -> void:
	var mid := player_view.size * 0.5 + _creature_offset(true)
	var radius := minf(player_view.size.x, player_view.size.y) * 0.42 * BATTLE_GFX_SCALE
	player_view.draw_circle(player_view.size * 0.5 + Vector2(0, player_view.size.y * 0.28), radius * 0.85, Color(0, 0, 0, 0.25))
	if _player_hit > 0.0:
		player_view.modulate = Color(1.0, 1.0 - _player_hit * 0.35, 1.0 - _player_hit * 0.35, 1)
	else:
		player_view.modulate = Color.WHITE
	PlaceholderArt.draw_creature(player_view, player, mid + Vector2(0, -6), radius, _anim_t)

func _draw_enemy_battle() -> void:
	var mid := enemy_view.size * 0.5 + _creature_offset(false)
	var radius := minf(enemy_view.size.x, enemy_view.size.y) * (0.46 if is_boss else 0.40) * BATTLE_GFX_SCALE
	enemy_view.draw_circle(enemy_view.size * 0.5 + Vector2(0, radius * 0.75), radius * 0.85, Color(0, 0, 0, 0.28))
	if _enemy_hit > 0.0:
		enemy_view.modulate = Color(1, 1.0 - _enemy_hit * 0.35, 1.0 - _enemy_hit * 0.35, 1)
	else:
		enemy_view.modulate = Color.WHITE
	PlaceholderArt.draw_creature(enemy_view, enemy, mid + Vector2(0, -8), radius, _anim_t)

func _view_center_global(view: Control) -> Vector2:
	return view.get_global_rect().get_center()

func _draw_fx() -> void:
	if not _fx_active and _fx_impact <= 0.0:
		return
	var from_src: Control = player_view if _fx_from_player else enemy_view
	var to_src: Control = enemy_view if _fx_from_player else player_view
	var from_pt: Vector2 = fx_layer.to_local(_view_center_global(from_src))
	var to_pt: Vector2 = fx_layer.to_local(_view_center_global(to_src))

	var p: float = clampf(_fx_t / maxf(_fx_duration, 0.001), 0.0, 1.0)
	var col: Color = _fx_color
	var bolt_tex: Texture2D = BattleArt.fx("bolt")
	var slash_tex: Texture2D = BattleArt.fx("slash")
	var impact_tex: Texture2D = BattleArt.fx("impact")
	var miss_tex: Texture2D = BattleArt.fx("miss")

	if _fx_active:
		if _fx_kind == "special":
			var ease_p: float = p * p * (3.0 - 2.0 * p)
			var pos: Vector2 = from_pt.lerp(to_pt, ease_p)
			var arc: float = sin(ease_p * PI) * 48.0
			pos += Vector2(arc * (1.0 if _fx_from_player else -1.0), -arc * 0.6)
			for i in range(4):
				var tp: float = clampf(ease_p - float(i) * 0.06, 0.0, 1.0)
				var tpos: Vector2 = from_pt.lerp(to_pt, tp)
				var tarc: float = sin(tp * PI) * 48.0
				tpos += Vector2(tarc * (1.0 if _fx_from_player else -1.0), -tarc * 0.6)
				var trail_a: float = 0.55 - float(i) * 0.12
				fx_layer.draw_circle(tpos, 14.0 - float(i) * 2.0, Color(col.r, col.g, col.b, trail_a))
			if bolt_tex != null:
				var bsz := 56.0 if _fx_critical else 44.0
				fx_layer.draw_texture_rect(bolt_tex, Rect2(pos - Vector2(bsz, bsz) * 0.5, Vector2(bsz, bsz)), false, col)
			else:
				fx_layer.draw_circle(pos, 20.0 if not _fx_critical else 26.0, col)
				fx_layer.draw_circle(pos, 8.0, Color(1, 1, 1, 0.95))
		elif _fx_kind == "physical":
			if p > 0.25 and p < 0.9:
				var slash_p: float = (p - 0.25) / 0.65
				var mid: Vector2 = from_pt.lerp(to_pt, 0.68)
				if slash_tex != null:
					var ssz := Vector2(110.0 if _fx_critical else 90.0, 70.0)
					var tint := Color(col.r, col.g, col.b, 0.95 - slash_p * 0.35)
					fx_layer.draw_texture_rect(slash_tex, Rect2(mid - ssz * 0.5, ssz), false, tint)
				else:
					var ang: float = (-0.7 if _fx_from_player else 0.7) + slash_p * 0.5
					var slash_len: float = 72.0 + (18.0 if _fx_critical else 0.0)
					var axis: Vector2 = Vector2(cos(ang), sin(ang)) * slash_len
					var width_col := Color(col.r, col.g, col.b, 0.95 - slash_p * 0.4)
					fx_layer.draw_line(mid - axis, mid + axis, width_col, 10.0 if _fx_critical else 7.0)
		elif _fx_kind == "miss":
			var miss_pos: Vector2 = from_pt.lerp(to_pt, minf(p * 1.2, 0.85))
			var miss_a: float = 0.55 * (1.0 - p)
			if miss_tex != null:
				var msz := 48.0 + p * 20.0
				fx_layer.draw_texture_rect(miss_tex, Rect2(miss_pos - Vector2(msz, msz) * 0.5, Vector2(msz, msz)), false, Color(1, 1, 1, miss_a))
			else:
				fx_layer.draw_circle(miss_pos, 16.0 + p * 10.0, Color(0.85, 0.85, 0.9, miss_a))

	if _fx_impact > 0.0:
		var burst: Vector2 = to_pt
		var impact_a: float = _fx_impact
		var r: float = 28.0 + (1.0 - impact_a) * 52.0
		if impact_tex != null:
			var isz := r * 2.2
			fx_layer.draw_texture_rect(impact_tex, Rect2(burst - Vector2(isz, isz) * 0.5, Vector2(isz, isz)), false, Color(col.r, col.g, col.b, 0.85 * impact_a))
		else:
			fx_layer.draw_circle(burst, r, Color(col.r, col.g, col.b, 0.45 * impact_a))
			fx_layer.draw_circle(burst, r * 0.45, Color(1, 1, 1, 0.7 * impact_a))
		for i in range(6):
			var bang: float = float(i) * TAU / 6.0 + _anim_t * 2.0
			var outer: Vector2 = Vector2(cos(bang), sin(bang)) * (r * 1.15)
			var inner: Vector2 = Vector2(cos(bang), sin(bang)) * (r * 0.55)
			fx_layer.draw_line(burst + inner, burst + outer, Color(col.r, col.g, col.b, 0.7 * impact_a), 3.0)

func _ability_fx_color(ability_id: String) -> Color:
	var ab: Dictionary = DataRegistry.get_ability(ability_id)
	var el = ab.get("element", null)
	if el != null and DataRegistry.elements.has(str(el)):
		return Color.html(str(DataRegistry.elements[str(el)].get("color", "#ffcc66")))
	if str(ab.get("category", "physical")) == "special":
		return Color(0.55, 0.75, 1.0)
	return Color(1.0, 0.85, 0.45)

func _play_attack_fx(from_player: bool, ability_id: String, hit: bool, critical: bool) -> void:
	var ab: Dictionary = DataRegistry.get_ability(ability_id)
	var category := str(ab.get("category", "physical"))
	_fx_from_player = from_player
	_fx_color = _ability_fx_color(ability_id)
	_fx_critical = critical
	_fx_t = 0.0
	if not hit:
		_fx_kind = "miss"
		_fx_duration = 0.35
		if from_player:
			_player_lunge = 0.55
			_enemy_miss = 1.0
		else:
			_enemy_lunge = 0.55
			_player_miss = 1.0
	elif category == "special":
		_fx_kind = "special"
		_fx_duration = 0.48
		if from_player:
			_player_lunge = 0.35
		else:
			_enemy_lunge = 0.35
	else:
		_fx_kind = "physical"
		_fx_duration = 0.38
		if from_player:
			_player_lunge = 1.0
		else:
			_enemy_lunge = 1.0
	_fx_active = true
	# Wait until near impact, then apply hit feedback
	var impact_at := _fx_duration * (0.72 if _fx_kind == "special" else 0.55)
	await get_tree().create_timer(impact_at).timeout
	if hit:
		_fx_impact = 1.0
		if from_player:
			_enemy_hit = 1.0
		else:
			_player_hit = 1.0
	# Finish remaining animation
	var remain := maxf(0.05, _fx_duration - impact_at + 0.08)
	await get_tree().create_timer(remain).timeout

func _refresh() -> void:
	LevelSystem.ensure_fields(player)
	player_name.text = "%s  ·  Lv %d" % [str(player.get("name", "You")), int(player.get("level", 1))]
	enemy_name.text = "%s  ·  Lv %d" % [str(enemy.get("name", "Enemy")), int(enemy.get("level", 1))]
	var tags: Array = []
	if is_boss:
		tags.append("BOSS")
	if enemy.get("is_obelisk_guardian", false):
		tags.append("OBELISK")
	if enemy.get("is_alpha", false):
		tags.append("ALPHA")
	if enemy.get("is_legendary", false):
		tags.append("LEGENDARY")
	var els: Array = enemy.get("elements", [])
	if not els.is_empty():
		var names: PackedStringArray = []
		for e in els:
			var id := str(e)
			if DataRegistry.elements.has(id):
				names.append(str(DataRegistry.elements[id].get("name", id)))
			else:
				names.append(id.capitalize())
		tags.append(" · ".join(names))
	enemy_meta.text = " · ".join(PackedStringArray(tags))
	player_hp.max_value = float(player.get("max_hp", 1))
	player_hp.value = float(player.get("hp", 0))
	enemy_hp.max_value = float(enemy.get("max_hp", 1))
	enemy_hp.value = float(enemy.get("hp", 0))
	player_hp_text.text = "HP %d / %d   ·   Shards %d/%d" % [
		int(player.get("hp", 0)),
		int(player.get("max_hp", 1)),
		GameState.get_bond_shards(),
		GameState.BOND_SHARD_CAP
	]
	enemy_hp_text.text = "HP %d / %d" % [int(enemy.get("hp", 0)), int(enemy.get("max_hp", 1))]
	_tint_hp_bar(player_hp, float(player.get("hp", 0)) / maxf(float(player.get("max_hp", 1)), 1.0))
	_tint_hp_bar(enemy_hp, float(enemy.get("hp", 0)) / maxf(float(enemy.get("max_hp", 1)), 1.0))
	heal_btn.text = "SHARD\n%d/%d" % [GameState.get_bond_shards(), GameState.BOND_SHARD_CAP]
	player_view.queue_redraw()
	enemy_view.queue_redraw()
	GameState.set_companion(player)
	GameState.autosave()

func _tint_hp_bar(bar: ProgressBar, ratio: float) -> void:
	var col := Color(0.3, 0.85, 0.45)
	if ratio < 0.5:
		col = Color(0.95, 0.75, 0.25)
	if ratio < 0.25:
		col = Color(0.95, 0.3, 0.3)
	bar.modulate = col

func _append(text: String) -> void:
	log_box.append_text(text + "\n")

func _set_actions_enabled(on: bool) -> void:
	for c in action_row.get_children():
		if c is Button:
			c.disabled = not on
	if on:
		$Safe/VBox/Actions/FleeBtn.disabled = not can_flee
		var can_shard := GameState.can_use_bond_shard() and int(player.get("hp", 0)) < int(player.get("max_hp", 1))
		heal_btn.disabled = not can_shard
		heal_btn.text = "SHARD\n%d/%d" % [GameState.get_bond_shards(), GameState.BOND_SHARD_CAP]

func _show_abilities() -> void:
	if busy:
		return
	for c in ability_list.get_children():
		c.queue_free()
	ability_list.visible = true
	for aid in player.get("abilities", []):
		var ab: Dictionary = DataRegistry.get_ability(str(aid))
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(0, 56)
		var el = ab.get("element", null)
		var el_txt := str(el).capitalize() if el != null else "Neutral"
		btn.text = "%s   ·   %s   ·   Pwr %d" % [ab.get("name", aid), el_txt, ab.get("power", 0)]
		btn.pressed.connect(_player_act.bind(str(aid)))
		ability_list.add_child(btn)
	var cancel := Button.new()
	cancel.custom_minimum_size = Vector2(0, 48)
	cancel.text = "Cancel"
	cancel.pressed.connect(func(): ability_list.visible = false)
	ability_list.add_child(cancel)

func _player_act(ability_id: String) -> void:
	if busy:
		return
	busy = true
	ability_list.visible = false
	_set_actions_enabled(false)
	await _resolve_turn(ability_id)
	busy = false

func _flee() -> void:
	if busy or not can_flee:
		return
	busy = true
	_set_actions_enabled(false)
	if CombatSystem.attempt_flee(player, enemy):
		_append("Got away safely!")
		GameState.set_companion(player)
		GameState.autosave()
		await get_tree().create_timer(0.6).timeout
		get_tree().change_scene_to_file("res://scenes/overworld/Overworld.tscn")
	else:
		_append("Couldn't escape!")
		await _enemy_turn_only()
		busy = false
		_set_actions_enabled(true)

func _resolve_turn(player_ability: String) -> void:
	var order := CombatSystem.initiative_order(player, enemy)
	for actor in order:
		if int(player.get("hp", 0)) <= 0 or int(enemy.get("hp", 0)) <= 0:
			break
		if actor.get("instance_id") == player.get("instance_id"):
			if not CombatSystem.can_act(player):
				_append("%s is stunned and can't move!" % player.get("name"))
				CombatSystem.clear_stun(player)
			else:
				var res := CombatSystem.execute_ability(player, enemy, player_ability)
				await _play_attack_fx(
					true,
					player_ability,
					bool(res.get("hit", false)),
					bool(res.get("critical", false))
				)
				_append(str(res.get("log", "")))
				if res.get("status_applied", null) != null:
					_append("%s inflicted %s!" % [player.get("name"), res.get("status_applied")])
		else:
			await _do_enemy_action()
		_refresh()
		await get_tree().create_timer(0.2).timeout

	for log in CombatSystem.apply_end_of_turn_statuses(player):
		_append(str(log))
	for log in CombatSystem.apply_end_of_turn_statuses(enemy):
		_append(str(log))
	_refresh()

	if int(enemy.get("hp", 0)) <= 0:
		await _victory()
		return
	if int(player.get("hp", 0)) <= 0:
		await _on_player_fallen()
		return
	_set_actions_enabled(true)

func _enemy_turn_only() -> void:
	await _do_enemy_action()
	for log in CombatSystem.apply_end_of_turn_statuses(player):
		_append(str(log))
	for log in CombatSystem.apply_end_of_turn_statuses(enemy):
		_append(str(log))
	_refresh()
	if int(player.get("hp", 0)) <= 0:
		await _on_player_fallen()

func _do_enemy_action() -> void:
	if not CombatSystem.can_act(enemy):
		_append("%s is stunned and can't move!" % enemy.get("name"))
		CombatSystem.clear_stun(enemy)
		return
	var aid := CombatSystem.choose_enemy_ability(enemy)
	if aid == "":
		return
	var res := CombatSystem.execute_ability(enemy, player, aid)
	await _play_attack_fx(
		false,
		aid,
		bool(res.get("hit", false)),
		bool(res.get("critical", false))
	)
	_append(str(res.get("log", "")))
	if res.get("status_applied", null) != null:
		_append("%s inflicted %s!" % [enemy.get("name"), res.get("status_applied")])

func _victory() -> void:
	_append("%s was defeated!" % enemy.get("name"))
	# Bonus uses bosses already cleared — current boss is marked after XP grant.
	var xp_result: Dictionary = LevelSystem.grant_battle_xp(
		player, enemy, is_boss, GameState.bosses_defeated_count()
	)
	var xp_gained := int(xp_result.get("xp_gained", 0))
	if xp_gained > 0:
		_append("%s gained %d XP." % [player.get("name"), xp_gained])
	for line in xp_result.get("logs", []):
		_append(str(line))
	player["hp"] = int(player.get("max_hp", player.get("hp", 1)))
	player["statuses"] = []
	GameState.set_companion(player)
	if is_boss:
		GameState.mark_boss_defeated(str(enemy.get("template_id", enemy.get("id"))))
	GameState.end_battle_victory(enemy)
	var bonus_log := str(GameState.run.get("pending_obelisk_bonus_log", ""))
	if bonus_log != "":
		GameState.run["pending_obelisk_bonus_log"] = ""
		_append(bonus_log)
		await get_tree().create_timer(0.45).timeout
	var drop: Dictionary = GameState.try_grant_bond_shard_drop(enemy, is_boss)
	if bool(drop.get("granted", false)):
		_append(str(drop.get("log", "Found a Bond Shard!")))
		await get_tree().create_timer(0.55).timeout
	var region := GameState.current_region()
	if str(region.get("id")) == "meteor_hive" and is_boss:
		GameState.last_run_report = GameState.end_run(true)
		await get_tree().create_timer(0.8).timeout
		get_tree().change_scene_to_file("res://scenes/run_end/RunEnd.tscn")
		return
	await get_tree().create_timer(0.7).timeout
	get_tree().change_scene_to_file("res://scenes/absorb/AbsorbDecision.tscn")

func _on_player_fallen() -> void:
	busy = true
	ability_list.visible = false
	_set_actions_enabled(false)
	GameState.set_companion(player)
	if not GameState.can_shard_revive():
		await _defeat()
		return
	_awaiting_revive_choice = true
	_append("%s has fallen! Spend %d Bond Shards to revive, or give up." % [
		player.get("name"),
		GameState.BOND_SHARD_REVIVE_COST
	])
	revive_btn.text = "REVIVE (%d shards · %d left)" % [
		GameState.BOND_SHARD_REVIVE_COST,
		GameState.get_shard_revives_left()
	]
	action_row.visible = false
	revive_row.visible = true

func _confirm_shard_revive() -> void:
	if not _awaiting_revive_choice:
		return
	_awaiting_revive_choice = false
	revive_row.visible = false
	action_row.visible = true
	var res: Dictionary = GameState.try_shard_revive(player)
	if not bool(res.get("ok", false)):
		_append(str(res.get("log", "Revive failed.")))
		await _defeat()
		return
	_append(str(res.get("log", "Revived!")))
	GameState.set_companion(player)
	_refresh()
	busy = false
	_set_actions_enabled(true)

func _confirm_give_up() -> void:
	if not _awaiting_revive_choice:
		return
	_awaiting_revive_choice = false
	revive_row.visible = false
	action_row.visible = true
	await _defeat()

func _defeat() -> void:
	_awaiting_revive_choice = false
	revive_row.visible = false
	action_row.visible = true
	_append("%s has fallen... The bond is broken." % player.get("name"))
	GameState.set_companion(player)
	GameState.last_run_report = GameState.end_run(false)
	await get_tree().create_timer(1.0).timeout
	get_tree().change_scene_to_file("res://scenes/run_end/RunEnd.tscn")
