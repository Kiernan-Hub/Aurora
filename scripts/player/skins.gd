extends RefCounted

class_name Skins

# The skaters a player can pick on the start screen's Skaters modal. Each is one SpriteFrames
# with the same "skate" animation as the original, and only the look changes: the hitbox is the
# Player's capsule, so every skin is drawn the SAME HEIGHT as the girl (scripts/tools/
# build_skin_frames.py normalises them) or a taller one would look like it clips floes it clears.
#
# THE IDS ARE SAVE DATA (SaveStore.selected_skin): adding a row is free, renaming one sends every
# player who picked it back to the default. Table order is display order; the first is the default.
const SKINS: Array[Dictionary] = [
	{"id": "kid", "name": "Kid", "frames": "res://assets/sprites/player/player_skate_frames.tres"},
	{"id": "teen", "name": "Teen", "frames": "res://assets/sprites/player/teen/frames.tres"},
	{"id": "twenties", "name": "Twenties", "frames": "res://assets/sprites/player/twenties/frames.tres"},
	{"id": "mom", "name": "Mom", "frames": "res://assets/sprites/player/mom/frames.tres"},
	{"id": "dad", "name": "Dad", "frames": "res://assets/sprites/player/dad/frames.tres"},
]
const DEFAULT_ID: String = "kid"


# The row for id, or the default's for an unknown one (a save from a newer build, or a hand edit).
static func get_skin(id: String) -> Dictionary:
	for skin: Dictionary in SKINS:
		if skin["id"] == id:
			return skin
	return SKINS[0]
