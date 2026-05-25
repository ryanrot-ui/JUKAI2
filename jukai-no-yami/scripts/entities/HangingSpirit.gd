extends Node3D

enum State { HIDDEN, TRIGGERED, DESCENDING, GRABBING }

const DESCEND_SPEED_NORMAL = 0.28
const DESCEND_SPEED_FAST   = 2.8
const TRIGGER_DIST         = 10.0
const GRAB_DIST            = 1.3
const LINGER_TIME          = 3.5

@export var hang_height: float = 4.5

var state: State          = State.HIDDEN
var _ground_y: float      = 0.0
var _linger_t: float      = 0.0
var _creak_t: float       = 0.0
var _bob_t: float         = 0.0
var _descent_speed: float = DESCEND_SPEED_NORMAL
var _triggered: bool      = false
var _player: CharacterBody3D = null

func _ready() -> void:
	add_to_group("ghost")
	add_to_group("hanging")
	_ground_y = global_position.y
	global_position.y += hang_height
	visible = false
	_build_ghost_mesh()

func _process(delta: float) -> void:
	if GameManager.state != GameManager.GameState.PLAYING:
		return
	_player = GameManager.player_ref
	if not _player:
		return
	match state:
		State.HIDDEN:     _check_trigger()
		State.TRIGGERED:  _tick_triggered(delta)
		State.DESCENDING: _tick_descend(delta)

func _check_trigger() -> void:
	if _triggered:
		return
	if global_position.distance_to(_player.global_position) <= TRIGGER_DIST:
		_trigger_normal()

func _trigger_normal() -> void:
	_triggered = true
	state = State.TRIGGERED
	visible = true
	AudioManager.play_ghost_sound("whisper_jp_1")
	JumpscareSystem.trigger(JumpscareSystem.Intensity.MEDIUM)
	if GameManager.sanity_ref:
		GameManager.sanity_ref.drain(12.0)

func force_fast_drop() -> void:
	_triggered = true
	state = State.DESCENDING
	visible = true
	_descent_speed = DESCEND_SPEED_FAST
	AudioManager.play_ghost_sound("hair_drag")

# CollectibleNote dispatches ghost.activate() by name — provide an entry point
# so this dispatch stays safe if a note ever sets trigger_ghost_on_pickup = true.
func activate() -> void:
	force_fast_drop()

func _tick_triggered(delta: float) -> void:
	var look_pos = Vector3(_player.global_position.x, global_position.y, _player.global_position.z)
	look_at(look_pos, Vector3.UP)

	# Gentle oscillation — the body sways slightly while hanging
	_bob_t += delta
	var ghost_body = get_node_or_null("GhostBody")
	if ghost_body:
		ghost_body.rotation.z = sin(_bob_t * 0.8) * 0.04

	var dist = global_position.distance_to(_player.global_position)
	if dist <= TRIGGER_DIST * 1.3:
		_linger_t += delta
		# Periodic rope creak during linger
		_creak_t += delta
		if _creak_t >= randf_range(2.2, 4.8):
			_creak_t = 0.0
			AudioManager.play_sfx("rope_creak")
		if _linger_t >= LINGER_TIME:
			state = State.DESCENDING
	else:
		_linger_t = max(0.0, _linger_t - delta * 2.0)

func _tick_descend(delta: float) -> void:
	global_position.y -= _descent_speed * delta
	var dist = global_position.distance_to(_player.global_position)
	if dist <= GRAB_DIST or global_position.y <= _ground_y + 0.1:
		_grab()

func _grab() -> void:
	if state == State.GRABBING:
		return
	state = State.GRABBING
	JumpscareSystem.trigger(JumpscareSystem.Intensity.MAX)
	AudioManager.play_ghost_sound("yurei_shriek")
	if global_position.distance_to(_player.global_position) <= GRAB_DIST:
		if _player.has_method("die"):
			_player.die()

func _build_ghost_mesh() -> void:
	var body = Node3D.new()
	body.name = "GhostBody"
	add_child(body)

	# Rope — thin cord running above the head
	var rope_m = CylinderMesh.new()
	rope_m.height = 1.4; rope_m.top_radius = 0.016; rope_m.bottom_radius = 0.018
	var rope_mi = MeshInstance3D.new()
	rope_mi.mesh = rope_m; rope_mi.position = Vector3(0, 2.55, 0)
	var rope_mat = StandardMaterial3D.new()
	rope_mat.albedo_color = Color(0.32, 0.26, 0.18)
	rope_mat.roughness = 1.0; rope_mat.metallic = 0.0
	rope_mi.material_override = rope_mat
	body.add_child(rope_mi)

	# Body — pale translucent
	var bm = CapsuleMesh.new()
	bm.radius = 0.29; bm.height = 1.28
	var bmi = MeshInstance3D.new()
	bmi.mesh = bm; bmi.position = Vector3(0, 1.44, 0)
	bmi.material_override = _hang_mat(Color(0.82, 0.85, 0.92), 0.80)
	body.add_child(bmi)

	# Head — slightly tilted (hanged posture)
	var hm = SphereMesh.new()
	hm.radius = 0.24; hm.height = 0.48
	var hmi = MeshInstance3D.new()
	hmi.mesh = hm; hmi.position = Vector3(0.07, 2.15, 0)
	hmi.rotation_degrees.z = -14.0
	hmi.material_override = _hang_mat(Color(0.85, 0.88, 0.94), 0.84)
	body.add_child(hmi)

	# Hair — dark, cascading down behind
	var hair_m = CapsuleMesh.new()
	hair_m.radius = 0.17; hair_m.height = 0.72
	var hair_mi = MeshInstance3D.new()
	hair_mi.mesh = hair_m; hair_mi.position = Vector3(0, 1.92, -0.09)
	var hair_mat = StandardMaterial3D.new()
	hair_mat.albedo_color = Color(0.05, 0.04, 0.04, 0.94)
	hair_mat.roughness = 0.95; hair_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hair_mi.material_override = hair_mat
	body.add_child(hair_mi)

	# Arms — hanging limp at sides, slightly splayed outward
	for side in [-1, 1]:
		var arm_m = CapsuleMesh.new()
		arm_m.radius = 0.068; arm_m.height = 0.52
		var arm_mi = MeshInstance3D.new()
		arm_mi.mesh = arm_m
		arm_mi.position = Vector3(side * 0.44, 1.60, 0)
		arm_mi.rotation_degrees.z = side * 25.0
		arm_mi.material_override = _hang_mat(Color(0.82, 0.85, 0.92), 0.74)
		body.add_child(arm_mi)

	# Eyes — hollow dark sockets, no glow (she's dead and still)
	for side in [-1, 1]:
		var em = SphereMesh.new()
		em.radius = 0.044; em.height = 0.088
		var emi = MeshInstance3D.new()
		emi.mesh = em; emi.position = Vector3(side * 0.082 + 0.06, 2.19, 0.21)
		var eye_mat = StandardMaterial3D.new()
		eye_mat.albedo_color = Color(0.01, 0.01, 0.015)
		eye_mat.roughness = 0.1; eye_mat.metallic_specular = 0.0
		emi.material_override = eye_mat
		body.add_child(emi)

	# Mouth — slightly open
	var mm = BoxMesh.new()
	mm.size = Vector3(0.09, 0.038, 0.02)
	var mmi = MeshInstance3D.new()
	mmi.mesh = mm; mmi.position = Vector3(0.04, 2.10, 0.23)
	var mouth_mat = StandardMaterial3D.new()
	mouth_mat.albedo_color = Color(0.04, 0.02, 0.02)
	mouth_mat.roughness = 0.9
	mmi.material_override = mouth_mat
	body.add_child(mmi)

func _hang_mat(col: Color, alpha: float) -> ShaderMaterial:
	var m = ShaderMaterial.new()
	m.shader = load("res://shaders/ghost_material.gdshader")
	col.a = alpha
	m.set_shader_parameter("ghost_color", col)
	m.set_shader_parameter("edge_glow", 1.1)
	m.set_shader_parameter("distort_speed", 0.2)
	m.set_shader_parameter("distort_amount", 0.006)
	m.set_shader_parameter("flicker_speed", 1.4)
	return m
