class_name RoomData
extends RefCounted

enum RoomType {
	ENGINE_ROOM,
	POWER_ROOM,
	FUEL_BAY_BILGE,
	GALLEY,
	STORAGE,
	MORGUE,
	SERVER_ROOM,
	BATHROOM,
	CAFETERIA,
	PASSENGER_BEDROOMS,
	CREW_QUARTERS,
	MEDBAY,
	LIBRARY,
}

const CORE_ROOMS: Array[RoomType] = [
	RoomType.ENGINE_ROOM,
	RoomType.POWER_ROOM,
	RoomType.FUEL_BAY_BILGE,
	RoomType.GALLEY,
	RoomType.STORAGE,
]

const SUPPORT_ROOMS: Array[RoomType] = [
	RoomType.MORGUE,
	RoomType.SERVER_ROOM,
	RoomType.BATHROOM,
	RoomType.CAFETERIA,
	RoomType.PASSENGER_BEDROOMS,
	RoomType.CREW_QUARTERS,
	RoomType.MEDBAY,
	RoomType.LIBRARY,
]

# name, color, min_w, max_w, min_d, max_d, layer_weights[l1..l4], min_layer, max_layer
const DEFS: Dictionary = {
	RoomType.ENGINE_ROOM: {
		"name": "engine room", "color": Color(0.85, 0.30, 0.20),
		"min_w": 10, "max_w": 16, "min_d": 10, "max_d": 16,
		"weights": [1.0, 1.0, 0.4, 0.2], "min_layer": 1, "max_layer": 2,
	},
	RoomType.POWER_ROOM: {
		"name": "power room", "color": Color(0.95, 0.75, 0.15),
		"min_w": 8, "max_w": 12, "min_d": 8, "max_d": 12,
		"weights": [0.3, 0.8, 1.5, 1.0], "min_layer": 0, "max_layer": 0,
	},
	RoomType.FUEL_BAY_BILGE: {
		"name": "fuel bay and bilge", "color": Color(0.55, 0.35, 0.15),
		"min_w": 8, "max_w": 14, "min_d": 8, "max_d": 14,
		"weights": [1.0, 0.0, 0.0, 0.0], "min_layer": 1, "max_layer": 1,
	},
	RoomType.GALLEY: {
		"name": "galley", "color": Color(0.40, 0.75, 0.45),
		"min_w": 7, "max_w": 11, "min_d": 7, "max_d": 11,
		"weights": [0.2, 0.6, 1.0, 1.4], "min_layer": 0, "max_layer": 0,
	},
	RoomType.STORAGE: {
		"name": "storage", "color": Color(0.55, 0.55, 0.60),
		"min_w": 8, "max_w": 14, "min_d": 8, "max_d": 14,
		"weights": [0.8, 1.2, 1.2, 1.0], "min_layer": 0, "max_layer": 0,
	},
	RoomType.MORGUE: {
		"name": "morgue", "color": Color(0.45, 0.45, 0.50),
		"min_w": 5, "max_w": 8, "min_d": 5, "max_d": 8,
		"weights": [1.2, 1.4, 0.8, 0.4], "min_layer": 0, "max_layer": 0,
	},
	RoomType.SERVER_ROOM: {
		"name": "server room", "color": Color(0.20, 0.55, 0.85),
		"min_w": 6, "max_w": 10, "min_d": 6, "max_d": 10,
		"weights": [0.3, 0.8, 1.4, 1.0], "min_layer": 0, "max_layer": 0,
	},
	RoomType.BATHROOM: {
		"name": "bathroom", "color": Color(0.35, 0.70, 0.80),
		"min_w": 4, "max_w": 7, "min_d": 4, "max_d": 7,
		"weights": [0.4, 0.8, 1.0, 1.3], "min_layer": 0, "max_layer": 0,
	},
	RoomType.CAFETERIA: {
		"name": "cafeteria", "color": Color(0.90, 0.55, 0.25),
		"min_w": 9, "max_w": 14, "min_d": 9, "max_d": 14,
		"weights": [0.2, 0.5, 1.0, 1.5], "min_layer": 0, "max_layer": 0,
	},
	RoomType.PASSENGER_BEDROOMS: {
		"name": "passenger bedrooms", "color": Color(0.70, 0.45, 0.75),
		"min_w": 8, "max_w": 13, "min_d": 6, "max_d": 10,
		"weights": [0.2, 0.5, 1.2, 1.5], "min_layer": 0, "max_layer": 0,
	},
	RoomType.CREW_QUARTERS: {
		"name": "crew quarters", "color": Color(0.50, 0.65, 0.40),
		"min_w": 7, "max_w": 11, "min_d": 6, "max_d": 10,
		"weights": [0.3, 0.6, 1.0, 1.4], "min_layer": 0, "max_layer": 0,
	},
	RoomType.MEDBAY: {
		"name": "med bay", "color": Color(0.90, 0.90, 0.95),
		"min_w": 7, "max_w": 11, "min_d": 7, "max_d": 11,
		"weights": [0.4, 0.8, 1.0, 1.3], "min_layer": 0, "max_layer": 0,
	},
	RoomType.LIBRARY: {
		"name": "library", "color": Color(0.60, 0.45, 0.30),
		"min_w": 6, "max_w": 10, "min_d": 6, "max_d": 10,
		"weights": [0.4, 0.8, 1.1, 1.2], "min_layer": 0, "max_layer": 0,
	},
}

static func get_def(type: RoomType) -> Dictionary:
	return DEFS[type]
