extends RefCounted

class_name ChestTypes

enum Tier { NORMAL, RARE, AURORA }
const TYPES: Array[Dictionary] = [
	{"name": "Normal", "weight": 70, "glow": Color(1.0, 0.82, 0.45, 0.65), "glow_scale": 0.6,
		"closed": "res://assets/sprites/chest/closed.png", "open": "res://assets/sprites/chest/open.png"},
	{"name": "Rare", "weight": 25, "glow": Color(0.35, 0.8, 1.0, 1.0), "glow_scale": 0.95,
		"closed": "res://assets/sprites/chest/closed.png", "open": "res://assets/sprites/chest/open.png"},
	{"name": "Aurora", "weight": 5, "glow": Color(0.65, 0.4, 1.0, 1.0), "glow_scale": 1.15,
		"closed": "res://assets/sprites/chest/aurora_closed.png", "open": "res://assets/sprites/chest/aurora_open.png"},
]
const AURA: Texture2D = preload("res://assets/ui/collection/chest_aura.svg")


static func normalize(tier: int) -> int:
	return tier if tier >= 0 and tier < TYPES.size() else Tier.NORMAL


static func get_type(tier: int) -> Dictionary:
	return TYPES[normalize(tier)]


# A unit roll supplied by the spawner's own seeded hash: retries retain the same tier.
static func from_roll(unit: float) -> int:
	var roll: float = clampf(unit, 0.0, 0.999999) * 100.0
	for tier: int in range(TYPES.size()):
		roll -= float(TYPES[tier]["weight"])
		if roll < 0.0:
			return tier
	return Tier.NORMAL
