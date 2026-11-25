extends Control

signal translation_requested(delta: Vector3)
signal rotation_requested(axis: Vector3, angle: float)

const AXES := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
const AXIS_LABELS := ["X", "Y", "Z"]
const AXIS_COLORS := [Color("#f67066"), Color("#79df93"), Color("#70a9ff")]
const RING_AXES := [Vector2i(1, 2), Vector2i(2, 0), Vector2i(0, 1)]
const ARROW_LENGTH := 56.0
const RING_RADIUS := 79.0
const RING_STEPS := 64
const MIN_ARROW_LENGTH := 18.0
const CENTER_RADIUS := 8.0
const HIT_RADIUS := 7.0
const SHADOW := Color(0.04, 0.05, 0.07, 0.88)

var _projected := false
var _center := Vector2.ZERO
var _pixel_scale := 1.0
var _axis_vectors := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _axis_depths := Vector3.ZERO
var _rings: Array[PackedVector2Array] = []
var _hover := -1
var _drag := -1
var _drag_position := Vector2.ZERO
var _drag_axis := Vector2.ZERO
var _drag_center := Vector2.ZERO
var _drag_u := Vector2.ZERO
var _drag_v := Vector2.ZERO
var _drag_tangent := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func sync(camera_node: Camera3D, pivot: Vector3) -> void:
	if not is_instance_valid(camera_node) or not camera_node.is_inside_tree() \
			or not pivot.is_finite() or size.x <= 0.0 or size.y <= 0.0:
		_invalidate()
		return
	var view := camera_node.get_camera_transform().affine_inverse()
	var local_pivot := view * pivot
	var depth := -local_pivot.z
	if depth <= camera_node.near or depth >= camera_node.far:
		_invalidate()
		return

	var viewport_size := camera_node.get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		_invalidate()
		return
	var scale_to_overlay := size / viewport_size
	var screen := camera_node.unproject_position(pivot)
	var sample := camera_node.project_position(screen, depth)
	var world_per_x := sample.distance_to(camera_node.project_position(screen + Vector2.RIGHT, depth))
	var world_per_y := sample.distance_to(camera_node.project_position(screen + Vector2.DOWN, depth))
	if world_per_x <= 0.0 or world_per_y <= 0.0:
		_invalidate()
		return

	var pixels_per_unit := scale_to_overlay / Vector2(world_per_x, world_per_y)
	var perspective := Vector2.ZERO
	if camera_node.projection != Camera3D.PROJECTION_ORTHOGONAL:
		perspective = Vector2(local_pivot.x, -local_pivot.y) / depth
	var center := screen * scale_to_overlay
	var axis_vectors := PackedVector2Array()
	var axis_depths := Vector3.ZERO
	for index in range(AXES.size()):
		var axis: Vector3 = view.basis * AXES[index]
		# Differentiate the projection at the pivot so the rings stay centered
		# and their size does not depend on the camera or model distance.
		axis_vectors.append(pixels_per_unit * (Vector2(axis.x, -axis.y) + perspective * axis.z))
		axis_depths[index] = axis.z
	var pixel_scale := minf(pixels_per_unit.x, pixels_per_unit.y)
	if not center.is_finite() or not is_finite(pixel_scale) or pixel_scale <= 0.0:
		_invalidate()
		return
	if _projected and center.is_equal_approx(_center) and axis_vectors == _axis_vectors \
			and axis_depths.is_equal_approx(_axis_depths) and is_equal_approx(pixel_scale, _pixel_scale):
		return

	_projected = true
	_center = center
	_axis_vectors = axis_vectors
	_axis_depths = axis_depths
	_pixel_scale = pixel_scale
	_rings.clear()
	for axes: Vector2i in RING_AXES:
		var u := _axis_vectors[axes.x] * (RING_RADIUS / _pixel_scale)
		var v := _axis_vectors[axes.y] * (RING_RADIUS / _pixel_scale)
		var ring := PackedVector2Array()
		for step in range(RING_STEPS + 1):
			var angle := TAU * float(step) / RING_STEPS
			ring.append(_center + u * cos(angle) + v * sin(angle))
		_rings.append(ring)
	queue_redraw()


func cancel_drag() -> void:
	if _drag < 0 and _hover < 0:
		return
	_drag = -1
	_hover = -1
	queue_redraw()


func is_dragging() -> bool:
	return _drag >= 0


func handle_input(event: InputEvent) -> bool:
	if event is InputEventMouse and not event.position.is_finite():
		return false
	if not _projected or not is_visible_in_tree():
		cancel_drag()
		return false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			if _drag < 0:
				return false
			cancel_drag()
			_set_hover(_pick(event.position).x)
			return true
		var hit := _pick(event.position)
		if hit.x >= 0:
			_begin_drag(hit, event.position)
			return true
	elif event is InputEventMouseMotion:
		if _drag >= 0:
			if not (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
				cancel_drag()
				return false
			_update_drag(event.position)
			return true
		_set_hover(_pick(event.position).x if not (event.button_mask & MOUSE_BUTTON_MASK_LEFT) else -1)
	return false


func _invalidate() -> void:
	if _projected:
		_projected = false
		cancel_drag()
		queue_redraw()


func _set_hover(handle: int) -> void:
	if handle != _hover:
		_hover = handle
		queue_redraw()


func _arrow_vector(axis: int) -> Vector2:
	return _axis_vectors[axis] * (ARROW_LENGTH / _pixel_scale)


func _pick(position: Vector2) -> Vector2i:
	if position.distance_squared_to(_center) < CENTER_RADIUS * CENTER_RADIUS:
		return Vector2i(-1, -1)
	var arrow := -1
	var best_distance := HIT_RADIUS
	for axis in range(AXES.size()):
		var offset := _arrow_vector(axis)
		if offset.length() < MIN_ARROW_LENGTH:
			continue
		var from := _center + offset.normalized() * CENTER_RADIUS
		var closest := Geometry2D.get_closest_point_to_segment(position, from, _center + offset)
		var distance := position.distance_to(closest)
		if distance < best_distance:
			best_distance = distance
			arrow = axis
	if arrow >= 0:
		return Vector2i(arrow, -1)

	var hit := Vector2i(-1, -1)
	best_distance = HIT_RADIUS
	var best_depth := -INF
	for axis in range(_rings.size()):
		var ring := _rings[axis]
		var axes: Vector2i = RING_AXES[axis]
		for step in range(RING_STEPS):
			var closest := Geometry2D.get_closest_point_to_segment(position, ring[step], ring[step + 1])
			var distance := position.distance_to(closest)
			if distance >= HIT_RADIUS or distance > best_distance + 0.1:
				continue
			var angle := TAU * (float(step) + 0.5) / RING_STEPS
			var depth := _axis_depths[axes.x] * cos(angle) + _axis_depths[axes.y] * sin(angle)
			if distance < best_distance - 0.1 or depth > best_depth:
				best_distance = distance
				best_depth = depth
				hit = Vector2i(axis + AXES.size(), step)
	return hit


func _begin_drag(hit: Vector2i, position: Vector2) -> void:
	_drag = hit.x
	_drag_position = position
	_drag_center = _center
	if hit.x < AXES.size():
		_drag_axis = _axis_vectors[hit.x]
	else:
		var axes: Vector2i = RING_AXES[hit.x - AXES.size()]
		_drag_u = _axis_vectors[axes.x] * (RING_RADIUS / _pixel_scale)
		_drag_v = _axis_vectors[axes.y] * (RING_RADIUS / _pixel_scale)
		_drag_tangent = Vector2.ZERO
		if absf(_drag_u.cross(_drag_v)) < RING_RADIUS * RING_RADIUS * 0.22:
			# An edge-on ring cannot be inverted reliably. Keep the tangent
			# of the picked arc for the whole drag.
			var angle := TAU * (float(hit.y) + 0.5) / RING_STEPS
			_drag_tangent = _drag_v * cos(angle) - _drag_u * sin(angle)
			if _drag_tangent.length() < MIN_ARROW_LENGTH:
				_drag_tangent = _drag_u if _drag_u.length_squared() > _drag_v.length_squared() else _drag_v
	queue_redraw()


func _update_drag(position: Vector2) -> void:
	var previous := _drag_position
	_drag_position = position
	var movement := position - previous
	if _drag < AXES.size():
		var distance := movement.dot(_drag_axis) / _drag_axis.length_squared()
		if is_finite(distance) and not is_zero_approx(distance):
			translation_requested.emit(AXES[_drag] * distance)
		return

	var angle := 0.0
	if _drag_tangent != Vector2.ZERO:
		angle = movement.dot(_drag_tangent) / maxf(_drag_tangent.length() * RING_RADIUS, 1.0)
	else:
		var before := _ring_coordinates(previous)
		var after := _ring_coordinates(position)
		if before.length_squared() > 0.04 and after.length_squared() > 0.04:
			angle = before.angle_to(after)
	if is_finite(angle) and not is_zero_approx(angle):
		rotation_requested.emit(AXES[_drag - AXES.size()], angle)


func _ring_coordinates(position: Vector2) -> Vector2:
	var offset := position - _drag_center
	return Vector2(offset.cross(_drag_v), _drag_u.cross(offset)) / _drag_u.cross(_drag_v)


func _draw() -> void:
	if not _projected:
		return
	var active := _drag if _drag >= 0 else _hover
	for axis in range(_rings.size()):
		var emphasized := active == axis + AXES.size()
		var color: Color = AXIS_COLORS[axis]
		color.a = 1.0 if emphasized else 0.64
		draw_polyline(_rings[axis], SHADOW, 5.0 if emphasized else 3.5, true)
		draw_polyline(_rings[axis], color, 2.7 if emphasized else 1.5, true)
	for axis in range(AXES.size()):
		_draw_arrow(axis, active == axis)
	draw_circle(_center, 4.0, SHADOW, true, -1.0, true)
	draw_circle(_center, 2.0, Color("#f1f0e9"), true, -1.0, true)


func _draw_arrow(axis: int, emphasized: bool) -> void:
	var offset := _arrow_vector(axis)
	if offset.length() < MIN_ARROW_LENGTH:
		return
	var direction := offset.normalized()
	var from := _center + direction * 6.0
	var tip := _center + offset
	var base := tip - direction * 10.0
	var side := direction.orthogonal() * 5.0
	var color: Color = AXIS_COLORS[axis]
	if emphasized:
		color = color.lightened(0.28)
	draw_line(from, base, SHADOW, 6.5, true)
	draw_line(from, base, color, 3.5 if emphasized else 2.5, true)
	draw_colored_polygon(PackedVector2Array([tip, base + side, base - side]), color)
	var font := get_theme_default_font()
	var label: String = AXIS_LABELS[axis]
	var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
	var label_position := tip + direction * 12.0 + Vector2(-text_size.x * 0.5, 4.0)
	draw_string_outline(font, label_position, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 3, SHADOW)
	draw_string(font, label_position, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)
