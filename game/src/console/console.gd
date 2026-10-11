@tool
class_name Console extends Window

@onready var terminal: Terminal = %Terminal
@onready var line_edit: LineEdit = %LineEdit

var methods: Array[ConsoleLanguage.MethodInfo]

var logger: RobertLogger

func _init() -> void:
	logger = RobertLogger.new()
	logger.console = self

func _ready() -> void:
	line_edit.text_submitted.connect(execute_command)

func execute_command(command: String) -> void:
	print("> " + command + "\n")
	var tokens := ConsoleLanguage.new().tokenize(command)
	if tokens.has_error:
		_print_errors(command, tokens.errors)
		return
	var parser := ConsoleLanguage.Parser.new()
	parser.tokens = tokens.tokens
	var ast := parser.parse_command()
	if not parser.errors.is_empty():
		_print_errors(command, parser.errors)
		return
	var exec := ConsoleLanguage.Executor.new()
	var obj := preload("test_commands.gd").new()
	var result = exec.exec_command(ConsoleLanguage.get_environment_of(obj), ast)
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
	var err_range: Vector2i = error[ConsoleLanguage.RANGE]
	var message: String =	error[ConsoleLanguage.MESSAGE]
	var prefix := "error: "
	var prefix_w := " ".repeat(prefix.length())
	if is_first:
		print(  prefix + "| " + cmd)
	else:
		print(prefix_w + "| " + cmd)
	print(prefix_w + "| " + " ".repeat(err_range.x) + "^".repeat(err_range.y - err_range.x))
	if is_last:
		print(prefix_w + "'- " + message)
	else:
		print(prefix_w + "|- " + message)

class RobertLogger extends Logger:
	var console: Console

	func _init() -> void:
		OS.add_logger(self)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE:
			OS.remove_logger(self)

	@warning_ignore("unused_parameter")
	func _log_message(message: String, error: bool) -> void:
		if error:
			console.terminal.push_color(Color.RED)
		console.terminal.add_line(message)
		if error:
			console.terminal.pop()

	@warning_ignore("unused_parameter")
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		pass
