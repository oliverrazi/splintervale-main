extends Control
class_name HexHealthBar

@export var segments: int = 10
@export var max_hp: float = 100.0 : set = set_max_hp
@export var hp: float = 100.0 : set = set_hp

@export var gap: float = 8.0
@export var fill_inset: float = 3.0
@export var outline_width: float = 2.0

@export var outline_color: Color = Color(0.9, 0.9, 0.9, 0.8)
@export var empty_color: Color = Color(0.15, 0.15, 0.15, 0.6)
@export var fill_color: Color = Color(0.95, 0.2, 0.2, 0.95)

# Segment-Reihenfolge beim Leeren: rechts -> links
@export var drain_right_to_left: bool = true

func set_max_hp(v: float) -> void:
	max_hp = max(1.0, v)
	hp = clamp(hp, 0.0, max_hp)
	queue_redraw()

func set_hp(v: float) -> void:
	hp = clamp(v, 0.0, max_hp)
	queue_redraw()

func _draw() -> void:
	if segments <= 0:
		return

	var seg_value: float = max_hp / float(segments)
	var r: float = _compute_hex_radius()
	if r <= 1.0:
		return

	var hex_w: float = sqrt(3.0) * r
	var step_x: float = hex_w + gap

	var total_w: float = float(segments) * hex_w + float(segments - 1) * gap
	var origin: Vector2 = Vector2((size.x - total_w) * 0.5, size.y * 0.5)

	for i: int in range(segments):
		var draw_index: int = i
		if drain_right_to_left:
			draw_index = (segments - 1) - i

		var center: Vector2 = origin + Vector2(float(i) * step_x + hex_w * 0.5, 0.0)

		var poly: PackedVector2Array = _diamond_polygon(center, r)

		# Hintergrund (leer)
		draw_colored_polygon(poly, empty_color)

		# Outline (closed polyline Ersatz)
		_draw_polyline_closed(poly, outline_color, outline_width)

		# Füllstand für dieses Segment (0..1)
		var seg_start: float = float(draw_index) * seg_value
		var seg_fill: float = clamp((hp - seg_start) / seg_value, 0.0, 1.0)
		if seg_fill <= 0.0:
			continue

		var fill_poly: PackedVector2Array = _diamond_polygon(center, max(1.0, r - fill_inset))

		# Füllung wird innerhalb des Hex von links->rechts „geclippt“
		var clip_left: float = _min_x(fill_poly)
		var clip_right: float = _max_x(fill_poly)
		var clip_x: float = lerp(clip_left, clip_right, seg_fill)

		var clipped: PackedVector2Array = _clip_polygon_xmax(fill_poly, clip_x)
		if clipped.size() >= 3:
			draw_colored_polygon(clipped, fill_color)

func _draw_polyline_closed(poly: PackedVector2Array, color: Color, width: float) -> void:
	if poly.size() < 2:
		return
	var pts: PackedVector2Array = poly.duplicate()
	pts.append(poly[0]) # schließen
	draw_polyline(pts, color, width, true)

func _compute_hex_radius() -> float:
	var r_from_h: float = (size.y * 0.5) - outline_width
	if segments <= 0:
		return r_from_h

	var usable_w: float = max(1.0, size.x - float(segments - 1) * gap)
	# total_w = segments * sqrt(3) * r  => r = usable_w / (segments*sqrt(3))
	var denom: float = float(segments) * sqrt(3.0)
	var r_from_w: float = usable_w / denom

	return max(1.0, min(r_from_h, r_from_w))

func _hex_polygon(center: Vector2, r: float) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	for k: int in range(6):
		var ang: float = deg_to_rad(60.0 * float(k) - 30.0)
		pts.append(center + Vector2(cos(ang), sin(ang)) * r)
	return pts

func _diamond_polygon(center: Vector2, r: float) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	pts.append(center + Vector2(0, -r))  # oben
	pts.append(center + Vector2(r, 0))   # rechts
	pts.append(center + Vector2(0, r))   # unten
	pts.append(center + Vector2(-r, 0))  # links
	return pts

func _min_x(poly: PackedVector2Array) -> float:
	var m: float = poly[0].x
	for p: Vector2 in poly:
		m = min(m, p.x)
	return m

func _max_x(poly: PackedVector2Array) -> float:
	var m: float = poly[0].x
	for p: Vector2 in poly:
		m = max(m, p.x)
	return m

func _clip_polygon_xmax(poly: PackedVector2Array, xmax: float) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	if poly.size() < 3:
		return out

	for i: int in range(poly.size()):
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % poly.size()]
		var a_in: bool = a.x <= xmax
		var b_in: bool = b.x <= xmax

		if a_in and b_in:
			out.append(b)
		elif a_in and not b_in:
			out.append(_intersect_x(a, b, xmax))
		elif not a_in and b_in:
			out.append(_intersect_x(a, b, xmax))
			out.append(b)

	return out

func _intersect_x(a: Vector2, b: Vector2, x: float) -> Vector2:
	var dx: float = b.x - a.x
	if abs(dx) < 0.00001:
		return Vector2(x, a.y)
	var t: float = (x - a.x) / dx
	return a.lerp(b, clamp(t, 0.0, 1.0))
