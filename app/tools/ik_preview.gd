# Copyright 2026 RIGELIO Studio. SPDX-License-Identifier: MIT
extends TwoBoneIK3D

const MIN_LENGTH := 0.00001

var _goal: Node3D
var _pole: Node3D


func _init() -> void:
	active = false


func _ready() -> void:
	_goal = Node3D.new()
	_goal.name = "IKGoal"
	_goal.top_level = true
	add_child(_goal)
	_pole = Node3D.new()
	_pole.name = "IKPole"
	_pole.top_level = true
	add_child(_pole)


func pin(end_bone: int, goal_world: Vector3) -> bool:
	var skeleton := get_skeleton()
	if not skeleton or not _goal or end_bone < 0 or end_bone >= skeleton.get_bone_count() or not goal_world.is_finite():
		return false
	var middle := skeleton.get_bone_parent(end_bone)
	if middle < 0:
		return false
	var root := skeleton.get_bone_parent(middle)
	if root < 0 or not _invertible(skeleton.global_transform):
		return false

	var rest_root := skeleton.get_bone_global_rest(root)
	var rest_middle := skeleton.get_bone_global_rest(middle)
	var rest_end := skeleton.get_bone_global_rest(end_bone)
	var pose_root := skeleton.get_bone_global_pose(root)
	var pose_middle := skeleton.get_bone_global_pose(middle)
	var pose_end := skeleton.get_bone_global_pose(end_bone)
	for pose in [rest_root, rest_middle, rest_end, pose_root, pose_middle, pose_end]:
		if not _invertible(pose):
			return false
	if (not _segment(rest_root.origin, rest_middle.origin)
			or not _segment(rest_middle.origin, rest_end.origin)
			or not _segment(pose_root.origin, pose_middle.origin)
			or not _segment(pose_middle.origin, pose_end.origin)):
		return false

	var goal_local := skeleton.to_local(goal_world)
	if not _segment(pose_root.origin, goal_local):
		return false
	var aim := (goal_local - pose_root.origin).normalized()
	var bend := pose_middle.origin - pose_root.origin
	bend -= aim * bend.dot(aim)
	if bend.length_squared() <= MIN_LENGTH * MIN_LENGTH:
		var reference := Vector3.UP if absf(aim.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
		bend = reference - aim * reference.dot(aim)
	var length := pose_root.origin.distance_to(pose_middle.origin) + pose_middle.origin.distance_to(pose_end.origin)
	var pole_world := skeleton.to_global(pose_root.origin + bend.normalized() * length)
	if not pole_world.is_finite():
		return false

	active = false
	setting_count = 0
	setting_count = 1
	set_root_bone(0, root)
	set_middle_bone(0, middle)
	set_end_bone(0, end_bone)
	set_extend_end_bone(0, false)
	_goal.global_position = goal_world
	_pole.global_position = pole_world
	set_target_node(0, get_path_to(_goal))
	set_pole_node(0, get_path_to(_pole))
	active = true
	return true


func clear() -> void:
	active = false
	setting_count = 0


func _invertible(pose: Transform3D) -> bool:
	if not pose.is_finite():
		return false
	var basis := pose.basis
	var determinant := basis.determinant()
	var x := basis.x.normalized()
	var y := basis.y.normalized()
	var z := basis.z.normalized()
	return is_finite(determinant) and determinant != 0.0 and absf(x.dot(y.cross(z))) > 0.00001


func _segment(a: Vector3, b: Vector3) -> bool:
	var squared := a.distance_squared_to(b)
	return is_finite(squared) and squared > MIN_LENGTH * MIN_LENGTH
