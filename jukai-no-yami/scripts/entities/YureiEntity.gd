extends CharacterBody3D

enum State { DORMANT, IDLE_DISTANT, REVEALED, CRAWLING, BANISHED, GONE }

const CRAWL_SPEED      = 1.5
const DETECT_RANGE     = 24.0
const KILL_RANGE       = 1.1
const LOOK_BANISH_TIME = 0.6
const LOOK_THRESHOLD   = 0.91
const REAPPEAR_DELAY   = 20.0

@export var ghost_id: int = 0

var state: State = State.DORMANT
var _look_t: float = 0.0
var _gone_t: float = 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _origin: Vector3
var _player: CharacterBody3D = null
var _revealed_once: bool = false
var anim: AnimationPlayer = null
var audio: AudioStreamPlayer3D = null

func _ready() -> void:
	add_to_group("ghost")
	add_to_group("yurei")

	var cap = CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.6
	var col = CollisionShape3D.new()
	col.shape = cap
	col.position = Vector3(0, 0.8, 0)
	add_child(col)

	audio = AudioStreamPlayer3D.new()
	audio.bus = "Ghost" if AudioServer.get_bus_index("Ghost") >= 0 else "Master"
	audio.max_distance = 20.0
	add_child(audio)

	_origin = global_position
	_build_ghost_mesh()
	visible = false
	set_physics_process(false)

func activate() -> void:
	if state != State.DORMANT:
		return
	state = State.IDLE_DISTANT
	visible = true
	set_physics_process(true)
	AudioManager.play_ghost_sound("hair_drag")

func spawn_behind_player() -> void:
	if not GameManager.player_ref:
		return
	var p = GameManager.player_ref
	var behind = p.global_position - p.get_look_direction() * randf_range(0.8, 1.5)
	behind.y = p.global_position.y
	global_position = behind
	state = State.IDLE_DISTANT
	visible = true
	set_physics_process(true)
	AudioManager.play_ghost_sound("hair_drag")
	if GameManager.sanity_ref:
		GameManager.sanity_ref.drain(8.0)

func force_reveal_close() -> void:
	if not GameManager.player_ref:
		return
	var p = GameManager.player_ref
	var close = p.global_position + p.get_look_direction() * 1.2
	close.y = p.global_position.y
	global_position = close
	state = State.REVEALED
	visible = true
	set_physics_process(true)
	_do_jumpscare(JumpscareSystem.Intensity.MAX)

func _physics_process(delta: float) -> void:
	if GameManager.state != GameManager.GameState.PLAYING:
		return
	_player = GameManager.player_ref
	if not _player:
		return
	if not is_on_floor():
		velocity.y -= _gravity * delta
	match state:
		State.IDLE_DISTANT: _handle_idle(delta)
		State.REVEALED:     _handle_revealed(delta)
		State.CRAWLING:     _handle_crawl(delta)
		State.BANISHED:     _handle_banished(delta)
		State.GONE:         _handle_gone(delta)

func _handle_idle(_delta: float) -> void:
	var dist = global_position.distance_to(_player.global_position)
	if dist > DETECT_RANGE:
		_vanish()
		return
	var fl = _player.get_node_or_null("Camera3D/HandPivot/Flashlight")
	if fl and fl.check_beam_entry(ghost_id, global_position):
		_on_beam_reveal()
		return
	if dist < 6.0:
		state = State.CRAWLING

func _on_beam_reveal() -> void:
	state = State.REVEALED
	if not _revealed_once:
		_revealed_once = true
		_do_jumpscare(JumpscareSystem.Intensity.HARD)
	else:
		_do_jumpscare(JumpscareSystem.Intensity.MEDIUM)

func _handle_revealed(delta: float) -> void:
	var looking = _is_looked_at()
	if looking:
		_look_t += delta
		if GameManager.sanity_ref:
			GameManager.sanity_ref.set_ghost_visible(true)
		if _look_t >= LOOK_BANISH_TIME:
			_banish()
			return
	else:
		_look_t = max(0.0, _look_t - delta * 2.0)
		if GameManager.sanity_ref:
			GameManager.sanity_ref.set_ghost_visible(false)
	if not _is_in_flashlight_beam():
		state = State.CRAWLING
	_check_kill()

func _handle_crawl(delta: float) -> void:
	var fl = _player.get_node_or_null("Camera3D/HandPivot/Flashlight")
	if fl and fl.check_beam_entry(ghost_id, global_position):
		_on_beam_reveal()
		return
	if _is_looked_at():
		_look_t += delta
		if GameManager.sanity_ref:
			GameManager.sanity_ref.set_ghost_visible(true)
		if _look_t >= LOOK_BANISH_TIME:
			_banish()
			return
	else:
		_look_t = max(0.0, _look_t - delta * 1.5)
		if GameManager.sanity_ref:
			GameManager.sanity_ref.set_ghost_visible(false)
	var dir = (_player.global_position - global_position)
	dir.y = 0.0
	if dir.length() > 0.1:
		dir = dir.normalized()
		velocity.x = dir.x * CRAWL_SPEED
		velocity.z = dir.z * CRAWL_SPEED
		look_at(Vector3(_player.global_position.x, global_position.y, _player.global_position.z), Vector3.UP)
	move_and_slide()
	_check_kill()

func _handle_banished(delta: float) -> void:
	var away = (global_position - _player.global_position).normalized()
	velocity = velocity.move_toward(away * 3.0, delta * 5.0)
	move_and_slide()
	_look_t += delta
	if _look_t >= 1.5:
		_vanish()

func _handle_gone(delta: float) -> void:
	_gone_t += delta
	if _gone_t >= REAPPEAR_DELAY:
		_reset()

func _is_looked_at() -> bool:
	if not _player:
		return false
	return _player.get_look_direction().dot((global_position - _player.global_position).normalized()) > LOOK_THRESHOLD

func _is_in_flashlight_beam() -> bool:
	return _player.is_ghost_in_flashlight(global_position) if _player else false

func _check_kill() -> void:
	if global_position.distance_to(_player.global_position) <= KILL_RANGE:
		_do_jumpscare(JumpscareSystem.Intensity.MAX)
		if _player.has_method("die"):
			_player.die()

func _do_jumpscare(intensity: int) -> void:
	JumpscareSystem.trigger_flashlight_reveal("yurei", intensity)
	AudioManager.play_ghost_sound("yurei_shriek")

func _banish() -> void:
	state = State.BANISHED
	_look_t = 0.0
	if GameManager.sanity_ref:
		GameManager.sanity_ref.set_ghost_visible(false)

func _vanish() -> void:
	state = State.GONE
	visible = false
	_gone_t = 0.0
	set_physics_process(false)
	if GameManager.sanity_ref:
		GameManager.sanity_ref.set_ghost_visible(false)

func _reset() -> void:
	global_position = _origin
	state = State.DORMANT
	visible = false
	_look_t = 0.0

func _build_ghost_mesh() -> void:
	var body = Node3D.new()
	body.name = "GhostBody"
	add_child(body)

	# Body
	var bm = CapsuleMesh.new()
	bm.radius = 0.34; bm.height = 1.45
	var bmi = MeshInstance3D.new()
	bmi.mesh = bm; bmi.position = Vector3(0, 0.78, 0)
	bmi.material_override = _ghost_mat(Color(0.88, 0.90, 0.95), 0.80)
	body.add_child(bmi)

	# Head
	var hm = SphereMesh.new()
	hm.radius = 0.28; hm.height = 0.56
	var hmi = MeshInstance3D.new()
	hmi.mesh = hm; hmi.position = Vector3(0, 1.60, 0)
	hmi.material_override = _ghost_mat(Color(0.90, 0.92, 0.96), 0.88)
	body.add_child(hmi)

	# Hair (long dark strands, hangs from back of head)
	var hair_m = CapsuleMesh.new()
	hair_m.radius = 0.20; hair_m.height = 0.92
	var hair_mi = MeshInstance3D.new()
	hair_mi.mesh = hair_m; hair_mi.position = Vector3(0, 1.32, -0.12)
	var hair_mat = StandardMaterial3D.new()
	hair_mat.albedo_color = Color(0.04, 0.03, 0.03, 0.95)
	hair_mat.roughness = 0.95; hair_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hair_mi.material_override = hair_mat
	body.add_child(hair_mi)

	# Eyes (hollow black sockets)
	for side in [-1, 1]:
		var em = SphereMesh.new()
		em.radius = 0.050; em.height = 0.10
		var emi = MeshInstance3D.new()
		emi.mesh = em; emi.position = Vector3(side * 0.092, 1.65, 0.24)
		var eye_mat = StandardMaterial3D.new()
		eye_mat.albedo_color = Color(0.01, 0.01, 0.01)
		eye_mat.emission_enabled = true
		eye_mat.emission = Color(0.0, 0.0, 0.0)
		eye_mat.roughness = 0.1
		emi.material_override = eye_mat
		body.add_child(emi)

	# Mouth (dark open slit)
	var mm = BoxMesh.new()
	mm.size = Vector3(0.13, 0.05, 0.02)
	var mmi = MeshInstance3D.new()
	mmi.mesh = mm; mmi.position = Vector3(0, 1.55, 0.26)
	var mouth_mat = StandardMaterial3D.new()
	mouth_mat.albedo_color = Color(0.03, 0.02, 0.02)
	mouth_mat.roughness = 0.9
	mmi.material_override = mouth_mat
	body.add_child(mmi)

func _ghost_mat(col: Color, alpha: float) -> ShaderMaterial:
	var m = ShaderMaterial.new()
	m.shader = load("res://shaders/ghost_material.gdshader")
	col.a = alpha
	m.set_shader_parameter("ghost_color", col)
	m.set_shader_parameter("edge_glow", 1.6)
	m.set_shader_parameter("distort_speed", 0.7)
	m.set_shader_parameter("distort_amount", 0.016)
	m.set_shader_parameter("flicker_speed", 3.8)
	return m
