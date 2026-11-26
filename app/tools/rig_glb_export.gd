# Copyright 2026 RIGELIO Studio. SPDX-License-Identifier: MIT
extends RefCounted

const RigMotion = preload("res://tools/rig_motion.gd")
const MOTION_FPS := 30


static func save(preview: Node3D, path: String, source_path: String,
		with_motion := false) -> Error:
	var target := _absolute_path(path)
	var source := _absolute_path(source_path)
	var same_path := target == source
	if OS.get_name() == "Windows":
		same_path = target.nocasecmp_to(source) == 0
	if not is_instance_valid(preview) or target.is_relative_path() \
			or target.get_extension().to_lower() != "glb" or same_path:
		return ERR_INVALID_PARAMETER
	var directory := DirAccess.open(target.get_base_dir())
	if not directory:
		return DirAccess.get_open_error()
	if _occupied(directory, target.get_file()):
		return ERR_ALREADY_EXISTS

	var snapshot := _rest_snapshot(preview)
	if not snapshot:
		return ERR_INVALID_DATA
	if with_motion and not _add_motion(snapshot):
		snapshot.free()
		return ERR_INVALID_DATA
	var document := GLTFDocument.new()
	document.root_node_mode = GLTFDocument.ROOT_NODE_MODE_KEEP_ROOT
	var state := GLTFState.new()
	var result := document.append_from_scene(snapshot, state)
	var bytes := PackedByteArray()
	if result == OK:
		# A buffer guarantees that the export has no external texture or BIN sidecars.
		bytes = document.generate_buffer(state)
	snapshot.free()
	if result != OK:
		return result
	if bytes.is_empty() or not _has_weighted_meshes(state.json) \
			or (with_motion and state.json.get("animations", []).size() != 2):
		return ERR_INVALID_DATA

	var temporary_name := ".wob-rig-%s.glb" % Crypto.new().generate_random_bytes(16).hex_encode()
	if _occupied(directory, temporary_name):
		return ERR_ALREADY_EXISTS
	var temporary := target.get_base_dir().path_join(temporary_name)
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if not file:
		return FileAccess.get_open_error()
	var written := file.store_buffer(bytes)
	file.flush()
	result = file.get_error() if written else ERR_FILE_CANT_WRITE
	file.close()
	if result == OK:
		# Godot's Windows rename removes an existing target before moving.
		result = ERR_ALREADY_EXISTS if _occupied(directory, target.get_file()) \
			else directory.rename(temporary_name, target.get_file())
	if result != OK:
		directory.remove(temporary_name)
	return result


static func has_nonportable_materials(preview: Node3D) -> bool:
	if not is_instance_valid(preview):
		return false
	for child in preview.get_children():
		var instance := child as MeshInstance3D
		if not instance or not instance.mesh:
			continue
		if instance.material_overlay:
			return true
		for surface in range(instance.mesh.get_surface_count()):
			var material := instance.get_active_material(surface)
			if material and (not material is BaseMaterial3D or material.next_pass):
				return true
	return false


static func _rest_snapshot(preview: Node3D) -> Node3D:
	var original: Skeleton3D = preview.get("skeleton")
	if not is_instance_valid(original) or original.get_bone_count() == 0:
		return null
	var snapshot := Node3D.new()
	snapshot.name = "RiggedModel"
	var rig := Skeleton3D.new()
	rig.name = "Rig"
	snapshot.add_child(rig)
	for bone in range(original.get_bone_count()):
		rig.add_bone(original.get_bone_name(bone))
		rig.set_bone_rest(bone, original.get_bone_rest(bone))
	for bone in range(original.get_bone_count()):
		rig.set_bone_parent(bone, original.get_bone_parent(bone))
	# The glTF exporter serializes Godot's current bone poses as node transforms.
	rig.reset_bone_poses()

	var neutral := StandardMaterial3D.new()
	var count := 0
	for child in preview.get_children():
		var source := child as MeshInstance3D
		if not source or not source.mesh:
			continue
		if not source.skin or source.skin.get_bind_count() == 0:
			snapshot.free()
			return null
		count += 1
		var copy := MeshInstance3D.new()
		copy.name = source.name if not str(source.name).begins_with("@") else "Mesh_%d" % count
		copy.mesh = source.mesh
		copy.skin = source.skin
		snapshot.add_child(copy, true)
		copy.skeleton = copy.get_path_to(rig)
		for shape in range(source.mesh.get_blend_shape_count()):
			copy.set_blend_shape_value(shape, source.get_blend_shape_value(shape))
		for surface in range(source.mesh.get_surface_count()):
			var material := source.get_active_material(surface) as BaseMaterial3D
			if not material:
				material = source.get_surface_override_material(surface) as BaseMaterial3D
			if not material:
				material = source.mesh.surface_get_material(surface) as BaseMaterial3D
			# Mask an unexportable material on the shared mesh without changing it.
			if material or source.get_active_material(surface):
				copy.set_surface_override_material(surface, material if material else neutral)
	if count > 0:
		return snapshot
	snapshot.free()
	return null


static func _add_motion(snapshot: Node3D) -> bool:
	var rig := snapshot.get_node("Rig") as Skeleton3D
	var profile := RigMotion.get_profile(rig)
	if profile.is_empty():
		return false
	var library := AnimationLibrary.new()
	library.add_animation(&"walk_in_place_loop", _sample_motion(rig, profile, RigMotion.duration(profile, false),
		func(phase: float): RigMotion.apply(rig, profile, false, phase)))
	var fast_name := &"run_in_place_loop" if profile.kind == "human" else &"trot_in_place_loop"
	library.add_animation(fast_name, _sample_motion(rig, profile, RigMotion.duration(profile, true),
		func(phase: float): RigMotion.apply(rig, profile, true, phase)))
	rig.reset_bone_poses()
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	player.root_node = NodePath("..")
	snapshot.add_child(player)
	player.add_animation_library(&"", library)
	return true


static func _sample_motion(rig: Skeleton3D, profile: Dictionary, duration: float, sample_pose: Callable) -> Animation:
	var clip := Animation.new()
	clip.length = duration
	clip.loop_mode = Animation.LOOP_LINEAR
	var rotations := {}
	for joint: Dictionary in profile.joints.values():
		var bone: int = joint.index
		var track := clip.add_track(Animation.TYPE_ROTATION_3D)
		clip.track_set_path(track, NodePath("%s:%s" % [rig.name, rig.get_bone_name(bone)]))
		rotations[bone] = track
	var pelvis: int = profile.joints.pelvis.index
	var translation := clip.add_track(Animation.TYPE_POSITION_3D)
	clip.track_set_path(translation, NodePath("%s:%s" % [rig.name, rig.get_bone_name(pelvis)]))
	var steps := ceili(clip.length * MOTION_FPS)
	for index in range(steps + 1):
		var phase := float(index) / steps
		var seconds := clip.length * phase
		sample_pose.call(phase)
		for bone: int in rotations:
			clip.rotation_track_insert_key(rotations[bone], seconds, rig.get_bone_pose_rotation(bone))
		clip.position_track_insert_key(translation, seconds, rig.get_bone_pose_position(pelvis))
	return clip


static func _has_weighted_meshes(data: Dictionary) -> bool:
	if data.get("skins", []).is_empty() or data.get("meshes", []).is_empty():
		return false
	for node: Dictionary in data.get("nodes", []):
		if node.has("mesh") and not node.has("skin"):
			return false
	for mesh: Dictionary in data.meshes:
		for primitive: Dictionary in mesh.get("primitives", []):
			var attributes: Dictionary = primitive.get("attributes", {})
			if not attributes.has("JOINTS_0") or not attributes.has("WEIGHTS_0"):
				return false
	return true


static func _absolute_path(path: String) -> String:
	return ProjectSettings.globalize_path(path).replace("\\", "/").simplify_path()


static func _occupied(directory: DirAccess, name: String) -> bool:
	return directory.file_exists(name) or directory.dir_exists(name) or directory.is_link(name)
