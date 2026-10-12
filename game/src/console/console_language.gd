class_name ConsoleLanguage

const RANGE := &"range"
const MESSAGE := &"message"

static var _matchers: Dictionary[RegEx, Token.Type] = {
	RegEx.create_from_string('''^([a-zA-Z_]+[a-zA-Z_0-9\\/-]*)'''):
		Token.Type.Word,
	RegEx.create_from_string('''^("(?:[^"\\\\]*(?:\\.[^"\\\\]*)*)")'''):
		Token.Type.Str,
	RegEx.create_from_string("^((?:-?0[xX][0-9a-fA-F]+)|(?:-?[0-9]+))"): Token.Type.Int,
	RegEx.create_from_string("^([0-9]+\\.[0-9]+)"): Token.Type.Flt,
	RegEx.create_from_string("^\\$(-?[a-zA-Z_]+[a-zA-Z_0-9/-]*)"): Token.Type.VarRef,
}

const _SINGLE_CHAR_TOKENS: Dictionary[String, Token.Type] = {
	"[": Token.Type.BracketOpen,
	"]": Token.Type.BracketClose,
	"(": Token.Type.ParenOpen,
	")": Token.Type.ParenClose,
	"{": Token.Type.BraceOpen,
	"}": Token.Type.BraceClose,

	"+": Token.Type.Add,
	"-": Token.Type.Sub,
	"*": Token.Type.Mul,
	"/": Token.Type.Div,
	">": Token.Type.Gt,
	"<": Token.Type.Lt,
	"&": Token.Type.BitAnd,
	"|": Token.Type.BitOr,
	"^": Token.Type.BitXor,
}

const _TWO_CHAR_TOKENS: Dictionary[String, Token.Type] = {
	">>": Token.Type.Shr,
	"<<": Token.Type.Shl,
	"**": Token.Type.Pow,
	">=": Token.Type.Gte,
	"<=": Token.Type.Lte,
	"==": Token.Type.Eq,
	"!=": Token.Type.Neq,
	"&&": Token.Type.And,
	"||": Token.Type.Or,
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
		elif i < input.length() - 1 and input.substr(i, 2) in _TWO_CHAR_TOKENS:
			found_match = true
			var tk := Token.new()
			tk.loc = Vector4i(line, line_i, line, line_i + 2)
			tk.content = input[i]
			tk.type = _TWO_CHAR_TOKENS[input.substr(i, 2)]
			r.tokens.append(tk)
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
		Word,
		Str,
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

		Add,
		Sub,
		Mul,
		Div,
		Gt,
		Lt,
		BitAnd,
		BitOr,
		BitXor,
		Shr,
		Shl,
		Pow,
		Gte,
		Lte,
		Eq,
		Neq,
		And,
		Or,
		Not,
	}

	var loc: Vector4i
	var type: Type
	var content: String

	func _to_string() -> String:
		return "%s (%s)" % [content, Type.find_key(type)]

class Parser:
	const _CMD_ENDING_TOKENS: PackedInt32Array = [
		Token.Type.BracketClose,
		Token.Type.ParenClose,
		Token.Type.BraceClose,
		Token.Type.Break,
	]

	var tokens: Array[Token]
	var errors: Array[Dictionary]

	var i: int = 0
	var in_error: bool = false

	func parse_primary() -> Expr:
		var token := consume()
		if check_in_error("expression expected"): return null
		match token.type:
			Token.Type.Word:
				var e := CommandExpr.new()
				e.data.append(token)
				e.command = token.content
				while i < tokens.size() and peek().type not in _CMD_ENDING_TOKENS:
					var expr := parse_expr()
					if check_in_error(): return null
					e.args.append(expr)
				return e
			Token.Type.Str:
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

	func parse_prefix() -> Expr:
		var token := peek()
		if token != null:
			match token.type:
				Token.Type.Add, Token.Type.Sub:
					consume()
					var e := PrefixExpr.new()
					e.data.append(token)
					e.op = PrefixExpr.get_op(token.type)
					e.expr = parse_primary()
					if e.expr == null: return null
					return e
		return parse_primary()

	func parse_infix(min_prec := INT64_MIN) -> Expr:
		var left := parse_prefix()
		if left == null: return null
		while true:
			var next_tk := peek()
			if next_tk == null: break
			var op := InfixExpr.get_op(next_tk.type)
			if op == InfixExpr.Op.None: break
			var prec := InfixExpr.prec(op)
			if prec.x < min_prec:
				break
			consume()
			var right := parse_infix(prec.y)
			var expr := InfixExpr.new()
			expr.op = op
			expr.data.append(next_tk)
			expr.left = left
			expr.right = right
			left = expr
		return left

	func parse_expr() -> Expr:
		return parse_infix()

	func parse_command() -> CommandExpr:
		var invocation := CommandExpr.new()
		var next_tk := consume_ty(Token.Type.Word)
		if check_in_error("command expected"): return null

		invocation.data = [next_tk]
		invocation.command = next_tk.content

		while peek() and peek().type != Token.Type.Break:
			var expr := parse_expr()
			if check_in_error(): return null
			invocation.args.append(expr)

		return invocation

	func parse_statement() -> Statement:
		var cmd := parse_expr()
		if cmd == null: return null
		var expr_stmt := ExprStatement.new()
		expr_stmt.expr = cmd
		return expr_stmt

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
		if i >= tokens.size():
			in_error = true
			return null
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
			MESSAGE: message.format(token),
		})

class Executor:
	static var stop_immediately := RefCounted.new():
		set(value):
			if stop_immediately != null:
				assert(false)
				return
			stop_immediately = value

	var errors: Array[Dictionary]

	func exec_file(env: Env, file: File) -> Variant:
		for statement in file.statements:
			var value = statement.compute(self, env)
			if stop(value):
				return stop_immediately

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

@abstract class ASTNode:
	var data: Array[Token]

	@abstract func compute(e: Executor, env: Env) -> Variant

	static func compute_list(e: Executor, env: Env, list: Array[Expr]) -> Variant:
		var args: Array
		for arg in list:
			var v = arg.compute(e, env)
			if Executor.stop(v): return Executor.stop_immediately
			args.append(v)
		return args

@abstract class Expr extends ASTNode:
	var type: TypeInfo


class TextExpr extends Expr:
	var text: String

	func _to_string() -> String:
		return "(txt %s)" % text

	func compute(_e: Executor, _env: Env) -> Variant:
		return text

class IntExpr extends Expr:
	var num: int

	func _to_string() -> String:
		return "(num %s)" % num

	func compute(_e: Executor, _env: Env) -> Variant:
		return num

class FltExpr extends Expr:
	var num: float

	func _to_string() -> String:
		return "(num %s)" % num

	func compute(_e: Executor, _env: Env) -> Variant:
		return num

class VarExpr extends Expr:
	var name: String

	func _to_string() -> String:
		return "$%s" % name

	func compute(_e: Executor, _env: Env) -> Variant:
		return name

class VectorExpr extends Expr:
	var elements: Array[Expr]

	func _to_string() -> String:
		return "(%s)" % " ".join(elements)

	func compute(e: Executor, env: Env) -> Variant:
		if elements.size() > 4:
			e.generate_ast_error(self, "vector larger than 4")
			return Executor.stop_immediately
		if elements.size() == 0:
			e.generate_ast_error(self, "empty vector")
			return Executor.stop_immediately
		var args = compute_list(e, env, elements)
		if Executor.stop(args): return Executor.stop_immediately
		match elements.size():
			2:
				return Vector2(args[0], args[1])
			3:
				return Vector3(args[0], args[1], args[2])
			4:
				return Vector4(args[0], args[1], args[2], args[3])
			_:
				assert(false)
				return Executor.stop_immediately

class ListExpr extends Expr:
	var elements: Array[Expr]

	func _to_string() -> String:
		return "[%s]" % " ".join(elements)

	func compute(e: Executor, env: Env) -> Variant:
		return compute_list(e, env, elements)

class PrefixExpr extends Expr:
	const COMPATIBLE_TYPES: PackedInt32Array = [
		# atomic types
		#TYPE_BOOL,
		TYPE_INT,
		TYPE_FLOAT,
		TYPE_STRING,
		# math types
		TYPE_VECTOR2,
		TYPE_VECTOR2I,
		TYPE_RECT2,
		TYPE_RECT2I,
		TYPE_VECTOR3,
		TYPE_VECTOR3I,
		TYPE_TRANSFORM2D,
		TYPE_VECTOR4,
		TYPE_VECTOR4I,
		TYPE_PLANE,
		TYPE_QUATERNION,
		TYPE_AABB,
		TYPE_BASIS,
		TYPE_TRANSFORM3D,
		TYPE_PROJECTION,
		# misc types
		TYPE_COLOR,
		#TYPE_STRING_NAME,
		#TYPE_NODE_PATH,
		#TYPE_RID,
		#TYPE_OBJECT,
		#TYPE_CALLABLE,
		#TYPE_SIGNAL,
		#TYPE_DICTIONARY,
		#TYPE_ARRAY,
		# typed arrays
		#TYPE_PACKED_BYTE_ARRAY,
		#TYPE_PACKED_INT32_ARRAY,
		#TYPE_PACKED_INT64_ARRAY,
		#TYPE_PACKED_FLOAT32_ARRAY,
		#TYPE_PACKED_FLOAT64_ARRAY,
		#TYPE_PACKED_STRING_ARRAY,
		#TYPE_PACKED_VECTOR2_ARRAY,
		#TYPE_PACKED_VECTOR3_ARRAY,
		#TYPE_PACKED_COLOR_ARRAY,
		#TYPE_PACKED_VECTOR4_ARRAY,
	]

	enum Op {
		Not,
		Add,
		Sub,
	}

	var op: Op
	var expr: Expr

	static func get_op(tk: Token.Type) -> Op:
		if tk == Token.Type.Sub:
			return Op.Sub
		if tk == Token.Type.Not:
			return Op.Not
		else:
			return Op.Add

	func compute(e: Executor, env: Env) -> Variant:
		var value = expr.compute(e, env)
		if Executor.stop(value): return Executor.stop_immediately
		if op == Op.Not and value is bool:
			return not value
		if typeof(value) in COMPATIBLE_TYPES:
			if op == Op.Add:
				return +value
			else:
				return -value

		e.generate_ast_error(self, "incompatible type for " + Op.find_key(op).to_lower())
		return Executor.stop_immediately

	func _to_string() -> String:
		return "(%s %s)" % [Op.find_key(op), expr]

class InfixExpr extends Expr:
	const LEFT = -1
	const RIGHT = 1

	enum Op {
		None,
		Add =     LEFT * (15 << 5) | 0,
		Sub =     LEFT * (15 << 5) | 1,
		Mul =     LEFT * (16 << 5) | 2,
		Div =     LEFT * (16 << 5) | 3,
		Shr =    RIGHT * (17 << 5) | 4,
		Shl =    RIGHT * (17 << 5) | 5,
		Pow =    RIGHT * (17 << 5) | 6,
		Gt =      LEFT * (12 << 5) | 7,
		Lt =      LEFT * (12 << 5) | 8,
		Gte =     LEFT * (12 << 5) | 9,
		Lte =     LEFT * (12 << 5) | 10,
		Eq =      LEFT * (12 << 5) | 11,
		Neq =     LEFT * (12 << 5) | 12,
		And =    RIGHT * ( 2 << 5) | 13,
		Or =     RIGHT * ( 1 << 5) | 14,
		BitAnd = RIGHT * (11 << 5) | 15,
		BitOr =  RIGHT * (10 << 5) | 16,
		BitXor = RIGHT * (13 << 5) | 17,
	}

	const OP_STRINGS: Dictionary[Op, String] = {
		Op.Add: "+",
		Op.Sub: "-",
		Op.Mul: "*",
		Op.Div: "/",
		Op.Shr: ">>",
		Op.Shl: "<<",
		Op.Pow: "**",
		Op.Gt: ">",
		Op.Lt: "<",
		Op.Gte: ">=",
		Op.Lte: "<=",
		Op.Eq: "==",
		Op.Neq: "!=",
		Op.And: "&&",
		Op.Or: "||",
		Op.BitAnd: "&",
		Op.BitOr: "|",
		Op.BitXor: "^",
	}

	var op: Op
	var left: Expr
	var right: Expr

	static func get_op(tk: Token.Type) -> Op:
		if   tk == Token.Type.Add: return Op.Add
		elif tk == Token.Type.Sub: return Op.Sub
		elif tk == Token.Type.Mul: return Op.Mul
		elif tk == Token.Type.Div: return Op.Div
		elif tk == Token.Type.Shr: return Op.Shr
		elif tk == Token.Type.Shl: return Op.Shl
		elif tk == Token.Type.Pow: return Op.Pow
		elif tk == Token.Type.Gt: return Op.Gt
		elif tk == Token.Type.Lt: return Op.Lt
		elif tk == Token.Type.Gte: return Op.Gte
		elif tk == Token.Type.Lte: return Op.Lte
		elif tk == Token.Type.Eq: return Op.Eq
		elif tk == Token.Type.Neq: return Op.Neq
		elif tk == Token.Type.And: return Op.And
		elif tk == Token.Type.Or: return Op.Or
		elif tk == Token.Type.BitAnd: return Op.BitAnd
		elif tk == Token.Type.BitOr: return Op.BitOr
		elif tk == Token.Type.BitXor: return Op.BitXor
		return Op.None

	@warning_ignore("shadowed_variable")
	static func prec(op: Op) -> Vector2i:
		var assoc := signi(op)
		var p := ((op & ~0b11111) * assoc) >> 5
		if assoc == LEFT:
			return Vector2i(p * 2, p * 2 + 1)
		else:
			return Vector2i(p * 2 + 1, p * 2)

	func compute(e: Executor, env: Env) -> Variant:
		var expr := Expression.new()
		expr.parse("a %s b" % OP_STRINGS[op], ["a", "b"])
		var list = compute_list(e, env, [left, right])
		if Executor.stop(list): return Executor.stop_immediately

		var result = expr.execute(list)
		if expr.has_execute_failed():
			e.generate_ast_error(self, expr.get_error_text())
			return Executor.stop_immediately
		return result

	func _to_string() -> String:
		return "(%s %s %s)" % [Op.find_key(op), left, right]

@abstract class Statement extends ASTNode:
	pass

class ExprStatement extends Statement:
	var expr: Expr

	func compute(e: Executor, env: Env) -> Variant:
		var value = expr.compute(e, env)
		return value

class CommandExpr extends Expr:
	var command: String
	var args: Array[Expr]

	func compute(e: Executor, env: Env) -> Variant:
		if not command in env.methods:
			e.generate_ast_error(self, "unknown command {command}")
			return Executor.stop_immediately

		var method := env.methods[command]
		if args.size() < method.arguments.size():
			e.generate_ast_error(self, "too few arguments for {command} (missing %s)" % ", ".join(method.arguments.slice(args.size()).map(func(arg): return arg.name)))
			return Executor.stop_immediately
		elif args.size() > method.arguments.size():
			e.generate_ast_error(self, "too many arguments for {command}")
			return Executor.stop_immediately

		var arg_values_result = compute_list(e, env, args)
		if Executor.stop(arg_values_result): return Executor.stop_immediately
		var arg_values: Array = arg_values_result

		var logger := _ErrorCapturingLogger.new()
		OS.add_logger(logger)
		var result
		if method.callable.get_object() and method.callable.get_method():
			result = method.callable.get_object().callv(method.callable.get_method(), arg_values)
		else:
			result = method.callable.callv(arg_values)
		OS.remove_logger(logger)
		if logger.captured_error:
			e.generate_ast_error(args[logger.position - 1], "cannot convert from %s to %s" % [logger.from_type, logger.to_type])
			return Executor.stop_immediately
		return result

	func _to_string() -> String:
		return "(%s %s)" % [command, " ".join(args)]

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

class File:
	var statements: Array[Statement]

	func _to_string() -> String:
		return "\n".join(statements)

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
