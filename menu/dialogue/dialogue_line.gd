extends Resource
class_name DialogueLine

@export var speaker_name: String = ""
@export_multiline var text: String = ""
@export var choices: Array[DialogueChoice] = []

@export_group("Flow Control")
@export var condition: String = ""  # Condition für diese Line
@export var action: String = ""  # Action nach dieser Line
@export var ends_dialogue: bool = false
@export var next_line_index: int = -1  # -1 = nächste Line, sonst springe zu Index

@export_group("Block System")
@export var block_id: String = ""  # z.B. "intro", "quest_active", "quest_complete"
