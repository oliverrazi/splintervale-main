extends Resource
class_name PlayerData

signal hp_changed(current: int, maximum: int)
signal resonance_changed(current: int, maximum: int)
signal exp_changed(current: int, needed: int)
signal level_changed(new_level: int)
signal gold_changed(amount: int)
signal stats_changed()
signal stat_points_changed(points: int)
signal skill_points_changed(points: int)

# === LEVEL & EXP ===
@export var level: int = 1
@export var current_exp: int = 0
@export var exp_to_next_level: int = 30

# === UNSPENT POINTS ===
@export var stat_points: int = 0
@export var skill_points: int = 0

# === RESOURCES ===
@export var current_hp: int = 60
@export var max_hp: int = 60
@export var current_resonance: float  = 30.0
@export var max_resonance: float = 30.0

# === BASE STATS (vom Spieler verteilt) ===
@export var base_vitality: int = 6       # Beeinflusst max_hp
@export var base_strength: int = 3       # Beeinflusst Schaden
@export var base_attunement: int = 3      # Beeinflusst max_resonance
@export var base_attack_speed: int = 3   # Beeinflusst Angriffsgeschwindigkeit

@export var resonance_regen_rate: float = 20.0      # Resonance pro Sekunde
@export var resonance_regen_delay: float = 1.5  

# === GOLD ===
@export var gold: int = 0

# === STAT MULTIPLIERS ===
const HP_PER_VITALITY: int = 10
const RESONANCE_PER_ATTUNEMENT: int = 10
const DAMAGE_PER_STRENGTH: float = 0.5
const ATTACK_SPEED_PER_POINT: float = 0.05  # 5% schneller pro Punkt

# === EXP CURVE ===
const BASE_EXP_REQUIREMENT: int = 30
const EXP_GROWTH_RATE: float = 1.8

var _resonance_regen_timer: float = 0.0

func _init() -> void:
	recalculate_stats()


# ============ STAT CALCULATIONS ============

func recalculate_stats() -> void:
	var old_max_hp := max_hp
	var old_max_resonance := max_resonance
	
	max_hp = base_vitality * HP_PER_VITALITY
	max_resonance = base_attunement * RESONANCE_PER_ATTUNEMENT
	
	# HP proportional anpassen wenn max_hp sich ändert
	if old_max_hp > 0:
		var hp_ratio := float(current_hp) / float(old_max_hp)
		current_hp = int(hp_ratio * max_hp)
	else:
		current_hp = max_hp
	
	# Resonance proportional anpassen
	if old_max_resonance > 0:
		var resonance_ratio := float(current_resonance) / float(old_max_resonance)
		current_resonance = int(resonance_ratio * max_resonance)
	else:
		current_resonance = max_resonance
	
	exp_to_next_level = calculate_exp_for_level(level + 1)
	
	stats_changed.emit()


func calculate_exp_for_level(target_level: int) -> int:
	return int(BASE_EXP_REQUIREMENT * pow(EXP_GROWTH_RATE, target_level - 2))


func get_attack_damage(base_damage: int) -> int:
	var bonus := int(base_damage * base_strength * DAMAGE_PER_STRENGTH)
	return base_damage + bonus


func get_attack_speed_multiplier() -> float:
	# Basis 1.0, wird schneller mit mehr Punkten
	return 1.0 + (base_attack_speed * ATTACK_SPEED_PER_POINT)

func process_regeneration(delta: float) -> void:#
	if _resonance_regen_timer > 0.0:
		_resonance_regen_timer -= delta
		return
	if current_resonance < max_resonance:
		var regen_amount: float = resonance_regen_rate * delta
		current_resonance = min(max_resonance, current_resonance + regen_amount)
		# Signal nur bei ganzzahligen Änderungen für Performance
		resonance_changed.emit(int(current_resonance), max_resonance)

# ============ STAT POINT ALLOCATION ============

func can_spend_stat_point() -> bool:
	return stat_points > 0


func spend_stat_point_vitality() -> bool:
	if not can_spend_stat_point():
		return false
	
	stat_points -= 1
	base_vitality += 1
	recalculate_stats()
	stat_points_changed.emit(stat_points)
	hp_changed.emit(current_hp, max_hp)
	return true


func spend_stat_point_strength() -> bool:
	if not can_spend_stat_point():
		return false
	
	stat_points -= 1
	base_strength += 1
	recalculate_stats()
	stat_points_changed.emit(stat_points)
	return true


func spend_stat_point_attunement() -> bool:
	if not can_spend_stat_point():
		return false
	
	stat_points -= 1
	base_attunement += 1
	recalculate_stats()
	stat_points_changed.emit(stat_points)
	resonance_changed.emit(current_resonance, max_resonance)
	return true


func spend_stat_point_attack_speed() -> bool:
	if not can_spend_stat_point():
		return false
	
	stat_points -= 1
	base_attack_speed += 1
	recalculate_stats()
	stat_points_changed.emit(stat_points)
	return true


# ============ HP ============

func take_damage(amount: int) -> void:
	current_hp = max(0, current_hp - amount)
	hp_changed.emit(current_hp, max_hp)


func heal(amount: int) -> void:
	current_hp = min(max_hp, current_hp + amount)
	hp_changed.emit(current_hp, max_hp)


func heal_full() -> void:
	current_hp = max_hp
	current_resonance = max_resonance
	hp_changed.emit(current_hp, max_hp)
	resonance_changed.emit(current_resonance, max_resonance)


func is_alive() -> bool:
	return current_hp > 0


# ============ RESONANCE ============

func use_resonance(amount: int) -> bool:

	if current_resonance >= amount:
		current_resonance -= amount
		_resonance_regen_timer = resonance_regen_delay  # Regen-Verzögerung starten
		resonance_changed.emit(int(current_resonance), max_resonance)
		return true
	return false


func restore_resonance(amount: int) -> void:
	current_resonance = min(max_resonance, current_resonance + amount)
	resonance_changed.emit(current_resonance, max_resonance)


# ============ EXP & LEVELING ============

func add_exp(amount: int) -> void:
	current_exp += amount
	exp_changed.emit(current_exp, exp_to_next_level)
	
	# Level Up Check
	while current_exp >= exp_to_next_level:
		_level_up()


func _level_up() -> void:
	current_exp -= exp_to_next_level
	level += 1
	
	# Punkte vergeben statt automatischer Stat-Erhöhung
	stat_points += 1
	skill_points += 1
	
	# EXP für nächstes Level berechnen
	exp_to_next_level = calculate_exp_for_level(level + 1)
	
	# Voll heilen bei Level Up
	current_hp = max_hp
	current_resonance = max_resonance
	
	# Signals
	level_changed.emit(level)
	hp_changed.emit(current_hp, max_hp)
	resonance_changed.emit(current_resonance, max_resonance)
	exp_changed.emit(current_exp, exp_to_next_level)
	stat_points_changed.emit(stat_points)
	skill_points_changed.emit(skill_points)
	
	print("=== LEVEL UP! ===")
	print("Level: ", level)
	print("Stat Points: ", stat_points, " | Skill Points: ", skill_points)


# ============ GOLD ============

func add_gold(amount: int) -> void:
	gold += amount
	gold_changed.emit(gold)


func spend_gold(amount: int) -> bool:
	if gold >= amount:
		gold -= amount
		gold_changed.emit(gold)
		return true
	return false


# ============ SAVE / LOAD ============

func to_dict() -> Dictionary:
	return {
		"level": level,
		"current_exp": current_exp,
		"current_hp": current_hp,
		"current_resonance": current_resonance,
		"resonance_regen_rate": resonance_regen_rate,
		"resonance_regen_delay": resonance_regen_delay,
		"base_vitality": base_vitality,
		"base_strength": base_strength,
		"base_attunement": base_attunement,
		"base_attack_speed": base_attack_speed,
		"stat_points": stat_points,
		"skill_points": skill_points,
		"gold": gold
	}


func from_dict(data: Dictionary) -> void:
	level = data.get("level", 1)
	current_exp = data.get("current_exp", 0)
	resonance_regen_rate = data.get("resonance_regen_rate", 5.0)
	resonance_regen_delay = data.get("resonance_regen_delay", 1.5)
	base_vitality = data.get("base_vitality", 6)
	base_strength = data.get("base_strength", 3)
	base_attunement = data.get("base_attunement", 3)
	base_attack_speed = data.get("base_attack_speed", 3)
	stat_points = data.get("stat_points", 0)
	skill_points = data.get("skill_points", 0)
	gold = data.get("gold", 0)
	
	recalculate_stats()
	
	current_hp = data.get("current_hp", max_hp)
	current_resonance = data.get("current_resonance", max_resonance)
