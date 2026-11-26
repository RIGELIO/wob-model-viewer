# Copyright 2026 RIGELIO Studio. SPDX-License-Identifier: MIT
extends RefCounted

const TORSO := {"pelvis": "", "spine": "pelvis", "chest": "spine", "neck": "chest", "head": "neck"}
const HUMAN := {
	"shoulder_l": "chest", "elbow_l": "shoulder_l", "hand_l": "elbow_l",
	"shoulder_r": "chest", "elbow_r": "shoulder_r", "hand_r": "elbow_r",
	"hip_l": "pelvis", "knee_l": "hip_l", "foot_l": "knee_l", "toe_l": "foot_l",
	"hip_r": "pelvis", "knee_r": "hip_r", "foot_r": "knee_r", "toe_r": "foot_r",
}
const QUADRUPED := {
	"frontshoulder_l": "chest", "frontelbow_l": "frontshoulder_l", "frontfoot_l": "frontelbow_l",
	"frontshoulder_r": "chest", "frontelbow_r": "frontshoulder_r", "frontfoot_r": "frontelbow_r",
	"hindhip_l": "pelvis", "hindknee_l": "hindhip_l", "hindhock_l": "hindknee_l", "hindfoot_l": "hindhock_l",
	"hindhip_r": "pelvis", "hindknee_r": "hindhip_r", "hindhock_r": "hindknee_r", "hindfoot_r": "hindhock_r",
	"tail": "pelvis",
}
const HUMAN_CONTACTS := ["toe_l", "toe_r", "foot_l", "foot_r"]
const QUADRUPED_CONTACTS := ["frontfoot_l", "frontfoot_r", "hindfoot_l", "hindfoot_r"]


static func get_profile(skeleton: Skeleton3D) -> Dictionary:
	if not is_instance_valid(skeleton):
		return {}
	var names := {}
	for bone in range(skeleton.get_bone_count()):
		var key := skeleton.get_bone_name(bone).to_lower()
		if names.has(key):
			return {}
		names[key] = bone
	var joints := _match_joints(skeleton, names, HUMAN)
	var kind := "human"
	var contacts := HUMAN_CONTACTS
	if joints.is_empty():
		joints = _match_joints(skeleton, names, QUADRUPED)
		kind = "quadruped"
		contacts = QUADRUPED_CONTACTS
	if joints.is_empty():
		return {}
	var pelvis: int = joints["pelvis"]["index"]
	var lowest := INF
	var feet := PackedInt32Array()
	for name: String in contacts:
		var foot: int = joints[name]["index"]
		feet.append(foot)
		lowest = minf(lowest, skeleton.get_bone_global_rest(foot).origin.y)
	var height := skeleton.get_bone_global_rest(pelvis).origin.y - lowest
	if not is_finite(height) or height <= 0.00001:
		return {}
	return {"kind": kind, "skeleton": skeleton.get_instance_id(), "version": skeleton.get_version(),
		"joints": joints, "feet": feet, "floor": lowest, "height": height}


static func duration(profile: Dictionary, running: bool) -> float:
	match profile.get("kind", ""):
		"human":
			return 0.68 if running else 1.08
		"quadruped":
			return 0.76 if running else 1.28
	return 0.0


static func apply(skeleton: Skeleton3D, profile: Dictionary, running: bool, phase: float) -> void:
	if not is_instance_valid(skeleton) or not is_finite(phase) or profile.is_empty() \
		or profile.get("skeleton") != skeleton.get_instance_id() or profile.get("version") != skeleton.get_version():
		return
	var time := fposmod(phase, 1.0)
	var joints: Dictionary = profile.joints
	skeleton.reset_bone_poses()
	if profile.kind == "human":
		_human(skeleton, joints, running, time)
	else:
		_quadruped(skeleton, joints, running, time)

	var pelvis: int = joints["pelvis"]["index"]
	var origin := skeleton.get_bone_rest(pelvis).origin
	var ripple := 0.5 - 0.5 * cos(2.0 * TAU * time)
	var height: float = profile.height
	origin.x += height * sin(TAU * time) * (0.009 if running else 0.021)
	origin.y += height * ripple * (0.075 if running else 0.021)
	skeleton.set_bone_pose_position(pelvis, origin)
	var lowest := INF
	for foot in profile.feet:
		lowest = minf(lowest, skeleton.get_bone_global_pose(foot).origin.y)
	# Keep the articulated draft feet above their lowest rest-contact height.
	var lift := maxf(0.0, float(profile.floor) - lowest)
	if lift > 0.0:
		skeleton.set_bone_pose_position(pelvis, origin + Vector3.UP * lift)
	skeleton.force_update_all_bone_transforms()


static func _match_joints(skeleton: Skeleton3D, names: Dictionary, layout: Dictionary) -> Dictionary:
	var links := TORSO.duplicate()
	links.merge(layout)
	var result := {}
	for name: String in links:
		if not names.has(name):
			return {}
		var bone: int = names[name]
		var parent: String = links[name]
		var parent_index: int = names.get(parent, -1)
		if (not parent.is_empty() and parent_index < 0) or skeleton.get_bone_parent(bone) != parent_index:
			return {}
		var rest := skeleton.get_bone_rest(bone)
		var global_rest := skeleton.get_bone_global_rest(bone)
		if not rest.is_finite() or not global_rest.is_finite() or rest.basis.determinant() <= 0.000001 \
			or global_rest.basis.determinant() <= 0.000001:
			return {}
		result[name] = {"index": bone, "rest": rest.basis.get_rotation_quaternion(),
			"axis": global_rest.basis.get_rotation_quaternion().inverse()}
	return result


static func _human(skeleton: Skeleton3D, joints: Dictionary, running: bool, phase: float) -> void:
	var twist := cos(TAU * phase)
	var sway := sin(TAU * phase)
	var pitch := -8.0 if running else -2.5
	_rotate(skeleton, joints.pelvis, Vector3(pitch, 4.0 * twist, 2.3 * sway))
	_rotate(skeleton, joints.spine, Vector3(pitch * 0.45, -2.8 * twist, -1.3 * sway))
	_rotate(skeleton, joints.chest, Vector3(pitch * 0.30, -5.0 * twist, -1.1 * sway))
	_rotate(skeleton, joints.neck, Vector3(-pitch * 0.80, 2.6 * twist, 0.0))
	_rotate(skeleton, joints.head, Vector3(-pitch * 0.55, 1.2 * twist, 0.0))

	var stance := 0.44 if running else 0.62
	for side in range(2):
		var suffix := "_l" if side == 0 else "_r"
		var sign_z := 1.0 if side == 0 else -1.0
		var stride := _stride(phase + 0.5 * side, stance)
		var hip := stride.x * (34.0 if running else 21.0) + (5.0 if running else 1.5)
		var knee := -4.0 - stride.y * (76.0 if running else 37.0)
		var ankle := clampf(-0.74 * (hip + knee) + stride.y * 3.0, -22.0, 29.0)
		_rotate(skeleton, joints["hip" + suffix], Vector3(hip, 0.0, 0.0))
		_rotate(skeleton, joints["knee" + suffix], Vector3(knee, 0.0, 0.0))
		_rotate(skeleton, joints["foot" + suffix], Vector3(ankle, 0.0, 0.0))
		_rotate(skeleton, joints["toe" + suffix], Vector3(-0.25 * ankle, 0.0, 0.0))
		var shoulder := -stride.x * (30.0 if running else 16.0)
		var elbow := (42.0 if running else 11.0) + (0.5 - 0.5 * stride.x) * (22.0 if running else 10.0)
		_rotate(skeleton, joints["shoulder" + suffix], Vector3(shoulder, 0.0, 20.0 * sign_z))
		_rotate(skeleton, joints["elbow" + suffix], Vector3(elbow, 0.0, 2.0 * sign_z))


static func _quadruped(skeleton: Skeleton3D, joints: Dictionary, running: bool, phase: float) -> void:
	var rock := sin(TAU * phase)
	var nod := sin(2.0 * TAU * phase)
	_rotate(skeleton, joints.pelvis, Vector3(2.0 * nod, 2.0 * rock, 1.7 * rock))
	_rotate(skeleton, joints.spine, Vector3(-3.0 * nod, -1.5 * rock, -0.7 * rock))
	_rotate(skeleton, joints.chest, Vector3(-1.0 * nod, -1.0 * rock, -1.1 * rock))
	_rotate(skeleton, joints.neck, Vector3(4.0 * nod, 1.0 * rock, 0.0))
	_rotate(skeleton, joints.head, Vector3(-3.2 * nod, 0.0, -0.9 * rock))
	_rotate(skeleton, joints.tail, Vector3(4.0 * nod, (11.0 if running else 8.0) * rock, 0.0))

	var stance := 0.44 if running else 0.67
	var front_shift := 0.5 if running else 0.25
	for side in range(2):
		var suffix := "_l" if side == 0 else "_r"
		var hind := _stride(phase + 0.5 * side, stance)
		var front := _stride(phase + 0.5 * side + front_shift, stance)
		var shoulder := front.x * (32.0 if running else 19.0)
		var elbow := -front.y * (53.0 if running else 32.0)
		var hip := hind.x * (35.0 if running else 22.0)
		var knee := -hind.y * (44.0 if running else 27.0)
		var hock := hind.y * (43.0 if running else 26.0)
		_rotate(skeleton, joints["frontshoulder" + suffix], Vector3(shoulder, 0.0, 0.0))
		_rotate(skeleton, joints["frontelbow" + suffix], Vector3(elbow, 0.0, 0.0))
		_rotate(skeleton, joints["frontfoot" + suffix], Vector3(-0.6 * (shoulder + elbow), 0.0, 0.0))
		_rotate(skeleton, joints["hindhip" + suffix], Vector3(hip, 0.0, 0.0))
		_rotate(skeleton, joints["hindknee" + suffix], Vector3(knee, 0.0, 0.0))
		_rotate(skeleton, joints["hindhock" + suffix], Vector3(hock, 0.0, 0.0))
		_rotate(skeleton, joints["hindfoot" + suffix], Vector3(-0.6 * (hip + knee + hock), 0.0, 0.0))


static func _stride(phase: float, stance: float) -> Vector2:
	var time := fposmod(phase, 1.0)
	if time < stance:
		return Vector2(cos(PI * time / stance), 0.0)
	var swing := PI * (time - stance) / (1.0 - stance)
	var lift := sin(swing)
	return Vector2(-cos(swing), lift * lift)


static func _rotate(skeleton: Skeleton3D, joint: Dictionary, angles: Vector3) -> void:
	var axes: Quaternion = joint.axis
	var rotation := Quaternion(axes * Vector3.UP, deg_to_rad(angles.y)) \
		* Quaternion(axes * Vector3.RIGHT, deg_to_rad(angles.x)) \
		* Quaternion(axes * Vector3.BACK, deg_to_rad(angles.z))
	skeleton.set_bone_pose_rotation(joint.index, (Quaternion(joint.rest) * rotation).normalized())
