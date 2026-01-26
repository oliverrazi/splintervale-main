extends Resource
class_name DialogueLine

@export var speaker_name: String = ""
@export var text: String = ""
@export var portrait: Texture2D = null
@export var choices: Array[DialogueChoice] = []
@export var condition: String = ""  # Optional: Bedingung zum Anzeigen
@export var action: String = ""     # Optional: Aktion nach dieser Zeile
