@warning_ignore_start("unused_parameter")

func cmd1() -> void:
	print("cmd1")

func cmd2(x, y: int) -> void:
	print("cmd2 %s %s" % [x, y])

func cmd3(x, y: int, z: String = "hi") -> void:
	print("cmd3")

func cmd4(x, y: int, z: int = Time.get_ticks_msec()) -> void:
	print("cmd4")

func cmd5(x: Array, y: Array, z: Array) -> void:
	print("cmd5 %s %s %s" % [x, y, z])

func accepts_int(x: Array) -> void:
	print(x)

func p(x) -> void:
	print(x)
