@tool
class_name CommandInput extends CodeEdit

const KEYWORDS: PackedStringArray = ["if", "for", "end", "return", "fun", "var"]

signal command_submitted(text: String)

@export var height_in_lines: int = 0:
	set(value):
		if is_equal_approx(value, height_in_lines):
			return
		height_in_lines = value
		expand_to(height_in_lines)

var _height_in_lines: float = 0.0:
	set(value):
		if is_equal_approx(value, _height_in_lines):
			return
		_height_in_lines = value
		_update_minimum_size()

var stylebox: StyleBox
var font: Font
var font_size: int

func _ready() -> void:
	text_changed.connect(_on_text_changed)
	text_set.connect(_on_text_changed)

	var number_color := Color(0.804, 0.663, 0.49)
	var txt_color := Color(0.831, 0.831, 0.831)
	var kw_color := Color(0.704, 0.488, 0.836, 1.0)
	var str_color := Color(0.452, 0.767, 0.446, 1.0)

	var hl := CodeHighlighter.new()
	hl.number_color = number_color
	hl.symbol_color = txt_color
	hl.function_color = txt_color
	hl.member_variable_color = txt_color
	for kw in KEYWORDS:
		hl.add_keyword_color(kw, kw_color)
	hl.add_color_region('"', '"', str_color)
	syntax_highlighter = hl

func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		font = get_theme_font(&"font", &"CommandInput")
		if font == null:
			font = get_theme_default_font()
		font_size = get_theme_font_size(&"font_size", &"CommandInput")
		if font_size <= 0:
			font_size = get_theme_default_font_size()
		stylebox = get_theme_stylebox(&"normal", &"CommandInput")
		_update_minimum_size()

func _gui_input(event: InputEvent) -> void:
	var ke := event as InputEventKey
	if ke and ke.is_action("ui_text_newline") and ke.pressed:
		if ke.shift_pressed:
			pass
		else:
			command_submitted.emit(text)
			accept_event()

func _on_text_changed() -> void:
	var line_count := get_line_count()
	height_in_lines = clampi(line_count, 1, 4)
	gutters_draw_line_numbers = line_count >= 4

func _update_minimum_size() -> void:
	if font == null or font_size <= 0:
		custom_minimum_size = Vector2()

	var height := font.get_height(font_size) * _height_in_lines
	if stylebox != null:
		height += stylebox.content_margin_top + stylebox.content_margin_bottom
	custom_minimum_size = get_minimum_size() + Vector2(0.0, height)

var _tween: Tween
func expand_to(height: float) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "_height_in_lines", height, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
