extends Control

const AppTheme = preload("res://scripts/ui/AppTheme.gd")

@onready var tokens_label: Label = $Safe/VBox/Tokens
@onready var continue_btn: Button = $Safe/VBox/ContinueBtn
@onready var new_btn: Button = $Safe/VBox/NewBtn
@onready var shop_btn: Button = $Safe/VBox/ShopBtn
@onready var shop_panel: PanelContainer = $Safe/ShopPanel
@onready var shop_list: VBoxContainer = $Safe/ShopPanel/Margin/VBox/List
@onready var story: Label = $Safe/VBox/Story

func _ready() -> void:
	AppTheme.apply_to(self)
	if has_node("Safe/VBox/Title"):
		AppTheme.style_title($Safe/VBox/Title, 42)
	AppTheme.style_muted(story, 16)
	AppTheme.style_muted(tokens_label, 18)
	if has_node("BG") and $BG is ColorRect:
		($BG as ColorRect).color = AppTheme.COL_BG
	if has_node("BGArt") and ResourceLoader.exists("res://assets/ui/boot_bg.png"):
		$BGArt.texture = load("res://assets/ui/boot_bg.png")
	GameState.refresh_account()
	_refresh()
	shop_panel.visible = false
	continue_btn.pressed.connect(_on_continue)
	new_btn.pressed.connect(_on_new)
	shop_btn.pressed.connect(_toggle_shop)
	$Safe/ShopPanel/Margin/VBox/CloseBtn.pressed.connect(func(): shop_panel.visible = false)

func _refresh() -> void:
	var acc := GameState.account
	tokens_label.text = "Evolution Tokens: %d" % int(acc.get("evolution_tokens", 0))
	continue_btn.disabled = not GameState.has_continue()
	continue_btn.visible = GameState.has_continue()
	story.text = "Thousands of years ago a meteor struck Earth.\nAlien organisms rewrote DNA.\nBond with one creature. Absorb. Evolve. Survive."

func _on_continue() -> void:
	if GameState.continue_run():
		get_tree().change_scene_to_file("res://scenes/overworld/Overworld.tscn")

func _on_new() -> void:
	if GameState.has_continue():
		SaveService.clear_run()
	get_tree().change_scene_to_file("res://scenes/starter/StarterSelect.tscn")

func _toggle_shop() -> void:
	shop_panel.visible = not shop_panel.visible
	if shop_panel.visible:
		_rebuild_shop()

func _rebuild_shop() -> void:
	for c in shop_list.get_children():
		c.queue_free()
	GameState.refresh_account()
	tokens_label.text = "Evolution Tokens: %d" % int(GameState.account.get("evolution_tokens", 0))
	for entry in ProgressionSystem.shop_entries(GameState.account):
		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var owned := bool(entry.get("owned", false))
		lbl.text = "%s (%d tok)\n%s" % [entry.get("name"), entry.get("cost"), entry.get("description")]
		row.add_child(lbl)
		var btn := Button.new()
		btn.text = "Owned" if owned else "Buy"
		btn.disabled = owned
		var unlock_id := str(entry.get("id"))
		btn.pressed.connect(_buy.bind(unlock_id))
		row.add_child(btn)
		shop_list.add_child(row)

func _buy(unlock_id: String) -> void:
	var res := GameState.buy_unlock(unlock_id)
	_rebuild_shop()
	_refresh()
	if not res.get("ok", false):
		tokens_label.text = "%s — %s" % [tokens_label.text, res.get("message", "")]
