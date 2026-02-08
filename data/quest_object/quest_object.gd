@tool
extends Area3D
class_name QuestObject

signal collected(object_id: String)

@export_group("Quest Item Info")
@export var object_id: String = ""
@export var item_id: String = ""
@export var related_quest_id: String = ""

@export_group("Spawn Condition")
@export var require_quest_active: bool = true

@export_group("Interaction")
@export var auto_pickup: bool = true
@export var interaction_radius: float = 1.5
@export var pickup_sound: AudioStream = null

@export_group("Visuals")
@export var sprite_texture: Texture2D = null:
	set(value):
		sprite_texture = value
		if _sprite:
			_sprite.texture = value
@export var sprite_hframes: int = 1
@export var sprite_vframes: int = 1
@export var sprite_frame: int = 0

@export_group("Glow Light")
@export var light_enabled: bool = true
@export var light_color: Color = Color(0.6, 1.0, 0.7)
@export var light_energy: float = 0.8
@export var light_range: float = 2.0

@export_group("Editor Visualization")
@export var show_pickup_radius: bool = true:
	set(value):
		show_pickup_radius = value
		_update_editor_visualization()

var _sprite: Sprite3D = null
var _collision: CollisionShape3D = null
var _light: OmniLight3D = null
var _editor_mesh: MeshInstance3D = null
var _collected: bool = false
var _is_active: bool = false


func _ready() -> void:
	if Engine.is_editor_hint():
		_setup_editor()
		return
	
	add_to_group("quest_object")
	
	# Bereits gesammelt?
	if QuestManager.is_world_object_collected(object_id):
		queue_free()
		return
	
	# Quest-Prüfung
	if require_quest_active and related_quest_id != "":
		if not QuestManager.has_quest(related_quest_id):
			# Quest noch nicht aktiv - verstecken und auf Signal warten
			_hide_object()
			QuestManager.quest_added.connect(_on_quest_added)
			return
	
	_activate_object()


func _on_quest_added(quest_id: String) -> void:
	if quest_id != related_quest_id:
		return
	
	if not _is_active:
		# Signal trennen
		if QuestManager.quest_added.is_connected(_on_quest_added):
			QuestManager.quest_added.disconnect(_on_quest_added)
		
		_show_object()
		_activate_object()


func _hide_object() -> void:
	visible = false
	set_process(false)
	set_physics_process(false)
	# Area3D Monitoring deaktivieren
	monitoring = false


func _show_object() -> void:
	visible = true
	set_process(true)
	set_physics_process(true)
	monitoring = true


func _activate_object() -> void:
	_is_active = true
	
	_setup_sprite()
	_setup_collision()
	
	if light_enabled:
		_setup_glow_light()
	
	if auto_pickup:
		body_entered.connect(_on_body_entered)


func _setup_sprite() -> void:
	_sprite = Sprite3D.new()
	_sprite.texture = sprite_texture
	_sprite.hframes = sprite_hframes
	_sprite.vframes = sprite_vframes
	_sprite.frame = sprite_frame
	_sprite.pixel_size = 0.01
	_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sprite.transparent = true
	add_child(_sprite)


func _setup_collision() -> void:
	_collision = CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = interaction_radius
	_collision.shape = sphere
	add_child(_collision)
	
	collision_layer = 0
	collision_mask = 1
	monitoring = true
	monitorable = false


func _setup_glow_light() -> void:
	_light = OmniLight3D.new()
	_light.light_color = light_color
	_light.light_energy = light_energy
	_light.omni_range = light_range
	_light.shadow_enabled = false
	add_child(_light)


func _setup_editor() -> void:
	_update_editor_visualization()


func _update_editor_visualization() -> void:
	if not Engine.is_editor_hint():
		return
	
	if _editor_mesh:
		_editor_mesh.queue_free()
		_editor_mesh = null
	
	if show_pickup_radius:
		_editor_mesh = MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = interaction_radius
		sphere.height = interaction_radius * 2
		_editor_mesh.mesh = sphere
		
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.2, 0.8, 0.2, 0.3)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_editor_mesh.material_override = mat
		
		add_child(_editor_mesh)


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") and not _collected:
		collect()


func can_interact() -> bool:
	return not _collected and not auto_pickup and _is_active


func interact() -> void:
	if can_interact():
		collect()


func collect() -> void:
	if _collected:
		return
	
	_collected = true
	
	if item_id != "":
		InventoryManager.add_item(item_id, 1, true)
	
	QuestManager.collect_world_object(object_id, related_quest_id)
	
	if pickup_sound:
		var player := AudioStreamPlayer3D.new()
		player.stream = pickup_sound
		player.global_position = global_position
		get_tree().current_scene.add_child(player)
		player.play()
		player.finished.connect(player.queue_free)
	
	collected.emit(object_id)
	queue_free()
