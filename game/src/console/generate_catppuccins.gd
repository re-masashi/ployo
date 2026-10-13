@tool class_name GenerateCatppuccins extends EditorScript

const FLAVORS: PackedStringArray = ["latte", "mocha"]

func _run() -> void:
	var palette = load("res://src/console/palette.json").data
	for flavor in FLAVORS:
		var res := Catppuccin.new()
		res.name = palette[flavor].name
		res.dark = palette[flavor].dark
		for color in palette[flavor].colors:
			res[color] = Color.html(palette[flavor].colors[color].hex)
		ResourceSaver.save(res, "res://src/console/catppuccins/%s.tres" % flavor)
