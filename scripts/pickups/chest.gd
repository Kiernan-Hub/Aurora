extends Coin

class_name ChestPickup

# Same Coin lifecycle, player-only collection, hitbox and placement. Rarity is visual/data only.
var tier: int = ChestTypes.Tier.NORMAL
var aura: Sprite2D


func _ready() -> void:
	super._ready()
	set_tier(tier)


func set_tier(value: int) -> void:
	tier = ChestTypes.normalize(value)
	var style: Dictionary = ChestTypes.get_type(tier)
	var glow: Sprite2D = get_node("Visual/Glow") as Sprite2D
	glow.modulate = style["glow"]
	glow.scale = Vector2.ONE * float(style["glow_scale"])
	var art: Sprite2D = get_node("Visual/Art") as Sprite2D
	art.texture = load(style["closed"]) as Texture2D
	art.modulate = Color(0.8, 0.94, 1.0) if tier == ChestTypes.Tier.RARE else Color.WHITE
	if aura == null:
		aura = Sprite2D.new()
		aura.name = "Aura"
		aura.texture = ChestTypes.AURA
		aura.modulate.a = 0.8
		get_node("Visual").add_child(aura)
		get_node("Visual").move_child(aura, 1)
	aura.visible = tier == ChestTypes.Tier.AURORA


func _process(delta: float) -> void:
	super._process(delta)
	if aura != null and aura.visible:
		aura.rotation += delta * 0.35
