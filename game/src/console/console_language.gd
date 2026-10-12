class_name ConsoleLanguage

const RANGE := &"range"
const MESSAGE := &"message"

static var _matchers: Dictionary[RegEx, Token.Type] = {
	RegEx.create_from_string('''^("(?:[^"\\\\]*(?:\\.[^"\\\\]*)*)"|[a-zA-Z_]+[a-zA-Z_0-9\\/-]*)'''):
		Token.Type.Text,
	RegEx.create_from_string("^(-?0[xX][0-9a-fA-F]+|-?[0-9]+)E"): Token.Type.Int,
	RegEx.create_from_string("^([0-9]+\\.?[0-9]*)"): Token.Type.Flt,
	RegEx.create_from_string("^\\$(-?[a-zA-Z_]+[a-zA-Z_0-9/-]*)"): Token.Type.VarRef,
}

const _SINGLE_CHAR_TOKENS: Dictionary[String, Token.Type] = {
	"[": Token.Type.BracketOpen,
	"]": Token.Type.BracketClose,
	"(": Token.Type.ParenOpen,
	")": Token.Type.ParenClose,
	"{": Token.Type.BraceOpen,
	"}": Token.Type.BraceClose,
}

const _NO_RANGE = Vector2i(-1, -1)

func tokenize(input: String) -> TokenizationResult:
	var r := TokenizationResult.new()
	var i := 0
	var range_start := _NO_RANGE
	var line_start := 0
	var line := 0
	while i < input.length():
		var found_match := false
		var line_i := i - line_start
		if input[i] == " " or input[i] == "\t":
			found_match = true
		elif input[i] == "\n" or input[i] == ";":
			found_match = true
			if found_match and range_start != _NO_RANGE:
				r.errors.append({
					RANGE: Vector4i(range_start.x, range_start.y, line, line_i),
					MESSAGE: "invalid token",
				})
				range_start = _NO_RANGE
			if not r.tokens.size() == 0 and r.tokens[-1].type != Token.Type.Break:
				var tk := Token.new()
				tk.loc = Vector4i(line, line_i, line, line_i + 1)
				tk.type = Token.Type.Break
				tk.content = input[i]
				r.tokens.append(tk)
			if input[i] == "\n":
				line += 1
				line_start = i + 1
		elif input[i] in _SINGLE_CHAR_TOKENS:
			found_match = true
			var tk := Token.new()
			tk.loc = Vector4i(line, line_i, line, line_i + 1)
			tk.content = input[i]
			tk.type = _SINGLE_CHAR_TOKENS[input[i]]
			r.tokens.append(tk)
		else:
			var substr := input.substr(i)
			var longest_token: Token = null
			var longest_token_length: int = 0
			for matcher in _matchers:
				var m := matcher.search(substr)
				if m == null:
					continue
				found_match = true
				var end := m.get_end()
				if end > longest_token_length:
					if longest_token == null:
						longest_token = Token.new()
					longest_token_length = end
					longest_token.loc = Vector4i(line, line_i, line, line_i + end)
					longest_token.content = m.get_string(1)
					longest_token.type = _matchers[matcher]
			if longest_token != null:
				r.tokens.append(longest_token)
				i += longest_token_length - 1
		if not found_match and range_start == _NO_RANGE:
			range_start = Vector2i(line, line_i)
		if found_match and range_start != _NO_RANGE:
			r.errors.append({
				RANGE: Vector4i(range_start.x, range_start.y, line, line_i),
				MESSAGE: "invalid token",
			})
			range_start = _NO_RANGE
		i += 1
	if range_start != _NO_RANGE:
		r.errors.append({
			RANGE: Vector4i(range_start.x, range_start.y, line, i - line_start),
			MESSAGE: "invalid or unterminated token",
		})

	return r

static func get_environment_of(obj: Object, base_class: StringName = obj.get_class()) -> Env:
	var env := Env.new()
	var core_base_methods := ClassDB.class_get_method_list(base_class).map(func(e): return e.name)
	var core_base_vars := ClassDB.class_get_property_list(base_class).map(func(e): return e.name)

	for method in obj.get_method_list():
		if method.name in core_base_methods:
			continue
		var info := MethodInfo.new()
		info.name = method.name
		var args = method.args
		for i in args.size():
			var arg = args[i]
			var arg_info := ArgumentInfo.new()
			arg_info.name = arg.name
			arg_info.type = _get_type(arg)
			var default_args_i: int = i - args.size() + method.default_args.size()
			if default_args_i > 0:
				arg_info.optional = true
				arg_info.optional_default = method.default_args[default_args_i]
			info.arguments.append(arg_info)
		info.ret = _get_type(method.return)
		info.callable = Callable(obj, method.name)

		env.add_method(info)

	for variable in obj.get_property_list():
		if variable.name in core_base_vars:
			continue
		var info := VarInfo.new()
		info.name = variable.name
		info.type = _get_type(variable)

		env.add_variable(info)

	return env


static func _get_type(member: Dictionary) -> TypeInfo:
	var type_info := TypeInfo.new()
	type_info.clazz_name = member.class_name
	type_info.type = member.type
	type_info.hint = member.hint
	type_info.hint_string = member.hint_string
	type_info.usage = member.usage
	return type_info

class Token:
	enum Type {
		Text,
		Int,
		Flt,
		Break,
		VarRef,
		BracketOpen,
		BracketClose,
		ParenOpen,
		ParenClose,
		BraceOpen,
		BraceClose,
	}

	var loc: Vector4i
	var type: Type
	var content: String

	func _to_string() -> String:
		return "%s (%s)" % [content, Type.find_key(type)]

class Parser:
	var tokens: Array[Token]
	var errors: Array[Dictionary]

	var i: int = 0
	var in_error: bool = false

	func parse_primary() -> Expr:
		var token := consume()
		if check_in_error("expression expected"): return null
		match token.type:
			Token.Type.Text:
				var e := TextExpr.new()
				e.data.append(token)
				e.text = token.content
				return e
			Token.Type.Int:
				var e := IntExpr.new()
				e.data.append(token)
				var t := token.content
				e.num = (t.hex_to_int() if t.begins_with("0x") or t.begins_with("0X") else t.to_int())
				return e
			Token.Type.Flt:
				var e := FltExpr.new()
				e.data.append(token)
				e.num = token.content.to_float()
				return e
			Token.Type.VarRef:
				var e := VarExpr.new()
				e.data.append(token)
				e.name = token.content
				return e
			Token.Type.BracketOpen:
				var e := ListExpr.new()
				e.data.append(token)
				while i < tokens.size() and peek().type != Token.Type.BracketClose:
					var expr := parse_expr()
					if check_in_error(): return null
					e.elements.append(expr)
				var closing := consume_ty(Token.Type.BracketClose)
				if check_in_error("`]` expected"): return null
				e.data.append(closing)
				return e
			Token.Type.ParenOpen:
				var e := VectorExpr.new()
				e.data.append(token)
				while i < tokens.size() and peek().type != Token.Type.ParenClose:
					var expr := parse_expr()
					if check_in_error(): return null
					e.elements.append(expr)
				var closing := consume_ty(Token.Type.ParenClose)
				if check_in_error("`)` expected"): return null
				e.data.append(closing)
				if e.elements.size() == 1: return e.elements[0]
				return e
			_:
				in_error = true
				generate_token_error(token, "expression expected")
		return null

	func parse_expr() -> Expr:
		return parse_primary()

	func parse_command() -> Command:
		var invocation := Command.new()
		var next_tk := consume_ty(Token.Type.Text)
		if check_in_error("command expected"): return null

		invocation.data = [next_tk]
		invocation.command = next_tk.content

		while peek() and peek().type != Token.Type.Break:
			var expr := parse_primary()
			if check_in_error(): return null
			invocation.args.append(expr)

		return invocation

	func parse_statement() -> Statement:
		return parse_command()

	func parse_file() -> File:
		var file := File.new()
		while i < tokens.size():
			var statement := parse_statement()
			if statement == null: return null
			file.statements.append(statement)
			if i >= tokens.size(): break
			consume_ty(Token.Type.Break)
			if check_in_error("line break expected"): return null
		return file

	func peek() -> Token:
		if i >= tokens.size(): return null
		return tokens[i]

	func consume() -> Token:
		if i >= tokens.size(): return null
		i += 1
		return tokens[i - 1]

	func consume_ty(type: Token.Type) -> Token:
		var tk := consume()
		if not tk or tk.type != type:
			in_error = true
			return null
		return tk

	func check_in_error(message: String = "") -> bool:
		if not in_error:
			return false
		generate_expected_error(message)
		return true

	func generate_expected_error(message: String) -> void:
		if message.is_empty(): return

		errors.append({
			RANGE: Vector4i(0, 0, 0, 1) if i == 0 else Vector4i(tokens[i - 1].loc.z, tokens[i - 1].loc.w, tokens[i - 1].loc.z, tokens[i - 1].loc.w + 1),
			MESSAGE: message,
		})

	func generate_token_error(token: Token, message: String) -> void:
		if message.is_empty(): return

		errors.append({
			RANGE: token.loc,
			MESSAGE: message,
		})

class Executor:
	static var stop_immediately := RefCounted.new():
		set(value):
			if stop_immediately != null:
				assert(false)
				return
			stop_immediately = value

	var errors: Array[Dictionary]

	func exec_expr(env: Env, expr: Expr) -> Variant:
		if expr is TextExpr:
			return expr.text

		if expr is IntExpr:
			return expr.num

		if expr is FltExpr:
			return expr.num

		if expr is VarExpr:
			var var_expr := expr as VarExpr
			if not var_expr.name in env.variables:
				generate_ast_error(var_expr, "unknown variable `{name}`")
				return stop_immediately
			return env.variables[var_expr.name].type

		if expr is VectorExpr:
			var vector_expr := expr as VectorExpr
			if vector_expr.elements.size() > 4:
				generate_ast_error(vector_expr, "vector larger than 4")
				return stop_immediately
			if vector_expr.elements.size() == 0:
				generate_ast_error(vector_expr, "empty vector")
				return stop_immediately
			var args: Array
			for e in vector_expr.elements:
				var v = exec_expr(env, e)
				if stop(v): return stop_immediately
				args.append(v)
			match vector_expr.elements.size():
				2:
					return Vector2(args[0], args[1])
				3:
					return Vector3(args[0], args[1], args[2])
				4:
					return Vector4(args[0], args[1], args[2], args[3])
				_:
					assert(false)
					return stop_immediately

		if expr is ListExpr:
			var list_expr := expr as ListExpr
			var args: Array
			for e in list_expr.elements:
				var v = exec_expr(env, e)
				if stop(v): return stop_immediately
				args.append(v)
			return args
		assert(false)
		return stop_immediately

	func exec_command(env: Env, command: Command) -> Variant:
		if not command.command in env.methods:
			generate_ast_error(command, "unknown command {command}")
			return stop_immediately

		var method := env.methods[command.command]
		if command.args.size() < method.arguments.size():
			generate_ast_error(command, "too few arguments for {command} (missing %s)" % ", ".join(method.arguments.slice(command.args.size()).map(func(e): return e.name)))
			return stop_immediately
		elif command.args.size() > method.arguments.size():
			generate_ast_error(command, "too many arguments for {command}")
			return stop_immediately

		var args: Array
		for e in command.args:
			var v = exec_expr(env, e)
			if stop(v): return stop_immediately
			args.append(v)

		var logger := _ErrorCapturingLogger.new()
		OS.add_logger(logger)
		var result
		if method.callable.get_object() and method.callable.get_method():
			result = method.callable.get_object().callv(method.callable.get_method(), args)
		else:
			result = method.callable.callv(args)
		OS.remove_logger(logger)
		if logger.captured_error:
			generate_ast_error(command.args[logger.position - 1], "cannot convert from %s to %s" % [logger.from_type, logger.to_type])
			return stop_immediately
		return result

	func exec_file(env: Env, file: File) -> Variant:
		for statement in file.statements:
			var cmd := statement as Command
			if cmd:
				if stop(exec_command(env, cmd)): return stop_immediately

		return null

	func generate_ast_error(node: ASTNode, message: String) -> void:
		var range_min := Vector2i(INT32_MAX, INT32_MAX)
		var range_max := Vector2i(0, 0)
		for tok in node.data:
			var left := Vector2i(tok.loc.x, tok.loc.y)
			if left < range_min:
				range_min = left
			var right := Vector2i(tok.loc.z, tok.loc.w)
			if right > range_max:
				range_max = right
		errors.append({
			RANGE: Vector4i(range_min.x, range_min.y, range_max.x, range_max.y),
			MESSAGE: message.format(node),
		})

	static func stop(v) -> bool:
		return v is RefCounted and v == stop_immediately

	class _ErrorCapturingLogger extends Logger:
		static var _error_decoder := RegEx.create_from_string(r'''Cannot convert argument (\d+) from ([a-zA-Z0-9_\[\]-]+) to ([a-zA-Z0-9_\[\]-]+)''')

		var captured_error: bool
		var position: int
		var from_type: String
		var to_type: String

		@warning_ignore("unused_parameter")
		func _log_error(function: String, file: String, line: int, code: String, rationale: String, editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
			var m := _error_decoder.search(rationale)
			if m != null:
				captured_error = true
				position = m.get_string(1).to_int()
				from_type = m.get_string(2)
				to_type = m.get_string(3)

class Env:
	var methods: Dictionary[StringName, MethodInfo]
	var variables: Dictionary[StringName, VarInfo]

	func add_method(method: MethodInfo) -> void:
		methods[method.name] = method

	func add_variable(variable: VarInfo) -> void:
		variables[variable.name] = variable

	func duplicate() -> Env:
		var x := Env.new()
		x.methods = methods.duplicate()
		x.variables = variables.duplicate()
		return x

class ASTNode:
	var data: Array[Token]

class Expr extends ASTNode:
	var type: TypeInfo

class TextExpr extends Expr:
	var text: String

	func _to_string() -> String:
		return "(txt %s)" % text

class IntExpr extends Expr:
	var num: int

	func _to_string() -> String:
		return "(num %s)" % num

class FltExpr extends Expr:
	var num: float

	func _to_string() -> String:
		return "(num %s)" % num

class VarExpr extends Expr:
	var name: String

	func _to_string() -> String:
		return "$%s" % name

class VectorExpr extends Expr:
	var elements: Array[Expr]

	func _to_string() -> String:
		return "(%s)" % " ".join(elements)

class ListExpr extends Expr:
	var elements: Array[Expr]

	func _to_string() -> String:
		return "[%s]" % " ".join(elements)

class Statement extends ASTNode:
	pass

class Command extends Statement:
	var command: String
	var args: Array[Expr]

	func _to_string() -> String:
		return "(%s %s)" % [command, " ".join(args)]

class File:
	var statements: Array[Statement]

class TokenizationResult:
	var tokens: Array[Token]
	var errors: Array[Dictionary]

	var has_error: bool:
		set(_value): assert(false)
		get: return not errors.is_empty()

class MethodInfo:
	var name: String
	var arguments: Array[ArgumentInfo]
	var ret: TypeInfo

	var callable: Callable

class VarInfo:
	var name: String
	var type: TypeInfo

class ArgumentInfo extends VarInfo:
	var optional: bool
	var optional_default

class TypeInfo:
	var clazz_name: StringName
	var type: Variant.Type
	var hint: PropertyHint
	var hint_string: String
	var usage: PropertyUsageFlags
