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
var _music_fading_out: bool  = false   # guard so _tick_music doesn't restart the fade

# ── Environmental audio ───────────────────────────────────────────────────────
# First-creepy-sound delay PER level. Without this the timer persists across
# scene swaps (autoload outlives levels) and a creepy sting fires within
# 1-2 seconds of entering a new area, which kills horror pacing.
const ENV_FIRST_DELAY_MIN := 60.0
const ENV_FIRST_DELAY_MAX := 110.0
var _env_timer:    float = 0.0
var _env_interval: float = 75.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

const DRONE_RATE: float = 22050.0  # half rate — fine for sub-bass content
const MUSIC_RATE: float = 22050.0
const SYNTH_RATE: int = 22050
# Override OGG files with synthesized streams. The shipped OGGs are tiny
# (~4 KB) placeholders that sound metallic / "alien"; the procedural
# synthesizer below produces voice-formant cries and breathy whispers that
# read as ghostly. Set this to false if you drop real recorded OGGs in.
const SYNTH_OVERRIDES_OGG: bool = true
const USE_PROCEDURAL_FALLBACK: bool = true

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_setup_players()
	_preload_streams()
	_setup_generators()
	# Pre-cache synthesized AudioStreamWAV for every key. The cache is checked
	# before load(), so this transparently substitutes for the placeholder OGGs.
	if SYNTH_OVERRIDES_OGG:
		_build_synth_cache()

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
		# Don't hard-stop the music when leaving the menu — fade it out so
		# the transition into the game doesn't feel like the soundtrack got
		# yanked off the deck.
		if _music_player.playing and not _music_fading_out:
			_music_fading_out = true
			var fade = create_tween()
			fade.tween_property(_music_player, "volume_db", -80.0, 2.2)
			await fade.finished
			if _music_player.playing:
				_music_player.stop()
				_music_player.volume_db = -12.0
				_music_time = 0.0
			_music_fading_out = false
		return
	if not _music_player.playing:
		_music_time        = 0.0
		_music_note_start  = -999.0
		_music_next_note   = 2.5
		_music_player.volume_db = -80.0
		_music_player.play()
		# Fade IN when entering menu
		var fade_in = create_tween()
		fade_in.tween_property(_music_player, "volume_db", -12.0, 1.6)
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

# Called by LevelManager._start_common when a new level starts playing.
# Resets the env-sound timer so the first creepy sting is delayed by
# ENV_FIRST_DELAY_MIN..MAX seconds instead of firing 1-2s into the level.
func begin_level_ambience() -> void:
	_env_timer = 0.0
	_env_interval = _rng.randf_range(ENV_FIRST_DELAY_MIN, ENV_FIRST_DELAY_MAX)

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

# ─── Improved Procedural Audio (Voice-Formant Synthesis) ──────────────────────
# These functions pre-generate AudioStreamWAVs at startup and inject them
# into _stream_cache under the same path keys the OGG files use. Because
# _cache() returns from the dictionary before hitting load(), the synth
# audio transparently replaces the placeholder OGGs.
#
# The synthesis uses additive harmonics with formant-weighted amplitudes
# to approximate vocal-tract resonance. It's NOT a real recorded voice —
# but it reads as "ghost crying woman" instead of "computer beeping at you".

func _build_synth_cache() -> void:
	# SFX
	_cache_wav(SFX_PATHS["footstep_wet_1"], _synth_footstep(0))
	_cache_wav(SFX_PATHS["footstep_wet_2"], _synth_footstep(1))
	_cache_wav(SFX_PATHS["footstep_wet_3"], _synth_footstep(2))
	_cache_wav(SFX_PATHS["note_pickup"], _synth_pickup_chime())
	_cache_wav(SFX_PATHS["shrine_charge"], _synth_shrine_charge())
	_cache_wav(SFX_PATHS["flashlight_on"], _synth_click(0.045, true))
	_cache_wav(SFX_PATHS["flashlight_off"], _synth_click(0.05, false))
	_cache_wav(SFX_PATHS["battery_low"], _synth_battery_beep())
	_cache_wav(SFX_PATHS["jumpscare_sting"], _synth_jumpscare_sting())
	_cache_wav(SFX_PATHS["rope_creak"], _synth_rope_creak())
	_cache_wav(SFX_PATHS["breath_fast"], _synth_panic_breath())
	# Player monologue voices — we can't TTS, so a quiet inhale stand-in.
	_cache_wav(SFX_PATHS["player_voice_0"], _synth_short_breath(0.5))
	_cache_wav(SFX_PATHS["player_voice_1"], _synth_short_breath(0.6))
	_cache_wav(SFX_PATHS["player_voice_2"], _synth_short_breath(0.7))
	_cache_wav(SFX_PATHS["player_voice_3"], _synth_short_breath(0.8))

	# Ghost audio
	_cache_wav(GHOST_PATHS["whisper_jp_1"], _synth_whisper(0.9, 220.0))
	_cache_wav(GHOST_PATHS["whisper_jp_2"], _synth_whisper(1.0, 245.0))
	_cache_wav(GHOST_PATHS["whisper_jp_3"], _synth_whisper(0.8, 270.0))
	_cache_wav(GHOST_PATHS["cry_distant"], _synth_voice_cry(2.4, 240.0, 0.85, 0.30))
	_cache_wav(GHOST_PATHS["cry_closer"], _synth_voice_cry(2.0, 250.0, 0.65, 0.55))
	_cache_wav(GHOST_PATHS["cry_clear"], _synth_voice_cry(1.7, 260.0, 0.40, 0.80))
	_cache_wav(GHOST_PATHS["cry_intense"], _synth_cry_intense())
	_cache_wav(GHOST_PATHS["hair_drag"], _synth_hair_drag())
	_cache_wav(GHOST_PATHS["yurei_shriek"], _synth_shriek())
	_cache_wav(GHOST_PATHS["onryo_growl"], _synth_growl())
	_cache_wav(GHOST_PATHS["koto_sting"], _synth_koto_pluck(220.0))
	# Aliases — code references these even when they share an OGG.
	_cache_wav(GHOST_PATHS["stalker_roar"], _synth_growl())
	_cache_wav(GHOST_PATHS["stalker_retreat"], _synth_hair_drag())

func _cache_wav(path: String, samples: PackedVector2Array) -> void:
	_stream_cache[path] = _wav_from_samples(samples)

func _wav_from_samples(samples: PackedVector2Array) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SYNTH_RATE
	wav.stereo = true
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 4)
	for i in samples.size():
		var l := clampf(samples[i].x, -1.0, 1.0)
		var lv := int(l * 32767.0)
		bytes[i * 4]     =  lv        & 0xFF
		bytes[i * 4 + 1] = (lv >> 8)  & 0xFF
		var r := clampf(samples[i].y, -1.0, 1.0)
		var rv := int(r * 32767.0)
		bytes[i * 4 + 2] =  rv        & 0xFF
		bytes[i * 4 + 3] = (rv >> 8)  & 0xFF
	wav.data = bytes
	return wav

# ── Synth primitives ──────────────────────────────────────────────────────────

# Voice-formant harmonic stack. F0 is the fundamental; harmonics 2..8 get
# weights shaped to emphasize energy near 500 Hz (F1) and 1500 Hz (F2),
# producing a vowel-like timbre instead of a pure sawtooth.
func _voice_sample(f0: float, t: float) -> float:
	var s := 0.0
	for h in range(1, 9):
		var freq := f0 * float(h)
		# Formant-shaped amplitude. Peaks near 500 and 1500 Hz; rolloff at high freq.
		var w_f1 := exp(-pow((freq - 500.0) / 380.0, 2.0))
		var w_f2 := exp(-pow((freq - 1500.0) / 520.0, 2.0)) * 0.55
		var roll := 1.0 / float(h)        # natural harmonic falloff
		var amp := (w_f1 + w_f2 + roll * 0.18)
		s += sin(TAU * freq * t) * amp
	return s * 0.30

# Sad female crying with sob shudder. Pitch wobbles, breath noise overlays.
func _synth_voice_cry(duration: float, pitch_hz: float, breath: float, intensity: float) -> PackedVector2Array:
	var n := int(SYNTH_RATE * duration)
	var buf := PackedVector2Array()
	buf.resize(n)
	for i in n:
		var t := float(i) / float(SYNTH_RATE)
		var phase := t / duration
		# 4.5 Hz vibrato + 1.2 Hz sob shudder
		var vib := sin(TAU * 4.5 * t) * 0.022 + sin(TAU * 1.2 * t) * 0.055
		var f0 := pitch_hz * (1.0 + vib) * (1.0 + 0.04 * (1.0 - phase))
		var voiced := _voice_sample(f0, t)
		var bn := (_rng.randf() * 2.0 - 1.0) * breath * 0.55
		# Bell-shaped amplitude with sob amplitude wobble
		var env := sin(PI * phase) * (0.82 + 0.18 * sin(TAU * 1.2 * t))
		env *= 0.45 + 0.55 * intensity
		# Mild stereo width — left/right channels each get their own breath noise
		# (bn above is unused now; the stereo channels generate fresh noise per side).
		var sl := voiced * 0.65 * env + (_rng.randf() * 2.0 - 1.0) * breath * 0.55 * env * 0.35 + bn * 0.0
		var sr := voiced * 0.65 * env + (_rng.randf() * 2.0 - 1.0) * breath * 0.55 * env * 0.35
		buf[i] = Vector2(clampf(sl * 0.78, -1.0, 1.0), clampf(sr * 0.78, -1.0, 1.0))
	return buf

# Intense cry — two layered cries at slight pitch offset, more presence
func _synth_cry_intense() -> PackedVector2Array:
	var a := _synth_voice_cry(1.6, 270.0, 0.30, 1.0)
	var b := _synth_voice_cry(1.6, 320.0, 0.30, 0.85)
	var n: int = min(a.size(), b.size())
	var buf := PackedVector2Array()
	buf.resize(n)
	for i in n:
		buf[i] = Vector2(
			clampf(a[i].x * 0.65 + b[i].x * 0.55, -1.0, 1.0),
			clampf(a[i].y * 0.55 + b[i].y * 0.65, -1.0, 1.0))
	return buf

# Whisper — breathy fricative bursts that suggest spoken syllables.
# Not real speech, but more "haa-suu-keh" than "electronic chirp".
func _synth_whisper(duration: float, base_pitch: float) -> PackedVector2Array:
	var n := int(SYNTH_RATE * duration)
	var buf := PackedVector2Array()
	buf.resize(n)
	# 3-5 syllable bursts evenly spread; each has a quick noise transient
	# and a brief voiced tail.
	var syll_count := _rng.randi_range(3, 5)
	var syll_dur := duration / float(syll_count)
	for i in n:
		var t := float(i) / float(SYNTH_RATE)
		var syll_idx := int(t / syll_dur)
		var syll_t := t - float(syll_idx) * syll_dur
		var syll_phase := syll_t / syll_dur
		# Syllable envelope: quick attack, fade out before next syllable
		var env := exp(-syll_phase * 4.0) * smoothstep(0.0, 0.04, syll_phase) * 0.9
		# Breath / fricative noise
		var bn := (_rng.randf() * 2.0 - 1.0) * 0.85
		# Faint voiced tail (lower freq than the noise)
		var pf := base_pitch * (1.0 + 0.02 * sin(TAU * 3.0 * t))
		var voiced := _voice_sample(pf, t) * 0.18
		var s := (bn * 0.65 + voiced) * env
		buf[i] = Vector2(s * 0.55, s * 0.50)
	return buf

# Yurei shriek — high-pitched female scream with descending swoop
func _synth_shriek() -> PackedVector2Array:
	var duration := 0.85
	var n := int(SYNTH_RATE * duration)
	var buf := PackedVector2Array()
	buf.resize(n)
	for i in n:
		var t := float(i) / float(SYNTH_RATE)
		var phase := t / duration
		# Glide: 350 Hz → 900 Hz → 600 Hz (rise-and-fall)
		var glide_factor := 0.0
		if phase < 0.35:
			glide_factor = phase / 0.35  # 0..1
		else:
			glide_factor = 1.0 - (phase - 0.35) / 0.65 * 0.4  # 1..0.6
		var f0 := lerpf(350.0, 900.0, glide_factor)
		var voiced := _voice_sample(f0, t)
		# Screech overlay — high-frequency noise that follows the pitch
		var screech_freq := f0 * 4.0 + (_rng.randf() * 200.0 - 100.0)
		var screech := sin(TAU * screech_freq * t) * 0.18
		var bn := (_rng.randf() * 2.0 - 1.0) * 0.25
		# Sharp attack, slow fall
		var env := 1.0
		if phase < 0.05:
			env = phase / 0.05
		else:
			env = pow(1.0 - phase, 1.2)
		env *= 0.95
		var s := (voiced * 0.7 + screech * 0.35 + bn * 0.25) * env
		buf[i] = Vector2(clampf(s * 0.88, -1.0, 1.0), clampf(s * 0.95, -1.0, 1.0))
	return buf

# Onryo growl — sub-bass throat sound with slow modulation and grit
func _synth_growl() -> PackedVector2Array:
	var duration := 1.4
	var n := int(SYNTH_RATE * duration)
	var buf := PackedVector2Array()
	buf.resize(n)
	for i in n:
		var t := float(i) / float(SYNTH_RATE)
		var phase := t / duration
		var f0 := 78.0 * (1.0 + 0.06 * sin(TAU * 2.2 * t))
		# Stack low harmonics; emphasize 2nd and 3rd for chest resonance
		var v := sin(TAU * f0 * t) * 0.5
		v += sin(TAU * f0 * 2.0 * t) * 0.32
		v += sin(TAU * f0 * 3.0 * t) * 0.18
		v += sin(TAU * f0 * 5.0 * t) * 0.08
		# Wavefold for grit
		v = sin(v * 1.4) * 0.78
		# Throat noise overlay
		var bn := (_rng.randf() * 2.0 - 1.0) * 0.18
		var env := smoothstep(0.0, 0.18, phase) * smoothstep(1.0, 0.55, phase) * 0.92
		var s := (v + bn) * env
		buf[i] = Vector2(clampf(s * 0.78, -1.0, 1.0), clampf(s * 0.78, -1.0, 1.0))
	return buf

# Hair-drag — high-frequency filtered noise that crawls slowly
func _synth_hair_drag() -> PackedVector2Array:
	var duration := 1.6
	var n := int(SYNTH_RATE * duration)
	var buf := PackedVector2Array()
	buf.resize(n)
	var lp_l := 0.0
	var lp_r := 0.0
	for i in n:
		var t := float(i) / float(SYNTH_RATE)
		var phase := t / duration
		# Brown-noise-like via low-passed white noise
		var wl := _rng.randf() * 2.0 - 1.0
		var wr := _rng.randf() * 2.0 - 1.0
		lp_l = lp_l * 0.85 + wl * 0.15
		lp_r = lp_r * 0.85 + wr * 0.15
		# Slow tremolo
		var tremolo := 0.55 + 0.45 * sin(TAU * 0.8 * t)
		var env := smoothstep(0.0, 0.12, phase) * smoothstep(1.0, 0.7, phase)
		buf[i] = Vector2(lp_l * 0.85 * tremolo * env, lp_r * 0.85 * tremolo * env)
	return buf

# Koto pluck — plucked-string-like emotive sound
func _synth_koto_pluck(freq: float) -> PackedVector2Array:
	var duration := 1.6
	var n := int(SYNTH_RATE * duration)
	var buf := PackedVector2Array()
	buf.resize(n)
	for i in n:
		var t := float(i) / float(SYNTH_RATE)
		# Slight downward bend over time (eerie / out-of-tune)
		var bend := 1.0 - 0.04 * t
		var f := freq * bend
		# Karplus-strong-ish: harmonic stack + quick decay
		var s := sin(TAU * f * t) * 0.55
		s += sin(TAU * f * 2.0 * t) * 0.28 * exp(-t * 2.5)
		s += sin(TAU * f * 3.0 * t) * 0.16 * exp(-t * 3.5)
		s += sin(TAU * f * 4.0 * t) * 0.08 * exp(-t * 4.5)
		# Pluck attack: noise burst at t=0
		if t < 0.02:
			s += (_rng.randf() * 2.0 - 1.0) * 0.5 * (1.0 - t / 0.02)
		var env := exp(-t * 1.6)
		var out := s * env * 0.78
		buf[i] = Vector2(out * 0.95, out * 0.92)
	return buf

# Rope creak — low pitched whine with wood-like timbre
func _synth_rope_creak() -> PackedVector2Array:
	var duration := 0.95
	var n := int(SYNTH_RATE * duration)
	var buf := PackedVector2Array()
	buf.resize(n)
	for i in n:
		var t := float(i) / float(SYNTH_RATE)
		var phase := t / duration
		# Glide from 140 → 210 Hz
		var f := lerpf(140.0, 210.0, phase)
		var s := sin(TAU * f * t) * 0.55
		s += sin(TAU * f * 1.5 * t) * 0.28
		s += sin(TAU * f * 2.0 * t) * 0.18
		s += sin(TAU * f * 3.0 * t) * 0.08
		# Slow random amplitude flutter — wood under stress
		var flutter := 1.0 + 0.18 * sin(TAU * 12.0 * t + sin(TAU * 3.0 * t))
		var env := sin(PI * phase) * 0.85 * flutter
		var out := s * env * 0.7
		buf[i] = Vector2(clampf(out, -1.0, 1.0), clampf(out * 0.94, -1.0, 1.0))
	return buf

# Panic / fast breath — quick in/out pattern
func _synth_panic_breath() -> PackedVector2Array:
	var duration := 0.85
	var n := int(SYNTH_RATE * duration)
	var buf := PackedVector2Array()
	buf.resize(n)
	for i in n:
		var t := float(i) / float(SYNTH_RATE)
		var phase := t / duration
		# Two in-out cycles
		var cycle := sin(TAU * 2.2 * t)
		var env := smoothstep(0.0, 0.05, phase) * smoothstep(1.0, 0.85, phase)
		var noise := (_rng.randf() * 2.0 - 1.0) * 0.9
		# High-passed (subtract slow component)
		var s := noise - noise * 0.4
		s *= abs(cycle) * env * 0.55
		buf[i] = Vector2(s * 0.78, s * 0.85)
	return buf

# Single soft inhale — stand-in for the missing recorded player voiceovers.
func _synth_short_breath(duration: float) -> PackedVector2Array:
	var n := int(SYNTH_RATE * duration)
	var buf := PackedVector2Array()
	buf.resize(n)
	for i in n:
		var t := float(i) / float(SYNTH_RATE)
		var phase := t / duration
		var env := smoothstep(0.0, 0.25, phase) * smoothstep(1.0, 0.7, phase)
		var noise := (_rng.randf() * 2.0 - 1.0) * 0.55
		buf[i] = Vector2(noise * env * 0.42, noise * env * 0.42)
	return buf

# Wet footstep with material variation 0..2
func _synth_footstep(variant: int) -> PackedVector2Array:
	var duration := 0.12
	var n := int(SYNTH_RATE * duration)
	var buf := PackedVector2Array()
	buf.resize(n)
	var thud_freq := 70.0 + float(variant) * 8.0
	for i in n:
		var t := float(i) / float(SYNTH_RATE)
		var phase := t / duration
		var thud := sin(TAU * thud_freq * t) * exp(-t * 35.0) * 0.55
		# Scuff transient (high freq noise burst at start)
		var scuff := 0.0
		if t < 0.04:
			scuff = (_rng.randf() * 2.0 - 1.0) * (1.0 - t / 0.04) * 0.45
		# Wet splash high-pass tap
		var splash := 0.0
		if t > 0.02 and t < 0.07:
			splash = (_rng.randf() * 2.0 - 1.0) * 0.20 * exp(-(t - 0.02) * 30.0)
		var s := (thud + scuff + splash) * (0.9 - phase * 0.5)
		buf[i] = Vector2(s * 0.92, s * 0.95)
	return buf

# Gentle pickup chime — two soft sine tones a fifth apart
func _synth_pickup_chime() -> PackedVector2Array:
	var duration := 0.55
	var n := int(SYNTH_RATE * duration)
	var buf := PackedVector2Array()
	buf.resize(n)
	for i in n:
		var t := float(i) / float(SYNTH_RATE)
		var phase := t / duration
		var a := sin(TAU * 660.0 * t) * 0.32 * exp(-t * 4.0)
		var b := sin(TAU * 990.0 * t) * 0.28 * exp(-t * 4.5)
		var env := smoothstep(0.0, 0.02, phase) * smoothstep(1.0, 0.6, phase)
		var s := (a + b) * env
		buf[i] = Vector2(s, s * 0.92)
	return buf

# Shrine charge — soothing rising hum + soft chime
func _synth_shrine_charge() -> PackedVector2Array:
	var duration := 1.5
	var n := int(SYNTH_RATE * duration)
	var buf := PackedVector2Array()
	buf.resize(n)
	for i in n:
		var t := float(i) / float(SYNTH_RATE)
		var phase := t / duration
		var f := lerpf(180.0, 220.0, phase)
		var hum := sin(TAU * f * t) * 0.30 + sin(TAU * f * 2.0 * t) * 0.18
		var bell := sin(TAU * 880.0 * t) * 0.18 * exp(-(phase - 0.3) * 2.5)
		if phase < 0.3:
			bell = 0.0
		var env := smoothstep(0.0, 0.18, phase) * smoothstep(1.0, 0.7, phase)
		var s := (hum + bell) * env * 0.55
		buf[i] = Vector2(s, s * 0.95)
	return buf

# Click sounds for flashlight on/off — short noise burst
func _synth_click(duration: float, brighter: bool) -> PackedVector2Array:
	var n := int(SYNTH_RATE * duration)
	var buf := PackedVector2Array()
	buf.resize(n)
	var center_freq := 2200.0 if brighter else 1100.0
	for i in n:
		var t := float(i) / float(SYNTH_RATE)
		var noise := (_rng.randf() * 2.0 - 1.0)
		var pitch := sin(TAU * center_freq * t) * exp(-t * 80.0)
		var s := (noise * 0.45 + pitch * 0.55) * exp(-t * 60.0) * 0.55
		buf[i] = Vector2(s, s)
	return buf

# Battery-low beep — classic 880 Hz tone
func _synth_battery_beep() -> PackedVector2Array:
	var duration := 0.15
	var n := int(SYNTH_RATE * duration)
	var buf := PackedVector2Array()
	buf.resize(n)
	for i in n:
		var t := float(i) / float(SYNTH_RATE)
		var s := sin(TAU * 880.0 * t) * exp(-t * 12.0) * 0.40
		buf[i] = Vector2(s, s)
	return buf

# Jumpscare sting — sub rumble + high screech together, sharp attack
func _synth_jumpscare_sting() -> PackedVector2Array:
	var duration := 0.95
	var n := int(SYNTH_RATE * duration)
	var buf := PackedVector2Array()
	buf.resize(n)
	for i in n:
		var t := float(i) / float(SYNTH_RATE)
		var phase := t / duration
		# Sub rumble (50 Hz fundamental)
		var rumble := sin(TAU * 50.0 * t) * 0.55
		rumble += sin(TAU * 75.0 * t) * 0.25
		# High screech with bend
		var screech_f := 1800.0 - t * 600.0
		var screech := sin(TAU * screech_f * t) * 0.30
		# Noise impact
		var noise := (_rng.randf() * 2.0 - 1.0) * 0.30 * exp(-t * 9.0)
		# Attack envelope
		var env := 1.0
		if phase < 0.02:
			env = phase / 0.02
		else:
			env = exp(-(phase - 0.02) * 3.5)
		var s := (rumble + screech + noise) * env * 0.85
		buf[i] = Vector2(clampf(s * 0.95, -1.0, 1.0), clampf(s, -1.0, 1.0))
	return buf

