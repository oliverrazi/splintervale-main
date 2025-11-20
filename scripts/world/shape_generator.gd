class_name ShapeGenerator
extends RefCounted

## Utility-Klasse für Shape/Outline Generierung

static func generate_shape_outline(data: Dictionary, segments: int) -> PackedVector2Array:
	var points = PackedVector2Array()
	var radius = data.radius
	var shape_type = data.shape_type
	var irregularity = data.irregularity
	var num_sides = data.num_sides
	var corner_roundness = data.corner_roundness
	var stretch_x = data.stretch_x
	var stretch_y = data.stretch_y
	var rotation = data.rotation
	
	# ERHÖHE Segments für glattere Formen
	segments = max(segments, 128)
	
	if shape_type == 0:
		# KREIS - mit mehr Variation
		for i in range(segments):
			var angle = (float(i) / segments) * TAU
			
			# Mehrere Noise-Frequenzen für natürlichere Form
			var noise = sin(angle * 3.0) * 0.03 + sin(angle * 7.0) * 0.015 + sin(angle * 11.0) * 0.008
			var r = radius * (1.0 + noise * irregularity)
			
			var x = cos(angle) * r * stretch_x
			var y = sin(angle) * r * stretch_y
			var rx = x * cos(rotation) - y * sin(rotation)
			var ry = x * sin(rotation) + y * cos(rotation)
			
			points.append(Vector2(rx, ry))
	else:
		# POLYGON - mit besserer Rundung
		var corners = []
		for i in range(num_sides):
			var corner_angle = (float(i) / num_sides) * TAU
			var corner_x = cos(corner_angle) * radius
			var corner_y = sin(corner_angle) * radius
			corners.append(Vector2(corner_x, corner_y))
		
		for i in range(segments):
			var angle = (float(i) / segments) * TAU
			
			# Finde welche Kante wir interpolieren
			var corner_index = int(floor((float(i) / segments) * num_sides))
			var next_corner_index = (corner_index + 1) % num_sides
			
			var corner_a = corners[corner_index]
			var corner_b = corners[next_corner_index]
			
			# Position auf der Kante (0 = Ecke A, 1 = Ecke B)
			var t = fmod((float(i) / segments) * num_sides, 1.0)
			
			# Basis-Interpolation
			var point = corner_a.lerp(corner_b, t)
			
			# Rundung an Ecken - SANFTE KURVE statt harter Pull
			var distance_to_corner = min(t, 1.0 - t) * 2.0  # 0 an Ecken, 1 in Mitte
			var roundness_factor = smoothstep(0.0, corner_roundness, distance_to_corner)
			
			# Ziehe zur Mitte für Rundung (smoothstep macht es weich)
			var center_pull = lerp(0.85, 1.0, roundness_factor)  # An Ecken: 0.85, in Mitte: 1.0
			point *= center_pull
			
			# Leichte Variation für natürlichere Form
			var edge_noise = sin(angle * float(num_sides) * 2.0) * 0.01
			point *= (1.0 + edge_noise * irregularity)
			
			# Anwenden von Streckung und Rotation
			var x = point.x * stretch_x
			var y = point.y * stretch_y
			var rx = x * cos(rotation) - y * sin(rotation)
			var ry = x * sin(rotation) + y * cos(rotation)
			
			points.append(Vector2(rx, ry))
	
	return points
