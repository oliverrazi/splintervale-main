extends Node
class_name SynergyManager

## Synergy Flow / Resonance Chain
##
## Grundprinzip:
##   Wiederholung ist IMMER erlaubt. Variation wird über die RP-Ökonomie belohnt.
##
## Der Manager ist das ÖKONOMIE-HIRN und rein rechnend:
##   - Er zieht selbst KEIN RP ab und gutschreibt selbst KEIN RP.
##   - Kosten (Surcharge) zieht die Component beim Cast selbst ab.
##   - Refunds meldet der Manager per Signal (resonance_refunded) → der Player
##     schreibt gut und zeigt "+N RP" über Daryn.
##
## Drei gekoppelte Kurven, alle von der Combo getrieben:
##   Multiplier : 1.0 + mult_per_combo × (combo-1)      (Cap)   → immer steigend
##   Surcharge  : synergy_surcharge × combo_position             → immer steigend
##   Refund     : refund_base(distinct) × (1 + flow × (combo-1)) → Combo × Vielfalt
##
## Das Wettrennen: Wiederholung (distinct=1) → Refund ~0, Surcharge läuft weg
## → man trocknet aus. Variation (hohes distinct) → Refund überholt die Surcharge
## → Chain hält länger.

# ─── Signals ───

## Combo/Multiplier/Memory haben sich geändert (Commit oder Reset).
## memory ist eine Kopie der aktuellen ID-Reihenfolge (ältestes zuerst) für die Icon-Reihe.
signal chain_changed(combo: int, multiplier: float, memory: Array)

## Ein Variations-Refund wurde gewährt. Der Player schreibt gut + zeigt Popup.
signal resonance_refunded(amount: int)


# ══════════════════════════════════════════════════════════════
#  EXPORTS — MULTIPLIER
# ══════════════════════════════════════════════════════════════
@export_group("Multiplier")
## Zuwachs pro Combo-Stufe (0.03 = +3% je Combo). Steigt bei JEDER Synergie,
## egal ob Wiederholung oder Variation.
@export var multiplier_per_combo: float = 0.03
## Obergrenze des Multipliers.
@export var multiplier_cap: float = 2.0


# ══════════════════════════════════════════════════════════════
#  EXPORTS — KOSTEN (SURCHARGE)
# ══════════════════════════════════════════════════════════════
@export_group("Cost Surcharge")
## Zusatzkosten pro Chain-Position, linear. Erster Cast einer Chain: +0,
## dann +surcharge, +2×surcharge, … (das Relikt-Fixum zahlt die Component separat).
@export var synergy_surcharge: float = 3.0


# ══════════════════════════════════════════════════════════════
#  EXPORTS — REFUND (VARIATIONS-BELOHNUNG)
# ══════════════════════════════════════════════════════════════
@export_group("Refund")
## Wie viele Synergien im Erinnerungsfenster liegen. Größer = breiteres Kit
## nötig, um hohe Vielfalt zu erreichen. Demo hat effektiv 4 Synergien.
@export var memory_size: int = 8
## Basis-Refund pro distinct-Wert (Index = Anzahl UNTERSCHIEDLICHER Synergien
## im Fenster). Index 1 = reine Wiederholung (A→A→A) → 0. Index 2 = A→B (der
## "gute Variation"-Wechsel der Demo). Index 4 = A→B→C→D (großer Payoff).
## Wird bei Bedarf am oberen Ende geklemmt.
@export var refund_per_distinct: Array[float] = [
	0.0,   # distinct 0 (kommt bei aktiver Chain nicht vor)
	0.0,   # distinct 1 — reine Wiederholung: kein Refund
	6.0,   # distinct 2 — A→B
	12.0,  # distinct 3 — A→B→C
	20.0,  # distinct 4 — A→B→C→D
	26.0,  # distinct 5
	30.0,  # distinct 6
	34.0,  # distinct 7
	38.0,  # distinct 8
]
## Wie stark die Combo den Refund zusätzlich verstärkt (0.15 = +15% je Combo-Stufe).
## Sorgt für die Eskalation +5 → +8 → +12 → +20 bei längeren Chains.
@export var refund_flow_growth: float = 0.15


# ══════════════════════════════════════════════════════════════
#  EXPORTS — TIMER (CHAIN-LEBENSDAUER)
# ══════════════════════════════════════════════════════════════
@export_group("Chain Timer")
## Volle Chain-Zeit. Jeder Synergie-Treffer setzt den Timer hierauf zurück.
@export var chain_duration: float = 4.0
## Zeit, die ein NORMALER Treffer dem Timer gibt (gedeckelt auf chain_duration).
## Überbrückt die Setup-Lücken zwischen zwei Synergien.
@export var normal_hit_time_bonus: float = 0.4
## Zeit, die abgezogen wird, wenn der PLAYER getroffen wird.
@export var player_hit_time_penalty: float = 1.5


# ══════════════════════════════════════════════════════════════
#  EXPORTS — DEBUG
# ══════════════════════════════════════════════════════════════
@export_group("Debug")
## Prints an Cast/Commit/Refund/Reset. Zum Validieren an, danach aus.
@export var debug_prints: bool = true


# ══════════════════════════════════════════════════════════════
#  RUNTIME STATE
# ══════════════════════════════════════════════════════════════
var _combo_count: int = 0                 ## Chain-Position / Flow-Wert
var _timer: float = 0.0                   ## Verbleibende Chain-Zeit
var _multiplier: float = 1.0              ## Gehaltener Multiplier (fällt erst bei Reset)
var _memory: Array[String] = []           ## Ring-Buffer der IDs, ältestes zuerst


func _ready() -> void:
	# Chain-Reset bei Kampfende — Manager subscribed sich selbst.
	if has_node("/root/CombatManager"):
		if not CombatManager.combat_ended.is_connected(_on_combat_ended):
			CombatManager.combat_ended.connect(_on_combat_ended)


func _process(delta: float) -> void:
	if _combo_count <= 0:
		return
	_timer -= delta
	if _timer <= 0.0:
		if debug_prints:
			print("[Synergy] Timer abgelaufen → Chain-Reset (war combo=%d)" % _combo_count)
		_reset_chain()


# ══════════════════════════════════════════════════════════════
#  PUBLIC API — Synergie-Components
# ══════════════════════════════════════════════════════════════

## CAST: read-only. Liefert projizierten Combo/Multiplier für DIESE Synergie
## und die Zusatzkosten (Surcharge). Ändert KEINEN State.
## Die Component addiert cost_surcharge auf ihre eigene Basis-Kost und zieht ab.
func plan_synergy(_id: String) -> SynergyResult:
	var result := SynergyResult.new()
	result.allowed = true
	result.combo_count = _combo_count + 1
	result.damage_multiplier = _multiplier_for(_combo_count + 1)
	# Surcharge nach aktueller Chain-Position: combo 0 → 0, combo 1 → surcharge, …
	result.cost_surcharge = synergy_surcharge * float(_combo_count)

	if debug_prints:
		print("[Synergy] CAST id=%s → projected combo=%d mult=%.2fx surcharge=%.1f"
			% [_id, result.combo_count, result.damage_multiplier, result.cost_surcharge])
	return result


## ERSTER gelandeter Treffer einer Synergie: Chain vorrücken. Rechnet aus dem
## AKTUELLEN State (nicht aus einer stale Projektion) — robust gegen Timer-Ablauf
## zwischen Cast und Hit. Meldet den Refund per Signal.
func commit_synergy_hit(id: String) -> void:
	_combo_count += 1
	_multiplier = _multiplier_for(_combo_count)
	_timer = chain_duration

	_memory.append(id)
	while _memory.size() > memory_size:
		_memory.pop_front()

	var distinct: int = _count_distinct()
	var refund: int = _compute_refund(distinct)

	if debug_prints:
		print("[Synergy] HIT id=%s → combo=%d mult=%.2fx distinct=%d refund=%d  memory=%s"
			% [id, _combo_count, _multiplier, distinct, refund, str(_memory)])

	_emit_chain_changed()

	if refund > 0:
		resonance_refunded.emit(refund)


## WEITERER Treffer derselben Synergie-Ausführung: nur Timer refreshen.
## (Mehrere Treffer eines Casts zählen als EIN Treffer.)
func refresh_timer() -> void:
	if _combo_count <= 0:
		return
	_timer = chain_duration


# ══════════════════════════════════════════════════════════════
#  PUBLIC API — Normale Angriffe (SwordComponent)
# ══════════════════════════════════════════════════════════════

## Normaler Treffer während einer aktiven Chain: etwas Zeit dazu (gedeckelt).
## Hält die Chain über die Setup-Lücken zwischen Synergien am Leben.
func on_normal_hit() -> void:
	if _combo_count <= 0:
		return
	_timer = minf(chain_duration, _timer + normal_hit_time_bonus)


## Multiplier für externe Treffer (normale Angriffe profitieren von der Chain).
func get_damage_multiplier() -> float:
	return _multiplier


# ══════════════════════════════════════════════════════════════
#  PUBLIC API — Player
# ══════════════════════════════════════════════════════════════

## Player wurde getroffen: Chain-Zeit-Malus. Kann die Chain killen.
func on_player_hit() -> void:
	if _combo_count <= 0:
		return
	_timer -= player_hit_time_penalty
	if _timer <= 0.0:
		if debug_prints:
			print("[Synergy] Player-Treffer → Timer leer → Chain-Reset")
		_reset_chain()


# ══════════════════════════════════════════════════════════════
#  PUBLIC GETTERS — HUD (Polling für Timer)
# ══════════════════════════════════════════════════════════════

func get_combo_count() -> int:
	return _combo_count

func get_current_multiplier() -> float:
	return _multiplier

## 0.0 – 1.0, für die Timer-Bar.
func get_timer_normalized() -> float:
	if chain_duration <= 0.0:
		return 0.0
	return clampf(_timer / chain_duration, 0.0, 1.0)

## Kopie der ID-Reihenfolge (ältestes zuerst) für die Synergie-Icon-Reihe.
func get_memory() -> Array:
	return _memory.duplicate()

func is_chain_active() -> bool:
	return _combo_count > 0


# ══════════════════════════════════════════════════════════════
#  INTERNAL
# ══════════════════════════════════════════════════════════════

func _on_combat_ended() -> void:
	if _combo_count <= 0:
		return
	if debug_prints:
		print("[Synergy] Kampf beendet → Chain-Reset")
	_reset_chain()


func _reset_chain() -> void:
	_combo_count = 0
	_timer = 0.0
	_multiplier = 1.0
	_memory.clear()
	_emit_chain_changed()


func _emit_chain_changed() -> void:
	chain_changed.emit(_combo_count, _multiplier, _memory.duplicate())


func _multiplier_for(combo: int) -> float:
	if combo <= 0:
		return 1.0
	return minf(multiplier_cap, 1.0 + multiplier_per_combo * float(combo - 1))


func _count_distinct() -> int:
	var seen: Dictionary = {}
	for id in _memory:
		seen[id] = true
	return seen.size()


func _compute_refund(distinct: int) -> int:
	var base: float = _refund_base_for_distinct(distinct)
	if base <= 0.0:
		return 0
	var scaled: float = base * (1.0 + refund_flow_growth * float(_combo_count - 1))
	return int(round(scaled))


func _refund_base_for_distinct(distinct: int) -> float:
	if refund_per_distinct.is_empty():
		return 0.0
	var idx: int = clampi(distinct, 0, refund_per_distinct.size() - 1)
	return refund_per_distinct[idx]
