@tool
class_name Console extends Window

@onready var terminal: Terminal = %Terminal
@onready var command_input: CommandInput = %CommandInput

var methods: Array[ConsoleLanguage.MethodInfo]

var logger: RobertLogger

func _init() -> void:
	logger = RobertLogger.new()
	logger.console = self

func _ready() -> void:
	command_input.command_submitted.connect(execute_command)

func execute_command(command: String) -> void:
	for line in command.split("\n"):
		print("[color=green]>[/color] " + line)
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
		var start := err_range[1] if line_i == err_range[0] else 0
		var end := err_range[3] if line_i == err_range[2] else line.length()
		var is_really_first := is_first and line_i == err_range[0]
		if is_really_first:
			print("[color=red]%s%*d | [/color]" % [prefix, line_number_width, line_i + 1] + line)
		else:
			print(prefix_w + "[color=red]%*d | [/color]" % [line_number_width, line_i + 1] + line)
		print(prefix_w + line_number_w + "[color=red] | [/color]" + " ".repeat(start) + "^".repeat(end - start))
	if is_last:
		print(prefix_w + line_number_w + "[color=red] '- [/color]" + message)
	else:
		print(prefix_w + line_number_w + "[color=red] |- [/color]" + message)

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
