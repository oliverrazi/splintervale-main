extends Resource
class_name QuestData

enum QuestType {
	TALK,        # Mit NPC reden
	COLLECT,     # Items sammeln
	KILL,        # Gegner besiegen
	EXPLORE,     # Ort finden
	DELIVER      # Item abgeben
}

enum QuestStatus {
	NOT_STARTED,
	ACTIVE,
	COMPLETED,
	TURNED_IN
}

@export_group("Info")
@export var quest_id: String = ""
@export var quest_name: String = ""
@export_multiline var description: String = ""
@export var quest_type: QuestType = QuestType.TALK

@export_group("Requirements")
@export var required_level: int = 1
@export var required_quests: Array[String] = []  # Quests die vorher erledigt sein müssen

@export_group("Objectives")
@export var target_id: String = ""  # Item ID, Enemy ID, Location ID, NPC ID
@export var target_amount: int = 1

@export_group("Rewards")
@export var reward_exp: int = 0
@export var reward_gold: int = 0
@export var reward_items: Array[String] = []  # Item IDs

@export_group("Giver")
@export var giver_npc_id: String = ""
@export var turn_in_npc_id: String = ""  # Falls unterschiedlich
