extends Node

# ─── Audio Manager v4 — J-Horror Sound Engine ────────────────────────────────
# Procedural audio: binaural drone, synthesized menu music, random env events.
# All file-based paths fail silently — audio files are optional, synth fills gaps.

const SFX_PATHS = {
	"footstep_wet_1":  "res://audio/sfx/footstep_wet_1.ogg",
	"footstep_wet_2":  "res://audio/sfx/footstep_wet_2.ogg",
	"footstep_wet_3":  "res://audio/sfx/footstep_wet_3.ogg",
	"note_pickup":     "res://audio/sfx/note_pickup.ogg",
	"shrine_charge":   "res://audio/sfx/shrine_charge.ogg",
	"flashlight_on":   "res://audio/sfx/flashlight_click.ogg",
	"flashlight_off":  "res://audio/sfx/flashlight_off.ogg",
	"battery_low":     "res://audio/sfx/battery_low_beep.ogg",
	"jumpscare_sting": "res://audio/sfx/jumpscare_sting.ogg",
	"rope_creak":      "res://audio/sfx/rope_creak.ogg",
	"breath_fast":     "res://audio/sfx/breath_fast.ogg",
	"player_voice_0":  "res://audio/sfx/player_voice_note0.ogg",
	"player_voice_1":  "res://audio/sfx/player_voice_note1.ogg",
	"player_voice_2":  "res://audio/sfx/player_voice_note2.ogg",
	"player_voice_3":  "res://audio/sfx/player_voice_note3.ogg",
}

const GHOST_PATHS = {
	"whisper_jp_1":  "res://audio/ghost/whisper_jp_1.ogg",
	"whisper_jp_2":  "res://audio/ghost/whisper_jp_2.ogg",
	"whisper_jp_3":  "res://audio/ghost/whisper_jp_3.ogg",
	"cry_distant":   "res://audio/ghost/cry_distant.ogg",
	"cry_closer":    "res://audio/ghost/cry_closer.ogg",
	"cry_clear":     "res://audio/ghost/cry_clear.ogg",
	"cry_intense":   "res://audio/ghost/cry_intense.ogg",
	"hair_drag":     "res://audio/ghost/hair_dragging.ogg",
	"yurei_shriek":  "res://audio/ghost/yurei_shriek.ogg",
	"onryo_growl":   "res://audio/ghost/onryo_growl.ogg",
	"koto_sting":    "res://audio/ghost/koto_horror_sting.ogg",
	"stalker_roar":  "res://audio/ghost/onryo_growl.ogg",
	"stalker_retreat": "res://audio/ghost/hair_dragging.ogg",
}

const AMBIENT_PATHS = {
	"forest_night":  "res://audio/ambient/forest_night.ogg",
	"deep_forest":   "res://audio/ambient/deep_forest_drip.ogg",
	"cave_wind":     "res://audio/ambient/cave_wind.ogg",
	"rain_light":    "res://audio/ambient/rain_light.ogg",
	"tension_low":   "res://audio/ambient/tension_low.ogg",
	"tension_high":  "res://audio/ambient/tension_high.ogg",
	"heartbeat":     "res://audio/ambient/heartbeat.ogg",
}

# ── Japanese D-minor pentatonic for synthesized music (D2 octave) ─────────────
# D2=73.42  F2=87.31  G2=98.00  A2=110.00  C3=130.81  D3=146.83
const MENU_NOTES: Array = [73.42, 87.31, 98.00, 110.00, 130.81, 146.83, 98.00, 73.42]

# ── File-based players ────────────────────────────────────────────────────────
var _sfx_pool:    Array[AudioStreamPlayer] = []
var _ambient_bus: AudioStreamPlayer
var _ghost_bus:   AudioStreamPlayer
var _cry_bus:     AudioStreamPlayer
var _foot_idx:    int = 0
var _stream_cache: Dictionary = {}

# ── Procedural audio generators ───────────────────────────────────────────────
var _drone_player:  AudioStreamPlayer
var _music_player:  AudioStreamPlayer
var _forest_player: AudioStreamPlayer
var _music_time:    float = 0.0
var _forest_time:   float = 0.0
var _ambient_synth_active: bool = false
var _has_file_ambient: bool = false

# ── Menu-music note state ────────────────────────────────────────────────────
var _music_note_freq:  float = 98.00
var _music_note_start: float = -999.0  # absolute _music_time when note fired
var _music_next_note:  float = 2.0     # next trigger time

# ── Environmental audio ───────────────────────────────────────────────────────
var _env_timer:    float = 0.0
var _env_interval: float = 14.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

const DRONE_RATE: float = 22050.0  # half rate — fine for sub-bass content
const MUSIC_RATE: float = 22050.0
const USE_PROCEDURAL_FALLBACK: bool = false  # real OGG assets only in-game

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_setup_players()
	_preload_streams()
	_setup_generators()

func _setup_generators() -> void:
	# ── Binaural drone ─────────────────────────────────────────────────────────
	var drone_gen = AudioStreamGenerator.new()
	drone_gen.mix_rate    = DRONE_RATE
	drone_gen.buffer_length = 0.5
	_drone_player = AudioStreamPlayer.new()
	_drone_player.stream   = drone_gen
	_drone_player.bus      = "Ambient"
	_drone_player.volume_db = -18.0
	add_child(_drone_player)

	# ── Menu music ─────────────────────────────────────────────────────────────
	var music_gen = AudioStreamGenerator.new()
	music_gen.mix_rate    = MUSIC_RATE
	music_gen.buffer_length = 0.5
	_music_player = AudioStreamPlayer.new()
	_music_player.stream   = music_gen
	_music_player.bus      = "Ambient"
	_music_player.volume_db = -12.0
	add_child(_music_player)

	var forest_gen = AudioStreamGenerator.new()
	forest_gen.mix_rate = DRONE_RATE
	forest_gen.buffer_length = 0.5
	_forest_player = AudioStreamPlayer.new()
	_forest_player.stream = forest_gen
	_forest_player.bus = "Ambient"
	_forest_player.volume_db = -80.0
	add_child(_forest_player)

func _preload_streams() -> void:
	for path in SFX_PATHS.values():
		_cache(path)
	for path in GHOST_PATHS.values():
		_cache(path)
	for path in AMBIENT_PATHS.values():
		if ResourceLoader.exists(path):
			_has_file_ambient = true
		_cache(path)

func _cache(path: String) -> AudioStream:
	if _stream_cache.has(path):
		return _stream_cache[path]
	if not ResourceLoader.exists(path):
		return null
	var s: AudioStream = load(path)
	_stream_cache[path] = s
	return s

func _setup_players() -> void:
	for i in 10:
		var p = AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_sfx_pool.append(p)
	_ambient_bus = _make_player("Ambient", -6.0)
	_ghost_bus   = _make_player("Ghost",   -3.0)
	_cry_bus     = _make_player("Ghost",   -80.0)

func _make_player(bus: String, vol: float) -> AudioStreamPlayer:
	var p = AudioStreamPlayer.new()
	p.bus       = bus
	p.volume_db = vol
	add_child(p)
	return p

# ── Per-frame tick ────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	_ensure_drone_stopped()
	_tick_music()
	_tick_forest_ambient()
	_tick_env(delta)

func _ensure_drone_stopped() -> void:
	if _drone_player and _drone_player.playing:
		_drone_player.stop()

# ── Menu music — synthesised koto plucks over dark D-minor pentatonic drone ───

func _tick_music() -> void:
	var in_menu = (GameManager.state == GameManager.GameState.MENU)
	if not in_menu:
		if _music_player.playing:
			_music_player.stop()
			_music_time = 0.0
		return
	if not _music_player.playing:
		_music_time        = 0.0
		_music_note_start  = -999.0
		_music_next_note   = 2.5
		_music_player.play()
	var pb = _music_player.get_stream_playback() as AudioStreamGeneratorPlayback
	if not pb:
		return
	var frames = pb.get_frames_available()
	for i in frames:
		var t = _music_time + float(i) / MUSIC_RATE
		# ── Dark ambient pad — D bass drone ────────────────────────────────────
		var pad = sin(TAU * 36.71 * t) * 0.20        # D2 sub
		pad    += sin(TAU * 73.42 * t) * 0.10        # D3
		pad    += sin(TAU * 0.038 * t) * 0.04        # very slow waver (26s cycle)
		# ── FM koto pluck ─────────────────────────────────────────────────────
		var nt  = t - _music_note_start
		var pluck = 0.0
		if nt >= 0.0 and nt < 10.0:
			var env = exp(-nt * 1.05) * 0.55
			# FM: modulator at 2× carrier, index decays quickly
			var mod_i = 3.2 * exp(-nt * 2.4)
			var mod   = sin(TAU * _music_note_freq * 2.0 * nt) * mod_i
			pluck = sin(TAU * _music_note_freq * nt + mod) * env
		# Trigger next note
		if t >= _music_next_note:
			_music_next_note  = t + _rng.randf_range(3.5, 10.0)
			_music_note_start = t
			_music_note_freq  = MENU_NOTES[_rng.randi() % MENU_NOTES.size()]
		var out = (pad + pluck) * 0.40
		pb.push_frame(Vector2(out, out * 0.88))  # slight L/R asymmetry for width
	_music_time += float(frames) / MUSIC_RATE

# ── Procedural environmental sounds ─────────────────────────────────────────

func _tick_env(delta: float) -> void:
	if GameManager.state != GameManager.GameState.PLAYING:
		return
	_env_timer += delta
	if _env_timer < _env_interval:
		return
	_env_timer    = 0.0
	_env_interval = _rng.randf_range(7.0, 22.0)
	_trigger_env_sound()

func _trigger_env_sound() -> void:
	var tension = 0.0
	if GameManager.sanity_ref:
		tension = clamp(1.0 - GameManager.sanity_ref.sanity / 100.0, 0.0, 1.0)
	var r = _rng.randf()
	if r < 0.28:
		play_sfx("rope_creak", _rng.randf_range(-10.0, -4.0))
	elif r < 0.48:
		if tension > 0.20:
			play_whisper()
		else:
			play_sfx("rope_creak", -13.0)
	elif r < 0.65:
		play_sfx("breath_fast", _rng.randf_range(-15.0, -9.0))
	elif tension > 0.42 and r < 0.82:
		play_ghost_sound("koto_sting")
	elif tension > 0.70:
		play_ghost_sound("onryo_growl")

# ── SFX ──────────────────────────────────────────────────────────────────────

func play_sfx(key: String, vol_db: float = 0.0) -> void:
	if not SFX_PATHS.has(key):
		return
	var s = _cache(SFX_PATHS[key])
	if s:
		var p = _free_sfx()
		if p:
			p.stream = s
			p.volume_db = vol_db
			p.pitch_scale = 1.0
			p.play()
		return
	if USE_PROCEDURAL_FALLBACK:
		_play_synth_sfx(key, vol_db)

func play_footstep() -> void:
	var keys = ["footstep_wet_1", "footstep_wet_2", "footstep_wet_3"]
	_foot_idx = (_foot_idx + 1) % keys.size()
	var s = _cache(SFX_PATHS[keys[_foot_idx]])
	if s:
		var p = _free_sfx()
		if p:
			p.stream = s
			p.volume_db = _rng.randf_range(-3.0, 0.5)
			p.pitch_scale = _rng.randf_range(0.88, 1.12)
			p.play()
		return
	if USE_PROCEDURAL_FALLBACK:
		_play_synth_footstep()

func play_jumpscare_sting() -> void:
	if _cache(SFX_PATHS.get("jumpscare_sting", "")):
		play_sfx("jumpscare_sting", 2.5)
	elif USE_PROCEDURAL_FALLBACK:
		_play_synth_sting()

# ── Ghost / Whispers ─────────────────────────────────────────────────────────

func play_ghost_sound(key: String) -> void:
	if not GHOST_PATHS.has(key):
		return
	var s = _cache(GHOST_PATHS[key])
	if s:
		_ghost_bus.stream = s
		_ghost_bus.play()
		return
	if USE_PROCEDURAL_FALLBACK:
		_play_synth_ghost(key)

func play_whisper() -> void:
	var keys = ["whisper_jp_1", "whisper_jp_2", "whisper_jp_3"]
	var key = keys[randi() % keys.size()]
	if _cache(GHOST_PATHS[key]):
		play_ghost_sound(key)
	elif USE_PROCEDURAL_FALLBACK:
		_play_synth_whisper()

func set_cry_stream(key: String, target_vol_db: float, fade_time: float = 1.8) -> void:
	if not GHOST_PATHS.has(key):
		return
	var stream = _cache(GHOST_PATHS[key])
	if not stream:
		_cry_bus.volume_db = -80.0
		return
	if _cry_bus.stream != stream:
		_cry_bus.stream    = stream
		_cry_bus.volume_db = -80.0
		_cry_bus.play()
	var tween = create_tween()
	tween.tween_property(_cry_bus, "volume_db", target_vol_db, fade_time)

func stop_crying(fade_time: float = 2.0) -> void:
	var tween = create_tween()
	tween.tween_property(_cry_bus, "volume_db", -80.0, fade_time)
	await tween.finished
	_cry_bus.stop()

# ── Ambient ───────────────────────────────────────────────────────────────────

func play_ambient(key: String, fade: float = 2.0) -> void:
	if not AMBIENT_PATHS.has(key):
		return
	var path = AMBIENT_PATHS[key]
	if ResourceLoader.exists(path):
		var tween = create_tween()
		tween.tween_property(_ambient_bus, "volume_db", -80.0, fade * 0.4)
		await tween.finished
		_ambient_bus.stream = _cache(path)
		_ambient_bus.play()
		tween = create_tween()
		tween.tween_property(_ambient_bus, "volume_db", -4.0, fade * 0.6)
		_ambient_synth_active = false
		if _forest_player.playing:
			_forest_player.stop()
		return
	_start_forest_ambient_synth(fade)

# ── Helpers ───────────────────────────────────────────────────────────────────

func _free_sfx() -> AudioStreamPlayer:
	for p in _sfx_pool:
		if not p.playing:
			return p
	return _sfx_pool[0]

# ── Procedural fallbacks (no audio files required) ────────────────────────────

func _start_forest_ambient_synth(fade: float) -> void:
	_ambient_synth_active = true
	_forest_time = 0.0
	if not _forest_player.playing:
		_forest_player.play()
	var tween = create_tween()
	tween.tween_property(_forest_player, "volume_db", -14.0, fade)

func _tick_forest_ambient() -> void:
	if not USE_PROCEDURAL_FALLBACK or not _ambient_synth_active or GameManager.state != GameManager.GameState.PLAYING:
		if _forest_player.playing and not _has_file_ambient:
			_forest_player.stop()
		return
	if not _forest_player.playing:
		_forest_player.play()
	var pb = _forest_player.get_stream_playback() as AudioStreamGeneratorPlayback
	if not pb:
		return
	var frames = pb.get_frames_available()
	for i in frames:
		var t = _forest_time + float(i) / DRONE_RATE
		# Wind — filtered noise
		var wind = (_rng.randf() * 2.0 - 1.0) * 0.12
		wind += sin(TAU * 0.07 * t) * 0.04
		# Occasional water drip (sparse sine ping)
		var drip = 0.0
		if fmod(t, 4.7) < 0.018:
			drip = sin(TAU * 880.0 * fmod(t, 4.7)) * exp(-fmod(t, 4.7) * 180.0) * 0.35
		# Distant owl-like tone at low sanity
		var owl = 0.0
		if GameManager.sanity_ref and GameManager.sanity_ref.sanity < 45.0:
			owl = sin(TAU * 220.0 * t + sin(t * 0.3)) * 0.02 * (1.0 - GameManager.sanity_ref.sanity / 45.0)
		var mono = (wind + drip + owl) * 0.55
		pb.push_frame(Vector2(mono, mono * 0.94))
	_forest_time += float(frames) / DRONE_RATE

func _play_one_shot_wav(samples: PackedVector2Array, vol_db: float = 0.0, pitch: float = 1.0) -> void:
	var p = _free_sfx()
	if not p:
		return
	var rate := 22050
	var wav = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = true
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 4)
	for i in samples.size():
		var s = clampf(samples[i].x, -1.0, 1.0)
		var val := int(s * 32767.0)
		bytes[i * 4] = val & 0xFF
		bytes[i * 4 + 1] = (val >> 8) & 0xFF
		s = clampf(samples[i].y, -1.0, 1.0)
		val = int(s * 32767.0)
		bytes[i * 4 + 2] = val & 0xFF
		bytes[i * 4 + 3] = (val >> 8) & 0xFF
	wav.data = bytes
	p.stream = wav
	p.volume_db = vol_db
	p.pitch_scale = pitch
	p.play()

func _play_synth_footstep() -> void:
	var n := int(22050 * 0.09)
	var buf: PackedVector2Array = []
	buf.resize(n)
	for i in n:
		var t = float(i) / 22050.0
		var env = exp(-t * 42.0)
		var nse = (_rng.randf() * 2.0 - 1.0) * env
		var thud = sin(TAU * 95.0 * t) * env * 0.35
		var s = (nse * 0.55 + thud) * 0.7
		buf[i] = Vector2(s, s * 0.92)
	_play_one_shot_wav(buf, _rng.randf_range(-5.0, -1.0), _rng.randf_range(0.9, 1.1))

func _play_synth_sting() -> void:
	var n := int(22050 * 0.55)
	var buf: PackedVector2Array = []
	buf.resize(n)
	for i in n:
		var t = float(i) / 22050.0
		var env = exp(-t * 5.5)
		var s1 = sin(TAU * 180.0 * t) * env
		var s2 = sin(TAU * 271.0 * t) * env * 0.7
		var noise = (_rng.randf() * 2.0 - 1.0) * env * 0.25
		var s = (s1 + s2 + noise) * 0.65
		buf[i] = Vector2(s, -s * 0.85)
	_play_one_shot_wav(buf, 0.0)

func _play_synth_whisper() -> void:
	var n := int(22050 * 0.35)
	var buf: PackedVector2Array = []
	buf.resize(n)
	var base_f = _rng.randf_range(280.0, 420.0)
	for i in n:
		var t = float(i) / 22050.0
		var env = sin(PI * t / 0.35) * exp(-t * 2.2)
		var mod_i = 2.5 * exp(-t * 4.0)
		var mod = sin(TAU * base_f * 2.0 * t) * mod_i
		var carrier = sin(TAU * base_f * t + mod)
		var breath = (_rng.randf() * 2.0 - 1.0) * 0.08 * env
		var s = (carrier * 0.22 + breath) * env
		buf[i] = Vector2(s * 0.7, s * 0.5)
	_play_one_shot_wav(buf, _rng.randf_range(-12.0, -6.0))

func _play_synth_ghost(key: String) -> void:
	match key:
		"onryo_growl", "stalker_roar":
			_play_synth_sting()
		"hair_drag", "stalker_retreat":
			_play_synth_whisper()
		"koto_sting", "yurei_shriek":
			_play_synth_sting()
		_:
			_play_synth_whisper()

func _play_synth_sfx(key: String, vol_db: float) -> void:
	match key:
		"flashlight_on", "flashlight_off":
			var n := int(22050 * 0.04)
			var buf: PackedVector2Array = []
			buf.resize(n)
			for i in n:
				var t = float(i) / 22050.0
				var s = sin(TAU * 1200.0 * t) * exp(-t * 80.0) * 0.4
				buf[i] = Vector2(s, s)
			_play_one_shot_wav(buf, vol_db - 8.0)
		"note_pickup", "shrine_charge":
			_play_synth_whisper()
		"battery_low":
			_play_one_shot_wav(_make_beep_samples(880.0, 0.12), vol_db)
		"rope_creak", "breath_fast":
			_play_synth_whisper()
		_:
			_play_synth_footstep()

func _make_beep_samples(freq: float, dur: float) -> PackedVector2Array:
	var n := int(22050 * dur)
	var buf: PackedVector2Array = []
	buf.resize(n)
	for i in n:
		var t = float(i) / 22050.0
		var env = exp(-t * 12.0)
		var s = sin(TAU * freq * t) * env * 0.35
		buf[i] = Vector2(s, s)
	return buf
