extends Node3D

@onready var griffin_sprite: SmoothPixelSprite3D = $GriffinSprite
@onready var render_viewport: SubViewport = $RenderViewport

func _ready() -> void:
	griffin_sprite.hframes = 1
	griffin_sprite.vframes = 1
	griffin_sprite.texture = render_viewport.get_texture()
