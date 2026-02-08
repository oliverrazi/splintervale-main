extends CanvasLayer
# oder: extends Label

@onready var fps_label: Label = $FPSLabel

func _process(_delta):
	fps_label.text = "FPS: %d" % Engine.get_frames_per_second()
