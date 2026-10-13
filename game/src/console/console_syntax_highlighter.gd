class_name ConsoleSyntaxHighlighter extends SyntaxHighlighter

const TYPE = ConsoleLanguage.Token.Type

static func get_line_syntax_highlighting_tokens(line_text: String) -> Dictionary:
	var token_result := ConsoleLanguage.new().tokenize(line_text)
	var hl: Dictionary
	var comment_column := line_text.find("#")
	for token in token_result.tokens:
		var col0 := token.loc.y
		var col1 := token.loc.w
		if comment_column >= 0 and col0 > comment_column:
			continue
		var color := &"text"
		match token.type:
			TYPE.Word:
				color = &"text"
			TYPE.Str:
				color = &"green"
			TYPE.Int, TYPE.Flt:
				color = &"peach"
				color = &"peach"
			TYPE.Break:
				continue
			TYPE.VarRef:
				color = &"blue"
			TYPE.BracketOpen, TYPE.BracketClose, TYPE.ParenOpen, TYPE.ParenClose, TYPE.BraceOpen, TYPE.BraceClose:
				color = &"overlay2"
			TYPE.Colon, TYPE.Add, TYPE.Sub, TYPE.Mul, TYPE.Div, TYPE.Gt, TYPE.Lt, TYPE.BitAnd, TYPE.BitOr, TYPE.BitXor, TYPE.Shr, TYPE.Shl, TYPE.Pow, TYPE.Gte, TYPE.Lte, TYPE.Eq, TYPE.Neq, TYPE.And, TYPE.Or, TYPE.Not, TYPE.Assign:
				color = &"teal"
			TYPE.KwElseIf, TYPE.KwIf, TYPE.KwFor, TYPE.KwEnd, TYPE.KwFun, TYPE.KwVar, TYPE.KwElse, TYPE.KwTrue, TYPE.KwFalse, TYPE.KwBreak, TYPE.KwReturn, TYPE.KwContinue:
				color = &"mauve"

		hl[col0] = {
			color = color,
		}

		hl[col1] = {
			color = &"text",
		}
	if comment_column >= 0:
		hl[comment_column] = {
			color = &"overlay2",
		}
	return hl

func _get_line_syntax_highlighting(line: int) -> Dictionary:
	var tokens := get_line_syntax_highlighting_tokens(get_text_edit().get_line(line))
	for key in tokens:
		var data = tokens[key].duplicate()
		data.color = Console.C_THEME[data.color]
		tokens[key] = data
	return tokens
