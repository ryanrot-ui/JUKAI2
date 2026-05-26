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

	# ── Proper humanoid yurei — head/neck/torso/arms/legs as separate
	# articulated pieces with sphere joints, matching the same anatomy
	# the HangingCorpse uses (so when she "stands up" the silhouette
	# transition reads). All visible parts share the ghost shader so
	# the whole figure glows pale-translucent.
	var body_root := Node3D.new()
	body_root.name = "YureiForm"
	add_child(body_root)
	_mesh = MeshInstance3D.new()  # kept for _set_shader_alpha compatibility
	body_root.add_child(_mesh)

	# Shared pale ghost-shader material — referenced everywhere so
	# _set_shader_alpha can fade the whole figure during WAKING.
	var pale_mat := ShaderMaterial.new()
	pale_mat.shader = load("res://shaders/ghost_material.gdshader")
	pale_mat.set_shader_parameter("ghost_color",    Color(0.86, 0.90, 0.96, 0.82))
	pale_mat.set_shader_parameter("edge_glow",      1.6)
	pale_mat.set_shader_parameter("distort_speed",  0.30)
	pale_mat.set_shader_parameter("distort_amount", 0.010)
	pale_mat.set_shader_parameter("flicker_speed",  1.8)
	pale_mat.set_shader_parameter("body_glow",      0.55)
	pale_mat.set_shader_parameter("rim_bleed",      1.1)
	_mesh.material_override = pale_mat
	_mesh.mesh = SphereMesh.new()  # tiny invisible anchor; alpha-bound

	var cloth_mat := ShaderMaterial.new()
	cloth_mat.shader = load("res://shaders/ghost_material.gdshader")
	cloth_mat.set_shader_parameter("ghost_color",    Color(0.78, 0.82, 0.92, 0.74))
	cloth_mat.set_shader_parameter("edge_glow",      1.5)
	cloth_mat.set_shader_parameter("distort_speed",  0.40)
	cloth_mat.set_shader_parameter("distort_amount", 0.014)
	cloth_mat.set_shader_parameter("flicker_speed",  1.4)
	cloth_mat.set_shader_parameter("body_glow",      0.50)
	cloth_mat.set_shader_parameter("rim_bleed",      1.2)

	var hair_mat := StandardMaterial3D.new()
	hair_mat.albedo_color = Color(0.04, 0.03, 0.04, 0.96)
	hair_mat.roughness = 0.96
	hair_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hair_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var dark_mat := StandardMaterial3D.new()
	dark_mat.albedo_color = Color(0.01, 0.01, 0.015)
	dark_mat.roughness = 0.10

	# Anatomical landmarks (origin at the feet; total height ~1.70 m)
	var foot_y       := 0.08
	var ankle_y      := 0.10
	var knee_y       := 0.46
	var hip_y        := 0.90
	var waist_y      := 1.08
	var chest_y      := 1.36
	var shoulder_y   := 1.50
	var neck_y       := 1.56
	var head_y       := 1.72

	# Head — oval, jaw, hair cap
	var head := _make_sphere_st(body_root, 0.115, Vector3(0, head_y, 0), pale_mat)
	head.scale = Vector3(0.95, 1.05, 1.00)
	_make_sphere_st(body_root, 0.058, Vector3(0, head_y - 0.075, 0.060), pale_mat)
	_make_sphere_st(body_root, 0.128, Vector3(0, head_y + 0.020, -0.015), hair_mat)

	# Long hair down the back
	_make_capsule_st(body_root, 0.130, 0.85, Vector3(0, head_y - 0.50, -0.12), hair_mat)
	_make_capsule_st(body_root, 0.100, 0.55, Vector3(0, head_y - 1.10, -0.08), hair_mat)

	# Hair front curtain
	var hair_front := MeshInstance3D.new()
	var hfm := BoxMesh.new()
	hfm.size = Vector3(0.20, 0.30, 0.018)
	hair_front.mesh = hfm
	hair_front.position = Vector3(0, head_y - 0.02, 0.110)
	hair_front.material_override = hair_mat
	body_root.add_child(hair_front)

	# Eye sockets
	for side: float in [-1.0, 1.0]:
		_make_sphere_st(body_root, 0.036, Vector3(side * 0.058, head_y + 0.015, 0.105), dark_mat)

	# Slack open mouth
	var mouth := MeshInstance3D.new()
	var mm := BoxMesh.new()
	mm.size = Vector3(0.055, 0.038, 0.018)
	mouth.mesh = mm
	mouth.position = Vector3(0, head_y - 0.08, 0.115)
	mouth.material_override = dark_mat
	body_root.add_child(mouth)

	# Neck + throat sphere
	_make_capsule_st(body_root, 0.052, 0.14, Vector3(0, neck_y, 0), pale_mat)
	_make_sphere_st(body_root, 0.075, Vector3(0, shoulder_y - 0.02, 0.0), pale_mat)

	# Torso — chest + waist + hips
	_make_capsule_st(body_root, 0.155, 0.30, Vector3(0, chest_y, 0), cloth_mat)
	_make_capsule_st(body_root, 0.130, 0.22, Vector3(0, waist_y - 0.04, 0), cloth_mat)
	_make_capsule_st(body_root, 0.170, 0.18, Vector3(0, hip_y + 0.02, 0), cloth_mat)

	# Shoulders
	for side: float in [-1.0, 1.0]:
		_make_sphere_st(body_root, 0.072, Vector3(side * 0.165, shoulder_y - 0.04, 0.0), cloth_mat)

	# Arms
	for side: float in [-1.0, 1.0]:
		var sh_x := side * 0.180
		_make_capsule_st(body_root, 0.055, 0.28, Vector3(sh_x, 1.22, 0.0), cloth_mat)
		_make_sphere_st(body_root, 0.055, Vector3(sh_x, 1.06, 0.005), pale_mat)
		_make_capsule_st(body_root, 0.045, 0.26, Vector3(sh_x + side * 0.005, 0.90, 0.012), pale_mat)
		_make_sphere_st(body_root, 0.042, Vector3(sh_x + side * 0.005, 0.76, 0.020), pale_mat)
		var hand := MeshInstance3D.new()
		var hm := SphereMesh.new()
		hm.radius = 0.050
		hm.height = 0.100
		hand.mesh = hm
		hand.scale = Vector3(0.78, 1.20, 0.95)
		hand.position = Vector3(sh_x + side * 0.007, 0.68, 0.025)
		hand.material_override = pale_mat
		body_root.add_child(hand)

	# Legs — thigh, knee, shin, ankle, foot
	for side: float in [-1.0, 1.0]:
		var lg_x := side * 0.080
		_make_capsule_st(body_root, 0.100, 0.34, Vector3(lg_x, hip_y - 0.22, 0.0), cloth_mat)
		_make_sphere_st(body_root, 0.075, Vector3(lg_x, knee_y - 0.02, 0.005), cloth_mat)
		_make_capsule_st(body_root, 0.058, 0.34, Vector3(lg_x, knee_y - 0.20, 0.010), pale_mat)
		_make_sphere_st(body_root, 0.048, Vector3(lg_x, ankle_y + 0.04, 0.015), pale_mat)
		var foot := MeshInstance3D.new()
		var fm := SphereMesh.new()
		fm.radius = 0.058
		fm.height = 0.116
		foot.mesh = fm
		foot.scale = Vector3(1.0, 0.55, 1.60)
		foot.position = Vector3(lg_x, foot_y, 0.055)
		foot.material_override = pale_mat
		body_root.add_child(foot)


# Anatomy helpers — '_st' suffix because they're "stalker" versions that
# parent into a body_root and disable shadow casting (the figure should
# read as luminous, not throw shadows like a solid actor).
func _make_capsule_st(parent: Node3D, radius: float, height: float,
		pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = radius
	cm.height = height
	mi.mesh = cm
	mi.position = pos
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

func _make_sphere_st(parent: Node3D, radius: float, pos: Vector3,
		mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	mi.mesh = sm
	mi.position = pos
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

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
