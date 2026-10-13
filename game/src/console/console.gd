@tool
class_name Console extends Window

const C_THEME := preload("res://src/console/catppuccins/mocha.tres")

@onready var terminal: Terminal = %Terminal
@onready var command_input: CommandInput = %CommandInput

var methods: Array[ConsoleLanguage.MethodInfo]

var logger: RobertLogger

func _init() -> void:
	logger = RobertLogger.new()
	logger.console = self

	theme = make_theme()

func _ready() -> void:
	command_input.command_submitted.connect(execute_command)

func spans_to_bbcode(text: String, spans: Array[Dictionary]) -> String:
	var sb: PackedStringArray
	for i in text.length():
		var spans_im_in: Array[Dictionary] = []
		for span in spans:
			if i >= span.start and i < span.end:
				spans_im_in.append(span)
		for span in spans_im_in:
			sb.append(span.open)
		sb.append(text[i])
		var spans_im_in_backwards := spans_im_in
		spans_im_in_backwards.reverse()
		for span in spans_im_in_backwards:
			sb.append(span.close)
	return "".join(sb)

func highlight_line(line: String, extra_spans: Array[Dictionary] = []) -> String:
	var hl_tokens := ConsoleSyntaxHighlighter.get_line_syntax_highlighting_tokens(line)
	var spans: Array[Dictionary]
	for pos in hl_tokens:
		if not spans.is_empty():
			spans[-1].end = pos
		spans.append({
			start = pos,
			end = line.length(),
			open = "[c2 c=%s]" % hl_tokens[pos].color,
			close = "[/c2]"
		})
	spans.append_array(extra_spans)
	return spans_to_bbcode(line, spans)

func execute_command(command: String) -> void:
	var start_time := Time.get_ticks_usec()
	terminal.add_hr(100, 2, C_THEME.surface0, HORIZONTAL_ALIGNMENT_LEFT)
	terminal.newline()
	var result = _execute_command(command)
	var end_time := Time.get_ticks_usec()
	var delta := (end_time - start_time) * 1e-3
	var time_message := "in %.2f ms" % delta
	if ConsoleLanguage.Executor.stop(result):
		terminal.add_hr(75, 2, C_THEME.red, HORIZONTAL_ALIGNMENT_LEFT, false)
		print(" execution failed " + time_message)
	else:
		terminal.add_hr(75, 2, C_THEME.green, HORIZONTAL_ALIGNMENT_LEFT, false)
		print(" execution succeeded " + time_message)

func _execute_command(command: String) -> Variant:
	var longest_line: int = 11
	var lines := command.split("\n")
	terminal.push_fgcolor(Color(C_THEME.base, 0.5))
	for line in lines:
		longest_line = maxi(longest_line, line.length() + 2)
	print("[c2 c=yellow]running at %s:[/c2]" % Time.get_datetime_string_from_system())
	for line in lines:
		print(highlight_line(line))
	terminal.add_hr(50, 2, C_THEME.yellow, HORIZONTAL_ALIGNMENT_LEFT, false)
	terminal.newline()
	terminal.pop()
	var start := Time.get_ticks_usec()
	var tokens := ConsoleLanguage.new().tokenize(command)
	print("tokenization took %.2f ms" % ((Time.get_ticks_usec() - start) * 1e-3))
	if tokens.has_error:
		_print_errors(command, tokens.errors)
		return ConsoleLanguage.Executor.stop_immediately
	var parser := ConsoleLanguage.Parser.new()
	parser.tokens = tokens.tokens
	start = Time.get_ticks_usec()
	var file := parser.parse_file()
	print("parsing took %.2f ms" % ((Time.get_ticks_usec() - start) * 1e-3))
	if not parser.errors.is_empty():
		_print_errors(command, parser.errors)
		return ConsoleLanguage.Executor.stop_immediately
	#print(file)
	var exec := ConsoleLanguage.Executor.new()
	var obj := preload("test_commands.gd").new()
	start = Time.get_ticks_usec()
	var result = exec.exec_file(ConsoleLanguage.get_environment_of(obj), file)
	print("execution took %.2f ms" % ((Time.get_ticks_usec() - start) * 1e-3))
	if not exec.errors.is_empty():
		_print_errors(command, exec.errors)
		return ConsoleLanguage.Executor.stop_immediately
	if ConsoleLanguage.Executor.stop(result):
		#print("execution failed")
		#print()
		return ConsoleLanguage.Executor.stop_immediately
	#print("Executed successfully!")
	#print()
	terminal.pop_all()
	return result

func _print_errors(cmd: String, errors: Array[Dictionary]) -> void:
	print("[c2 c=red][b]error:[/b][/c2]")
	for i in errors.size():
		_print_error(cmd, errors[i], i == 0, i == errors.size() - 1)
	print()

func _print_error(cmd: String, error: Dictionary, is_first: bool, is_last: bool) -> void:
	var lines := cmd.split("\n")
	var line_number_width := 1
	var line_number_width_p10 := 10
	while line_number_width_p10 < lines.size():
		line_number_width += 1
		line_number_width_p10 *= 10
	var err_range: Vector4i = error[ConsoleLanguage.RANGE]
	var message: String = error[ConsoleLanguage.MESSAGE]
	var prefix_w := " "
	var line_number_w := " ".repeat(line_number_width)
	for line_i in range(maxi(err_range[0] - 1, 0), mini(err_range[2] + 2, lines.size())):
		var line := lines[line_i]
		var is_really_first := is_first and line_i == err_range[0]
		var extra_spans: Array[Dictionary]
		var is_context: bool = true
		if line_i >= err_range[0] and line_i <= err_range[2]:
			is_context = false
			var start := err_range[1] if line_i == err_range[0] else 0
			var end := err_range[3] if line_i == err_range[2] else line.length()
			end = mini(line.length(), end)
			start = mini(start, end - 1)
			extra_spans.append({
				start = start,
				end = end,
				open = "[u color=%s]" % C_THEME.red.to_html(false),
				close = "[/u]",
			})
		var hl_line := highlight_line(line, extra_spans)
		var fg_color := "[fgcolor=%s][i]" % Color(C_THEME.base, 0.5).to_html(true) if is_context else ""
		var fg_color_close := "[/i][/fgcolor]" if is_context else ""
		if is_really_first:
			print(prefix_w + "%s[c2 c=overlay2]%0*d[/c2]%s [c2 c=red]│ [/c2]" % [fg_color, line_number_width, line_i + 1, fg_color_close] + fg_color + hl_line + fg_color_close)
		else:
			print(prefix_w + "%s[c2 c=overlay2]%0*d[/c2]%s [c2 c=red]│ [/c2]" % [fg_color, line_number_width, line_i + 1, fg_color_close] + fg_color + hl_line + fg_color_close)
	if is_last:
		print(prefix_w + line_number_w + "[c2 c=red] ╰─ [/c2]" + message)
	else:
		print(prefix_w + line_number_w + "[c2 c=red] ├─ [/c2]" + message)

func make_theme(c: Catppuccin = C_THEME) -> Theme:
	var t := Theme.new()
	var base_panel := new_flat(c.base, [0], [4])
	t.set_color("search_result_color", "TextEdit", c.surface0)
	t.set_color("search_border_color", "TextEdit", c.teal)
	t.set_color("caret_color", "TextEdit", c.rosewater)
	t.set_color("caret_background_color", "TextEdit", c.base)
	t.set_color("selection_color", "TextEdit", Color(c.overlay2, 0.25))
	t.set_color("font_color", "TextEdit", c.text)
	t.set_color("font_readonly_color", "TextEdit", c.overlay2)
	t.set_color("font_placeholder_color", "TextEdit", c.overlay2)
	t.set_color("current_line_color", "TextEdit", Color(c.text, 0.1))
	t.set_color("word_highlighted_color", "TextEdit", Color(c.overlay2, 0.25))
	t.set_color("breakpoint_color", "TextEdit", c.red)
	t.set_color("bookmark_color", "TextEdit", c.blue)
	t.set_color("executing_line_color", "TextEdit", c.yellow)
	t.set_color("line_number_color", "TextEdit", c.overlay1)
	t.set_color("completion_scroll_color", "TextEdit", c.surface0)
	t.set_color("completion_scroll_color_hover", "TextEdit", c.surface1)
	t.set_color("completion_background_color", "TextEdit", c.mantle)
	t.set_color("completion_selected_color", "TextEdit", c.surface0)
	t.set_color("completion_existing_color", "TextEdit", c.surface1)
	t.set_color("brace_mismatch_color", "TextEdit", c.red)

	t.set_color("default_color", "RichTextLabel", c.text)
	t.set_color("selection_color", "RichTextLabel", Color(c.overlay2, 0.25))
	t.set_color("table_border", "RichTextLabel", c.yellow)

	t.set_stylebox("panel", "PanelContainer", base_panel)

	t.set_constant("separation", "Separator", 2)
	t.set_stylebox("separator", "Separator", new_line(c.surface0))

	return t

class RobertLogger extends Logger:
	var console: Console

	func _init() -> void:
		OS.add_logger(self)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE:
			OS.remove_logger(self)

	func _log_message(message: String, error: bool) -> void:
		if error:
			console.terminal.push_color(Color.RED)
		console.terminal.add_line(message)
		if error:
			console.terminal.pop()

	@warning_ignore("unused_parameter")
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		pass

static func new_flat(
		bg_color: Color,
		radii: PackedInt32Array = [0],
		margins: PackedInt32Array = [-1, -1, -1, -1],
		border_width: PackedInt32Array = [0],
		border_color := Color.TRANSPARENT,
		expand_margins: PackedInt32Array = [0]
	) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	# Uses indices relative to the end so that a single-item array will result
	# in all the radii being the same
	sb.corner_radius_top_left = maxi(0, int(radii[-4 % radii.size()]))
	sb.corner_radius_top_right = maxi(0, int(radii[-3 % radii.size()]))
	sb.corner_radius_bottom_left = maxi(0, int(radii[-2 % radii.size()]))
	sb.corner_radius_bottom_right = maxi(0, int(radii[-1 % radii.size()]))

	sb.content_margin_left = maxi(-1, int(margins[-4 % margins.size()]))
	sb.content_margin_top = maxi(-1, int(margins[-3 % margins.size()]))
	sb.content_margin_right = maxi(-1, int(margins[-2 % margins.size()]))
	sb.content_margin_bottom = maxi(-1, int(margins[-1 % margins.size()]))

	sb.border_width_left = int(border_width[-4 % border_width.size()])
	sb.border_width_top = int(border_width[-3 % border_width.size()])
	sb.border_width_right = int(border_width[-2 % border_width.size()])
	sb.border_width_bottom = int(border_width[-1 % border_width.size()])

	sb.expand_margin_left = maxi(-1, int(expand_margins[-4 % expand_margins.size()]))
	sb.expand_margin_top = maxi(-1, int(expand_margins[-3 % expand_margins.size()]))
	sb.expand_margin_right = maxi(-1, int(expand_margins[-2 % expand_margins.size()]))
	sb.expand_margin_bottom = maxi(-1, int(expand_margins[-1 % expand_margins.size()]))

	sb.border_color = border_color

	sb.bg_color = bg_color

	sb.draw_center = true

	return sb

static func new_line(
		color: Color,
		margins: PackedInt32Array = [-1, -1, -1, -1],
		thickness: int = 2,
		grow: PackedInt32Array = [0],
	) -> StyleBoxLine:
	var sb := StyleBoxLine.new()

	sb.content_margin_left = maxi(-1, int(margins[-4 % margins.size()]))
	sb.content_margin_top = maxi(-1, int(margins[-3 % margins.size()]))
	sb.content_margin_right = maxi(-1, int(margins[-2 % margins.size()]))
	sb.content_margin_bottom = maxi(-1, int(margins[-1 % margins.size()]))

	sb.grow_begin = maxi(0, int(grow[-2 % grow.size()]))
	sb.grow_end = maxi(0, int(grow[-1 % grow.size()]))

	sb.color = color
	sb.thickness = thickness
	return sb


static func change_bg_color(sb: StyleBoxFlat, bg_color: Color) -> StyleBoxFlat:
	sb.bg_color = bg_color
	return sb


static func change_corner_rad(sb: StyleBoxFlat, radii: PackedInt32Array = [0]) -> StyleBoxFlat:
	sb.corner_radius_top_left = radii[0]
	sb.corner_radius_top_right = radii[-3]
	sb.corner_radius_bottom_left = radii[-2]
	sb.corner_radius_bottom_right = radii[-1]
	return sb


static func change_content_margins(sb: StyleBox, margins: PackedInt32Array = [0]) -> StyleBox:
	sb.content_margin_left = int(margins[-4 % margins.size()])
	sb.content_margin_top = int(margins[-3 % margins.size()])
	sb.content_margin_right = int(margins[-2 % margins.size()])
	sb.content_margin_bottom = int(margins[-1 % margins.size()])
	return sb


static func shadowed(sb: StyleBoxFlat, color: Color, shadow_size: int, x_offset: float, y_offset: float) -> StyleBoxFlat:
	sb.shadow_color = color
	sb.shadow_size = shadow_size
	sb.shadow_offset = Vector2(x_offset, y_offset)
	return sb


static func blended(sb: StyleBoxFlat, blend := true) -> StyleBoxFlat:
	sb.border_blend = blend
	return sb


static func get_darkest(...colors: Array) -> Color:
	var darkest := Color.WHITE
	for color: Color in colors:
		if color.get_luminance() < darkest.get_luminance():
			darkest = color
	return darkest
