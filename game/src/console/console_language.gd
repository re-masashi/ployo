class_name ConsoleLanguage

const RANGE := &"range"
const MESSAGE := &"message"

static var _matchers: Dictionary[RegEx, Token.Type] = {
	RegEx.create_from_string('''^([a-zA-Z_]+[a-zA-Z_0-9]*)'''):
		Token.Type.Word,
	RegEx.create_from_string('''^"([^"\\\\]*(?:\\.[^"\\\\]*)*)"'''):
		Token.Type.Str,
	RegEx.create_from_string("^((?:-?0[xX][0-9a-fA-F]+)|(?:-?[0-9]+))"): Token.Type.Int,
	RegEx.create_from_string("^([0-9]+\\.[0-9]+)"): Token.Type.Flt,
	RegEx.create_from_string("^\\$(-?[a-zA-Z_]+[a-zA-Z_0-9/-]*)"): Token.Type.VarRef,
}

const _LITERAL_TOKENS: Dictionary[String, Token.Type] = {
	"[": Token.Type.BracketOpen,
	"]": Token.Type.BracketClose,
	"(": Token.Type.ParenOpen,
	")": Token.Type.ParenClose,
	"{": Token.Type.BraceOpen,
	"}": Token.Type.BraceClose,
	"==": Token.Type.Eq,
	"=": Token.Type.Assign,
	":": Token.Type.Colon,
	".": Token.Type.Dot,

	">>": Token.Type.Shr,
	"<<": Token.Type.Shl,
	"**": Token.Type.Pow,
	">=": Token.Type.Gte,
	"<=": Token.Type.Lte,
	"!=": Token.Type.Neq,
	"&&": Token.Type.And,
	"||": Token.Type.Or,

	"+": Token.Type.Add,
	"-": Token.Type.Sub,
	"*": Token.Type.Mul,
	"/": Token.Type.Div,
	">": Token.Type.Gt,
	"<": Token.Type.Lt,
	"&": Token.Type.BitAnd,
	"|": Token.Type.BitOr,
	"^": Token.Type.BitXor,

	"if": Token.Type.KwIf,

	"for": Token.Type.KwFor,
	"end": Token.Type.KwEnd,
	"fun": Token.Type.KwFun,
	"var": Token.Type.KwVar,

	"else": Token.Type.KwElse,
	"true": Token.Type.KwTrue,
	"false": Token.Type.KwFalse,

	"break": Token.Type.KwBreak,
	"return": Token.Type.KwReturn,
	"continue": Token.Type.KwContinue,
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
		if input[i] == "#":
			while i < input.length():
				if input[i] == "\n" or input[i] == ";":
					i -= 1
					break
				i += 1
			found_match = true
		elif input[i] == " " or input[i] == "\t":
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
		else:
			for token in _LITERAL_TOKENS:
				if i < input.length() - token.length() + 1 and input.substr(i, token.length()) == token:
					found_match = true
					if not r.tokens.is_empty() and token == "if" and r.tokens[-1].type == Token.Type.KwElse:
						# if an `if` token follows an `else` with nothing in between, turn it into `else if` (one token)
						r.tokens[-1].content = "else if"
						r.tokens[-1].loc.w = line_i + token.length()
						r.tokens[-1].type = Token.Type.KwElseIf
					else:
						var tk := Token.new()
						tk.loc = Vector4i(line, line_i, line, line_i + token.length())
						tk.content = token
						tk.type = _LITERAL_TOKENS[token]
						r.tokens.append(tk)
					i += token.length() - 1
					break
			if found_match == false:
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
		if not variable.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			continue
		var info := VarInfo.new()
		info.name = variable.name
		info.type = _get_type(variable)
		info.getter = obj.get.bind(info.name)
		info.setter = func(v): obj.set(info.name, v)

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
		Assign,
		Colon,

		Dot,

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

		KwIf,
		KwFor,
		KwEnd,
		KwFun,
		KwVar,
		KwElse,
		KwTrue,
		KwFalse,
		KwBreak,
		KwReturn,
		KwContinue,

		KwElseIf,
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
		Token.Type.KwEnd,
	]

	var tokens: Array[Token]
	var errors: Array[Dictionary]

	var i: int = 0
	var in_error: bool = false

	func _consume_all_breaks() -> void:
		while peek() and peek().type == Token.Type.Break: consume()

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
			Token.Type.KwTrue, Token.Type.KwFalse:
				var e := BoolExpr.new()
				e.data.append(token)
				e.value = token.type == Token.Type.KwTrue
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
					_consume_all_breaks()
					var expr := parse_expr()
					if check_in_error(): return null
					e.elements.append(expr)
					_consume_all_breaks()
				var closing := consume_ty(Token.Type.BracketClose)
				if check_in_error("`]` expected"): return null
				e.data.append(closing)
				return e
			Token.Type.ParenOpen:
				var e := VectorExpr.new()
				e.data.append(token)
				while i < tokens.size() and peek().type != Token.Type.ParenClose:
					_consume_all_breaks()
					var expr := parse_expr()
					if check_in_error(): return null
					e.elements.append(expr)
					_consume_all_breaks()
				var closing := consume_ty(Token.Type.ParenClose)
				if check_in_error("`)` expected"): return null
				e.data.append(closing)
				if e.elements.size() == 1: return e.elements[0]
				return e
			Token.Type.BraceOpen:
				var e := DictExpr.new()
				e.data.append(token)
				while peek() and peek().type != Token.Type.BraceClose:
					_consume_all_breaks()
					var key := parse_expr()
					if key == null: return null
					consume_ty(Token.Type.Colon)
					if check_in_error("`:` expected"): return null
					var value := parse_expr()
					if value == null: return null
					e.elements[key] = value
					_consume_all_breaks()
				var closing := consume_ty(Token.Type.BraceClose)
				if check_in_error("`}` expected"): return null
				e.data.append(closing)
				return e
			_:
				in_error = true
				generate_token_error(token, "expression expected")
		return null

	func parse_postfix() -> Expr:
		var left := parse_primary()
		if left == null: return null
		var token := peek()
		if token != null:
			match token.type:
				Token.Type.Dot:
					while true:
						consume()
						var next := parse_primary()
						if next == null: return null
						if next is CommandExpr:
							var next_ce := next as CommandExpr
							var expr := MethodExpr.new()
							expr.data.append_array(next_ce.data)
							expr.target = left
							expr.command = next_ce.command
							expr.args = next_ce.args
							left = expr
						else:
							var expr := FieldAccessExpr.new()
							expr.data.append(token)
							expr.target = left
							expr.field = next
							left = expr
						if not peek() or peek().type != Token.Type.Dot:
							return left
		return left

	func parse_prefix() -> Expr:
		var token := peek()
		if token != null:
			match token.type:
				Token.Type.Add, Token.Type.Sub:
					consume()
					var e := PrefixExpr.new()
					e.data.append(token)
					e.op = PrefixExpr.get_op(token.type)
					e.expr = parse_postfix()
					if e.expr == null: return null
					return e
		return parse_postfix()

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

	func parse_statement() -> Statement:
		var tk := peek()
		if tk == null:
			in_error = true
			generate_expected_error("expected statement")
			return null
		match tk.type:
			Token.Type.KwIf:
				consume()
				var if_stmt := IfStatement.new()
				if_stmt.data.append(tk)
				if_stmt.condition = parse_expr()
				if if_stmt.condition == null: return null
				if_stmt.scope_end = current_token_end()
				consume_ty(Token.Type.Break)
				if check_in_error("line break expected"): return null
				var body := CompoundStatement.new()
				if_stmt.body = body
				var toplevel_if := if_stmt
				while true:
					var next := peek()
					if next == null: break
					if next.type == Token.Type.KwElseIf:
						if if_stmt.else_body != null:
							generate_token_error(next, "unexpected `else if`")
						var kw := consume()
						if_stmt.scope_end = current_token_start()
						if_stmt.data.append(kw)
						var next_if := IfStatement.new()
						next_if.data.append(next)
						next_if.condition = parse_expr()
						if next_if.condition == null: return null
						consume_ty(Token.Type.Break)
						if check_in_error("line break expected"): return null
						if_stmt.else_body = next_if
						if_stmt = next_if
						body = CompoundStatement.new()
						next_if.body = body
					elif next.type == Token.Type.KwElse:
						var kw := consume()
						if_stmt.scope_end = current_token_start()
						if_stmt.data.append(kw)
						consume_ty(Token.Type.Break)
						if check_in_error("line break expected"): return null
						body = CompoundStatement.new()
						if_stmt.else_body = body
					elif next.type == Token.Type.KwEnd:
						break

					var stmt := parse_statement()
					consume_ty(Token.Type.Break)
					if check_in_error("line break expected"): return null
					if stmt == null: return null
					body.statements.append(stmt)
				var end := consume_ty(Token.Type.KwEnd)
				if_stmt.scope_end = current_token_start()
				if_stmt.data.append(end)
				if check_in_error("`end` expected"): return null
				return toplevel_if
			Token.Type.KwVar:
				consume()
				var name := consume_ty(Token.Type.VarRef)
				if check_in_error("variable expected"): return null
				consume_ty(Token.Type.Assign)
				if check_in_error("`=` expected"): return null
				var var_decl := VarDeclStatement.new()
				var_decl.data.append(name)
				var_decl.name = name.content
				var_decl.value = parse_expr()
				if var_decl.value == null: return null
				var_decl.scope_end = current_token_end()
				return var_decl
			Token.Type.VarRef:
				var eq := peek(1)
				if eq and eq.type == Token.Type.Assign:
					consume() # VarRef
					consume() # Assign
					var var_assign := VarAssignmentStatement.new()
					var_assign.data.append(tk)
					var_assign.name = tk.content
					var_assign.value = parse_expr()
					if var_assign.value == null: return null
					return var_assign
			Token.Type.KwReturn:
				consume()
				var ret := ReturnStatement.new()
				ret.data.append(tk)
				if peek() and peek().type != Token.Type.Break:
					ret.value = parse_expr()
					if ret.value == null: return null
				return ret
			Token.Type.KwBreak:
				consume()
				var brk := BreakStatement.new()
				brk.data.append(tk)
				return brk
			Token.Type.KwContinue:
				consume()
				var cont := ContinueStatement.new()
				cont.data.append(tk)
				return cont
			Token.Type.KwFun:
				consume()
				var name := consume_ty(Token.Type.Word)
				if check_in_error("function name expected"): return null
				var fun := FunStatement.new()
				fun.name = name.content
				fun.data.append(name)
				while peek() and peek().type != Token.Type.Break:
					var arg_name := consume_ty(Token.Type.VarRef)
					if check_in_error("parameter name expected"): return null
					fun.args.append(arg_name.content)
				fun.scope_start = current_token_end()
				consume_ty(Token.Type.Break)
				if check_in_error("line break expected"): return null
				var body := CompoundStatement.new()
				fun.body = body
				while true:
					var next := peek()
					if next == null: break
					if next.type == Token.Type.KwEnd:
						break
					var stmt := parse_statement()
					consume_ty(Token.Type.Break)
					if check_in_error("line break expected"): return null
					if stmt == null: return null
					body.statements.append(stmt)
				var end := consume_ty(Token.Type.KwEnd)
				fun.data.append(end)
				if check_in_error("`end` expected"): return null
				fun.scope_end = current_token_start()
				fun.stmt_end = current_token_end()
				return fun
			Token.Type.KwFor:
				consume()
				var loop_name := consume_ty(Token.Type.VarRef)
				if check_in_error("variable name expected"): return null
				consume_ty(Token.Type.Colon)
				if check_in_error("`:` expected"): return null
				var loop := ForLoopStatement.new()
				loop.scope_start = current_token_end()
				loop.data.append(tk)
				loop.name = loop_name.content
				loop.iterator = parse_expr()
				if loop.iterator == null: return null
				consume_ty(Token.Type.Break)
				if check_in_error("line break expected"): return null
				var body := CompoundStatement.new()
				loop.body = body
				while true:
					var next := peek()
					if next == null: break
					if next.type == Token.Type.KwEnd:
						break
					var stmt := parse_statement()
					consume_ty(Token.Type.Break)
					if check_in_error("line break expected"): return null
					if stmt == null: return null
					body.statements.append(stmt)
				var end := consume_ty(Token.Type.KwEnd)
				loop.data.append(end)
				if check_in_error("`end` expected"): return null
				loop.scope_end = current_token_start()
				return loop

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

	func peek(offset: int = 0) -> Token:
		if i + offset >= tokens.size(): return null
		return tokens[i + offset]

	func consume() -> Token:
		if i >= tokens.size():
			in_error = true
			return null
		i += 1
		return tokens[i - 1]

	func consume_ty(type: Token.Type) -> Token:
		if i >= tokens.size():
			in_error = true
			return null
		var tk := tokens[i]
		if tk.type != type:
			in_error = true
			return null
		i += 1
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

	func current_token_start() -> Vector2i:
		return Vector2i(tokens[i - 1].loc.x, tokens[i - 1].loc.y)

	func current_token_end() -> Vector2i:
		return Vector2i(tokens[i - 1].loc.z, tokens[i - 1].loc.w)

class Executor:
	static var stop_immediately := RefCounted.new():
		set(value):
			if stop_immediately != null:
				assert(false)
				return
			stop_immediately = value
	static var halted := RefCounted.new():
		set(value):
			if halted != null:
				assert(false)
				return
			halted = value

	var errors: Array[Dictionary]

	func exec_file(env: Env, file: File) -> Variant:
		return file.compute(self, env)

	func generate_ast_error(node: ASTNode, message: String) -> void:
		errors.append({
			RANGE: get_loc_range(node.data),
			MESSAGE: message.format(node),
		})

	static func get_loc_range(tokens: Array[Token]) -> Vector4i:
		var range_min := Vector2i(INT32_MAX, INT32_MAX)
		var range_max := Vector2i(0, 0)
		for tok in tokens:
			var left := Vector2i(tok.loc.x, tok.loc.y)
			if left < range_min:
				range_min = left
			var right := Vector2i(tok.loc.z, tok.loc.w)
			if right > range_max:
				range_max = right
		return Vector4i(range_min.x, range_min.y, range_max.x, range_max.y)

	static func stop(v) -> bool:
		return v is RefCounted and v == stop_immediately

class Env:
	# This does assume that the outer scopes will not be modified before this goes out of scope.
	# However, since scopes are strictly nested, I believe this will always hold.
	var methods_copied: bool = false
	var variables_copied: bool = false

	var methods: Dictionary[StringName, MethodInfo]
	var variables: Dictionary[StringName, VarInfo]

	func add_method(method: MethodInfo) -> void:
		if methods_copied:
			methods = methods.duplicate()
			methods_copied = false
		methods[method.name] = method

	func add_variable(variable: VarInfo) -> void:
		if variables_copied:
			variables = variables.duplicate()
			variables_copied = false
		variables[variable.name] = variable

	func duplicate() -> Env:
		var x := Env.new()
		x.methods = methods
		x.variables = variables
		x.methods_copied = true
		x.variables_copied = true
		return x

	func _to_string() -> String:
		return "Env(\n  methods=%s\n  variables=%s\n)" % [", ".join(methods.keys()), ", ".join(variables.keys())]

@abstract class ASTNode:
	var data: Array[Token]

	@abstract func compute(e: Executor, env: Env) -> Variant

	@warning_ignore("unused_parameter")
	func add_completion_env(caret_pos: Vector2i, env: Env) -> void:
		pass

	static func compute_list(e: Executor, env: Env, list: Array[Expr]) -> Variant:
		var args: Array
		for arg in list:
			var v = arg.compute(e, env)
			if Executor.stop(v): return Executor.stop_immediately
			args.append(v)
		return args

	static func caret_in_range(caret_pos: Vector2i, loc_range: Vector4i) -> bool:
		if caret_pos.x == loc_range.x:
			return caret_pos.y >= loc_range.y
		if caret_pos.x == loc_range.z:
			return caret_pos.y < loc_range.w
		return caret_pos.x > loc_range.x and caret_pos.x <= loc_range.z

	static func caret_in_range_2(caret_pos: Vector2i, loc_range_start: Vector2i, loc_range_end: Vector2i) -> bool:
		return loc_gte(caret_pos, loc_range_start) and loc_lt(caret_pos, loc_range_end)

	static func loc_gt(a: Vector2i, b: Vector2i) -> bool:
		if a.x == b.x:
			return a.y > b.y
		return a.x > b.x

	static func loc_gte(a: Vector2i, b: Vector2i) -> bool:
		if a.x == b.x:
			return a.y >= b.y
		return a.x >= b.x

	static func loc_lt(a: Vector2i, b: Vector2i) -> bool:
		if a.x == b.x:
			return a.y < b.y
		return a.x < b.x

	static func loc_lte(a: Vector2i, b: Vector2i) -> bool:
		if a.x == b.x:
			return a.y <= b.y
		return a.x <= b.x

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

class BoolExpr extends Expr:
	var value: bool

	func _to_string() -> String:
		return "(bool %s)" % value

	func compute(_e: Executor, _env: Env) -> Variant:
		return value

class VarExpr extends Expr:
	var name: String

	func _to_string() -> String:
		return "$%s" % name

	func compute(e: Executor, env: Env) -> Variant:
		if name in env.variables:
			var v := env.variables[name]
			if v.getter.is_null():
				e.generate_ast_error(self, "cannot get this variable")
				return Executor.stop_immediately
			return v.getter.call()
		e.generate_ast_error(self, "unknown variable ${name}")
		return Executor.stop_immediately

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
		var is_float := false
		var args: Array
		for arg in elements:
			var arg_v = arg.compute(e, env)
			if Executor.stop(arg_v): return Executor.stop_immediately
			args.append(arg_v)
			if arg_v is int:
				continue
			elif arg_v is float:
				is_float = true
			else:
				e.generate_ast_error(arg, "invalid type for vector `%s`" % type_string(typeof(arg_v)))
				return Executor.stop_immediately
		if Executor.stop(args): return Executor.stop_immediately
		match elements.size():
			2:
				if is_float:
					return Vector2(args[0], args[1])
				else:
					return Vector2i(args[0], args[1])
			3:
				if is_float:
					return Vector3(args[0], args[1], args[2])
				else:
					return Vector3i(args[0], args[1], args[2])
			4:
				if is_float:
					return Vector4(args[0], args[1], args[2], args[3])
				else:
					return Vector4i(args[0], args[1], args[2], args[3])
			_:
				assert(false)
				return Executor.stop_immediately


class ListExpr extends Expr:
	var elements: Array[Expr]

	func _to_string() -> String:
		return "[%s]" % " ".join(elements)

	func compute(e: Executor, env: Env) -> Variant:
		return compute_list(e, env, elements)

class DictExpr extends Expr:
	var elements: Dictionary[Expr, Expr]

	func _to_string() -> String:
		var values: PackedStringArray
		for element in elements:
			values.append("%s: %s" % [element, elements[element]])
		return "{%s}" % " ".join(values)

	func compute(e: Executor, env: Env) -> Variant:
		var result: Dictionary
		for element in elements:
			var key = element.compute(e, env)
			if Executor.stop(key): return Executor.stop_immediately
			var value = elements[element].compute(e, env)
			if Executor.stop(value): return Executor.stop_immediately
			result[key] = value
		return result

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

		var result = expr.execute(list, null, false)
		if expr.has_execute_failed():
			if op == Op.Eq:
				return false
			if op == Op.Neq:
				return true
			e.generate_ast_error(self, expr.get_error_text())
			return Executor.stop_immediately
		return result

	func _to_string() -> String:
		return "(%s %s %s)" % [Op.find_key(op), left, right]

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
		if method.callable.is_standard() and method.callable.get_object() and method.callable.get_method():
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

class FieldAccessExpr extends Expr:
	var target: Expr
	var field: Expr

	func compute(e: Executor, env: Env) -> Variant:
		var target_val = target.compute(e, env)
		if Executor.stop(target_val): return Executor.stop_immediately
		var field_val = field.compute(e, env)
		if Executor.stop(field_val): return Executor.stop_immediately

		var expr := Expression.new()
		expr.parse("a[b]", ["a", "b"])
		var result = expr.execute([target_val, field_val], null, false)
		if expr.has_execute_failed():
			e.generate_ast_error(field, expr.get_error_text())
			return Executor.stop_immediately
		return result

class MethodExpr extends Expr:
	var target: Expr
	var command: String
	var args: Array[Expr]

	func compute(e: Executor, env: Env) -> Variant:
		var target_result = target.compute(e, env)
		if Executor.stop(target_result): return Executor.stop_immediately

		var arg_values_result = compute_list(e, env, args)
		if Executor.stop(arg_values_result): return Executor.stop_immediately
		var arg_values: Array = arg_values_result

		var obtainer := Expression.new()
		obtainer.parse("a.%s" % command, ["a"])
		var callable = obtainer.execute([target_result], null, false)
		if obtainer.has_execute_failed():
			e.generate_ast_error(self, obtainer.get_error_text())
			return Executor.stop_immediately
		if callable is not Callable:
			e.generate_ast_error(self, "cannot convert `%s` to Callable" % type_string(typeof(callable)))
			return Executor.stop_immediately

		var logger := CommandExpr._ErrorCapturingLogger.new()
		OS.add_logger(logger)
		var result = callable.callv(arg_values)
		OS.remove_logger(logger)
		if logger.captured_error:
			e.generate_ast_error(args[logger.position - 1], "cannot convert from %s to %s" % [logger.from_type, logger.to_type])
			return Executor.stop_immediately
		return result

@abstract class Statement extends ASTNode:
	pass

class CompoundStatement extends Statement:
	var statements: Array[Statement]

	func compute(e: Executor, env: Env) -> Variant:
		var new_env := env.duplicate()
		for stmt in statements:
			var value = stmt.compute(e, new_env)
			if Executor.stop(value):
				return Executor.stop_immediately
			if value is _StatementResult:
				return value
		return null

	func add_completion_env(caret_pos: Vector2i, env: Env) -> void:
		for statement in statements:
			statement.add_completion_env(caret_pos, env)

	func _to_string() -> String:
		return "\n".join(statements)

class ExprStatement extends Statement:
	var expr: Expr

	func compute(e: Executor, env: Env) -> Variant:
		var value = expr.compute(e, env)
		return value

	func _to_string() -> String:
		return expr.to_string()

class IfStatement extends Statement:
	var condition: Expr
	var body: Statement
	var else_body: Statement

	var scope_start: Vector2i
	var scope_end: Vector2i

	func compute(e: Executor, env: Env) -> Variant:
		var cond = condition.compute(e, env) if condition != null else true
		if Executor.stop(cond): return Executor.stop_immediately
		if cond:
			var value = body.compute(e, env)
			if value is _StatementResult:
				return value
		elif else_body != null:
			var value = else_body.compute(e, env)
			if value is _StatementResult:
				return value
		return null

	func add_completion_env(caret_pos: Vector2i, env: Env) -> void:
		if caret_in_range_2(caret_pos, scope_start, scope_end):
			body.add_completion_env(caret_pos, env)
		else:
			else_body.add_completion_env(caret_pos, env)

	func _to_string() -> String:
		return "if %s\n  %s\nelse\n  %s\nend" % [
			condition,
			str(body).replace("\n", "\n  "),
			str(else_body).replace("\n", "\n  "),
		]

class VarDeclStatement extends Statement:
	var name: String
	var value: Expr

	var scope_end: Vector2i

	func compute(e: Executor, env: Env) -> Variant:
		var value_value = value.compute(e, env)
		if Executor.stop(value_value): return Executor.stop_immediately

		var info := VarInfo.new()
		info.name = name
		info.type = null
		_make_storage_for(value_value, info)
		env.add_variable(info)
		return null

	static func _make_storage_for(initial_value, info: VarInfo) -> void:
		var data_holder: Array = [initial_value]
		info.setter = func(new_value):
			data_holder[0] = new_value
		info.getter = func():
			return data_holder[0]

	func add_completion_env(caret_pos: Vector2i, env: Env) -> void:
		if loc_gte(caret_pos, scope_end):
			var info := VarInfo.new()
			info.name = name
			env.add_variable(info)

	func _to_string() -> String:
		return "var ${name} = {value}".format(self)

class VarAssignmentStatement extends Statement:
	var name: String
	var value: Expr

	func compute(e: Executor, env: Env) -> Variant:
		if name not in env.variables:
			e.generate_ast_error(self, "unknown variable ${name}")
			return Executor.stop_immediately
		var value_value = value.compute(e, env)
		if Executor.stop(value_value): return Executor.stop_immediately
		var info := env.variables[name]
		if info.setter.is_null():
			e.generate_ast_error(self, "cannot assign to a read-only variable")
			return Executor.stop_immediately
		info.setter.call(value_value)
		return null

	func _to_string() -> String:
		return "E${name} = {value}".format(self)

class ReturnStatement extends Statement:
	var value: Expr

	func compute(e: Executor, env: Env) -> Variant:
		if value == null:
			return _StatementResult.new_return(self, null)

		var result = value.compute(e, env)
		if Executor.stop(result): return Executor.stop_immediately

		return _StatementResult.new_return(self, result)

	func _to_string() -> String:
		if value == null:
			return "return"
		else:
			return "return " + str(value)

class ForLoopStatement extends Statement:
	var name: String
	var iterator: Expr
	var body: Statement

	var scope_start: Vector2i
	var scope_end: Vector2i

	func compute(e: Executor, env: Env) -> Variant:
		var value = iterator.compute(e, env)
		if Executor.stop(value): return Executor.stop_immediately
		if value is not Array and value is not Dictionary and value is not int:
			e.generate_ast_error(iterator, "cannot be iterated upon")
		var current_value: Array = [null]
		var loop_var := VarInfo.new()
		loop_var.name = name
		loop_var.getter = func(): return current_value[0]
		var loop_env := env.duplicate()
		loop_env.add_variable(loop_var)

		for i in value:
			current_value[0] = i
			var result = body.compute(e, loop_env)
			if Executor.stop(result): return Executor.stop_immediately
			if result is _StatementResult:
				if result.type == _StatementResult.Type.Return:
					return result
				elif result.type == _StatementResult.Type.Break:
					break
				elif result.type == _StatementResult.Type.Continue:
					pass

		return null

	func add_completion_env(caret_pos: Vector2i, env: Env) -> void:
		if caret_in_range_2(caret_pos, scope_start, scope_end):
			var info := VarInfo.new()
			info.name = name
			env.add_variable(info)
			body.add_completion_env(caret_pos, env)

class BreakStatement extends Statement:
	@warning_ignore("unused_parameter")
	func compute(e: Executor, env: Env) -> Variant:
		return _StatementResult.new_break(self)

	func _to_string() -> String:
		return "break"

class ContinueStatement extends Statement:
	@warning_ignore("unused_parameter")
	func compute(e: Executor, env: Env) -> Variant:
		return _StatementResult.new_continue(self)

	func _to_string() -> String:
		return "continue"

class FunStatement extends Statement:
	var name: String
	var args: PackedStringArray
	var body: Statement

	var scope_start: Vector2i
	var scope_end: Vector2i
	var stmt_end: Vector2i

	func compute(e: Executor, env: Env) -> Variant:
		var method_info := MethodInfo.new()
		method_info.name = name
		env.add_method(method_info)
		var saved_env := env.duplicate()
		var arguments: Array[ArgumentInfo]
		for arg in args:
			var info := ArgumentInfo.new()
			info.name = arg
			arguments.append(info)
		method_info.arguments = arguments
		method_info.callable = func(...passed_args):
			# this should be validated by CommandExpr but just to be safe
			assert(passed_args.size() == args.size())
			var new_env := saved_env.duplicate()
			for arg_i in passed_args.size():
				var info := VarInfo.new()
				info.name = args[arg_i]
				VarDeclStatement._make_storage_for(passed_args[arg_i], info)
				new_env.add_variable(info)
			var value = body.compute(e, new_env)
			if value is _StatementResult:
				if value.type == _StatementResult.Type.Return:
					return value.value
				else:
					if value.type == _StatementResult.Type.Break:
						e.generate_ast_error(value.data, "cannot use `break` outside of a loop")
					else:
						e.generate_ast_error(value.data, "cannot use `continue` outside of a loop")
					return Executor.stop_immediately
			return value
		return null

	func add_completion_env(caret_pos: Vector2i, env: Env) -> void:
		if caret_in_range_2(caret_pos, scope_start, scope_end):
			for arg in args:
				var info := VarInfo.new()
				info.name = arg
				env.add_variable(info)
			body.add_completion_env(caret_pos, env)
		if loc_gt(caret_pos, scope_start):
			var method_info := MethodInfo.new()
			method_info.name = name
			env.add_method(method_info)
			var arguments: Array[ArgumentInfo]
			for arg in args:
				var info := ArgumentInfo.new()
				info.name = arg
				arguments.append(info)
			method_info.arguments = arguments

	func _to_string() -> String:
		return "fun %s %s\n  %s\nend" % [name, " ".join(args), str(body).replace("\n", "\n  ")]

class File extends CompoundStatement:
	func compute(e: Executor, env: Env) -> Variant:
		for statement in statements:
			var value = statement.compute(e, env)
			if Executor.stop(value):
				return Executor.stop_immediately
			if value is _StatementResult:
				if value.type == _StatementResult.Type.Return:
						return value.value
				else:
					if value.type == _StatementResult.Type.Break:
						e.generate_ast_error(value.data, "cannot use `break` outside of a loop")
					else:
						e.generate_ast_error(value.data, "cannot use `continue` outside of a loop")
					return Executor.stop_immediately
		return Executor.halted

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

	var setter: Callable
	var getter: Callable

class ArgumentInfo extends VarInfo:
	var optional: bool
	var optional_default

class TypeInfo:
	var clazz_name: StringName
	var type: Variant.Type
	var hint: PropertyHint
	var hint_string: String
	var usage: PropertyUsageFlags

class _StatementResult:
	enum Type {
		Return,
		Break,
		Continue,
	}

	var data: ASTNode
	var type: Type
	var value: Variant

	@warning_ignore("shadowed_variable")
	static func new_return(data: ASTNode, value: Variant) -> _StatementResult:
		var result := new()
		result.data = data
		result.type = Type.Return
		result.value = value
		return result

	@warning_ignore("shadowed_variable")
	static func new_break(data: ASTNode) -> _StatementResult:
		var result := new()
		result.data = data
		result.type = Type.Break
		return result

	@warning_ignore("shadowed_variable")
	static func new_continue(data: ASTNode) -> _StatementResult:
		var result := new()
		result.data = data
		result.type = Type.Continue
		return result
