extends Area2D

class_name Coin

signal collected(value: int)

@export var value: int = 1

# Radians/sec of the horizontal squash that reads as a spinning disc. The two scenes set
# this apart on purpose: the ordinary coin is calm because ~168 of them cross the screen in
# a two-minute run and a fast one turns the ground into strobing, while the rare diamond
# spins hard precisely BECAUSE it is rare -- it has ~0.92s on screen to be noticed.
@export var spin_speed: float = 3.575
# How far the squash goes. 1.0 is no spin; 0.0 flips through zero width like a Mario coin,
# which also means the pickup is invisible at every half-turn. That is the opposite of what
# the sprite rebuild was for, so both scenes stay well clear of it -- the coin only hints at
# a spin, the diamond squashes far enough to flash without ever disappearing.
@export var spin_min_scale: float = 0.55

# Collect feedback. Short and small deliberately: this fires up to 168 times a run, so
# anything with real scale or duration reads as screen noise rather than reward.
const POP_DURATION: float = 0.16
const POP_SCALE: float = 1.35

var has_been_collected: bool = false
# Set by CoinSpawner the frame this coin passes behind the player uncollected, so the combo
# break fires exactly once per coin. Lives here rather than in a spawner-side set because the
# spawner already frees coins on its own schedule and a keyed set would outlive them.
var has_been_missed: bool = false

var visual: CanvasItem
var visual_base_scale: Vector2 = Vector2.ONE
# Keeps a row of coins from squashing in lockstep, which reads as one pulsing object rather
# than several spinning ones. Derived from position instead of randf() so the look is a pure
# function of where the coin was placed, like everything else the spawners produce.
var spin_phase: float = 0.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	visual = get_node_or_null("Visual") as CanvasItem
	if visual == null:
		set_process(false)
		return
	visual_base_scale = visual.scale
	spin_phase = fmod(absf(position.x) * 0.021 + absf(position.y) * 0.013, TAU)


func _process(delta: float) -> void:
	spin_phase = fmod(spin_phase + (spin_speed * delta), TAU)
	# abs(cos) rather than a full rotation: a Sprite2D scaled through negative x mirrors
	# itself, which is the correct read for a disc but costs a frame of zero width. Staying
	# positive keeps the silhouette continuous.
	var squash: float = spin_min_scale + ((1.0 - spin_min_scale) * absf(cos(spin_phase)))
	visual.scale.x = visual_base_scale.x * squash


# The ONE place that knows how a coin is drawn. Both spawners push a biome's coin_color
# through here rather than reaching for the visual themselves -- see visuals.md's art-swap
# traps, where the loose get_node("ColorRect") was one of four.
#
# The visual is a Sprite2D, so the biome colour is a MULTIPLY over the sprite's own gold,
# not the absolute fill the ColorRect took. All nine palettes author a warm gold at or below
# the sprite's own, so the multiply only deepens it; it can never brighten, which is why the
# palettes stay the readable-contrast source of truth for biome_schedule_check.
#
# The rare coin uses this scene's script but no spawner pushes a colour into it, so the
# diamond keeps modulate WHITE and renders as authored.
#
# Refuses to paint a collected coin: apply_biome_color() runs on every frame of a crossfade
# and would otherwise reset modulate.a to 1 partway through the collect fade, undoing it.
#
# Safe to call the frame the scene is instantiated, before add_child(): an instanced scene's
# children exist immediately, they just haven't entered the tree. `visual` is still null at
# that point, hence the lookup here rather than a cached reference.
func set_visual_color(color: Color) -> void:
	if has_been_collected:
		return
	var target: CanvasItem = visual if visual != null else get_node_or_null("Visual") as CanvasItem
	if target != null:
		target.modulate = color


func _on_body_entered(body: Node2D) -> void:
	if has_been_collected:
		return
	if not body.is_in_group("player"):
		return

	has_been_collected = true
	set_deferred("monitoring", false)
	collected.emit(value)
	play_collect_pop()


# Frees the coin either way -- the value is already banked by the time this runs, so the
# node lingering for POP_DURATION only affects what is drawn. The spawners' despawn path
# queue_free()s the whole chunk group, which takes a mid-pop coin with it harmlessly.
func play_collect_pop() -> void:
	if visual == null:
		queue_free()
		return

	set_process(false)
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(visual, "scale", visual_base_scale * POP_SCALE, POP_DURATION) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(visual, "modulate:a", 0.0, POP_DURATION) \
		.set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(queue_free)
