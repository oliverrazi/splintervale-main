extends Node3D
class_name AlertPopup

@onready var label: Label3D = $Label3D

@export var duration: float = 1.0


func _ready() -> void:
	scale = Vector3.ZERO
	
	# Billboarding vom Label ausschalten - wir machen es manuell
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	
	call_deferred("play", duration)


func _process(_delta: float) -> void:
	# Zur Kamera ausrichten (wie das Goblin Sprite)
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	
	# Nur Y-Rotation zur Kamera
	var to_camera := camera.global_position - global_position
	to_camera.y = 0
	
	if to_camera.length() > 0.01:
		look_at(global_position + to_camera, Vector3.UP)
		# 180° drehen damit Text zur Kamera zeigt
		rotate_y(PI)


func play(duration: float = 1) -> void:
	var tween := create_tween()
	var pop_in_time: float = duration * 0.1       
	var settle_time: float = duration * 0.05      
	var hold_time: float = duration * 0.65        
	var fade_out_time: float = duration * 1
	
	
	tween.tween_property(self, "scale", Vector3(1.3, 1.3, 1.3), pop_in_time)\
			.set_ease(Tween.EASE_OUT)\
			.set_trans(Tween.TRANS_BACK)
	
	tween.tween_property(self, "scale", Vector3(1.0, 1.0, 1.0), settle_time)
	
	# Halten
	tween.tween_interval(hold_time)
	
	# Fade Out + nach oben
	tween.set_parallel(true)
	tween.tween_property(label, "modulate:a", 0.5, fade_out_time-0.5)
	tween.tween_property(label, "outline_modulate:a", 0.5, fade_out_time-0.5)

	tween.tween_property(self, "position:y", position.y + 0.1, fade_out_time)\
		.set_ease(Tween.EASE_IN)
	
	tween.chain()
	tween.tween_callback(queue_free)
	
	#_vibrate(duration)
	
func _vibrate(duration: float) -> void:
	var vibrate_tween := create_tween()
	vibrate_tween.set_loops(int(duration / 0.08))  # Anzahl Vibrationen
	
	var intensity: float = 0.06
	
	# Schnelles Hin-und-Her
	vibrate_tween.tween_property(self, "position:x", position.x + intensity, 0.015)
	vibrate_tween.tween_property(self, "position:x", position.x - intensity, 0.03)
	vibrate_tween.tween_property(self, "position:x", position.x, 0.015)
