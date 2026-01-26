extends CanvasLayer

signal loading_finished  # Signal ganz oben!

@onready var background: ColorRect = $ColorRect
@onready var label: Label = $ColorRect/VBoxContainer/Label
@onready var progress_bar: ProgressBar = $ColorRect/VBoxContainer/ProgressBar

var _target_scene: String = ""
var _progress: Array = []


func _ready() -> void:
	layer = 100
	visible = false
	
	background.color = Color(0.05, 0.05, 0.08, 1.0)
	label.text = "Loading..."
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	progress_bar.min_value = 0.0
	progress_bar.max_value = 1.0
	progress_bar.value = 0.0


func load_scene(scene_path: String) -> void:
	_target_scene = scene_path
	visible = true
	label.text = "Loading..."
	progress_bar.value = 0.0
	
	background.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(background, "modulate:a", 1.0, 0.2)
	tween.tween_callback(_start_loading)


func _start_loading() -> void:
	ResourceLoader.load_threaded_request(_target_scene)
	set_process(true)


func _process(_delta: float) -> void:
	var status := ResourceLoader.load_threaded_get_status(_target_scene, _progress)
	
	match status:
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			if _progress.size() > 0:
				progress_bar.value = _progress[0]
				label.text = "Loading... %d%%" % int(_progress[0] * 100)
		
		ResourceLoader.THREAD_LOAD_LOADED:
			set_process(false)
			_on_loading_complete()
		
		ResourceLoader.THREAD_LOAD_FAILED:
			set_process(false)
			push_error("Failed to load scene: ", _target_scene)
			label.text = "Loading failed!"


func _on_loading_complete() -> void:
	progress_bar.value = 1.0
	label.text = "Loading... 100%"
	
	await get_tree().create_timer(0.2).timeout
	
	var packed_scene: PackedScene = ResourceLoader.load_threaded_get(_target_scene)
	get_tree().change_scene_to_packed(packed_scene)
	
	await get_tree().process_frame
	await get_tree().process_frame
	
	loading_finished.emit()
	
	var tween := create_tween()
	tween.tween_property(background, "modulate:a", 0.0, 0.3)
	tween.tween_callback(func(): visible = false)
	
