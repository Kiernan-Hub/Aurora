extends ThinIce

class_name BlackIce

# BLACK ICE: a glassy stretch you cannot take off from. Not deadly on its own -- it takes the
# jump away, so whatever follows it has to be cleared by jumping BEFORE it or after it ends.
# A new decision (commit early), not a new body: Player asks ObstacleSpawner.is_black_ice_at()
# at its one ground take-off site, and terrain_invariant_check's fairness model bans take-off
# frames over the span the same way. Landing on it is fine; air moves are unaffected.
#
# Never cracks, so ThinIce's span check is switched off. Not a danger colour either: it is
# drawn as authored (dark glass, white gloss) and ignores the biome's obstacle red, which is
# what keeps it from reading as thin ice, whose meaning (keep hopping) is the opposite.

const BLACK_TEXTURE: Texture2D = preload("res://assets/sprites/hazards/black_ice.png")


func build_visual(terrain: TerrainGenerator, _color: Color) -> void:
	super.build_visual(terrain, Color.WHITE)


func get_strip_texture() -> Texture2D:
	return BLACK_TEXTURE


func set_visual_color(_color: Color) -> void:
	pass


func _physics_process(_delta: float) -> void:
	pass
