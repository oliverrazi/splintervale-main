extends Node3D
## Vogelschwarm fuer die Aufwach-Cutscene.
##
## Spawnt 3 SmoothPixelSprite3D-Voegel, die von RECHTS nach LINKS durchs
## Bild fliegen — zeitversetzt, mit leichter Hoehen- und Tempo-Varianz.
## Jeder Vogel animiert seinen Fluegelschlag ueber die Frames 0,1,2 (erste
## Zeile des Sheets) und entfernt sich selbst, sobald er links raus ist.
##
## Wird vom WakeUpDirector instanziiert. Position dieses Node = ungefaehres
## Zentrum, durch das die Voegel ziehen (am besten vor/ueber dem Wald, im
## Sichtfeld der unteren Start-Kamera).

# === Spritesheet ===
@export_group("Spritesheet")
@export var bird_texture: Texture2D
@export var hframes: int = 10
@export var vframes: int = 2
## Frames des Fluegelschlags (erste Zeile). Rest ist Platzhalter.
@export var flap_frames: Array[int] = [0, 1, 2]
@export var flap_fps: float = 8.0
## Skalierung des Billboards in Welt-Einheiten.
@export var bird_scale: float = 0.5

# === Flugbahn ===
@export_group("Flugbahn")
## Startversatz nach rechts (relativ zu diesem Node), wo die Voegel starten.
@export var spawn_offset_right: float = 14.0
## Wie weit nach links sie fliegen, bis sie despawnen.
@export var travel_distance: float = 28.0
## Basis-Flughoehe (Y relativ zu diesem Node).
@export var base_height: float = 4.0
## Basis-Tiefe (Z relativ zu diesem Node) — Abstand zur Kamera.
@export var base_depth: float = 0.0
## Grund-Fluggeschwindigkeit (Welt-Einheiten/Sekunde).
@export var base_speed: float = 4.0

# === Schwarm-Varianz ===
@export_group("Schwarm")
@export var bird_count: int = 3
## Zeitlicher Versatz zwischen den Voegeln (Sekunden). Klein halten — ein
## Schwarm fliegt dicht, sie sollen fast gleichzeitig ins Bild kommen.
@export var stagger: float = 0.18
## Zufaellige Hoehen-Streuung (+/-). Klein — Schwarm haelt enge Formation.
@export var height_variance: float = 0.4
## Zufaellige Tempo-Streuung (+/-). Klein — sonst zerfaellt die Formation.
@export var speed_variance: float = 0.25
## Zufaellige Tiefen-Streuung (+/-).
@export var depth_variance: float = 0.6
## Ganz dezentes vertikales Wippen. Sehr klein halten.
@export var bob_amplitude: float = 0.05
@export var bob_speed: float = 1.6
## Versatz im Fluegelschlag: jeder Vogel startet auf einem anderen Frame,
## damit die Fluegel nicht synchron schlagen (lebendiger Schwarm).
@export var flap_phase_offset: bool = true
## Lockere Formations-Staffelung: leichter X/Y-Versatz pro Vogel, damit sie
## als Gruppe versetzt fliegen statt exakt uebereinander. Klein halten.
@export var formation_spread_x: float = 1.2
@export var formation_spread_y: float = 0.5

var _rng := RandomNumberGenerator.new()
var _active_birds: int = 0
var _done: bool = false

signal flock_finished


func _ready() -> void:
	_rng.randomize()


## Startet den Schwarm. Laeuft nebenher; der Director muss nicht awaiten,
## kann aber ueber das "flock_finished"-Signal das Ende abwarten.
func launch() -> void:
	if bird_texture == null:
		push_warning("BirdFlock: bird_texture nicht zugewiesen.")
		flock_finished.emit()
		return

	for i in bird_count:
		var delay := float(i) * stagger
		_spawn_bird_delayed(delay, i)


func _spawn_bird_delayed(delay: float, index: int) -> void:
	_active_birds += 1
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	_spawn_bird(index)


func _spawn_bird(index: int) -> void:
	var bird := _make_bird_sprite()
	add_child(bird)

	# Start- und Ziel-Position in LOKALEN Koordinaten dieses Node.
	# Formations-Staffelung: Index um die Mitte herum verteilen, damit der
	# Schwarm als versetzte Gruppe fliegt statt exakt uebereinander.
	var centered := float(index) - float(bird_count - 1) * 0.5
	var form_x := centered * formation_spread_x
	var form_y := centered * formation_spread_y

	var h := base_height + form_y + _rng.randf_range(-height_variance, height_variance)
	var d := base_depth + _rng.randf_range(-depth_variance, depth_variance)
	var start_local := Vector3(spawn_offset_right + form_x, h, d)
	var end_local := Vector3(spawn_offset_right + form_x - travel_distance, h, d)

	bird.position = start_local

	var speed := base_speed + _rng.randf_range(-speed_variance, speed_variance)
	speed = maxf(speed, 0.5)
	var flight_time := travel_distance / speed

	# Fluegelschlag-Animation starten (laeuft, bis der Vogel weg ist).
	# Jeder Vogel startet auf einem anderen Frame -> kein synchrones Schlagen.
	var flap_start := 0
	if flap_phase_offset and flap_frames.size() > 0:
		flap_start = index % flap_frames.size()
	_animate_flap(bird, flap_start)

	# Horizontaler Flug nach links + sanftes Wippen.
	var phase := _rng.randf_range(0.0, TAU)
	var t := create_tween()
	t.set_trans(Tween.TRANS_LINEAR)
	t.tween_method(
		func(p: float):
			if not is_instance_valid(bird):
				return
			var x := lerpf(start_local.x, end_local.x, p)
			var bob := sin(phase + p * flight_time * bob_speed * TAU) * bob_amplitude
			bird.position = Vector3(x, h + bob, d),
		0.0, 1.0, flight_time
	)
	t.tween_callback(func(): _on_bird_done(bird))


func _make_bird_sprite() -> Node3D:
	# SmoothPixelSprite3D zur Laufzeit erzeugen. Falls die Klasse global
	# registriert ist (class_name), koennen wir sie direkt instanziieren.
	var bird: Node3D
	if ClassDB.class_exists("SmoothPixelSprite3D"):
		bird = ClassDB.instantiate("SmoothPixelSprite3D")
	else:
		# Fallback ueber den Script-Pfad, falls nur als Script vorhanden.
		var sps := load("res://SmoothPixelSprite3D.gd")
		if sps:
			bird = sps.new()
		else:
			# Letzter Fallback: normales Sprite3D (zur Not sichtbar).
			var s := Sprite3D.new()
			s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			bird = s

	# Properties defensiv setzen (alle existieren laut SmoothPixelSprite3D-API).
	if "texture" in bird:
		bird.texture = bird_texture
	if "hframes" in bird:
		bird.hframes = hframes
	if "vframes" in bird:
		bird.vframes = vframes
	if "frame" in bird:
		bird.frame = flap_frames[0] if flap_frames.size() > 0 else 0
	# Voegel fliegen nach links -> nach links schauen. flip_h je nach
	# Zeichenrichtung deines Sheets evtl. invertieren.
	if "flip_h" in bird:
		bird.flip_h = true

	if "scale" in bird:
		bird.scale = Vector3(bird_scale, bird_scale, bird_scale)

	return bird


func _animate_flap(bird: Node3D, start_index: int = 0) -> void:
	if flap_frames.is_empty() or not ("frame" in bird):
		return
	var fps := maxf(flap_fps, 0.1)
	var per_frame := 1.0 / fps
	# Frame-Reihenfolge so rotieren, dass dieser Vogel mittendrin einsteigt.
	var ordered: Array[int] = []
	var n := flap_frames.size()
	for k in n:
		ordered.append(flap_frames[(start_index + k) % n])
	# Loop-Tween ueber die rotierten Flap-Frames, laeuft bis der Vogel queue_freet.
	var loop := create_tween().set_loops()
	for fr in ordered:
		loop.tween_callback(func():
			if is_instance_valid(bird) and ("frame" in bird):
				bird.frame = fr
		)
		loop.tween_interval(per_frame)
	# Tween an den Vogel binden, damit er mit ihm stirbt.
	bird.tree_exited.connect(func():
		if loop.is_valid():
			loop.kill()
	)


func _on_bird_done(bird: Node3D) -> void:
	if is_instance_valid(bird):
		bird.queue_free()
	_active_birds -= 1
	if _active_birds <= 0 and not _done:
		_done = true
		flock_finished.emit()
