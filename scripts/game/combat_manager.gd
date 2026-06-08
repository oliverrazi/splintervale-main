extends Node

signal combat_started
signal combat_ended

## Auto-Heal nach Kampfende: wenn HP darunter, sanft hochheilen.
@export var auto_heal_enabled: bool = true
@export_range(0.0, 1.0) var auto_heal_to_percent: float = 0.25
@export var auto_heal_duration: float = 0.8

var _in_combat: bool = false
var _engaged_enemies: Array = []
var _heal_tween: Tween


func _ready() -> void:
	# Auch im Pause-Modus reagierbar (z.B. Kampf-Pause-Fenster soll weiter
	# wissen, dass wir im Kampf sind).
	process_mode = Node.PROCESS_MODE_ALWAYS
	combat_ended.connect(_on_combat_ended_autoheal)


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
## für AI-Coordinator oder UI, die alle Gegner anzeigt.
func get_engaged_enemies() -> Array:
	# is_instance_valid prüfen, falls ein Feind ohne disengage gefreed wurde
	_engaged_enemies = _engaged_enemies.filter(func(e): return is_instance_valid(e))
	return _engaged_enemies.duplicate()


# ---------------------------------------------------------------------
#  Auto-Heal nach Kampfende
# ---------------------------------------------------------------------

func _on_combat_ended_autoheal() -> void:
	if not auto_heal_enabled:
		return
	if GameManager == null or GameManager.player_data == null:
		return
	var pd: PlayerData = GameManager.player_data
	if not pd.is_alive():
		return

	var target: int = int(pd.max_hp * auto_heal_to_percent)
	if pd.current_hp >= target:
		return

	# Sanft hochzaehlen: jeder Tween-Schritt setzt current_hp + emittet
	# hp_changed, sodass HUD und Vignette mitlaufen.
	if _heal_tween and _heal_tween.is_valid():
		_heal_tween.kill()
	var start: int = pd.current_hp
	_heal_tween = create_tween()
	_heal_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_heal_tween.tween_method(
		func(v: float):
			pd.current_hp = int(round(v))
			pd.hp_changed.emit(pd.current_hp, pd.max_hp),
		float(start), float(target), auto_heal_duration)
