extends Node
## Zentraler Musik-Router. Einziger Ort, an dem Musik-AudioStreamPlayer leben.
##
## Prinzip: Requester (Zonen, Boss, Cutscenes) melden einen Wunsch an —
## einen Track mit Owner-Token und Priorität. Der Manager spielt immer den
## Request mit der höchsten Priorität. Fällt der weg, kommt automatisch der
## darunterliegende zurück (z.B. Overworld-Zone nach dem Boss).
##
## Track-Wechsel INNERHALB desselben Owners fallen nie auf einen tieferen
## Layer zurück — dadurch blitzt zwischen Boss-Intro→Boss→Outro nie die
## Zonenmusik durch, auch wenn kurz kein Track anliegt.

const MUSIC_BUS := "Music"
const SILENCE_DB := -80.0

class MusicRequest:
	var owner: String
	var track: AudioStream
	var priority: int
	var crossfade: float
	var silent: bool
	var _pop_pending: bool = false
	func _init(o: String, t: AudioStream, p: int, cf: float, s: bool = false) -> void:
		owner = o
		track = t
		priority = p
		crossfade = cf
		silent = s

var _requests: Array[MusicRequest] = []

var _current_player: AudioStreamPlayer
var _next_player: AudioStreamPlayer
var _tween: Tween

var _active_track: AudioStream = null   # was JETZT tatsächlich läuft


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_current_player = _make_player()
	_next_player = _make_player()


func _make_player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = MUSIC_BUS
	add_child(p)
	return p


# === PUBLIC API ===

func push_music(owner: String, track: AudioStream, priority: int, crossfade: float = 2.0) -> void:
	if track == null:
		return
	var existing := _find_request(owner)
	if existing != null:
		existing.track = track
		existing.priority = priority
		existing.crossfade = crossfade
		existing.silent = false
		existing._pop_pending = false   # ← Pop abbrechen, Owner bleibt
	else:
		_requests.append(MusicRequest.new(owner, track, priority, crossfade))
	_reevaluate()


## Entfernt den Wunsch eines Owners. Danach übernimmt automatisch der
## nächsthöhere Request (oder Stille, wenn keiner mehr da ist).
func pop_music(owner: String, crossfade_override: float = -1.0) -> void:
	# Verzögert poppen: Bei Szenenwechseln poppt die alte Zone, und die neue
	# Zone (gleicher Kontext) pusht im selben oder nächsten Frame wieder.
	# Wir warten einen Frame — wenn der Owner dann noch als "pop-pending"
	# markiert ist (also NICHT neu gepusht wurde), poppen wir wirklich.
	var req := _find_request(owner)
	if req == null:
		return
	req._pop_pending = true
	if crossfade_override >= 0.0:
		req.crossfade = crossfade_override
	_deferred_pop(owner)


func _deferred_pop(owner: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame   # zwei Frames Puffer für Szenenwechsel
	var req := _find_request(owner)
	if req == null:
		return
	if not req._pop_pending:
		return   # wurde zwischenzeitlich neu gepusht → Pop verworfen
	_requests.erase(req)
	_reevaluate()


func has_owner(owner: String) -> bool:
	return _find_request(owner) != null


# === CORE ===

func _find_request(owner: String) -> MusicRequest:
	for r in _requests:
		if r.owner == owner:
			return r
	return null


func _top_request() -> MusicRequest:
	if _requests.is_empty():
		return null
	# Höchste Priorität gewinnt; bei Gleichstand der zuletzt gepushte
	# (stabiler Sort erhält Einfügereihenfolge, wir nehmen den letzten).
	var best := _requests[0]
	for i in range(1, _requests.size()):
		if _requests[i].priority >= best.priority:
			best = _requests[i]
	return best

func push_silence(owner: String, priority: int, fade: float = 1.0) -> void:
	var existing := _find_request(owner)
	if existing != null:
		existing.track = null
		existing.priority = priority
		existing.crossfade = fade
		existing.silent = true
	else:
		_requests.append(MusicRequest.new(owner, null, priority, fade, true))
	_reevaluate()

func _reevaluate() -> void:
	var top := _top_request()
	if top == null:
		_fade_out(2.0)
		return
	if top.silent:
		if _active_track != null:
			_fade_out(top.crossfade)
		return
	if _same_track(top.track, _active_track):
		return   # gleicher Track (auch szenenübergreifend) → weiterlaufen lassen
	_crossfade_to(top.track, top.crossfade)


func _same_track(a: AudioStream, b: AudioStream) -> bool:
	if a == b:
		return true
	if a == null or b == null:
		return false
	# Szenenübergreifend: gleicher Ressourcen-Pfad = gleicher Track,
	# auch wenn es zwei verschiedene Stream-Objekte sind.
	if not a.resource_path.is_empty() and a.resource_path == b.resource_path:
		return true
	return false


func _crossfade_to(track: AudioStream, fade_time: float) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()

	_active_track = track
	_next_player.stream = track
	_next_player.volume_db = SILENCE_DB
	_next_player.play()

	if fade_time <= 0.0:
		_current_player.volume_db = SILENCE_DB
		_next_player.volume_db = 0.0
		_swap_players()
		return

	_tween = create_tween().set_parallel()
	_tween.tween_property(_current_player, "volume_db", SILENCE_DB, fade_time)
	_tween.tween_property(_next_player, "volume_db", 0.0, fade_time)
	_tween.chain().tween_callback(_swap_players)


func _fade_out(fade_time: float) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_active_track = null
	if fade_time <= 0.0:
		_current_player.stop()
		_current_player.stream = null
		return
	var player := _current_player
	_tween = create_tween()
	_tween.tween_property(player, "volume_db", SILENCE_DB, fade_time)
	_tween.tween_callback(func():
		player.stop()
		player.stream = null
	)


func _swap_players() -> void:
	_current_player.stop()
	var temp := _current_player
	_current_player = _next_player
	_next_player = temp


# === PAUSE (unverändert genutzt) ===

func pause_music() -> void:
	_current_player.stream_paused = true
	_next_player.stream_paused = true


func resume_music() -> void:
	_current_player.stream_paused = false
	_next_player.stream_paused = false
