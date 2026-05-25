extends CanvasLayer
## Chillas Art / Fears to Fathom film grade — not VHS.

var _mat: ShaderMaterial
var _overlay: ColorRect
var _enabled: bool = true

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 127
	_overlay = ColorRect.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/horror_grade.gdshader")
	_overlay.material = _mat
	apply_quality_preset(GameManager.graphics_quality, true)

func apply_quality_preset(quality: int, enabled: bool = true) -> void:
	_enabled = enabled
	if not _mat:
		return
	_overlay.visible = enabled
	if not enabled:
		return
	var grain := 0.012
	var vig := 0.42
	var desat := 0.12
	match quality:
		GameManager.GraphicsQuality.LOW:
			grain = 0.008
			vig = 0.38
			desat = 0.10
		GameManager.GraphicsQuality.MEDIUM:
			grain = 0.012
			vig = 0.44
			desat = 0.12
		GameManager.GraphicsQuality.HIGH:
			grain = 0.018
			vig = 0.52
			desat = 0.18
	_mat.set_shader_parameter("grain_amount", grain)
	_mat.set_shader_parameter("vignette_power", vig)
	_mat.set_shader_parameter("desaturate", desat)

func _process(_delta: float) -> void:
	if not _mat or not _enabled:
		return
	var san = 100.0
	if GameManager.sanity_ref:
		san = GameManager.sanity_ref.sanity
	_mat.set_shader_parameter("sanity_drain", clamp(1.0 - san / 100.0, 0.0, 1.0))
