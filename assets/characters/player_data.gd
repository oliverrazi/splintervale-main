extends Resource
class_name PlayerData

signal hp_changed(current: int, maximum: int)
signal exp_changed(current: int, needed: int)
signal level_changed(new_level: int)
signal gold_changed(amount: int)
signal stats_changed()

# === LEVEL & EXP ===
@export var level: int = 1
@export var current_exp: int = 0
@export var exp_to_next_level: int = 30

# === RESOURCES ===
@export var current_hp: int = 60
@export var max_hp: int = 60
@export var current_mp: int = 30
@export var max_mp: int = 30
@export var current_stamina: int = 30
@export var max_stamina: int = 30

# === BASE STATS ===
@export var base_health: int = 6      # Beeinflusst max_hp
@export var base_magic: int = 3        # Beeinflusst max_mp
@export var base_strength: int = 3     # Beeinflusst Schaden
@export var base_defense: int = 3     # Reduziert eingehenden Schaden
@export var base_endurance: int = 3    # Beeinflusst max_stamina

# === GOLD ===
@export var gold: int = 0

# === STAT GROWTH PER LEVEL ===
const HEALTH_PER_LEVEL: int = 3
const MAGIC_PER_LEVEL: int = 2
const STRENGTH_PER_LEVEL: int = 1
const DEFENSE_PER_LEVEL: int = 1
const ENDURANCE_PER_LEVEL: int = 1

# === STAT MULTIPLIERS ===
const HP_PER_HEALTH: int = 10
const MP_PER_MAGIC: int = 10
const STAMINA_PER_ENDURANCE: int = 10
const DAMAGE_PER_STRENGTH: float = 0.5
const DAMAGE_REDUCTION_PER_DEFENSE: float = 0.02  # 2% pro Punkt

# === EXP CURVE ===
const BASE_EXP_REQUIREMENT: int = 30
const EXP_GROWTH_RATE: float = 1.8


func _init() -> void:
	recalculate_stats()


# ============ STAT CALCULATIONS ============

func recalculate_stats() -> void:
	var old_max_hp := max_hp
	var old_max_mp := max_mp
	var old_max_stamina := max_stamina
	
	max_hp = base_health * HP_PER_HEALTH
	max_mp = base_magic * MP_PER_MAGIC
	max_stamina = base_endurance * STAMINA_PER_ENDURANCE
	
	# HP proportional anpassen wenn max_hp sich ändert
	if old_max_hp > 0:
		var hp_ratio := float(current_hp) / float(old_max_hp)
		current_hp = int(hp_ratio * max_hp)
	else:
		current_hp = max_hp
	
	# MP proportional anpassen
	if old_max_mp > 0:
		var mp_ratio := float(current_mp) / float(old_max_mp)
		current_mp = int(mp_ratio * max_mp)
	else:
		current_mp = max_mp
	
	# Stamina proportional anpassen
	if old_max_stamina > 0:
		var stamina_ratio := float(current_stamina) / float(old_max_stamina)
		current_stamina = int(stamina_ratio * max_stamina)
	else:
		current_stamina = max_stamina
	
	exp_to_next_level = calculate_exp_for_level(level + 1)
	
	stats_changed.emit()


func calculate_exp_for_level(target_level: int) -> int:
	return int(BASE_EXP_REQUIREMENT * pow(EXP_GROWTH_RATE, target_level - 2))


func get_attack_damage(base_damage: int) -> int:
	var bonus := int(base_damage * base_strength * DAMAGE_PER_STRENGTH)
	return base_damage + bonus


func get_damage_reduction() -> float:
	return clamp(base_defense * DAMAGE_REDUCTION_PER_DEFENSE, 0.0, 0.8)  # Max 80% Reduktion


func calculate_incoming_damage(raw_damage: int) -> int:
	var reduction := get_damage_reduction()
	return max(1, int(raw_damage * (1.0 - reduction)))


# ============ HP ============

func take_damage(amount: int) -> void:
	var actual_damage := calculate_incoming_damage(amount)
	current_hp = max(0, current_hp - actual_damage)
	hp_changed.emit(current_hp, max_hp)


func heal(amount: int) -> void:
	current_hp = min(max_hp, current_hp + amount)
	hp_changed.emit(current_hp, max_hp)


func heal_full() -> void:
	current_hp = max_hp
	current_mp = max_mp
	current_stamina = max_stamina
	hp_changed.emit(current_hp, max_hp)


func is_alive() -> bool:
	return current_hp > 0


# ============ EXP & LEVELING ============

func add_exp(amount: int) -> void:
	current_exp += amount
	exp_changed.emit(current_exp, exp_to_next_level)
	
	print("current",current_exp, "NEXT",exp_to_next_level)
	# Level Up Check
	while current_exp >= exp_to_next_level:
		_level_up()


func _level_up() -> void:
	current_exp -= exp_to_next_level
	level += 1
	
	# Stats erhöhen
	base_health += HEALTH_PER_LEVEL
	base_magic += MAGIC_PER_LEVEL
	base_strength += STRENGTH_PER_LEVEL
	base_defense += DEFENSE_PER_LEVEL
	base_endurance += ENDURANCE_PER_LEVEL
	
	# Neu berechnen (heilt auch voll)
	recalculate_stats()
	
	# Voll heilen bei Level Up
	current_hp = max_hp
	current_mp = max_mp
	current_stamina = max_stamina
	
	level_changed.emit(level)
	hp_changed.emit(current_hp, max_hp)
	exp_changed.emit(current_exp, exp_to_next_level)
	
	print("=== LEVEL UP! ===")
	print("Level: ", level)
	print("HP: ", max_hp, " | MP: ", max_mp, " | Stamina: ", max_stamina)
	print("STR: ", base_strength, " | DEF: ", base_defense)


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
		"current_mp": current_mp,
		"current_stamina": current_stamina,
		"base_health": base_health,
		"base_magic": base_magic,
		"base_strength": base_strength,
		"base_defense": base_defense,
		"base_endurance": base_endurance,
		"gold": gold
	}


func from_dict(data: Dictionary) -> void:
	level = data.get("level", 1)
	current_exp = data.get("current_exp", 0)
	base_health = data.get("base_health", 10)
	base_magic = data.get("base_magic", 5)
	base_strength = data.get("base_strength", 5)
	base_defense = data.get("base_defense", 5)
	base_endurance = data.get("base_endurance", 5)
	gold = data.get("gold", 0)
	
	recalculate_stats()
	
	current_hp = data.get("current_hp", max_hp)
	current_mp = data.get("current_mp", max_mp)
	current_stamina = data.get("current_stamina", max_stamina)
