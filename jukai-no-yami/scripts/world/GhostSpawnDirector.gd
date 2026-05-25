extends Node

# ─── Ghost Spawn Director ─────────────────────────────────────────────────────
# Manages the 5 well-timed jump scares across all three levels.
# Each level scene instances this node and exports the ghost node paths.
#
# SCARE DESIGN:
#   1. (Forest Entrance, ~90s) Yurei appears at flashlight edge. Shining on it
#      triggers the first reveal scare. Player then turns and it reappears close.
#   2. (Forest Entrance, Note 0 pickup) Yurei spawns directly behind player.
#      Hair-drag audio cue → player turns → it's RIGHT THERE.
#   3. (Dense Tree Sea, ~3min) Director forces a dramatic flashlight flicker.
#      During darkness, Onryo teleports from 18m to 4m. Light returns → reveal.
#   4. (Dense Tree Sea, Note 2 pickup) Hanging Spirit drops fast overhead.
#      Looking up is natural → it's directly above descending → screen shake.
#   5. (Ribbon Path, Note 3 pickup) Flashlight briefly dies. When it comes back,
#      Yurei is right at camera filling the frame → MAX intensity scare.

signal all_scares_complete

@export_group("Level Scare Config")
@export var scare_1_ghost_path:   NodePath  # Yurei for edge-reveal
@export var scare_1_delay:        float = 90.0
@export var scare_2_ghost_path:   NodePath  # Yurei for behind-player
@export var scare_2_note_id:      int   = -1  # -1 = time-based instead
@export var scare_2_delay:        float = 150.0
@export var scare_3_onryo_path:   NodePath  # Onryo for flicker-teleport
@export var scare_3_delay:        float = 60.0
@export var scare_4_hang_path:    NodePath  # HangingSpirit for fast-drop
@export var scare_4_note_id:      int   = -1
@export var scare_5_yurei_path:   NodePath  # Yurei for final face-reveal
@export var scare_5_note_id:      int   = -1

var _triggered: Array[bool] = [false, false, false, false, false]
var _timer: float = 0.0
var _player: CharacterBody3D = null

func _ready() -> void:
	await get_tree().process_frame
	_player = GameManager.player_ref
	# Connect to note collection signal for note-based scares
	GameManager.note_collected.connect(_on_note_collected)

func _process(delta: float) -> void:
	if GameManager.state != GameManager.GameState.PLAYING:
		return
	_timer += delta
	_player = GameManager.player_ref

	# Time-based scare checks
	if not _triggered[0] and scare_1_ghost_path != NodePath("") and _timer >= scare_1_delay:
		_trigger_scare_1()
	if not _triggered[1] and scare_2_ghost_path != NodePath("") and scare_2_note_id < 0 and _timer >= scare_2_delay:
		_trigger_scare_2()
	if not _triggered[2] and scare_3_onryo_path != NodePath("") and _timer >= scare_3_delay:
		_trigger_scare_3()

# ─── Scare 1: Edge-of-beam reveal ─────────────────────────────────────────────

func _trigger_scare_1() -> void:
	_triggered[0] = true
	var ghost = _get_node(scare_1_ghost_path)
	if not ghost or not ghost.has_method("activate"):
		return
	# Place ghost at edge of flashlight cone so beam sweeping reveals it
	_place_at_beam_edge(ghost, 14.0, 18.0)
	ghost.activate()

func _place_at_beam_edge(ghost: Node3D, dist_min: float, dist_max: float) -> void:
	if not _player:
		return
	# Offset 18-22 degrees from player's current look direction
	var look_angle = _player.rotation.y
	var offset_angle = look_angle + deg_to_rad(randf_range(16.0, 22.0) * (1.0 if randf() > 0.5 else -1.0))
	var dist = randf_range(dist_min, dist_max)
	ghost.global_position = _player.global_position + Vector3(sin(offset_angle) * dist, 0.0, cos(offset_angle) * dist)

# ─── Scare 2: Spawn behind player ─────────────────────────────────────────────

func _trigger_scare_2() -> void:
	_triggered[1] = true
	var ghost = _get_node(scare_2_ghost_path)
	if not ghost or not ghost.has_method("spawn_behind_player"):
		return
	ghost.spawn_behind_player()

# ─── Scare 3: Forced flicker → Onryo close teleport ──────────────────────────

func _trigger_scare_3() -> void:
	_triggered[2] = true
	var onryo = _get_node(scare_3_onryo_path)
	if not onryo:
		return
	_do_scare_3_sequence(onryo)

func _do_scare_3_sequence(onryo: Node) -> void:
	# Force flashlight into dramatic flicker
	var flashlight = _get_flashlight()
	if flashlight and flashlight.has_method("force_flicker_event"):
		flashlight.force_flicker_event(0.4)

	# Slight delay so flicker starts before teleport
	await get_tree().create_timer(0.25).timeout

	# During darkness, Onryo silently teleports close
	if onryo.has_method("teleport_close_silent"):
		onryo.teleport_close_silent()

	# When light comes back on, the beam hits Onryo → beam_entry fires the scare
	# (handled inside OnryoEntity._handle_close_stalk)

# ─── Scare 4: Fast-drop hanging spirit ────────────────────────────────────────

func _trigger_scare_4() -> void:
	_triggered[3] = true
	var spirit = _get_node(scare_4_hang_path)
	if not spirit:
		return
	# Override hang speed for this scare — very fast drop
	if "hang_height" in spirit:
		spirit.hang_height = 5.5
	if spirit.has_method("force_fast_drop"):
		spirit.force_fast_drop()
	elif spirit.has_method("activate"):
		spirit.activate()
	JumpscareSystem.trigger(JumpscareSystem.Intensity.HARD)
	AudioManager.play_ghost_sound("yurei_shriek")

# ─── Scare 5: Flashlight dies → face in the dark ─────────────────────────────

func _trigger_scare_5() -> void:
	_triggered[4] = true
	var ghost = _get_node(scare_5_yurei_path)
	if not ghost:
		return
	_do_scare_5_sequence(ghost)

func _do_scare_5_sequence(ghost: Node) -> void:
	var flashlight = _get_flashlight()
	if flashlight and flashlight.has_method("force_flicker_event"):
		flashlight.force_flicker_event(0.42)
	else:
		await get_tree().create_timer(0.42).timeout

	if ghost.has_method("force_reveal_close"):
		ghost.force_reveal_close()

	if flashlight:
		flashlight.visible = true
		if flashlight.has_method("recharge"):
			flashlight.recharge()

# ─── Note-triggered scares ────────────────────────────────────────────────────

func _on_note_collected(note_id: int) -> void:
	if note_id == scare_2_note_id and not _triggered[1]:
		_trigger_scare_2()
	if note_id == scare_4_note_id and not _triggered[3]:
		_trigger_scare_4()
	if note_id == scare_5_note_id and not _triggered[4]:
		_trigger_scare_5()

# ─── Helpers ──────────────────────────────────────────────────────────────────

func _get_node(path: NodePath) -> Node:
	if path == NodePath(""):
		return null
	return get_node_or_null(path)

func _get_flashlight() -> Node:
	if not _player:
		return null
	return _player.get_node_or_null("Camera3D/HandPivot/Flashlight")
