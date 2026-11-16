extends RefCounted

class_name Cosmetics

# Chest-only, permanent finds. IDs are save data; this catalogue has no services or physics.
# Charms are collection pieces. Trails and outfit colours can be equipped independently.
const KINDS: Array[String] = ["trail", "outfit", "charm"]
const TITLES: Dictionary = {"trail": "Skate trails", "outfit": "Outfit colours", "charm": "Ice charms"}
const ICONS: Dictionary = {
	"trail": "res://assets/ui/collection/trail.svg",
	"outfit": "res://assets/ui/collection/outfit.svg",
	"charm": "res://assets/ui/collection/crystal.svg",
}
const ITEMS: Array[Dictionary] = [
	{"id": "trail_comet", "kind": "trail", "name": "Comet", "color": Color(0.55, 1.0, 0.82), "length": 26.0, "width": 2.5},
	{"id": "trail_frost", "icon": "res://assets/ui/collection/frost.svg", "kind": "trail", "name": "Frost dust", "color": Color(0.65, 0.85, 1.0), "length": 5.0, "width": 3.0},
	{"id": "trail_ribbon", "icon": "res://assets/ui/collection/ribbon.svg", "kind": "trail", "name": "Ribbon", "color": Color(0.85, 0.65, 1.0), "length": 32.0, "width": 1.2},
	{"id": "outfit_glacier", "kind": "outfit", "name": "Glacier", "color": Color(0.25, 0.8, 0.85)},
	{"id": "outfit_moonstone", "kind": "outfit", "name": "Moonstone", "color": Color(0.65, 0.5, 0.9)},
	{"id": "outfit_sunstone", "kind": "outfit", "name": "Sunstone", "color": Color(1.0, 0.7, 0.3)},
	{"id": "charm_crystal", "kind": "charm", "name": "Ice crystal", "color": Color(0.65, 0.9, 1.0)},
	{"id": "charm_snowflake", "kind": "charm", "name": "Snowflake", "color": Color(0.9, 0.95, 1.0), "icon": "res://assets/ui/collection/snowflake.svg"},
	{"id": "charm_moon", "kind": "charm", "name": "Moon shard", "color": Color(0.85, 0.75, 1.0), "icon": "res://assets/ui/collection/moon.svg"},
]
# Clothing hues in the five existing sprite sets. The outfit shader replaces this hue only,
# preserving skin/hair and the clothing's light and shade. No sprite geometry changes.
const CLOTHING_HUES: Dictionary = {"kid": 0.97, "teen": 0.62, "twenties": 0.38, "mom": 0.01, "dad": 0.65}

const CLOTHING_HUE_RADIUS: Dictionary = {"kid": 0.04, "teen": 0.05, "twenties": 0.11, "mom": 0.015, "dad": 0.04}


static func get_item(id: String) -> Dictionary:
	for item: Dictionary in ITEMS:
		if item["id"] == id:
			return item
	return {}


static func get_unowned(owned: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	for item: Dictionary in ITEMS:
		if not owned.get(item["id"], false):
			ids.append(item["id"])
	return ids
