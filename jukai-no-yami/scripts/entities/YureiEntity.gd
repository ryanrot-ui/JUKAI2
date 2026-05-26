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

	# Ghosts are not solid — the player should pass straight through them
	# (collision was creating "stand on the ghost's head" platforms). They
	# still detect the ground for gravity by keeping collision_mask=1.
	collision_layer = 0

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
	# Proper humanoid anatomy — head, neck, chest/waist/hips, shoulders,
	# arms with elbows + wrists + hands, thighs + knees + shins + feet.
	# Same skeleton as the HangingCorpse so the "this is the same person,
	# now risen" reading lands. Materials use the ghost shader so the
	# whole figure glows pale-translucent rather than reading as skin.
	var body := Node3D.new()
	body.name = "GhostBody"
	add_child(body)

	# Shared ghost material for skin and kimono — pale luminous white.
	var ghost := _ghost_mat(Color(0.86, 0.90, 0.96), 0.82)
	# Slightly cooler version for the kimono cloth so it reads as fabric.
	var ghost_cloth := _ghost_mat(Color(0.78, 0.80, 0.90), 0.74)

	var hair_mat := StandardMaterial3D.new()
	hair_mat.albedo_color = Color(0.04, 0.03, 0.04, 0.96)
	hair_mat.roughness = 0.95
	hair_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hair_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var dark_mat := StandardMaterial3D.new()
	dark_mat.albedo_color = Color(0.02, 0.02, 0.02)
	dark_mat.roughness = 0.9

	# Anatomical Y-coordinates (yurei stands upright, not stretched).
	# Origin at the feet; total height ~1.70 m.
	var foot_y       := 0.08
	var ankle_y      := 0.10
	var knee_y       := 0.46
	var hip_y        := 0.90
	var waist_y      := 1.08
	var chest_y      := 1.36
	var shoulder_y   := 1.50
	var neck_y       := 1.56
	var head_y       := 1.72

	# Head — slightly oval (squashed along X) so it reads as a face.
	var head := _make_sphere(0.115, Vector3(0, head_y, 0), ghost, Vector3.ZERO)
	head.scale = Vector3(0.95, 1.05, 1.00)
	body.add_child(head)
	# Jaw / chin
	body.add_child(_make_sphere(0.058, Vector3(0, head_y - 0.075, 0.060), ghost, Vector3.ZERO))

	# Hair cap (back of head)
	body.add_child(_make_sphere(0.128, Vector3(0, head_y + 0.020, -0.015), hair_mat, Vector3.ZERO))

	# Long flowing hair down the back — two stacked capsules
	body.add_child(_make_capsule(0.130, 0.85, Vector3(0, head_y - 0.50, -0.12), hair_mat, Vector3.ZERO))
	body.add_child(_make_capsule(0.100, 0.55, Vector3(0, head_y - 1.10, -0.08), hair_mat, Vector3.ZERO))

	# Hair front curtain — partially covers the face (classic yurei look)
	var hair_front := MeshInstance3D.new()
	var hfm := BoxMesh.new()
	hfm.size = Vector3(0.20, 0.30, 0.018)
	hair_front.mesh = hfm
	hair_front.position = Vector3(0, head_y - 0.02, 0.110)
	hair_front.material_override = hair_mat
	body.add_child(hair_front)

	# Eye sockets — hollow black holes barely visible under the hair
	for side: float in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var em := SphereMesh.new()
		em.radius = 0.038
		em.height = 0.076
		eye.mesh = em
		eye.position = Vector3(side * 0.060, head_y + 0.015, 0.105)
		eye.material_override = dark_mat
		body.add_child(eye)

	# Slack open mouth
	var mouth := MeshInstance3D.new()
	var mm := BoxMesh.new()
	mm.size = Vector3(0.055, 0.038, 0.018)
	mouth.mesh = mm
	mouth.position = Vector3(0, head_y - 0.08, 0.115)
	mouth.material_override = dark_mat
	body.add_child(mouth)

	# Neck + throat sphere
	body.add_child(_make_capsule(0.052, 0.14, Vector3(0, neck_y, 0), ghost, Vector3.ZERO))
	body.add_child(_make_sphere(0.075, Vector3(0, shoulder_y - 0.02, 0.0), ghost, Vector3.ZERO))

	# Torso — chest, waist, hips (three tapered capsules)
	body.add_child(_make_capsule(0.155, 0.30, Vector3(0, chest_y, 0), ghost_cloth, Vector3.ZERO))
	body.add_child(_make_capsule(0.130, 0.22, Vector3(0, waist_y - 0.04, 0), ghost_cloth, Vector3.ZERO))
	body.add_child(_make_capsule(0.170, 0.18, Vector3(0, hip_y + 0.02, 0), ghost_cloth, Vector3.ZERO))

	# Shoulder spheres
	for side: float in [-1.0, 1.0]:
		body.add_child(_make_sphere(0.072, Vector3(side * 0.165, shoulder_y - 0.04, 0.0), ghost_cloth, Vector3.ZERO))

	# Arms — upper arm, elbow, forearm, wrist, hand
	for side: float in [-1.0, 1.0]:
		var sh_x := side * 0.180
		body.add_child(_make_capsule(0.055, 0.28, Vector3(sh_x, 1.22, 0.0), ghost_cloth, Vector3.ZERO))
		body.add_child(_make_sphere(0.055, Vector3(sh_x, 1.06, 0.005), ghost, Vector3.ZERO))
		body.add_child(_make_capsule(0.045, 0.26, Vector3(sh_x + side * 0.005, 0.90, 0.012), ghost, Vector3.ZERO))
		body.add_child(_make_sphere(0.042, Vector3(sh_x + side * 0.005, 0.76, 0.020), ghost, Vector3.ZERO))
		# Hand — flattened sphere, slightly curled
		var hand := MeshInstance3D.new()
		var hm := SphereMesh.new()
		hm.radius = 0.050
		hm.height = 0.100
		hand.mesh = hm
		hand.scale = Vector3(0.78, 1.20, 0.95)
		hand.position = Vector3(sh_x + side * 0.007, 0.68, 0.025)
		hand.material_override = ghost
		body.add_child(hand)

	# Legs — kimono skirt over thigh, bare ghostly shin, foot.
	# Traditional yurei imagery shows feet trailing into mist — here we
	# show real feet for definition, but offset them slightly inward so
	# the silhouette tapers downward.
	for side: float in [-1.0, 1.0]:
		var lg_x := side * 0.080
		body.add_child(_make_capsule(0.100, 0.34, Vector3(lg_x, hip_y - 0.22, 0.0), ghost_cloth, Vector3.ZERO))
		body.add_child(_make_sphere(0.075, Vector3(lg_x, knee_y - 0.02, 0.005), ghost_cloth, Vector3.ZERO))
		body.add_child(_make_capsule(0.058, 0.34, Vector3(lg_x, knee_y - 0.20, 0.010), ghost, Vector3.ZERO))
		body.add_child(_make_sphere(0.048, Vector3(lg_x, ankle_y + 0.04, 0.015), ghost, Vector3.ZERO))
		# Foot — flat, slightly forward
		var foot := MeshInstance3D.new()
		var fm := SphereMesh.new()
		fm.radius = 0.058
		fm.height = 0.116
		foot.mesh = fm
		foot.scale = Vector3(1.0, 0.55, 1.60)
		foot.position = Vector3(lg_x, foot_y, 0.055)
		foot.material_override = ghost
		body.add_child(foot)

# ── Anatomy helpers — same shape as HangingCorpse so the silhouettes match ──

func _make_capsule(radius: float, height: float, pos: Vector3,
		mat: Material, rot_deg: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = radius
	cm.height = height
	mi.mesh = cm
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.material_override = mat
	return mi

func _make_sphere(radius: float, pos: Vector3,
		mat: Material, rot_deg: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	mi.mesh = sm
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.material_override = mat
	return mi

func _ghost_mat(col: Color, alpha: float) -> ShaderMaterial:
	var m = ShaderMaterial.new()
	m.shader = load("res://shaders/ghost_material.gdshader")
	col.a = alpha
	m.set_shader_parameter("ghost_color", col)
	m.set_shader_parameter("edge_glow", 1.6)
	m.set_shader_parameter("distort_speed", 0.7)
	m.set_shader_parameter("distort_amount", 0.016)
	m.set_shader_parameter("flicker_speed", 3.8)
	m.set_shader_parameter("body_glow", 0.55)
	m.set_shader_parameter("rim_bleed", 1.2)
	return m
