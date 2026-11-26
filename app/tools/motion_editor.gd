# Copyright 2026 RIGELIO Studio. SPDX-License-Identifier: MIT
extends Control

const PosePreview = preload("res://tools/pose_preview.gd")
const IKPreview = preload("res://tools/ik_preview.gd")
const MARK := Color("#ffd36b")
const BONE := Color("#82caff")

var stage: Control
var skeleton: Skeleton3D
var selected := PackedInt32Array()
var tool := 0
var fps := 30
var mark_seconds := 1.0
var marks: Array[Dictionary] = []
var keys: Array[Dictionary] = []
var finding: Dictionary
var preview_enabled := true
var _preview: SkeletonModifier3D
var _ik: IKPreview
var _ik_pin: Dictionary
var _dragging := false
var _origin := Vector2.ZERO
var _cursor := Vector2.ZERO
var _mark := -1


func update_model(value: Skeleton3D) -> void:
	if skeleton == value:
		return
	if is_instance_valid(_preview):
		_preview.queue_free()
	if is_instance_valid(_ik):
		_ik.queue_free()
	skeleton = value
	selected.clear()
	marks.clear()
	keys.clear()
	_ik_pin = {}
	finding.clear()
	_mark = -1
	_dragging = false
	if skeleton:
		_preview = PosePreview.new()
		_preview.active = preview_enabled
		_preview.set("edits", self)
		skeleton.add_child(_preview)
		_ik = IKPreview.new()
		skeleton.add_child(_ik)


func set_editing(enabled: bool) -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS if enabled else Control.MOUSE_FILTER_IGNORE
	_dragging = false


func clear_selection() -> void:
	selected.clear()
	_mark = -1


func set_preview_enabled(enabled: bool) -> void:
	preview_enabled = enabled
	if is_instance_valid(_preview):
		_preview.active = enabled
	_update_ik()
	if stage.animation_player:
		stage.seek(_time())


func pin_selected() -> bool:
	if not skeleton or not _ik or not stage.animation_player or selected.size() != 1:
		return false
	var bone := selected[0]
	var goal := _pose(bone).origin
	var start := _time()
	return pin_for_interval(bone, goal, start, start + mark_seconds)


func pin_for_interval(bone: int, goal: Vector3, start: float, finish: float) -> bool:
	if not skeleton or not _ik or not stage.animation_player or not _ik.pin(bone, goal):
		return false
	_ik_pin = {"bone": skeleton.get_bone_name(bone), "clip": str(stage.current_clip),
		"start": start, "end": minf(finish, stage.animation_player.current_animation_length),
		"goal": [goal.x, goal.y, goal.z]}
	_update_ik()
	stage.seek(start)
	return true


func clear_ik() -> void:
	_ik_pin = {}
	if is_instance_valid(_ik):
		_ik.clear()
	if stage.animation_player:
		stage.seek(_time())


func current_pin() -> Dictionary:
	return _ik_pin.duplicate(true) if _ik_pin.get("clip") == str(stage.current_clip) else {}


func _update_ik() -> void:
	if is_instance_valid(_ik):
		_ik.active = preview_enabled and not _ik_pin.is_empty() and _active(_ik_pin)


func step(direction: int) -> void:
	var player: AnimationPlayer = stage.animation_player
	if not player:
		return
	player.pause()
	var frame := roundi(player.current_animation_position * fps) + direction
	stage.seek(clampf(float(frame) / fps, 0.0, player.current_animation_length))


func put_key(bone: int, time: float, delta: Quaternion) -> void:
	var clip := str(stage.current_clip)
	var frame := roundi(time * fps)
	for key in keys:
		if key.clip == clip and key.bone == bone and key.frame == frame and key.fps == fps:
			key.delta = delta.normalized()
			stage.seek(time)
			return
	keys.append({"clip": clip, "bone": bone, "frame": frame, "fps": fps, "delta": delta.normalized()})
	stage.seek(time)


func apply_pose(rig: Skeleton3D) -> void:
	if not rig or not stage.animation_player or keys.is_empty():
		return
	var time := _time()
	var clip := str(stage.current_clip)
	for bone in range(rig.get_bone_count()):
		var before := {}
		var after := {}
		var previous := -INF
		var following := INF
		for key in keys:
			if key.bone != bone or key.clip != clip:
				continue
			var sample: float = float(key.frame) / key.fps
			if sample <= time and sample > previous:
				before = key
				previous = sample
			if sample >= time and sample < following:
				after = key
				following = sample
		if before.is_empty() and after.is_empty():
			continue
		var delta := Quaternion.IDENTITY
		if not before.is_empty() and not after.is_empty() and following > previous:
			var first: Quaternion = before.delta
			delta = first.slerp(after.delta, (time - previous) / (following - previous))
		elif not before.is_empty() and absf(time - previous) <= 0.5 / before.fps:
			delta = before.delta
		elif not after.is_empty() and absf(time - following) <= 0.5 / after.fps:
			delta = after.delta
		rig.set_bone_pose_rotation(bone, (rig.get_bone_pose_rotation(bone) * delta).normalized())


func remove_mark() -> void:
	if _mark >= 0 and _mark < marks.size():
		marks.remove_at(_mark)
		_mark = -1


func _time() -> float:
	return stage.animation_player.current_animation_position if stage.animation_player else 0.0


func _pose(bone: int) -> Transform3D:
	return skeleton.global_transform * skeleton.get_bone_global_pose(bone)


func _point(world: Vector3) -> Vector2:
	return stage.camera.unproject_position(world) * size / Vector2(stage.viewport_3d.size)


func _local_point(point: Vector2, pose: Transform3D) -> Vector3:
	var camera: Camera3D = stage.camera
	var depth := maxf(-camera.to_local(pose.origin).z, camera.near)
	var viewport_point := point * Vector2(stage.viewport_3d.size) / size
	return pose.affine_inverse() * camera.project_position(viewport_point, depth)


func _closest_bone(point: Vector2) -> int:
	var picked := -1
	var distance := 42.0
	for bone in range(skeleton.get_bone_count()):
		var position := _pose(bone).origin
		if stage.camera.is_position_behind(position):
			continue
		var gap := _point(position).distance_to(point)
		if gap < distance:
			picked = bone
			distance = gap
	return picked


func _active(mark: Dictionary) -> bool:
	return mark.clip == str(stage.current_clip) and _time() >= mark.start and _time() <= mark.end


func _gui_input(event: InputEvent) -> void:
	if not skeleton or not stage.animation_player:
		return
	# The editor overlays the stage. Forward camera events which the overlay does not handle.
	if event is InputEventMouse and not _dragging \
			and (event is InputEventMouseMotion or event.button_index != MOUSE_BUTTON_LEFT):
		stage._gui_input(event)
		return
	if event is InputEventMouseMotion and _dragging:
		_cursor = event.position
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			stage.animation_player.pause()
			_origin = event.position
			_cursor = _origin
			_dragging = true
		elif _dragging:
			_dragging = false
			if tool == 0:
				_select_or_move(event.position, event.ctrl_pressed)
			else:
				_add_mark(event.position)
		accept_event()


func _select_or_move(finish: Vector2, additive: bool) -> void:
	_mark = -1
	if not additive:
		for index in range(marks.size() - 1, -1, -1):
			var mark := marks[index]
			if not _active(mark):
				continue
			var pose := _pose(mark.bone)
			if _point(pose * mark.points[0]).distance_to(_origin) > 16.0 or is_zero_approx(pose.basis.determinant()):
				continue
			_mark = index
			selected = PackedInt32Array([mark.bone])
			var offset := _local_point(finish, pose) - _local_point(_origin, pose)
			for index_in_mark in range(mark.points.size()):
				mark.points[index_in_mark] += offset
			return
		selected.clear()
	if _origin.distance_to(finish) > 6.0:
		var region := Rect2(_origin, finish - _origin).abs()
		for bone in range(skeleton.get_bone_count()):
			var position := _pose(bone).origin
			if not stage.camera.is_position_behind(position) and region.has_point(_point(position)) and not selected.has(bone):
				selected.append(bone)
		return
	var bone := _closest_bone(finish)
	if bone >= 0:
		var previous := selected.find(bone)
		if previous >= 0:
			selected.remove_at(previous)
		else:
			selected.append(bone)


func _add_mark(finish: Vector2) -> void:
	var bone := selected[0] if selected.size() == 1 else _closest_bone(_origin)
	if bone < 0:
		return
	var pose := _pose(bone)
	if is_zero_approx(pose.basis.determinant()):
		return
	var positions: Array[Vector2] = [_origin]
	if tool in [2, 3]:
		positions.append(finish)
	if tool == 4:
		var radius := maxf(_origin.distance_to(finish), 8.0)
		for segment in range(25):
			positions.append(_origin + Vector2.from_angle(TAU * segment / 24.0) * radius)
	var points: Array[Vector3] = []
	for position in positions:
		points.append(_local_point(position, pose))
	var now := _time()
	marks.append({"clip": str(stage.current_clip), "bone": bone, "shape": tool,
		"points": points, "start": now, "end": minf(now + mark_seconds, stage.animation_player.current_animation_length)})
	_mark = marks.size() - 1


func _process(_delta: float) -> void:
	_update_ik()
	queue_redraw()


func _draw() -> void:
	if not skeleton or not stage.animation_player or size.x <= 0.0 or size.y <= 0.0:
		return
	for bone in selected:
		var origin := _pose(bone).origin
		if not stage.camera.is_position_behind(origin):
			draw_circle(_point(origin), 6.0, BONE, false, 2.0, true)
	draw_annotations(self, stage.camera, size / Vector2(stage.viewport_3d.size))
	if _dragging and tool == 0:
		draw_rect(Rect2(_origin, _cursor - _origin).abs(), BONE, false, 1.0)


func draw_annotations(target: CanvasItem, camera: Camera3D, scale := Vector2.ONE) -> void:
	if not skeleton or not stage.animation_player:
		return
	if not finding.is_empty() and finding.clip == str(stage.current_clip) and _time() >= finding.start - 0.02 and _time() <= finding.end + 0.02:
		var bone := skeleton.find_bone(finding.bone)
		if bone >= 0:
			var origin := _pose(bone).origin
			if not camera.is_position_behind(origin):
				target.draw_circle(camera.unproject_position(origin) * scale, 13.0, Color.SALMON, false, 3.0, true)
	for index in range(marks.size()):
		var mark := marks[index]
		if _active(mark):
			_draw_mark(target, camera, scale, mark, WHITE if target == self and index == _mark else MARK)


const WHITE := Color("#fff8e7")

func _draw_mark(target: CanvasItem, camera: Camera3D, scale: Vector2, mark: Dictionary, color: Color) -> void:
	var pose := _pose(mark.bone)
	if camera.is_position_behind(pose.origin):
		return
	var points := PackedVector2Array()
	for point: Vector3 in mark.points:
		points.append(camera.unproject_position(pose * point) * scale)
	match int(mark.shape):
		1: target.draw_circle(points[0], 5.0, color, true, -1, true)
		2: target.draw_line(points[0], points[1], color, 2.5, true)
		3:
			target.draw_line(points[0], points[1], color, 2.5, true)
			var tail := (points[0] - points[1]).normalized() * 14.0
			target.draw_polyline(PackedVector2Array([points[1] + tail.rotated(-0.45), points[1], points[1] + tail.rotated(0.45)]), color, 2.5, true)
		4: target.draw_polyline(points.slice(1), color, 2.5, true)


func exported_edits() -> Dictionary:
	var annotated: Array[Dictionary] = []
	for mark in marks:
		var entry := mark.duplicate()
		entry.bone = skeleton.get_bone_name(mark.bone)
		entry.points = []
		for point: Vector3 in mark.points:
			entry.points.append([point.x, point.y, point.z])
		annotated.append(entry)
	var poses: Array[Dictionary] = []
	for key in keys:
		var entry := key.duplicate()
		var delta: Quaternion = key.delta
		entry.delta = [delta.x, delta.y, delta.z, delta.w]
		entry.bone = skeleton.get_bone_name(key.bone)
		poses.append(entry)
	return {"annotations": annotated, "pose_keys": poses, "ik_pin": _ik_pin.duplicate()}
