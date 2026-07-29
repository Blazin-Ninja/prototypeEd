extends RefCounted
class_name AppTheme
## Chimera Bond Phase A visual theme — warm moss + bioluminescent accents.

const FONT_DISPLAY := "res://assets/fonts/Fredoka-Variable.ttf"
const FONT_BODY := "res://assets/fonts/Karla-Regular.ttf"
const FONT_BODY_BOLD := "res://assets/fonts/Karla-Bold.ttf"

const COL_BG := Color(0.06, 0.11, 0.09, 1.0)
const COL_PANEL := Color(0.09, 0.15, 0.13, 0.94)
const COL_TEXT := Color(0.88, 0.95, 0.90, 1.0)
const COL_MUTED := Color(0.62, 0.74, 0.68, 1.0)
const COL_ACCENT := Color(0.45, 0.92, 0.72, 1.0)
const COL_ACCENT_DIM := Color(0.22, 0.45, 0.36, 1.0)
const COL_DANGER := Color(0.95, 0.42, 0.38, 1.0)
const COL_WARN := Color(0.95, 0.78, 0.35, 1.0)

static var _theme: Theme
static var _display: Font
static var _body: Font
static var _body_bold: Font

static func get_theme() -> Theme:
	if _theme != null:
		return _theme
	_load_fonts()
	_theme = Theme.new()
	_theme.default_font = _body
	_theme.default_font_size = 16
	_style_buttons(_theme)
	_style_panels(_theme)
	_style_labels(_theme)
	_style_progress(_theme)
	return _theme

static func apply_to(root: Control) -> void:
	if root == null:
		return
	root.theme = get_theme()

static func display_font() -> Font:
	_load_fonts()
	return _display

static func body_font() -> Font:
	_load_fonts()
	return _body

static func _load_fonts() -> void:
	if _display != null:
		return
	_display = _load_font(FONT_DISPLAY)
	_body = _load_font(FONT_BODY)
	_body_bold = _load_font(FONT_BODY_BOLD)
	if _display == null:
		_display = ThemeDB.fallback_font
	if _body == null:
		_body = ThemeDB.fallback_font
	if _body_bold == null:
		_body_bold = _body

static func _load_font(path: String) -> Font:
	if not ResourceLoader.exists(path):
		return null
	var res = load(path)
	if res is Font:
		return res
	return null

static func _style_buttons(t: Theme) -> void:
	var normal := _tex_style("res://assets/ui/btn_normal.png", 14)
	var hover := _tex_style("res://assets/ui/btn_hover.png", 14)
	var pressed := _tex_style("res://assets/ui/btn_pressed.png", 14)
	var disabled := _tex_style("res://assets/ui/btn_disabled.png", 14)
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_stylebox("focus", "Button", hover)
	t.set_color("font_color", "Button", COL_TEXT)
	t.set_color("font_hover_color", "Button", Color(1, 1, 1, 1))
	t.set_color("font_pressed_color", "Button", COL_ACCENT)
	t.set_color("font_disabled_color", "Button", Color(0.45, 0.5, 0.48, 1))
	t.set_font("font", "Button", _body_bold)
	t.set_font_size("font_size", "Button", 18)
	t.set_constant("h_separation", "Button", 8)

static func _style_panels(t: Theme) -> void:
	var panel := _tex_style("res://assets/ui/panel.png", 18)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)

static func _style_labels(t: Theme) -> void:
	t.set_color("font_color", "Label", COL_TEXT)
	t.set_font("font", "Label", _body)
	t.set_font_size("font_size", "Label", 16)
	t.set_color("default_color", "RichTextLabel", COL_TEXT)
	t.set_font("normal_font", "RichTextLabel", _body)
	t.set_font_size("normal_font_size", "RichTextLabel", 15)

static func _style_progress(t: Theme) -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.12, 0.11, 0.9)
	bg.set_corner_radius_all(8)
	bg.content_margin_left = 2
	bg.content_margin_right = 2
	bg.content_margin_top = 2
	bg.content_margin_bottom = 2
	var fill := StyleBoxFlat.new()
	fill.bg_color = COL_ACCENT
	fill.set_corner_radius_all(6)
	t.set_stylebox("background", "ProgressBar", bg)
	t.set_stylebox("fill", "ProgressBar", fill)

static func _tex_style(path: String, margin: int) -> StyleBox:
	if ResourceLoader.exists(path):
		var tex = load(path)
		if tex is Texture2D:
			var sb := StyleBoxTexture.new()
			sb.texture = tex
			sb.set_texture_margin_all(float(margin))
			sb.set_content_margin_all(12.0)
			return sb
	var flat := StyleBoxFlat.new()
	flat.bg_color = COL_PANEL
	flat.border_color = COL_ACCENT_DIM
	flat.set_border_width_all(2)
	flat.set_corner_radius_all(10)
	flat.set_content_margin_all(12.0)
	return flat

static func style_title(label: Label, size: int = 40) -> void:
	if label == null:
		return
	_load_fonts()
	label.add_theme_font_override("font", _display)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", COL_TEXT)

static func style_muted(label: Label, size: int = 16) -> void:
	if label == null:
		return
	_load_fonts()
	label.add_theme_font_override("font", _body)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", COL_MUTED)
