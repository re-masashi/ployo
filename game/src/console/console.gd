@tool
class_name Console extends Window

@onready var text_edit: TextEdit = %TextEdit
@onready var line_edit: LineEdit = %LineEdit

var methods: Array[ConsoleLanguage.MethodInfo]

var logger: RobertLogger:
	get:
		if logger == null:
			logger = RobertLogger.new()
			logger.console = self
		return logger

func _ready() -> void:
	if Engine.is_editor_hint(): return

	var test := 'cmd2 [1 2 3] (6 7 8 9 10)'
	var tokens := ConsoleLanguage.new().tokenize(test)
	if tokens.has_error:
		print(tokens.errors)
		return
	print(tokens.tokens)
	var parser := ConsoleLanguage.Parser.new()
	parser.tokens = tokens.tokens
	var command := parser.parse_command()
	if not parser.errors.is_empty():
		print(parser.errors)
		return
	print(command)
	var checker := ConsoleLanguage.Typechecker.new()
	var obj := preload("test_commands.gd").new()
	checker.check_command(ConsoleLanguage.get_environment_of(obj), command)
	if not checker.errors.is_empty():
		print(checker.errors)
		return
	print("Checked successfully!")

class RobertLogger extends Logger:
	var console: Console

	func _notification(what: int) -> void:
		if what == NOTIFICATION_POSTINITIALIZE:
			OS.add_logger(self)
		elif what == NOTIFICATION_PREDELETE:
			OS.remove_logger(self)

	@warning_ignore("unused_parameter")
	func _log_message(message: String, error: bool) -> void:
		pass

	@warning_ignore("unused_parameter")
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		pass
