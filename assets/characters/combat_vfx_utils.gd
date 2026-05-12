class_name CombatVFXUtils
extends Object

## Geteilte VFX-Helper für Combat-Components.
## Kein Singleton, nur statische Funktionen — kein Setup nötig.
## Jeder Component kann diese aufrufen ohne Referenzen oder Autoloads.

## Spawnt eine Impact-VFX-Szene am gegebenen Welt-Punkt.
## Behandelt Particle-Toggle (für delayed start), Lifetime-Cleanup,
## Skalierung und zufällige Y-Rotation.
##
## Parameters:
##   parent: Node der dem current_scene den VFX hinzufügt (z.B. Player oder Component)
##   impact_scene: PackedScene der gespawnt wird
##   pos: Welt-Position für den Impact
##   scale: Uniformer Scale-Faktor (1.0 = original)
##   delay: Verzögerung bis Particles emittieren
##   lifetime: Wie lang die Szene existiert bevor queue_free
static func spawn_impact(parent: Node, impact_scene: PackedScene, pos: Vector3, scale: float = 1.0, delay: float = 0.1, lifetime: float = 0.5) -> void:
	if impact_scene == null or parent == null:
		return
	
	var tree := parent.get_tree()
	if tree == null:
		return
	
	var vfx := impact_scene.instantiate() as Node3D
	tree.current_scene.add_child(vfx)
	vfx.global_position = pos
	vfx.rotation_degrees.y = randf() * 360.0
	vfx.scale = Vector3(scale, scale, scale)
	
	if delay > 0.0:
		# Particles erstmal aus, dann verzögert anschalten — gibt subtilen Wuchteffekt
		for child in vfx.get_children():
			if child is GPUParticles3D:
				child.emitting = false
		tree.create_timer(delay).timeout.connect(func():
			if is_instance_valid(vfx):
				for child in vfx.get_children():
					if child is GPUParticles3D:
						child.emitting = true
		)
	else:
		for child in vfx.get_children():
			if child is GPUParticles3D:
				child.emitting = true
	
	tree.create_timer(lifetime + delay).timeout.connect(func():
		if is_instance_valid(vfx):
			vfx.queue_free()
)
