extends CharacterBody3D

# ─── Stalker AI — Full Psychological State Machine ────────────────────────────
#
# STATE FLOW:
#   INACTIVE → WAKING → SHADOW_LURK → STALK → CLOSE_WATCH → RETREAT → COOLDOWN
#                                                          ↘ LUNGE (rare)
#
# PACING DESIGN:
#   • SHADOW_LURK: 90–180 s at 25–42 m range — lurks, rotates, scratches trees.
#     Player hears 3D sounds from a known direction but CANNOT approach safely.
#   • STALK: closes to 14 m — only moves when player looks away.
#   • CLOSE_WATCH: 45–120 s at 9 m — heavy breathing audible, barely visible.
#   • LUNGE: ONLY if sanity < 40 AND player looked away ≥ 8 s continuously.
#   • RETREAT: any direct stare triggers retreat; re-enters COOLDOWN.
#   • COOLDOWN: strict 2–5 min timer. Monster is invisible and silent.

enum State {
	INACTIVE,
	WAKING,
	SHADOW_LURK,
	STALK,
	CLOSE_WATCH,
	LUNGE,
	RETREAT,
	COOLDOWN
}

# ── Tuning constants ──────────────────────────────────────────────────────────
const WAKING_DURATION         := 2.8
const LURK_MIN                := 90.0
const LURK_MAX                := 180.0
const LURK_DIST_MIN           := 25.0
const LURK_DIST_MAX           := 42.0
const SCRATCH_INTERVAL_MIN    := 16.0
const SCRATCH_INTERVAL_MAX    := 44.0
const STALK_SPEED             := 2.6
const STALK_TARGET_DIST       := 14.0
const STALK_TIMEOUT           := 90.0
const CLOSE_WATCH_MIN         := 45.0
const CLOSE_WATCH_MAX         := 120.0
const CLOSE_WATCH_DIST        := 9.0
const CLOSE_CREEP_SPEED       := 1.1
const LUNGE_LOOK_AWAY_TRIGGER := 8.0
const LUNGE_SPEED             := 5.8
const KILL_DISTANCE           := 1.6
const RETREAT_SPEED           := 4.8
const RETREAT_DIST_TARGET     := 36.0
const RETREAT_TIMEOUT         := 12.0
const COOLDOWN_MIN            := 120.0   # 2 minutes
const COOLDOWN_MAX            := 300.0   # 5 minutes
const LOOK_DOT_DIRECT         := 0.90
const LOOK_DOT_SOFT           := 0.62

@export var activation_sanity:     float = 60.0
@export var lunge_sanity_threshold: float = 40.0

# ── Runtime state ─────────────────────────────────────────────────────────────
var state: State = State.INACTIVE

var _state_timer:      float = 0.0
var _state_duration:   float = 0.0
var _cooldown_left:    float = 0.0
var _scratch_timer:    float = 0.0
var _scratch_next:     float = 0.0
var _lunge_look_timer: float = 0.0
var _retreat_target:   Vector3 = Vector3.ZERO
var _waking_alpha:     float = 0.0

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _player:  CharacterBody3D = null
var _audio:   Node = null       # StalkerAudio child
var _mesh:    MeshInstance3D = null

# ─── Setup ────────────────────────────────────────────────────────────────────

func _ready() -> void:
	add_to_group("stalker")
	visible = false
	set_physics_process(false)
	# _process stays enabled so we can monitor sanity and auto-activate
	# the first time the player crosses the threshold.
	_build_body()
	# Create StalkerAudio child
	var audio_node = Node3D.new()
	audio_node.name = "StalkerAudio"
	audio_node.set_script(preload("res://scripts/entities/StalkerAudio.gd"))
	add_child(audio_node)
	await get_tree().process_frame
	_audio = get_node_or_null("StalkerAudio")

func _process(_delta: float) -> void:
	# Monitor sanity and auto-activate when the player first crosses the
	# threshold. Once active, _physics_process drives the state machine.
	if state != State.INACTIVE:
		return
	if GameManager.state != GameManager.GameState.PLAYING:
		return
	if not GameManager.sanity_ref or not GameManager.player_ref:
		return
	if GameManager.sanity_ref.sanity <= activation_sanity:
		activate()

func _build_body() -> void:
	# Pass-through to the player (proximity-based, not collision-based).
	collision_layer = 0

	var cap = CapsuleShape3D.new()
	cap.radius = 0.34
	cap.height = 1.90
	var col = CollisionShape3D.new()
	col.shape = cap
	col.position.y = 0.95
	add_child(col)

	# Dark shadowy silhouette using ghost shader (nearly opaque, very dark)
	_mesh = MeshInstance3D.new()
	var body_mesh = CapsuleMesh.new()
	body_mesh.radius = 0.34
	body_mesh.height = 1.90
	body_mesh.radial_segments = 10
	body_mesh.rings = 4
	_mesh.mesh = body_mesh
	_mesh.position.y = 0.95
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Re-use ghost shader but tuned for a dark lurking silhouette
	var mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/ghost_material.gdshader")
	mat.set_shader_parameter("ghost_color",    Color(0.04, 0.02, 0.06, 0.70))
	mat.set_shader_parameter("edge_glow",      0.25)
	mat.set_shader_parameter("distort_speed",  0.08)
	mat.set_shader_parameter("distort_amount", 0.005)
	mat.set_shader_parameter("flicker_speed",  0.4)
	_mesh.material_override = mat
	add_child(_mesh)

# ─── Public API ───────────────────────────────────────────────────────────────

func activate() -> void:
	if state == State.INACTIVE or state == State.COOLDOWN:
		_player = GameManager.player_ref
		if _player:
			_enter_waking()

# ─── Physics tick ─────────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	if GameManager.state != GameManager.GameState.PLAYING:
		return
	_player = GameManager.player_ref
	if not _player:
		return
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0

	# Sanity gate: recover above threshold → early retreat
	if GameManager.sanity_ref and GameManager.sanity_ref.sanity > activation_sanity:
		match state:
			State.SHADOW_LURK, State.STALK, State.CLOSE_WATCH, State.LUNGE:
				_enter_retreat()

	match state:
		State.WAKING:       _tick_waking(delta)
		State.SHADOW_LURK:  _tick_shadow_lurk(delta)
		State.STALK:        _tick_stalk(delta)
		State.CLOSE_WATCH:  _tick_close_watch(delta)
		State.LUNGE:        _tick_lunge(delta)
		State.RETREAT:      _tick_retreat(delta)
		State.COOLDOWN:     _tick_cooldown(delta)

# ─── WAKING ───────────────────────────────────────────────────────────────────

func _enter_waking() -> void:
	state = State.WAKING
	_state_timer  = 0.0
	_waking_alpha = 0.0
	var pos = _pick_lurk_position()
	global_position = pos
	visible = true
	set_physics_process(true)
	_set_shader_alpha(0.0)
	if _audio:
		_audio.play_distant_whistle()

func _tick_waking(delta: float) -> void:
	_state_timer += delta
	_waking_alpha = clamp(_state_timer / WAKING_DURATION, 0.0, 1.0)
	_set_shader_alpha(_waking_alpha * 0.70)
	if _state_timer >= WAKING_DURATION:
		_set_shader_alpha(0.70)
		_enter_shadow_lurk()

# ─── SHADOW_LURK ──────────────────────────────────────────────────────────────
# Monster stands far away. Does nothing but rotate to face the player
# and occasionally scratch or creak. Pure atmosphere. No approach.

func _enter_shadow_lurk() -> void:
	state           = State.SHADOW_LURK
	_state_timer    = 0.0
	_state_duration = randf_range(LURK_MIN, LURK_MAX)
	_scratch_timer  = 0.0
	_scratch_next   = randf_range(SCRATCH_INTERVAL_MIN, SCRATCH_INTERVAL_MAX)
	velocity        = Vector3.ZERO
	if _audio:
		_audio.start_distant_ambience()

func _tick_shadow_lurk(delta: float) -> void:
	_state_timer   += delta
	_scratch_timer += delta

	# Slowly rotate to face player — unsettling, deliberate
	var to_player = (_player.global_position - global_position)
	to_player.y = 0.0
	if to_player.length() > 0.5:
		var target_yaw = atan2(to_player.x, to_player.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, delta * 0.4)

	# If player somehow walks too close to the lurk spot, reposition
	var dist = global_position.distance_to(_player.global_position)
	if dist < LURK_DIST_MIN * 0.70:
		var new_pos = _pick_lurk_position()
		global_position = new_pos
		_state_timer *= 0.6   # reset most of the timer — player spooked it

	# Periodic scrapes/scratches — pure psychological audio
	if _scratch_timer >= _scratch_next:
		_scratch_timer = 0.0
		_scratch_next  = randf_range(SCRATCH_INTERVAL_MIN, SCRATCH_INTERVAL_MAX)
		if _audio:
			_audio.play_scratch()

	if _state_timer >= _state_duration:
		_enter_stalk()

# ─── STALK ────────────────────────────────────────────────────────────────────
# Monster closes in from 25 m → 14 m. Moves ONLY when player not looking.
# Footsteps audible — player can hear it approaching.

func _enter_stalk() -> void:
	state        = State.STALK
	_state_timer = 0.0
	if _audio:
		_audio.stop_distant_ambience()
		_audio.start_footsteps(0.62)

func _tick_stalk(delta: float) -> void:
	_state_timer += delta
	move_and_slide()
	var dist = global_position.distance_to(_player.global_position)

	# Freeze when player looks even softly in our direction
	if _is_looking(LOOK_DOT_SOFT):
		velocity.x = 0.0
		velocity.z = 0.0
		# Direct stare triggers retreat from STALK
		if _is_looking(LOOK_DOT_DIRECT):
			_enter_retreat()
		return

	if dist > STALK_TARGET_DIST:
		var dir = (_player.global_position - global_position).normalized()
		dir.y = 0.0
		velocity.x = dir.x * STALK_SPEED
		velocity.z = dir.z * STALK_SPEED
		if _audio:
			_audio.tick_footstep(delta)
	else:
		velocity.x = 0.0
		velocity.z = 0.0

	if dist <= STALK_TARGET_DIST + 1.0:
		_enter_close_watch()

	if _state_timer >= STALK_TIMEOUT:
		_enter_retreat()  # Player ran — monster retreats, resets pacing

# ─── CLOSE_WATCH ──────────────────────────────────────────────────────────────
# Monster hovers at 9 m for 45–120 s. Heavy breathing. Almost visible.
# Creeps slightly while player isn't looking.
# Lunge only triggers when: sanity < 40 AND player looked away ≥ 8 s in a row.

func _enter_close_watch() -> void:
	state             = State.CLOSE_WATCH
	_state_timer      = 0.0
	_lunge_look_timer = 0.0
	_state_duration   = randf_range(CLOSE_WATCH_MIN, CLOSE_WATCH_MAX)
	velocity          = Vector3.ZERO
	if _audio:
		_audio.stop_footsteps()
		_audio.start_breathing()

func _tick_close_watch(delta: float) -> void:
	_state_timer += delta
	var dist    = global_position.distance_to(_player.global_position)
	var looking = _is_looking(LOOK_DOT_DIRECT)

	if looking:
		# Player sees us — freeze, reset lunge accumulator
		_lunge_look_timer = 0.0
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		# Long direct stare → monster retreats (it doesn't like being watched)
		if _state_timer >= _state_duration:
			_enter_retreat()
		return

	# Player is NOT looking — accumulate look-away time
	_lunge_look_timer += delta

	# Creep slightly to maintain 9 m watch distance
	var dir = (_player.global_position - global_position).normalized()
	dir.y = 0.0
	if dist > CLOSE_WATCH_DIST + 1.5:
		velocity.x = dir.x * CLOSE_CREEP_SPEED
		velocity.z = dir.z * CLOSE_CREEP_SPEED
	elif dist < CLOSE_WATCH_DIST - 2.0:
		velocity.x = -dir.x * CLOSE_CREEP_SPEED
		velocity.z = -dir.z * CLOSE_CREEP_SPEED
	else:
		velocity.x = 0.0
		velocity.z = 0.0
	move_and_slide()

	# Passive sanity drain from proximity
	if GameManager.sanity_ref:
		GameManager.sanity_ref.drain(2.2 * delta)

	# Kill if somehow walked into us
	if dist < KILL_DISTANCE:
		if _player.has_method("die"):
			_player.die()
		return

	# LUNGE condition: only after sustained look-away AND low sanity
	if _lunge_look_timer >= LUNGE_LOOK_AWAY_TRIGGER:
		var sanity_val = GameManager.sanity_ref.sanity if GameManager.sanity_ref else 100.0
		if sanity_val <= lunge_sanity_threshold:
			_enter_lunge()
			return
		else:
			# High sanity — monster hesitates, resets look-away timer
			_lunge_look_timer = 0.0

	# Natural end of close-watch → retreat and reset pacing
	if _state_timer >= _state_duration:
		_enter_retreat()

# ─── LUNGE ────────────────────────────────────────────────────────────────────

func _enter_lunge() -> void:
	state = State.LUNGE
	_state_timer = 0.0
	if _audio:
		_audio.stop_breathing()
		_audio.play_lunge_roar()
	JumpscareSystem.trigger(JumpscareSystem.Intensity.HARD)
	AudioManager.play_ghost_sound("stalker_roar")

func _tick_lunge(delta: float) -> void:
	_state_timer += delta
	var dist = global_position.distance_to(_player.global_position)
	if dist < KILL_DISTANCE:
		if _player.has_method("die"):
			_player.die()
		return
	# Face and charge
	var dir = (_player.global_position - global_position).normalized()
	dir.y = 0.0
	rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), delta * 14.0)
	velocity.x = dir.x * LUNGE_SPEED
	velocity.z = dir.z * LUNGE_SPEED
	move_and_slide()
	if _state_timer > 7.0:
		_enter_retreat()

# ─── RETREAT ──────────────────────────────────────────────────────────────────

func _enter_retreat() -> void:
	state            = State.RETREAT
	_state_timer     = 0.0
	_retreat_target  = _pick_lurk_position()
	if _audio:
		_audio.stop_breathing()
		_audio.stop_footsteps()
		_audio.stop_distant_ambience()
		_audio.play_retreat()

func _tick_retreat(delta: float) -> void:
	_state_timer += delta
	var dist = global_position.distance_to(_retreat_target)
	if dist > 2.0:
		var dir = (_retreat_target - global_position).normalized()
		dir.y = 0.0
		velocity.x = dir.x * RETREAT_SPEED
		velocity.z = dir.z * RETREAT_SPEED
		move_and_slide()
	else:
		_enter_cooldown()
	if _state_timer >= RETREAT_TIMEOUT:
		_enter_cooldown()

# ─── COOLDOWN ─────────────────────────────────────────────────────────────────
# Mandatory 2–5 minute silent rest. No sounds, invisible.
# Reactivation only when conditions are right AND timer expires.

func _enter_cooldown() -> void:
	state          = State.COOLDOWN
	_cooldown_left = randf_range(COOLDOWN_MIN, COOLDOWN_MAX)
	visible        = false
	velocity       = Vector3.ZERO
	if _audio:
		_audio.stop_all()

func _tick_cooldown(delta: float) -> void:
	_cooldown_left -= delta
	if _cooldown_left <= 0.0:
		var sanity_val = GameManager.sanity_ref.sanity if GameManager.sanity_ref else 100.0
		if sanity_val <= activation_sanity and GameManager.player_ref:
			_player = GameManager.player_ref
			_enter_waking()
		else:
			_cooldown_left = 30.0  # Conditions not met — wait 30 s and re-check

# ─── Helpers ──────────────────────────────────────────────────────────────────

func _pick_lurk_position() -> Vector3:
	if not _player:
		return global_position
	var look = _player.get_look_direction() if _player.has_method("get_look_direction") else -Vector3.FORWARD
	for _attempt in 24:
		var angle = randf_range(0.0, TAU)
		var dist  = randf_range(LURK_DIST_MIN, LURK_DIST_MAX)
		var pos   = _player.global_position + Vector3(sin(angle) * dist, 0.0, cos(angle) * dist)
		# Strongly prefer positions behind or to the sides of the player
		var to_pos = (pos - _player.global_position).normalized()
		if look.dot(to_pos) < 0.20:
			return pos
	# Fallback: anything in range
	var a = randf_range(0.0, TAU)
	return _player.global_position + Vector3(sin(a), 0.0, cos(a)) * LURK_DIST_MIN

func _is_looking(dot_threshold: float) -> bool:
	if not _player or not _player.has_method("get_look_direction"):
		return false
	var to_self = (global_position - _player.global_position)
	to_self.y = 0.0
	if to_self.length() < 0.1:
		return true
	return _player.get_look_direction().dot(to_self.normalized()) > dot_threshold

func _set_shader_alpha(a: float) -> void:
	if _mesh and _mesh.material_override is ShaderMaterial:
		var mat = _mesh.material_override as ShaderMaterial
		var col = mat.get_shader_parameter("ghost_color") as Color
		col.a = a
		mat.set_shader_parameter("ghost_color", col)
