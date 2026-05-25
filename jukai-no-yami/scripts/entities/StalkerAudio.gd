extends Node3D

# ─── StalkerAudio — 3D Spatial Audio for the Stalker Entity ──────────────────
# Attach as child of StalkerAI (CharacterBody3D).
# All AudioStreamPlayer3D nodes sit at local (0,0,0) so they move with the monster.
# Godot 4 positional audio then handles attenuation + panning automatically.

const STALKER_SOUNDS = {
	"footstep_1":       "res://audio/stalker/footstep_heavy_1.ogg",
	"footstep_2":       "res://audio/stalker/footstep_heavy_2.ogg",
	"footstep_3":       "res://audio/stalker/footstep_heavy_3.ogg",
	"footstep_4":       "res://audio/stalker/footstep_heavy_4.ogg",
	"breath_slow":      "res://audio/stalker/breath_slow.ogg",      # loops
	"scratch_bark":     "res://audio/stalker/scratch_bark.ogg",
	"scratch_leaf":     "res://audio/stalker/scratch_leaf.ogg",
	"whistle_distant":  "res://audio/stalker/distant_whistle.ogg",
	"lunge_roar":       "res://audio/stalker/lunge_roar.ogg",
	"retreat_rustle":   "res://audio/stalker/retreat_rustle.ogg",
	"ambient_lurk":     "res://audio/stalker/ambient_lurk_hum.ogg", # loops during SHADOW_LURK
}

var _step_player:   AudioStreamPlayer3D
var _breath_player: AudioStreamPlayer3D
var _ambient_player: AudioStreamPlayer3D
var _oneshot_player: AudioStreamPlayer3D

var _step_timer:    float = 0.0
var _step_interval: float = 0.0
var _foot_idx:      int   = 0

func _ready() -> void:
	_step_player    = _make_player(12.0, 32.0, -4.0,  "SFX")
	_breath_player  = _make_player(6.0,  20.0, -80.0, "Ghost")
	_ambient_player = _make_player(28.0, 60.0, -80.0, "Ghost")
	_oneshot_player = _make_player(18.0, 40.0, -3.0,  "Ghost")

func _make_player(min_dist: float, max_dist: float, vol: float, bus: String) -> AudioStreamPlayer3D:
	var p = AudioStreamPlayer3D.new()
	p.unit_size              = min_dist
	p.max_distance           = max_dist
	p.volume_db              = vol
	p.bus                    = bus
	p.attenuation_model      = AudioStreamPlayer3D.ATTENUATION_LOGARITHMIC
	p.max_polyphony          = 2
	add_child(p)
	return p

# ─── Footsteps ────────────────────────────────────────────────────────────────

func start_footsteps(interval: float = 0.55) -> void:
	_step_interval = interval
	_step_timer    = 0.0

func stop_footsteps() -> void:
	_step_interval = 0.0
	# Soft fade — footsteps are short transients so a quick 0.4s glide is
	# enough to avoid the "audio yanked off the deck" feel.
	_fade_out(_step_player, 0.4)

func tick_footstep(delta: float) -> void:
	if _step_interval <= 0.0:
		return
	_step_timer += delta
	if _step_timer >= _step_interval:
		_step_timer = 0.0
		_play_footstep()

func _play_footstep() -> void:
	var keys = ["footstep_1", "footstep_2", "footstep_3", "footstep_4"]
	_foot_idx = (_foot_idx + 1) % keys.size()
	_load_and_play(_step_player, STALKER_SOUNDS[keys[_foot_idx]])

# ─── Breathing ────────────────────────────────────────────────────────────────

func start_breathing() -> void:
	var path = STALKER_SOUNDS["breath_slow"]
	if not ResourceLoader.exists(path):
		return
	_breath_player.stream = load(path)
	var tween = create_tween()
	tween.tween_property(_breath_player, "volume_db", -8.0, 1.5)
	if not _breath_player.playing:
		_breath_player.play()

func stop_breathing() -> void:
	var tween = create_tween()
	tween.tween_property(_breath_player, "volume_db", -80.0, 1.2)
	await tween.finished
	_breath_player.stop()

# ─── Distant ambience (played during SHADOW_LURK) ────────────────────────────

func start_distant_ambience() -> void:
	var path = STALKER_SOUNDS["ambient_lurk"]
	if not ResourceLoader.exists(path):
		return
	_ambient_player.stream = load(path)
	var tween = create_tween()
	tween.tween_property(_ambient_player, "volume_db", -16.0, 2.0)
	if not _ambient_player.playing:
		_ambient_player.play()

func stop_distant_ambience() -> void:
	var tween = create_tween()
	tween.tween_property(_ambient_player, "volume_db", -80.0, 1.8)
	await tween.finished
	_ambient_player.stop()

# ─── One-shot events ──────────────────────────────────────────────────────────

func play_scratch() -> void:
	var keys = ["scratch_bark", "scratch_leaf"]
	_load_and_play(_oneshot_player, STALKER_SOUNDS[keys[randi() % keys.size()]])

func play_distant_whistle() -> void:
	_load_and_play(_oneshot_player, STALKER_SOUNDS["whistle_distant"])

func play_lunge_roar() -> void:
	_oneshot_player.volume_db = 2.0
	_load_and_play(_oneshot_player, STALKER_SOUNDS["lunge_roar"])

func play_retreat() -> void:
	_load_and_play(_oneshot_player, STALKER_SOUNDS["retreat_rustle"])

# ─── Helpers ──────────────────────────────────────────────────────────────────

func stop_all() -> void:
	# Fade everything out together instead of slamming each player to stop.
	# The stalker entering cooldown should feel like the presence drifts
	# away, not like the audio engine crashed.
	_fade_out(_step_player, 0.8)
	_fade_out(_breath_player, 1.5)
	_fade_out(_ambient_player, 2.0)
	_fade_out(_oneshot_player, 1.2)
	_step_interval = 0.0


# Tween volume_db down to -80, then stop the player. Idempotent if the
# player isn't currently playing.
func _fade_out(player: AudioStreamPlayer3D, time: float) -> void:
	if not player or not player.playing:
		return
	var orig_db := player.volume_db
	var tw := create_tween()
	tw.tween_property(player, "volume_db", -80.0, time)
	await tw.finished
	if player and player.playing:
		player.stop()
		player.volume_db = orig_db

func _load_and_play(player: AudioStreamPlayer3D, path: String) -> void:
	if not ResourceLoader.exists(path):
		return
	player.stream = load(path)
	player.play()
