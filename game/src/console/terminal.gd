@tool class_name Terminal extends RichTextLabel

func _init() -> void:
	install_effect(CatEffect.new())

	clip_contents = true

func add_line(line: String) -> void:
	append_text(line)

class CatEffect extends RichTextEffect:
	var bbcode = "c2"

	func _process_custom_fx(char_fx: CharFXTransform) -> bool:
		char_fx.color = Console.C_THEME.get(char_fx.env.c)
		return true
