extends Area3D
class_name VFXHitArea

## Generischer Hit-Volumen-Helper für VFX-Szenen.
## An eine Area3D in einer VFX-Szene hängen, CollisionShape3D rein,
## Scale auf dem AnimationPlayer synchron zum sichtbaren Effekt animieren.
## Der Spawner setzt `damage` zur Laufzeit.

@export var damage: int = 0
@export var target_group: String = "player"   # "enemies" für Spieler-VFX
@export var knockback_from: Node3D = null     # optional: Quelle für from_position

var _hit: Dictionary = {}

signal hit_landed(body: Node)

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if damage <= 0:
		return
	if target_group != "" and not body.is_in_group(target_group):
		return
	if not body.has_method("take_damage"):
		return
	var id := body.get_instance_id()
	if _hit.has(id):
		return
	_hit[id] = true
	var from: Vector3 = global_position
	if knockback_from and is_instance_valid(knockback_from):
		from = knockback_from.global_position
	body.take_damage(damage, from)
	hit_landed.emit(body)
