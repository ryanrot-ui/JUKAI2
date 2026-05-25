extends Node

# ─── Jumpscare System (Autoload) ──────────────────────────────────────────────
# Central controller for all J-horror jump scare effects.
# Screen flash → brief static → camera shake → sanity drain → audio sting.
# Ghosts call trigger() when revealed in the flashlight beam.

signal jumpscare_fired(intensity: int)

enum Intensity { SOFT = 0, MEDIUM = 1, HARD = 2, MAX = 3 }

const FLASH_ALPHA    = [0.35, 0.60, 0.80, 0.95]
const FLASH_DURATION = [0.20, 0.35, 0.50, 0.70]
const SHAKE_MAG      = [0.003, 0.007, 0.014, 0.026]
const SHAKE_DUR      = [0.25, 0.40, 0.60, 0.90]
const SANITY_DRAIN   = [4.0,  10.0, 18.0, 28.0]
const STATIC_DUR     = [0.00, 0.05, 0.10, 0.18]

var _shake_mag: float   = 0.0
var _shake_dur: float   = 0.0
var _shake_t:   float   = 0.0
var _is_shaking: bool   = false
var _cooldown:   float  = 0.0
const MIN_COOLDOWN      = 3.5  # seconds between jump scares

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(delta: float) -> void:
	_cooldown = max(0.0, _cooldown - delta)

	if not _is_shaking:
		return
	_shake_t -= delta
	if _shake_t <= 0.0:
		_is_shaking = false
		_reset_camera_shake()
		return
	# Shake is applied by Player.gd via get_shake_offset() — it owns camera
	# rotation each frame, so it has to layer the shake on top of pitch/roll.

# ─── Public API ───────────────────────────────────────────────────────────────

func trigger(intensity: int = Intensity.HARD) -> void:
	if _cooldown > 0.0:
		return
	_cooldown = MIN_COOLDOWN

	jumpscare_fired.emit(intensity)
	_start_shake(SHAKE_MAG[intensity], SHAKE_DUR[intensity])

	if GameManager.sanity_ref:
		GameManager.sanity_ref.drain(SANITY_DRAIN[intensity])
	AudioManager.play_jumpscare_sting()

# Called specifically when a ghost is revealed in the flashlight beam
func trigger_flashlight_reveal(_ghost_type: String = "yurei", intensity: int = Intensity.HARD) -> void:
	if _cooldown > 0.0:
		return
	trigger(intensity)
	# Extra koto sting for flashlight reveals
	if intensity >= Intensity.HARD:
		AudioManager.play_ghost_sound("koto_sting")

# ─── Camera Shake ─────────────────────────────────────────────────────────────

func _start_shake(mag: float, dur: float) -> void:
	_shake_mag = mag
	_shake_dur = dur
	_shake_t   = dur
	_is_shaking = true

# Returns (pitch_offset, roll_offset). Decays with remaining shake time.
# Player.gd reads this and layers it on top of cam_pitch_smooth / roll each
# frame, so pitch shake actually survives the camera-rotation rewrite.
func get_shake_offset() -> Vector2:
	if not _is_shaking or _shake_dur <= 0.0:
		return Vector2.ZERO
	var t = clampf(_shake_t / _shake_dur, 0.0, 1.0)
	var mag = _shake_mag * t
	return Vector2(randf_range(-mag, mag), randf_range(-mag * 0.5, mag * 0.5))

func _reset_camera_shake() -> void:
	_shake_mag = 0.0
	_shake_t = 0.0
