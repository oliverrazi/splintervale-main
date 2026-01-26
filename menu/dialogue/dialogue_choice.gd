extends Resource
class_name DialogueChoice

@export var text: String = ""
@export var next_line_index: int = -1  # -1 = Ende
@export var condition: String = ""      # Optional: Bedingung zum Anzeigen
@export var action: String = ""         # z.B. "add_quest:quest_001" oder "give_item:potion"
