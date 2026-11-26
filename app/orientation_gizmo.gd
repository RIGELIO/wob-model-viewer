extends Control

const NORMALS := [Vector3.BACK, Vector3.RIGHT, Vector3.FORWARD, Vector3.LEFT, Vector3.UP, Vector3.DOWN]
const LABELS := ["Předek", "Pravá", "Zadek", "Levá", "Vršek", "Spodek"]
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
		var fill := Color("#746b5e").lerp(Color("#b6a99a"), facing)
		if index == 4:
			fill = Color("#c2b6a6")
		draw_colored_polygon(polygon, Color("#a77c4c") if index == _hover else fill)
		var border := polygon.duplicate()
		border.append(polygon[0])
		draw_polyline(border, Color("#d1ae7e") if index == _hover else Color("#c2a574"), 1.2, true)
		if facing > 0.26:
			var font := get_theme_default_font()
			var label := tr(LABELS[index])
			var extent := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
			draw_string(font, _project(inverse * normal) + Vector2(-extent.x * 0.5, 4.0), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#211d1b"))


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
	return tr(LABELS[index]) if index >= 0 else tr("Tažením otočíš pohled")


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
