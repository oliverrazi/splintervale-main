extends Node
class_name SynergyManager

## Verwaltet das Overheat- und Combo-System für Synergie-Moves.
##
## Mechaniken:
## - Combo wird nur durch Variation erhöht (frische Synergie = +1)
## - Combo wird nur registriert, wenn die Synergie auch trifft
## - Folge-Hits derselben Synergie refreshen nur den Combo-Timer
## - Direkte Wiederholung (A→A): 0.50x, dann Overheat
## - In History (A→B→A oder A→wait→A): 0.85x, Combo-Reset
## - History ist zeitbasiert pro Eintrag (10s default)
## - Combo verfällt nach 5s ohne Hit
## - Heat decayt nach 3s Delay nach letzter Synergie

signal heat_changed(heat: float, max_heat: float)
signal overheat_started(duration: float)
signal overheat_ended()
signal combo_changed(combo: int, multiplier: float)
signal synergy_blocked(synergy_id: String, reason: int)

# === HEAT SYSTEM ===
@export_group("Heat")
@export var max_heat: float = 100.0
@export var heat_decay_per_second: float = 8.0
@export var heat_decay_delay: float = 3.0          ## Sekunden nach Synergie-Hit, bevor Decay startet
@export var heat_for_variation_early: float = 10.0  ## Combo 2-3
@export var heat_for_variation_late: float = 5.0    ## Combo 4+
@export var heat_for_history_repeat: float = 40.0   ## A→B→A
@export var heat_for_direct_repeat: float = 100.0   ## A→A → Overheat

# === COMBO MEMORY ===
@export_group("Combo Memory")
@export var combo_memory_duration: float = 5.0     ## Sekunden bis Combo verfällt
@export var combo_normal_hit_floor: float = 2.0
@export var history_entry_duration: float = 10.0   ## Sekunden bis ein History-Eintrag verschwindet

# === OVERHEAT ===
@export_group("Overheat")
@export var overheat_duration: float = 12.0

# === HISTORY ===
@export_group("History")
@export var history_size: int = 7

# === MULTIPLIERS ===
@export_group("Multipliers")
@export var multiplier_combo_1: float = 1.00
@export var multiplier_combo_2: float = 1.10
@export var multiplier_combo_3: float = 1.20
@export var multiplier_combo_4: float = 1.25
@export var multiplier_combo_5plus: float = 1.30
@export var multiplier_combo_cap: float = 1.35
@export var multiplier_history_repeat: float = 0.85
@export var multiplier_direct_repeat: float = 0.50


# === RUNTIME STATE ===
var _heat: float = 0.0
var _is_overheating: bool = false
var _overheat_remaining: float = 0.0
var _combo_count: int = 0
var _combo_timer: float = 0.0           ## Wie lange noch bis Combo verfällt
var _heat_decay_delay_remaining: float = 0.0  ## Noch verbleibende Verzögerung bis Decay startet

var _is_in_penalty: bool = false
var _penalty_multiplier: float = 1.0

## History speichert Synergie-IDs MIT verbleibender Zeit (in Sekunden).
## Format: [{"id": String, "time_left": float}, ...] — neueste am Ende.
var _history: Array[Dictionary] = []


func _process(delta: float) -> void:
	if _is_overheating:
		_overheat_remaining -= delta
		if _overheat_remaining <= 0.0:
			_end_overheat()
		return
	
	# History-Einträge timer-basiert ablaufen lassen
	var history_changed: bool = false
	for i in range(_history.size() - 1, -1, -1):
		_history[i]["time_left"] -= delta
		if _history[i]["time_left"] <= 0.0:
			_history.remove_at(i)
			history_changed = true
	
	# Combo-Timer ticken
	if _combo_count > 0:
		_combo_timer -= delta
		if _combo_timer <= 0.0:
			_combo_count = 0
			_is_in_penalty = false
			_penalty_multiplier = 1.0
			combo_changed.emit(_combo_count, 1.0)
	
	# Heat-Decay-Delay
	if _heat_decay_delay_remaining > 0.0:
		_heat_decay_delay_remaining -= delta
	elif _heat > 0.0:
		# Decay läuft erst nachdem die Verzögerung abgelaufen ist
		_heat = max(0.0, _heat - heat_decay_per_second * delta)
		heat_changed.emit(_heat, max_heat)


# ============================================
# PUBLIC API
# ============================================

func register_synergy_hit(projected_combo: int, projected_multiplier: float) -> void:
	if _is_overheating:
		return
	
	_combo_count = projected_combo
	_combo_timer = combo_memory_duration
	combo_changed.emit(_combo_count, projected_multiplier)

func register_synergy_use(synergy_id: String) -> SynergyResult:
	var result := SynergyResult.new()
	
	if _is_overheating:
		result.allowed = false
		result.reason = SynergyResult.Reason.BLOCKED_OVERHEAT
		result.combo_count = _combo_count
		synergy_blocked.emit(synergy_id, result.reason)
		return result
	
	var direct_repeat: bool = not _history.is_empty() and _history[-1]["id"] == synergy_id
	var in_history: bool = _is_in_history(synergy_id)
	
	# Heat-Decay zurücksetzen — Spieler ist aktiv
	_heat_decay_delay_remaining = heat_decay_delay
	
	if direct_repeat:
		# A → A: Heat sofort voll, Overheat triggert
		result.allowed = true
		result.damage_multiplier = multiplier_direct_repeat
		result.reason = SynergyResult.Reason.DIRECT_REPEAT
		result.triggered_overheat = true
		_add_heat(heat_for_direct_repeat)
		# History reset auf [A] — wir merken uns nur die aktuelle Synergie
		_history.clear()
		_history.append({"id": synergy_id, "time_left": history_entry_duration})
		result.combo_count = 1
		
		_is_in_penalty = true
		_penalty_multiplier = multiplier_direct_repeat
		_combo_count = 1
		_combo_timer = combo_memory_duration
		
		# Bei A→A: UI sofort updaten (siehe Patch von gestern wegen Overheat-Block)
		combo_changed.emit(_combo_count, multiplier_direct_repeat)
	elif in_history:
		# A → B → A: Heat-Penalty, Combo wird beim Hit auf 1 gesetzt
		result.allowed = true
		result.damage_multiplier = multiplier_history_repeat
		result.reason = SynergyResult.Reason.REPEAT_IN_HISTORY
		_add_heat(heat_for_history_repeat)
		_history.clear()
		_history.append({"id": synergy_id, "time_left": history_entry_duration})
		result.combo_count = 1
		
		# Penalty-State aktivieren
		_is_in_penalty = true
		_penalty_multiplier = multiplier_history_repeat
	else:
		# Frische Variation
		_is_in_penalty = false
		_penalty_multiplier = 1.0
		
		var projected_combo: int = _combo_count + 1
		result.allowed = true
		result.damage_multiplier = _get_multiplier_for_combo(projected_combo)
		result.combo_count = projected_combo
		
		if projected_combo == 1:
			result.reason = SynergyResult.Reason.FRESH
			_add_heat(heat_for_variation_early)
		else:
			result.reason = SynergyResult.Reason.VARIATION
			var heat_inc: float = heat_for_variation_early if projected_combo <= 3 else heat_for_variation_late
			_add_heat(heat_inc)
		
		_history.append({"id": synergy_id, "time_left": history_entry_duration})
		while _history.size() > history_size:
			_history.pop_front()
	
	return result


## Wird vom Component aufgerufen, wenn ein WEITERER Hit derselben Synergie trifft
## (also nicht der erste). Refresht nur den Combo-Timer, ändert keinen anderen State.
func refresh_combo_timer() -> void:
	if _is_overheating:
		return
	if _combo_count <= 0:
		return
	_combo_timer = combo_memory_duration
	# Heat-Decay auch refreshen — Spieler ist aktiv
	_heat_decay_delay_remaining = heat_decay_delay


## Aktueller Multiplier basierend auf Combo-Stand (für UI).
func get_current_multiplier() -> float:
	if _combo_count == 0:
		return 1.0
	return _get_multiplier_for_combo(_combo_count)


func get_heat_normalized() -> float:
	return _heat / max_heat


func is_overheating() -> bool:
	return _is_overheating


func get_overheat_remaining() -> float:
	return _overheat_remaining if _is_overheating else 0.0


func get_combo_count() -> int:
	return _combo_count


# ============================================
# INTERNAL
# ============================================

func _is_in_history(synergy_id: String) -> bool:
	for entry in _history:
		if entry["id"] == synergy_id:
			return true
	return false


func _remove_history_entry(synergy_id: String) -> void:
	for i in range(_history.size() - 1, -1, -1):
		if _history[i]["id"] == synergy_id:
			_history.remove_at(i)
			return  # Es kann nur einen geben (Duplikate verhindern wir beim Append)


func _get_multiplier_for_combo(combo: int) -> float:
	match combo:
		1: return multiplier_combo_1
		2: return multiplier_combo_2
		3: return multiplier_combo_3
		4: return multiplier_combo_4
		5: return multiplier_combo_5plus
		_: return multiplier_combo_cap


func _add_heat(amount: float) -> void:
	if _is_overheating:
		return
	
	_heat = min(max_heat, _heat + amount)
	heat_changed.emit(_heat, max_heat)
	
	if _heat >= max_heat:
		_start_overheat()


func _start_overheat() -> void:
	_is_overheating = true
	_overheat_remaining = overheat_duration
	overheat_started.emit(overheat_duration)


func _end_overheat() -> void:
	_is_overheating = false
	_overheat_remaining = 0.0
	_heat = 0.0
	_history.clear()
	_combo_count = 0
	_combo_timer = 0.0
	_heat_decay_delay_remaining = 0.0
	_is_in_penalty = false
	_penalty_multiplier = 1.0
	overheat_ended.emit()
	heat_changed.emit(_heat, max_heat)
	combo_changed.emit(_combo_count, 1.0)
	
func extend_combo_on_normal_hit() -> void:
	if _is_overheating:
		return
	if _combo_count <= 0:
		return
	if _is_in_penalty:
		return
	print(_combo_count)
	_combo_timer = max(_combo_timer, combo_normal_hit_floor)


func get_damage_multiplier_for_external_hit() -> float:
	if _is_in_penalty:
		return _penalty_multiplier
	if _is_overheating:
		return 1.0
	if _combo_count <= 0:
		return 1.0
	return _get_multiplier_for_combo(_combo_count)
