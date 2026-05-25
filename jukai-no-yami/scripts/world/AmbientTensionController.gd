extends Node

# ─── Ambient Tension Controller ───────────────────────────────────────────────
# Monitors player-to-stalker distance every 0.4 s and modulates:
#   • Overall ambient volume (ducks when monster is close)
#   • A dedicated tension music layer (rises with proximity)
#   • Heartbeat pulse layer at very close range
# Added automatically by LevelManager._start_common().

const CHECK_INTERVAL    := 0.40
const FAR_THRESHOLD     := 40.0   # Beyond this: no tension effect
const MED_THRESHOLD     := 22.0   # Medium tension
const CLOSE_THRESHOLD   := 12.0   # High tension + heartbeat

const TENSION_PATHS = {
	"tension_low":   "res://audio/ambient/tension_low.ogg",
	"tension_high":  "res://audio/ambient/tension_high.ogg",
	"heartbeat":     "res://audio/ambient/heartbeat.ogg",
}

var _check_timer: float = 0.0
var _stalker: Node       = null
var _player:  Node       = null

var _tension_low:  AudioStreamPlayer = null
var _tension_high: AudioStreamPlayer = null
var _heartbeat:    AudioStreamPlayer = null

var _current_band: int = 0   # 0=far, 1=medium, 2=close, 3=very_close

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_players()

func _build_players() -> void:
	_tension_low  = _make_player("Ambient", -80.0)
	_tension_high = _make_player("Ambient", -80.0)
	_heartbeat    = _make_player("SFX",     -80.0)

func _make_player(bus: String, vol: float) -> AudioStreamPlayer:
	var p = AudioStreamPlayer.new()
	p.bus = bus
	p.volume_db = vol
	add_child(p)
	return p

func _process(delta: float) -> void:
	if GameManager.state != GameManager.GameState.PLAYING:
		return
	_check_timer += delta
	if _check_timer < CHECK_INTERVAL:
		return
	_check_timer = 0.0
	_update_tension()

func _update_tension() -> void:
	_player  = GameManager.player_ref
	_stalker = _find_stalker()

	if not _player or not _stalker:
		_set_band(0)
		return

	# Only react when stalker is active (not INACTIVE or COOLDOWN)
	var stalker_state = _stalker.state if "state" in _stalker else 0
	# State enum: 0=INACTIVE, 7=COOLDOWN — both mean no tension
	if stalker_state == 0 or stalker_state == 7:
		_set_band(0)
		return

	var dist = _player.global_position.distance_to(_stalker.global_position)

	if dist > FAR_THRESHOLD:
		_set_band(0)
	elif dist > MED_THRESHOLD:
		_set_band(1)
	elif dist > CLOSE_THRESHOLD:
		_set_band(2)
	else:
		_set_band(3)

func _set_band(band: int) -> void:
	if band == _current_band:
		return
	_current_band = band

	match band:
		0:  # Far — silence tension layers
			_fade(_tension_low,  -80.0, 2.5)
			_fade(_tension_high, -80.0, 2.5)
			_fade(_heartbeat,    -80.0, 1.5)
		1:  # Medium — soft low tension
			_ensure_playing(_tension_low, "tension_low")
			_fade(_tension_low,  -18.0, 2.0)
			_fade(_tension_high, -80.0, 1.5)
			_fade(_heartbeat,    -80.0, 1.0)
		2:  # Close — both tension layers
			_ensure_playing(_tension_low,  "tension_low")
			_ensure_playing(_tension_high, "tension_high")
			_fade(_tension_low,  -10.0, 1.5)
			_fade(_tension_high, -18.0, 1.5)
			_fade(_heartbeat,    -80.0, 1.0)
		3:  # Very close — full tension + heartbeat
			_ensure_playing(_tension_low,  "tension_low")
			_ensure_playing(_tension_high, "tension_high")
			_ensure_playing(_heartbeat,    "heartbeat")
			_fade(_tension_low,  -5.0,  1.0)
			_fade(_tension_high, -8.0,  1.0)
			_fade(_heartbeat,    -12.0, 0.8)

func _ensure_playing(player: AudioStreamPlayer, key: String) -> void:
	if player.playing:
		return
	var path = TENSION_PATHS.get(key, "")
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	player.stream = load(path)
	player.play()

func _fade(player: AudioStreamPlayer, target_db: float, time: float) -> void:
	var tween = create_tween()
	tween.tween_property(player, "volume_db", target_db, time)

func _find_stalker() -> Node:
	var stalkers = get_tree().get_nodes_in_group("stalker")
	return stalkers[0] if stalkers.size() > 0 else null
