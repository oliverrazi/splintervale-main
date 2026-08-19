extends Node
## CombatManager
##
## Verwaltet den Kampf-State (in_combat + engagierte Gegner) und den
## Safety-Heal: der Spieler wird sanft auf eine Mindest-HP aufgefuellt,
## sobald es "sicher" ist. Sicher = nicht im Kampf und seit kurzem kein
## Schaden mehr eingegangen.
##
## Zwei Ausloeser:
##   1) Kampfende (combat_ended)       -> sofortiger Top-up
##   2) Schaden ausserhalb des Kampfes -> Top-up nach kurzer Ruhephase
##      (z.B. Sturz ins Wasser, Umwelt-Hazard, DoT)

signal combat_started
signal combat_ended

## Safety-Heal aktiv?
@export var auto_heal_enabled: bool = true
## Auf welchen Anteil der max_hp aufgefuellt wird.
@export_range(0.0, 1.0) var auto_heal_to_percent: float = 0.25
## Dauer des Heil-Tweens.
@export var auto_heal_duration: float = 0.8
## Wie lange kein Schaden mehr eingehen darf, bevor der Out-of-Combat-Heal
## startet. Faengt DoT / kontinuierlichen Umweltschaden sauber ab: solange
## Schaden reinkommt, wird der Timer neu gestartet, geheilt wird erst in der
## Ruhephase danach.
@export var auto_heal_delay: float = 0.4

var _in_combat: bool = false
var _engaged_enemies: Array = []

var _heal_tween: Tween
var _heal_delay_timer: Timer
var _bound_pd: PlayerData = null
var _last_hp: int = -1

func _ready() -> void:
	# Auch im Pause-Modus reagierbar (z.B. Kampf-Pause-Fenster soll weiter
	# wissen, dass wir im Kampf sind).
	process_mode = Node.PROCESS_MODE_ALWAYS
	combat_ended.connect(_on_combat_ended_autoheal)

	# Debounce-Timer fuer den Out-of-Combat-Heal.
	_heal_delay_timer = Timer.new()
	_heal_delay_timer.one_shot = true
	_heal_delay_timer.timeout.connect(_on_heal_delay_timeout)
	add_child(_heal_delay_timer)

	# Falls player_data schon existiert, direkt binden. Wird sie erst spaeter
	# (Neues Spiel / Load) erzeugt, muss dort bind_player_data() gerufen werden.
	_try_auto_bind.call_deferred()

# ---------------------------------------------------------------------
#  Manuelle API – wenn du den State direkt setzen willst
# ---------------------------------------------------------------------
func start_combat() -> void:
	if _in_combat:
		return
	_in_combat = true
	combat_started.emit()

func end_combat() -> void:
	if not _in_combat:
		return
	_in_combat = false
	_engaged_enemies.clear()
	combat_ended.emit()

func is_in_combat() -> bool:
	return _in_combat

# ---------------------------------------------------------------------
#  Enemy-Tracking – komfortabler, automatisch
# ---------------------------------------------------------------------
#
# In eurem Enemy-Script:
#   func _on_player_detected(): CombatManager.engage_enemy(self)
#   func _on_died():           CombatManager.disengage_enemy(self)
#
# Sobald der erste Feind sich engagiert, startet Combat automatisch.
# Sobald der letzte Feind raus ist, endet Combat automatisch.
func engage_enemy(enemy: Node) -> void:
	if enemy == null:
		return
	if not _engaged_enemies.has(enemy):
		_engaged_enemies.append(enemy)
	if not _in_combat:
		start_combat()

func disengage_enemy(enemy: Node) -> void:
	_engaged_enemies.erase(enemy)
	if _engaged_enemies.is_empty() and _in_combat:
		end_combat()

## Liste aller aktuell engagierten Feinde (Kopie). Praktisch z.B.
## fuer AI-Coordinator oder UI, die alle Gegner anzeigt.
func get_engaged_enemies() -> Array:
	# is_instance_valid pruefen, falls ein Feind ohne disengage gefreed wurde
	_engaged_enemies = _engaged_enemies.filter(func(e): return is_instance_valid(e))
	return _engaged_enemies.duplicate()

# ---------------------------------------------------------------------
#  PlayerData-Bindung (fuer Out-of-Combat-Heal)
# ---------------------------------------------------------------------
## Muss aufgerufen werden, wenn player_data erzeugt oder ausgetauscht wird
## (Neues Spiel, Load). Verbindet den hp_changed-Listener neu.
func bind_player_data(pd: PlayerData) -> void:
	if pd == _bound_pd:
		return
	if _bound_pd != null and _bound_pd.hp_changed.is_connected(_on_player_hp_changed):
		_bound_pd.hp_changed.disconnect(_on_player_hp_changed)
	_bound_pd = pd
	if pd != null and not pd.hp_changed.is_connected(_on_player_hp_changed):
		pd.hp_changed.connect(_on_player_hp_changed)
		_last_hp = pd.current_hp

func _try_auto_bind() -> void:
	if _bound_pd == null and GameManager != null and GameManager.player_data != null:
		bind_player_data(GameManager.player_data)

# ---------------------------------------------------------------------
#  Safety-Heal
# ---------------------------------------------------------------------
func _on_player_hp_changed(current: int, _max: int) -> void:
	# Nur auf SCHADEN reagieren. Der Heil-Tween erhoeht HP und emittet
	# ebenfalls hp_changed – das ignorieren wir, sonst gaebe es eine Schleife.
	var decreased := current < _last_hp
	_last_hp = current
	if not decreased:
		return
	if not auto_heal_enabled or _in_combat:
		return
	# Schaden waehrend eines laufenden Out-of-Combat-Heals: Heal abbrechen,
	# damit der Schaden wirklich zaehlt, danach sauber neu aufbauen.
	if _heal_tween and _heal_tween.is_valid():
		_heal_tween.kill()
	# Solange Schaden reinkommt neu starten -> geheilt wird erst in Ruhe.
	_heal_delay_timer.start(auto_heal_delay)

func _on_heal_delay_timeout() -> void:
	_start_safety_heal()

func _on_combat_ended_autoheal() -> void:
	# Kampf vorbei -> sofort auffuellen (keine Ruhephase noetig).
	_start_safety_heal()

func _start_safety_heal() -> void:
	if not auto_heal_enabled or _in_combat:
		return
	if _bound_pd == null:
		_try_auto_bind()
	var pd: PlayerData = _bound_pd
	if pd == null or not pd.is_alive():
		return
	var target: int = int(pd.max_hp * auto_heal_to_percent)
	if pd.current_hp >= target:
		return
	# Sanft hochzaehlen: jeder Tween-Schritt setzt current_hp + emittet
	# hp_changed, sodass HUD und Vignette mitlaufen.
	if _heal_tween and _heal_tween.is_valid():
		_heal_tween.kill()
	var start_hp: int = pd.current_hp
	_heal_tween = create_tween()
	_heal_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_heal_tween.tween_method(
		func(v: float):
			var hp: int = int(round(v))
			pd.current_hp = hp
			_last_hp = hp  # eigenen Heal-Tick vor dem emit "neutralisieren"
			pd.hp_changed.emit(pd.current_hp, pd.max_hp),
		float(start_hp), float(target), auto_heal_duration)
