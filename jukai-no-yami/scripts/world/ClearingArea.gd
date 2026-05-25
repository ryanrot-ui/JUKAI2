extends Area3D

# ─── Clearing Area ─────────────────────────────────────────────────────────────
# Place in open areas of the forest where tree canopy is thin.
# Causes flashlight battery to drain faster — player feels the openness.
# Also slightly worsens flicker because open areas = less shelter = more fear.

@export var drain_multiplier: float = 1.0  # set on the Flashlight node directly

func _ready() -> void:
	body_entered.connect(_on_entered)
	body_exited.connect(_on_exited)
	collision_layer = 0
	collision_mask  = 1  # player layer

func _on_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	var flashlight = body.get_node_or_null("Camera3D/HandPivot/Flashlight")
	if flashlight and flashlight.has_method("set_clearing"):
		flashlight.set_clearing(true)

func _on_exited(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	var flashlight = body.get_node_or_null("Camera3D/HandPivot/Flashlight")
	if flashlight and flashlight.has_method("set_clearing"):
		flashlight.set_clearing(false)
