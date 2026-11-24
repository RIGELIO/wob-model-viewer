extends Control

const AXES := [Vector3.RIGHT, Vector3.UP, Vector3.BACK, Vector3.LEFT, Vector3.DOWN, Vector3.FORWARD]
const LABELS := ["X", "Y", "Z", "−X", "−Y", "−Z"]
const COLORS := [Color("#ef785b"), Color("#91dc6c"), Color("#8ca6fc")]
const RADIUS := 34.0
const DOT := 10.0

var stage: SubViewportContainer
var _camera_basis := Basis.IDENTITY
var _draw_order: Array[int] = []
var _projection: Array[Vector3] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	custom_minimum_size = Vector2(100.0, 100.0)
	queue_redraw()


func _process(_delta: float) -> void:
	if stage == null or stage.camera == null:
		return
	var basis: Basis = stage.camera.global_basis
	if not basis.is_equal_approx(_camera_basis):
		_camera_basis = basis
		queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var inverse := _camera_basis.inverse()
	_draw_order.clear()
	_projection.clear()
	for index in range(AXES.size()):
		_draw_order.append(index)
		_projection.append(inverse * AXES[index])
	_draw_order.sort_custom(func(a: int, b: int) -> bool: return _projection[a].z < _projection[b].z)
	draw_circle(center, 46.0, Color("#18191cdf"), true, -1.0, true)
	draw_circle(center, 46.0, Color("#81705b"), false, 1.0, true)
	for index in _draw_order:
		var axis_color: Color = COLORS[index % 3]
		var positive := index < 3
		draw_line(center, _endpoint(index), axis_color if positive else axis_color.darkened(0.5), 1.5, true)
	for index in _draw_order:
		var axis_color: Color = COLORS[index % 3]
		var positive := index < 3
		var position := _endpoint(index)
		draw_circle(position, DOT if positive else DOT * 0.67, axis_color if positive else axis_color.darkened(0.48), true, -1.0, true)
		if positive:
			var font := get_theme_default_font()
			var label: String = LABELS[index]
			var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			draw_string(font, position + Vector2(-width * 0.5, 4.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#151719"))


func _endpoint(index: int) -> Vector2:
	var projected := _projection[index]
	return size * 0.5 + Vector2(projected.x, -projected.y) * RADIUS


func _pick(position: Vector2) -> int:
	for depth_index in range(_draw_order.size() - 1, -1, -1):
		var axis := _draw_order[depth_index]
		if _endpoint(axis).distance_squared_to(position) <= DOT * DOT:
			return axis
	return -1


func _get_tooltip(at_position: Vector2) -> String:
	var index := _pick(at_position)
	return LABELS[index] if index >= 0 else ""


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var index := _pick(event.position)
		if index >= 0 and stage:
			stage.orient_to(AXES[index])
			accept_event()
