# Copyright 2026 RIGELIO Studio. SPDX-License-Identifier: MIT
extends Control

signal selection_changed
signal preview_changed
signal weight_selection_changed
signal timeline_changed

const Draft = preload("res://tools/rig_draft.gd")
const SkinPreview = preload("res://tools/rig_skin_preview.gd")
const RigMotion = preload("res://tools/rig_motion.gd")
const JOINT := Color("#9cd3ff")
const ACTIVE := Color("#ffd082")
const NO_VERTEX := Vector3i(-1, -1, -1)

enum Motion { TEST_POSE, WALK, RUN }

var stage: Control
var selected := -1
var placing := false
var weight_mode := false
var selected_vertex := NO_VERTEX
var _drafts: Dictionary
var _model_path := ""
var _draft: RefCounted
var _dragging := false
var _drag_depth := 0.0
var _drag_delta := Vector3.ZERO
var _preview: SkinPreview
var _preview_model: RefCounted
var _pose_axis := Vector3.RIGHT
var _pose_degrees := 30.0
var motion := Motion.TEST_POSE
var motion_playing := false
var motion_phase := 0.0
var motion_speed := 1.0
var _motion_profile: Dictionary


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_window().focus_exited.connect(_cancel_drag)


func set_model(path: String) -> void:
	stop_skin_preview()
	if _model_path == path:
		_cancel_drag()
		return
	_model_path = path
	_draft = _drafts.get(path)
	_reset_input()


func reset_template(kind: int) -> void:
	_set_draft(Draft.fit(kind, stage.bounds))


func toggle_placement() -> void:
	stop_skin_preview()
	placing = not placing
	if not _draft:
		_draft = Draft.fit(-1, stage.bounds)
		_drafts[_model_path] = _draft
	selection_changed.emit()


func has_joints() -> bool:
	return _draft != null and not _draft.joints.is_empty()


func selection_label() -> String:
	if selected < 0:
		return ""
	return _draft.joints[selected].name


func rename_selected(label: String) -> bool:
	if not _draft or not _draft.rename_joint(selected, label):
		return false
	stop_skin_preview()
	selection_changed.emit()
	return true


func save(path: String) -> Error:
	if not has_joints():
		return ERR_DOES_NOT_EXIST
	return _draft.save(path, _model_path.get_file())


func load_draft(path: String) -> bool:
	var loaded := Draft.read(path, _model_path.get_file())
	if not loaded:
		return false
	_set_draft(loaded)
	return true


func _set_draft(value: RefCounted) -> void:
	stop_skin_preview()
	_draft = value
	_drafts[_model_path] = value
	_reset_input()


func _reset_input() -> void:
	selected = -1
	placing = false
	_cancel_drag()
	selection_changed.emit()


func _cancel_drag() -> void:
	_dragging = false


func _process(delta: float) -> void:
	if _preview and (not visible or stage.model != _preview_model or not _skin_display_available()):
		stop_skin_preview()
	if motion_playing and motion_speed > 0.0:
		motion_phase = fposmod(motion_phase + delta * motion_speed / motion_length(), 1.0)
		_update_pose()
	if visible:
		queue_redraw()
	elif _dragging:
		_cancel_drag()


func has_skin_preview() -> bool:
	return _preview != null


func unmatched_weight_count() -> int:
	return _preview.unmatched_weight_count() if _preview else 0


func remapped_weight_count() -> int:
	return _preview.remapped_weight_count() if _preview else 0


func discard_unmatched_weights() -> void:
	if _preview:
		_preview.discard_unmatched_weights()
		_draft.weights.assign(_preview.resolved_weights())
		weight_selection_changed.emit()


func selected_weight_conflicts() -> bool:
	return weight_mode and _preview.has_unmatched_weight(selected_vertex)


func can_preview_skin() -> bool:
	return visible and has_joints() and stage.model != null and stage.clips.is_empty() \
		and stage._skeletons.is_empty() and _skin_display_available()


func _skin_display_available() -> bool:
	return stage._display_mode == 0 and not stage._isolated


func start_skin_preview(authorized: Callable) -> bool:
	if not can_preview_skin() or not authorized.call():
		return false
	var model: RefCounted = stage.model
	var draft := _draft
	var anchor: Node3D = stage._model_anchor
	var next := SkinPreview.new()
	var valid := func() -> bool:
		return visible and stage.model == model and _draft == draft and _skin_display_available() and authorized.call()
	if not await next.build(draft.joints.duplicate(true), model.meshes, anchor, stage.bounds.size.length(),
			get_tree(), valid, draft.weights.duplicate(true)) or not valid.call():
		next.free()
		return false
	placing = false
	_cancel_drag()
	_preview = next
	_preview_model = model
	draft.weights.assign(next.resolved_weights())
	_motion_profile = RigMotion.get_profile(next.skeleton)
	anchor.add_child(_preview)
	_preview.show_preview()
	if selected < 0:
		selected = _initial_pose_joint()
	_update_pose()
	selection_changed.emit()
	preview_changed.emit()
	return true


func stop_skin_preview() -> void:
	if not _preview:
		return
	_preview.restore_sources()
	_preview.queue_free()
	_preview = null
	_preview_model = null
	_motion_profile.clear()
	motion = Motion.TEST_POSE
	motion_playing = false
	motion_phase = 0.0
	weight_mode = false
	selected_vertex = NO_VERTEX
	preview_changed.emit()


func has_motion_profile() -> bool:
	return has_skin_preview() and not _motion_profile.is_empty()


func motion_profile() -> Dictionary:
	return _motion_profile


func set_motion(index: int) -> void:
	if not has_motion_profile() or weight_mode or index < Motion.TEST_POSE or index > Motion.RUN:
		return
	var from_test_pose := motion == Motion.TEST_POSE
	motion = index as Motion
	if motion == Motion.TEST_POSE:
		motion_playing = false
		motion_phase = 0.0
		_preview.skeleton.reset_bone_poses()
	elif from_test_pose:
		motion_playing = true
	_update_pose()


func toggle_motion_playback() -> void:
	if motion != Motion.TEST_POSE:
		motion_playing = not motion_playing


func seek_motion(phase: float) -> void:
	if motion != Motion.TEST_POSE and is_finite(phase):
		motion_phase = clampf(phase, 0.0, 1.0)
		_update_pose()
		timeline_changed.emit()


func set_motion_speed(value: float) -> void:
	if is_finite(value):
		motion_speed = clampf(value, 0.0, 2.0)


func motion_length() -> float:
	return RigMotion.duration(_motion_profile, motion == Motion.RUN)


func step_motion_frame(direction: int) -> void:
	if motion == Motion.TEST_POSE or direction == 0:
		return
	motion_playing = false
	var frames := motion_length() * 30.0
	var position := motion_phase * frames
	var target := floorf(position + 0.000001) + 1.0 if direction > 0 else ceilf(position - 0.000001) - 1.0
	seek_motion(target / frames)


func set_pose_axis(index: int) -> void:
	_pose_axis = [Vector3.RIGHT, Vector3.UP, Vector3.BACK][index]
	_update_pose()


func set_pose_degrees(degrees: float) -> void:
	_pose_degrees = degrees
	_update_pose()


func set_weight_mode(enabled: bool) -> void:
	weight_mode = enabled and _preview != null
	selected_vertex = NO_VERTEX
	if weight_mode and motion != Motion.TEST_POSE:
		motion = Motion.TEST_POSE
		motion_playing = false
		motion_phase = 0.0
		_preview.skeleton.reset_bone_poses()
	if weight_mode and selected < 0:
		selected = _initial_pose_joint()
	_update_pose()
	weight_selection_changed.emit()
	selection_changed.emit()


func weight_bones() -> PackedStringArray:
	var labels := PackedStringArray()
	for joint: Dictionary in _draft.joints:
		labels.append(joint.name)
	return labels


func choose_weight_bone(index: int) -> void:
	selected = index
	weight_selection_changed.emit()
	selection_changed.emit()


func selected_weight() -> float:
	if not weight_mode or selected_vertex == NO_VERTEX:
		return 0.0
	var data := _preview.vertex_data(selected_vertex)
	var value := 0.0
	for index in range(data.bones.size()):
		if data.bones[index] == selected:
			value += data.weights[index]
	return value


func set_vertex_weight(weight: float) -> bool:
	if not weight_mode or selected_vertex == NO_VERTEX:
		return false
	var data := _preview.edited_vertex(selected_vertex, selected, weight)
	if data.is_empty() or not _preview.apply_vertex(selected_vertex, data):
		return false
	_draft.weights[selected_vertex] = data
	weight_selection_changed.emit()
	return true


func _initial_pose_joint() -> int:
	for joint in range(_draft.joints.size()):
		var label: String = _draft.joints[joint].name.to_lower()
		if "knee" in label or "elbow" in label:
			return joint
	for joint: Dictionary in _draft.joints:
		if joint.parent >= 0:
			return joint.parent
	return 0


func _update_pose() -> void:
	if not _preview:
		return
	if motion == Motion.TEST_POSE:
		_preview.pose(-1 if weight_mode else selected, _pose_axis, _pose_degrees)
	else:
		RigMotion.apply(_preview.skeleton, _motion_profile, motion == Motion.RUN, motion_phase)


func _joint_point(index: int) -> Vector3:
	return _preview.joint_point(index) if _preview else _draft.joints[index].point


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not stage.model or not event is InputEventMouse:
		return
	if _dragging and event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_move_joint(_local_mouse(event.position))
			get_viewport().set_input_as_handled()
		else:
			_cancel_drag()
		return
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if not event.pressed:
		if _dragging:
			_cancel_drag()
			get_viewport().set_input_as_handled()
		return
	var hovered := get_viewport().gui_get_hovered_control()
	if hovered != stage and (not hovered or not stage.is_ancestor_of(hovered)):
		return
	if _press(_local_mouse(event.position)):
		get_viewport().set_input_as_handled()


func _local_mouse(point: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * point


func _press(point: Vector2) -> bool:
	if not Rect2(Vector2.ZERO, size).has_point(point):
		return false
	if weight_mode:
		var camera: Camera3D = stage.camera
		var anchor: Node3D = stage._model_anchor
		var pixel := point / _projection_scale()
		var origin := camera.project_ray_origin(pixel)
		var direction := camera.project_ray_normal(pixel)
		selected_vertex = _preview.pick_vertex(anchor.to_local(origin + direction * camera.near),
			anchor.to_local(origin + direction * camera.far))
		weight_selection_changed.emit()
		return selected_vertex != NO_VERTEX
	if placing:
		var reference: Vector3 = _draft.joints[selected].point if selected >= 0 else stage.bounds.get_center()
		var depth := _depth(reference)
		if depth > stage.camera.near:
			var joint: int = _draft.add_joint(selected, _point_at_depth(point, depth))
			if joint >= 0:
				selected = joint
				placing = false
				selection_changed.emit()
		return true
	var joint := _pick(point)
	if joint < 0:
		if selected >= 0:
			selected = -1
			_update_pose()
			selection_changed.emit()
		return false
	selected = joint
	if _preview:
		_update_pose()
		selection_changed.emit()
		return true
	var current: Vector3 = _draft.joints[joint].point
	_drag_depth = _depth(current)
	_drag_delta = current - _point_at_depth(point, _drag_depth)
	_dragging = true
	selection_changed.emit()
	return true


func _move_joint(point: Vector2) -> void:
	var moved := _point_at_depth(point, _drag_depth) + _drag_delta
	if moved.is_finite():
		_draft.joints[selected].point = moved


func _projection_scale() -> Vector2:
	var camera: Camera3D = stage.camera
	return size / camera.get_viewport().get_visible_rect().size.max(Vector2.ONE)


func _point_at_depth(point: Vector2, depth: float) -> Vector3:
	var world: Vector3 = stage.camera.project_position(point / _projection_scale(), depth)
	return stage._model_anchor.to_local(world)


func _depth(point: Vector3) -> float:
	var camera: Camera3D = stage.camera
	var world: Vector3 = stage._model_anchor.to_global(point)
	return -(camera.get_camera_transform().affine_inverse() * world).z


func _project(point: Vector3) -> Vector2:
	var world: Vector3 = stage._model_anchor.to_global(point)
	if _depth(point) <= stage.camera.near:
		return Vector2.INF
	return stage.camera.unproject_position(world) * _projection_scale()


func _pick(point: Vector2) -> int:
	if not has_joints():
		return -1
	var nearest := -1
	var distance := 13.0
	for index in range(_draft.joints.size()):
		var center := _project(_joint_point(index))
		var candidate := center.distance_to(point)
		if candidate < distance:
			nearest = index
			distance = candidate
	return nearest


func _draw() -> void:
	if not has_joints() or not stage.camera or size.x <= 0.0 or size.y <= 0.0:
		return
	var points := PackedVector2Array()
	for index in range(_draft.joints.size()):
		points.append(_project(_joint_point(index)))
	for index in range(points.size()):
		var parent: int = _draft.joints[index].parent
		if parent >= 0 and points[index].is_finite() and points[parent].is_finite():
			draw_line(points[parent], points[index], Color("#141a24"), 5.0, true)
			draw_line(points[parent], points[index], JOINT, 2.0, true)
	for index in range(points.size()):
		if points[index].is_finite():
			draw_circle(points[index], 7.0, Color("#141a24"), true, -1.0, true)
			draw_circle(points[index], 5.0, ACTIVE if selected == index else JOINT, true, -1.0, true)
	if weight_mode and selected_vertex != NO_VERTEX:
		var point := _project(_preview.vertex_data(selected_vertex).point)
		if point.is_finite():
			draw_circle(point, 9.0, ACTIVE, false, 2.0, true)
