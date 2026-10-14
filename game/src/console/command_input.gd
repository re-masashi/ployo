@tool
class_name CommandInput extends CodeEdit

const KEYWORDS: PackedStringArray = [
	"if",
	"for",
	"end",
	"fun",
	"var",
	"else",
	"true",
	"false",
	"break",
	"return",
	"continue",
]

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
var errors: Array[Dictionary]:
	set(value):
		errors = value
		queue_redraw()
var file: ConsoleLanguage.File

func is_deletable(ch: String) -> bool:
	if ch == "$": return true
	if ch == "_": return true
	if ord(ch) >= ord("a") and ord(ch) <= ord("z"): return true
	if ord(ch) >= ord("A") and ord(ch) <= ord("Z"): return true
	return false

func _confirm_code_completion(_replace: bool) -> void:
	var option := get_code_completion_option(get_code_completion_selected_index())
	for caret_index in get_caret_count():
		var line_index := get_caret_line(caret_index)
		var line_text := get_line(line_index)
		var caret_column := clampi(get_caret_column(caret_index), 0, maxi(0, line_text.length() - 1))
		var i := caret_column
		while i >= 0:
			if not is_deletable(line_text[i]):
				break
			backspace(caret_index)
			i -= 1
	insert_text_at_caret(option.insert_text + " ")
	cancel_code_completion.call_deferred()

func _ready() -> void:
	code_completion_enabled = true
	code_completion_prefixes = ["$"]

	text_changed.connect(_on_text_changed)
	text_set.connect(_on_text_changed)
	#lines_edited_from.connect(_on_lines_edited_from, CONNECT_DEFERRED)

	syntax_highlighter = ConsoleSyntaxHighlighter.new()

	get_h_scroll_bar().value_changed.connect(queue_redraw.unbind(1))
	get_v_scroll_bar().value_changed.connect(queue_redraw.unbind(1))

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

func _draw() -> void:
		for error in errors:
			var err_range: Vector4i = error[ConsoleLanguage.RANGE]
			for line in range(err_range.x, err_range.z + 1):
				var start := err_range.y if line == err_range.x else 0
				var end := err_range.w if line == err_range.z else get_line(line).length()
				_draw_underline(line, start, end)

func _draw_underline(line: int, from_col: int, to_col: int) -> void:
	var descent := font.get_underline_position(font_size) + font.get_ascent(font_size)
	var line_string := get_line(line)
	var left := Vector2(get_rect_at_line_column(line, mini(from_col + 1, line_string.length())).position) + Vector2(0, descent)
	var right := get_rect_at_line_column(line, mini(to_col, line_string.length()))
	var real_right_pos := right.position.x + right.size.x
	var width := real_right_pos - left.x
	draw_rect(Rect2(left, Vector2(width, 2.0)), Console.C_THEME.red)

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
	height_in_lines = clampi(line_count, 2, 10)
	gutters_draw_line_numbers = line_count >= 3

	reparse()
	var completions := ConsoleLanguage.get_environment_of(preload("test_commands.gd").new())
	if file != null:
		var caret_pos := Vector2i(get_caret_line(), get_caret_column())
		file.add_completion_env(caret_pos, completions)
	for caret_index in get_caret_count():
		var line_index := get_caret_line(caret_index)
		var line_text := get_line(line_index)
		if line_text.substr(clampi(get_caret_column(caret_index), 0, maxi(0, line_text.length() - 1)), 1) == "$":
			for variable_name in completions.variables:
				add_code_completion_option(CodeEdit.KIND_VARIABLE, "$" + variable_name, "$" + variable_name)
			for method_name in completions.methods:
				add_code_completion_option(CodeEdit.KIND_FUNCTION, method_name, method_name)
			update_code_completion_options(true)
			return

	for variable_name in completions.variables:
		add_code_completion_option(CodeEdit.KIND_VARIABLE, "$" + variable_name, "$" + variable_name)
	for method_name in completions.methods:
		add_code_completion_option(CodeEdit.KIND_FUNCTION, method_name, method_name)
	update_code_completion_options(false)
	request_code_completion()

#func _on_lines_edited_from(_from_line: int, _to_line: int) -> void:
#	(func():
#	).call_deferred()

func reparse() -> void:
	var command := text
	#file = null
	errors = []
	var tokens := ConsoleLanguage.new().tokenize(command)
	if tokens.has_error:
		errors = tokens.errors
		return
	var parser := ConsoleLanguage.Parser.new()
	parser.tokens = tokens.tokens
	file = parser.parse_file()
	if not parser.errors.is_empty():
		errors = parser.errors
	return

func _update_minimum_size() -> void:
	var height := get_line_height() * _height_in_lines
	if stylebox != null:
		height += stylebox.content_margin_top + stylebox.content_margin_bottom
	custom_minimum_size = get_minimum_size() + Vector2(0.0, height)

var _tween: Tween
func expand_to(height: float) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "_height_in_lines", height, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
