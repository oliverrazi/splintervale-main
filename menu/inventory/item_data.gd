extends Resource
class_name ItemData

enum ItemType {
	WEAPON,
	CONSUMABLE,
	KEY_ITEM,
	MATERIAL,
	EQUIPMENT
}

enum ItemRarity {
	COMMON,
	UNCOMMON,
	RARE,
	EPIC,
	LEGENDARY
}

@export_group("Basic Info")
@export var item_id: String = ""
@export var item_name: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D = null
@export var item_type: ItemType = ItemType.CONSUMABLE
@export var rarity: ItemRarity = ItemRarity.COMMON


@export_group("Pickup Display")
@export_multiline var pickup_text: String = "" 

@export_group("Stacking")
@export var stackable: bool = true
@export var max_stack: int = 99

@export_group("Usage")
@export var usable: bool = true  # Kann im Kampf/Welt benutzt werden
@export var consumable: bool = true  # Wird bei Benutzung verbraucht

@export_group("Weapon Stats")
@export var attack_damage: int = 10
@export var attack_range: float = 1.0
@export var attack_speed: float = 1.0

@export_group("Effects")
@export var heal_amount: int = 0
@export var mana_restore: int = 0
@export var stamina_restore: int = 0
@export var damage_bonus: int = 0
@export var effect_action: String = ""  # z.B. "buff:attack:10:30" (buff type, amount, duration)

@export_group("Value")
@export var buy_price: int = 0
@export var sell_price: int = 0


func get_rarity_color() -> Color:
	match rarity:
		ItemRarity.COMMON:
			return Color(0.8, 0.8, 0.8)
		ItemRarity.UNCOMMON:
			return Color(0.3, 0.9, 0.3)
		ItemRarity.RARE:
			return Color(0.3, 0.5, 1.0)
		ItemRarity.EPIC:
			return Color(0.7, 0.3, 0.9)
		ItemRarity.LEGENDARY:
			return Color(1.0, 0.6, 0.1)
	return Color.WHITE
	
func get_pickup_display_text() -> String:
	"""Gibt den formatierten Pickup-Text zurück"""
	if pickup_text != "":
		return pickup_text
	
	# Standard-Text generieren
	var color_hex: String = get_rarity_color().to_html(false)
	return "[center]You got [b][color=#%s]%s[/color][/b]![/center]" % [color_hex, item_name]
