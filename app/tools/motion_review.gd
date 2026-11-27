# Copyright 2026 RIGELIO Studio. SPDX-License-Identifier: MIT
extends RefCounted


static func sample(stage: Control, skeleton: Skeleton3D, start: float, finish: float, fps: int,
		ground_y: float) -> Dictionary:
	var player: AnimationPlayer = stage.animation_player
	var original_time := player.current_animation_position
	var was_playing := player.is_playing()
	var in_place: bool = stage._animation_in_place
	var clip := player.get_animation(stage.current_clip)
	var loop_mode := clip.loop_mode
	player.pause()
	clip.loop_mode = Animation.LOOP_NONE
	stage.animation_in_place(false)
	var names := PackedStringArray()
	for bone in range(skeleton.get_bone_count()):
		names.append(skeleton.get_bone_name(bone))
	var poses: Array[PackedVector3Array] = []
	var rotations: Array[Array] = []
	var count := ceili((finish - start) * fps) + 1
	for frame in range(count):
		stage.seek(minf(finish, start + float(frame) / fps))
		var positions := PackedVector3Array()
		var pose_rotations: Array[Quaternion] = []
		for bone in range(names.size()):
			positions.append(skeleton.to_global(skeleton.get_bone_global_pose(bone).origin))
			pose_rotations.append(skeleton.get_bone_pose_rotation(bone).normalized())
		poses.append(positions)
		rotations.append(pose_rotations)
	clip.loop_mode = loop_mode
	stage.seek(original_time)
	stage.animation_in_place(in_place)
	if was_playing:
		stage.resume_preview()

	var findings: Array[Dictionary] = []
	var scale: float = maxf(stage.bounds.size.y, 0.1)
	for bone in range(names.size()):
		var label: String = names[bone]
		var lower := label.to_lower()
		if "foot" in lower or "ankle" in lower or "chodid" in lower:
			_find_slides(findings, poses, bone, label, start, fps, scale)
			_find_ground_penetration(findings, poses, bone, label, start, finish, fps, ground_y,
				maxf(0.005, scale * 0.005))
		_find_spike(findings, rotations, bone, label, start, fps)
	var seam := 0.0
	var seam_bone := -1
	for bone in range(names.size()):
		var first: Quaternion = rotations[0][bone]
		var last: Quaternion = rotations[-1][bone]
		var angle := rad_to_deg(first.angle_to(last))
		if angle > seam:
			seam = angle
			seam_bone = bone
	if seam_bone >= 0 and seam > 14.0:
		findings.append({"type": "loop_seam", "bone": names[seam_bone], "start": finish, "end": finish,
			"value": snappedf(seam, 0.01), "unit": "deg", "recommendation": "Review the last-to-first pose transition."})
	findings.sort_custom(func(a: Dictionary, b: Dictionary): return a.start < b.start)
	return {"schema": 1, "clip": str(stage.current_clip), "from": start, "to": finish,
		"fps": fps, "ground_y": ground_y, "findings": findings}


static func _find_ground_penetration(out: Array[Dictionary], poses: Array[PackedVector3Array],
		bone: int, label: String, start: float, finish: float, fps: int, ground_y: float,
		tolerance: float) -> void:
	var first := -1
	var depth := 0.0
	for frame in range(poses.size() + 1):
		var penetration := ground_y - poses[frame][bone].y if frame < poses.size() else 0.0
		if penetration > tolerance:
			if first < 0:
				first = frame
			depth = maxf(depth, penetration)
		elif first >= 0:
			var contact := poses[first][bone]
			out.append({"type": "ground_penetration", "bone": label,
				"start": minf(finish, start + float(first) / fps),
				"end": minf(finish, start + float(frame - 1) / fps),
				"value": snappedf(depth, 0.001), "unit": "m",
				"ik_goal": [contact.x, ground_y, contact.z],
				"recommendation": "Preview a foot IK pin at the floor, then check the sole and knee."})
			first = -1
			depth = 0.0


static func _find_slides(out: Array[Dictionary], poses: Array[PackedVector3Array], bone: int,
		label: String, start: float, fps: int, scale: float) -> void:
	var floor_y := INF
	for pose in poses:
		floor_y = minf(floor_y, pose[bone].y)
	var first := 0
	var travel := 0.0
	for frame in range(1, poses.size() + 1):
		var distance := 0.0
		if frame < poses.size():
			var before := poses[frame - 1][bone]
			var after := poses[frame][bone]
			if maxf(before.y, after.y) - floor_y <= scale * 0.03:
				distance = Vector2(after.x - before.x, after.z - before.z).length()
		if distance * fps > scale * 0.10:
			if first == 0:
				first = frame
			travel += distance
			continue
		if first > 0 and float(frame - first) / fps >= 0.12:
			out.append({"type": "foot_slide", "bone": label, "start": start + float(first - 1) / fps,
				"end": start + float(frame - 1) / fps, "value": snappedf(travel, 0.001), "unit": "m",
				"recommendation": "Check ground contact in this interval and consider a foot IK pin."})
		first = 0
		travel = 0.0


static func _find_spike(out: Array[Dictionary], rotations: Array[Array], bone: int,
		label: String, start: float, fps: int) -> void:
	var worst := 21.0
	var best := -1
	var repair := Quaternion.IDENTITY
	for frame in range(1, rotations.size() - 1):
		var before: Quaternion = rotations[frame - 1][bone]
		var after: Quaternion = rotations[frame + 1][bone]
		var expected := before.slerp(after, 0.5)
		var current: Quaternion = rotations[frame][bone]
		var residual := rad_to_deg(expected.angle_to(current))
		if rad_to_deg(before.angle_to(after)) < 32.0 and residual > worst:
			worst = residual
			best = frame
			repair = expected
	if best >= 0:
		var time := start + float(best) / fps
		out.append({"type": "rotation_spike", "bone": label, "start": time, "end": time,
			"value": snappedf(worst, 0.01), "unit": "deg",
			"correction": [repair.x, repair.y, repair.z, repair.w],
			"recommendation": "Preview an orientation interpolated from the adjacent samples."})
