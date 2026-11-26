extends Control

const NORMALS := [Vector3.BACK, Vector3.RIGHT, Vector3.FORWARD, Vector3.LEFT, Vector3.UP, Vector3.DOWN]
const LABELS := ["Front", "Right", "Back", "Left", "Top", "Bottom"]
const FACE_SHADES := ["#706b66", "#8c8680", "#706b66", "#8c8680", "#beb8b1", "#635c54"]
const EDGE := Color("#b59b71")
const CORNERS := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]

var stage: SubViewportContainer
var _camera_basis := Basis.IDENTITY
var _polygons: Dictionary[int, PackedVector2Array]
var _hover := -1
var _pressing := false
var _dragging := false
var _press_origin := Vector2.ZERO


func _ready() -> void:
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_exited.connect(func():
		_hover = -1
		queue_redraw()
	)
	get_window().focus_exited.connect(func(): _pressing = false)
	queue_redraw()


func _process(_delta: float) -> void:
	if not stage or not stage.camera:
		return
	var basis: Basis = stage.orientation_display_basis()
	if not basis.is_equal_approx(_camera_basis):
		_camera_basis = basis
		queue_redraw()


func _draw() -> void:
	var inverse := _camera_basis.transposed()
	_polygons.clear()
	for index in range(NORMALS.size()):
		var normal: Vector3 = NORMALS[index]
		var facing := (inverse * normal).z
		if facing <= 0.005:
			continue
		var up := Vector3.FORWARD if absf(normal.y) > 0.5 else Vector3.UP
		var right := up.cross(normal)
		var polygon := PackedVector2Array()
		for corner: Vector2 in CORNERS:
			polygon.append(_project(inverse * (normal + right * corner.x + up * corner.y)))
		_polygons[index] = polygon
		var shade := Color(FACE_SHADES[index])
		if index == _hover:
			shade = shade.lerp(Color("#d3a868"), 0.53)
		draw_polygon(polygon, PackedColorArray([shade.darkened(0.05), shade.darkened(0.02),
			shade.lightened(0.05), shade.lightened(0.02)]))
		var border := polygon.duplicate()
		border.append(polygon[0])
		draw_polyline(border, EDGE.lightened(0.22) if index == _hover else EDGE, 1.05, true)
		_draw_face_label(index, polygon, facing)


func _draw_face_label(index: int, polygon: PackedVector2Array, facing: float) -> void:
	if facing < 0.22:
		return
	var x_axis := (polygon[1] - polygon[0]) * 0.5
	var y_axis := (polygon[0] - polygon[3]) * 0.5
	var half_extent := minf(size.x, size.y) * 0.235
	var font := get_theme_default_font()
	var label: String = LABELS[index]
	var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	var fit := minf(1.0, half_extent * 1.67 / maxf(width, 1.0))
	var center := (polygon[0] + polygon[2]) * 0.5
	draw_set_transform_matrix(Transform2D(x_axis / half_extent * fit, y_axis / half_extent, center))
	draw_string(font, Vector2(-width / 2.0, 3.8), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#1f1b18"))
	draw_set_transform_matrix(Transform2D.IDENTITY)


func _project(local: Vector3) -> Vector2:
	var extent := minf(size.x, size.y) * 0.235
	return size * 0.5 + Vector2(local.x, -local.y) * extent


func _pick(position: Vector2) -> int:
	for index in _polygons:
		if Geometry2D.is_point_in_polygon(position, _polygons[index]):
			return index
	return -1


func _get_tooltip(at_position: Vector2) -> String:
	var index := _pick(at_position)
	return LABELS[index] if index >= 0 else tr("Tažením otočíš pohled")


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if _pressing:
			if not _dragging and _press_origin.distance_to(event.position) > 4.0:
				_dragging = true
			if _dragging:
				stage.orbit_by(event.relative)
		_hover = _pick(event.position) if not _dragging else -1
		queue_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press_origin = event.position
			_pressing = true
			_dragging = false
		elif _pressing:
			var index := _pick(event.position)
			if not _dragging and index >= 0:
				stage.orient_to(NORMALS[index])
			_pressing = false
			_dragging = false
		accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		queue_redraw()
