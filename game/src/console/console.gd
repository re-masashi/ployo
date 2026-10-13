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

func execute_command(command: String) -> void:
	for line in command.split("\n"):
		var line_h: PackedStringArray
		line_h.append("[c2 c=text]")
		var last_token_pos: int = 0
		var hl_tokens := ConsoleSyntaxHighlighter.get_line_syntax_highlighting_tokens(line)
		for pos in hl_tokens:
			line_h.append(line.substr(last_token_pos, pos - last_token_pos))
			last_token_pos = pos
			line_h.append("[/c2]")
			line_h.append("[c2 c=%s]" % hl_tokens[pos].color)
		line_h.append(line.substr(last_token_pos))
		line_h.append("[/c2]")
		print("[c2 c=green]>[/c2] " + "".join(line_h))
	print()
	var tokens := ConsoleLanguage.new().tokenize(command)
	if tokens.has_error:
		_print_errors(command, tokens.errors)
		return
	var parser := ConsoleLanguage.Parser.new()
	parser.tokens = tokens.tokens
	var file := parser.parse_file()
	if not parser.errors.is_empty():
		_print_errors(command, parser.errors)
		return
	#print(file)
	var exec := ConsoleLanguage.Executor.new()
	var obj := preload("test_commands.gd").new()
	var result = exec.exec_file(ConsoleLanguage.get_environment_of(obj), file)
	if not exec.errors.is_empty():
		_print_errors(command, exec.errors)
		return
	if ConsoleLanguage.Executor.stop(result):
		print("execution failed")
		print()
		return
	print("Executed successfully!")
	print()

func _print_errors(cmd: String, errors: Array[Dictionary]) -> void:
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
	var prefix := "error: "
	var prefix_w := " ".repeat(prefix.length())
	var line_number_w := " ".repeat(line_number_width)
	for line_i in range(err_range[0], err_range[2] + 1):
		var line := lines[line_i]
		var start := line.substr(0, err_range[1]).replace("\t", "    ").length() if line_i == err_range[0] else 0
		var end := line.substr(0, err_range[3]).replace("\t", "    ").length() if line_i == err_range[2] else line.length()
		var is_really_first := is_first and line_i == err_range[0]
		if is_really_first:
			print("[c2 c=red]%s%*d | [/c2]" % [prefix, line_number_width, line_i + 1] + line.replace("\t", "    "))
		else:
			print(prefix_w + "[c2 c=red]%*d | [/c2]" % [line_number_width, line_i + 1] + line.replace("\t", "    "))
		print(prefix_w + line_number_w + "[c2 c=red] | [/c2]" + " ".repeat(start) + "[c2 c=yellow]" + "^".repeat(end - start) + "[/c2]")
	if is_last:
		print(prefix_w + line_number_w + "[c2 c=red] '- [/c2]" + message)
	else:
		print(prefix_w + line_number_w + "[c2 c=red] |- [/c2]" + message)

func make_theme(c: Catppuccin = C_THEME) -> Theme:
	var t := Theme.new()
	var base_panel := StyleBoxFlat.new()
	base_panel.bg_color = c.base
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

	t.set_stylebox("panel", "PanelContainer", base_panel)

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
