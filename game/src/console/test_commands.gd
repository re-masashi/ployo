@warning_ignore_start("unused_parameter")

func cmd1() -> void:
	print("cmd1")

func cmd2(x, y: int) -> void:
	print("cmd2")

func cmd3(x, y: int, z: String = "hi") -> void:
	print("cmd3")

func cmd4(x, y: int, z: int = Time.get_ticks_msec()) -> void:
	print("cmd4")

func cmd5(x: Array[Node], y: Array[int], z: Array[Quaternion]) -> void:
	print("cmd5")
