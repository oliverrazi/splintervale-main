@tool
extends EditorScript

const OUT_DIR := "res://assets/base_tiles/waterfall/waterfall1/"

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	
	# Weicher runder Blob (für Splash/Spray)
	#_generate_soft_blob(128, OUT_DIR + "soft_blob.png", 2.5)
	# Engerer Blob für kleine Wassertropfen
	#_generate_soft_blob(128, OUT_DIR + "soft_blob_tight.png", 4.5)
	# Wolkige Puff-Textur (für Mist)
	#_generate_cloud_puff(256, OUT_DIR + "mist_puff.png")
	# Weicher Ring (für Pool-Ripples)
	#_generate_ring(256, OUT_DIR + "ripple_ring.png")
	
	
	_generate_godray_streaks(128, 512, OUT_DIR + "godray_streaks.png")
	_generate_godray_motes(256, OUT_DIR + "godray_motes.png")
	
	EditorInterface.get_resource_filesystem().scan()
	print("Particle-Texturen erzeugt in ", OUT_DIR)

func _generate_soft_blob(size: int, path: String, falloff_power: float) -> void:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size, size) * 0.5
	var max_d := float(size) * 0.5
	for y in size:
		for x in size:
			var d: float = Vector2(x, y).distance_to(center) / max_d
			d = clamp(d, 0.0, 1.0)
			var alpha: float = pow(1.0 - d, falloff_power)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	img.save_png(path)

func _generate_cloud_puff(size: int, path: String) -> void:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size, size) * 0.5
	var max_d := float(size) * 0.5
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.frequency = 0.025
	noise.fractal_octaves = 3
	for y in size:
		for x in size:
			var d: float = Vector2(x, y).distance_to(center) / max_d
			d = clamp(d, 0.0, 1.0)
			var radial: float = pow(1.0 - d, 2.0)
			var n: float = noise.get_noise_2d(float(x), float(y)) * 0.35 + 0.65
			var alpha: float = clamp(radial * n, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	img.save_png(path)

func _generate_ring(size: int, path: String) -> void:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size, size) * 0.5
	var max_d := float(size) * 0.5
	var ring_pos := 0.82
	var ring_width := 0.08
	for y in size:
		for x in size:
			var d: float = Vector2(x, y).distance_to(center) / max_d
			d = clamp(d, 0.0, 1.0)
			var ring_alpha: float = 1.0 - smoothstep(0.0, ring_width, abs(d - ring_pos))
			ring_alpha = pow(ring_alpha, 2.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, ring_alpha))
	img.save_png(path)




func _generate_godray_streaks(width: int, height: int, path: String) -> void:
	# Vertikale, weiche Lichtstreifen
	var img := Image.create(width, height, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.frequency = 0.05
	noise.fractal_octaves = 2
	for y in height:
		for x in width:
			# Vertikal stark gestreckt → wirkt wie Streifen
			var n: float = noise.get_noise_2d(float(x) * 2.0, float(y) * 0.08)
			n = (n + 1.0) * 0.5
			n = pow(n, 1.3)
			img.set_pixel(x, y, Color(n, n, n, 1.0))
	img.save_png(path)

func _generate_godray_motes(size: int, path: String) -> void:
	# Kleine helle Punkte (Staubpartikel im Licht)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	noise.frequency = 0.04
	noise.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	for y in size:
		for x in size:
			var n: float = noise.get_noise_2d(float(x), float(y))
			n = (n + 1.0) * 0.5
			n = pow(n, 4.5)  # nur Spitzen überleben → punktförmige Highlights
			img.set_pixel(x, y, Color(n, n, n, 1.0))
	img.save_png(path)
