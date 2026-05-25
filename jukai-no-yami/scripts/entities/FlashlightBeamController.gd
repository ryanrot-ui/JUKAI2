extends MeshInstance3D

# ─── Flashlight Volumetric Beam ───────────────────────────────────────────────
# Child of the SpotLight3D (Flashlight node).
# Uses a cone mesh with flashlight_volumetric.gdshader for fake volumetric rays.
# Syncs visibility and flicker to the parent flashlight.

var _flashlight: Node = null
var _mat: ShaderMaterial = null
var _last_on: bool = true

func _ready() -> void:
	_flashlight = get_parent()
	if material_override is ShaderMaterial:
		_mat = material_override as ShaderMaterial

func _process(_delta: float) -> void:
	if not _flashlight:
		return

	# Mirror flashlight visibility
	var fl_visible = _flashlight.visible and _flashlight.is_on
	if fl_visible != _last_on:
		_last_on = fl_visible
		visible  = fl_visible

	if not visible or not _mat:
		return

	# Drive flicker_amount shader param from battery level + sanity
	var bat_factor    = 1.0 - clampf(_flashlight.battery / 100.0, 0.0, 1.0)
	var sanity_factor = 0.0
	if GameManager.sanity_ref:
		sanity_factor = 1.0 - clampf(GameManager.sanity_ref.sanity / 100.0, 0.0, 1.0)
	var flicker = clampf(bat_factor * 0.5 + sanity_factor * 0.5, 0.0, 0.85)
	_mat.set_shader_parameter("flicker_amount", flicker)
	# Dim beam density as battery drains
	_mat.set_shader_parameter("density", lerpf(0.28, 0.10, bat_factor))
