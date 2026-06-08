extends Node
## Globaler Spielfluss- / Szenenübergangs-Manager.
##
## Als Autoload registrieren mit dem Namen:  GameFlow
## (Project -> Project Settings -> Autoload -> Name "GameFlow")
##
## Verantwortlich für:
##  - "New Game" Einstieg (setzt is_new_game und lädt das Intro)
##  - Übergang Intro -> erstes Level mit sauberem Fade
##  - Ein persistentes Fade-Overlay, damit Szenenwechsel nie hart schneiden

const INTRO_CUTSCENE := "res://scenes/cutscenes/intro_cutscene.tscn"
const FIRST_LEVEL    := "res://scenes/levels/forest_clearing.tscn"

## True, sobald über das Hauptmenü "New Game" gewählt wurde.
## Damit kann z. B. ein Continue/Load-Pfad das Intro überspringen.
var is_new_game := false

var _fade: ColorRect


func _ready() -> void:
	# Persistentes Overlay auf einer sehr hohen Layer, liegt immer oben.
	var layer := CanvasLayer.new()
	layer.layer = 128
	add_child(layer)

	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fade)


## Vom Hauptmenü-Button "New Game" aufrufen.
func start_new_game() -> void:
	is_new_game = true
	# Die Intro-Szene startet selbst auf komplettem Schwarz (FadeOverlay im
	# Editor auf A=255 gesetzt), deshalb genügt hier ein harter Wechsel –
	# es entsteht kein Blitz.
	get_tree().change_scene_to_file(INTRO_CUTSCENE)


## Vom CutsceneDirector am Ende des Intros aufgerufen.
func go_to_first_level() -> void:
	get_tree().change_scene_to_file(FIRST_LEVEL)
	# Ein paar Frames warten, bis das Level wirklich aufgebaut ist,
	# dann sauf das neue Level aufblenden.
	await get_tree().process_frame
	await get_tree().process_frame
	await fade_in(0.8)


func fade_out(duration: float) -> void:
	var t := create_tween()
	t.tween_property(_fade, "color:a", 1.0, duration)
	await t.finished


func fade_in(duration: float) -> void:
	_fade.color.a = 1.0
	var t := create_tween()
	t.tween_property(_fade, "color:a", 0.0, duration)
	await t.finished
