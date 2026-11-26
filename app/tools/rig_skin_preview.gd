# Copyright 2026 RIGELIO Studio. SPDX-License-Identifier: MIT
extends Node3D

const INFLUENCES := 4
const WORK_SLICE_USEC := 8000

var skeleton := Skeleton3D.new()
var _sources: Dictionary[MeshInstance3D, bool]
var _posed_joint := -1
var _starts := PackedVector3Array()
var _ends: Array[PackedVector3Array] = []
var _softness: float
var _meshes: Array[MeshInstance3D] = []
var _pick_surfaces: Dictionary[Vector2i, TriangleMesh]
var _unmatched_weights: Dictionary
var _resolved_weights: Dictionary
var _remapped_count := 0
var _anchor: Node3D
var _mesh_sources: Array[MeshInstance3D]
var _surface_identities: Dictionary[Vector2i, Dictionary]


func _init() -> void:
	skeleton.name = "PreviewRig"
	add_child(skeleton)


func build(joints: Array[Dictionary], meshes: Array[MeshInstance3D], anchor: Node3D,
		scale: float, frame_tree: SceneTree, keep_building: Callable, manual: Dictionary = {}) -> bool:
	_softness = pow(maxf(scale * 0.015, 0.0001), 2.0)
	_anchor = anchor
	_mesh_sources.assign(meshes)
	_unmatched_weights = manual.duplicate()
	_resolved_weights = manual.duplicate()
	var overrides := {}
	if not manual.is_empty():
		var remaps: Variant = await _resolve_weights(manual, frame_tree, keep_building)
		if remaps == null:
			return false
		overrides = remaps
	for joint: Dictionary in joints:
		var index := skeleton.add_bone(joint.name)
		var parent: int = joint.parent
		var start: Vector3 = joint.point
		_starts.append(start)
		_ends.append(PackedVector3Array())
		if parent >= 0:
			skeleton.set_bone_parent(index, parent)
			_ends[parent].append(start)
			start -= _starts[parent]
		skeleton.set_bone_rest(index, Transform3D(Basis.IDENTITY, start))
	skeleton.reset_bone_poses()
	var skin := Skin.new()
	for bone in range(_starts.size()):
		skin.add_bind(bone, Transform3D(Basis.IDENTITY, -_starts[bone]))
	for source in meshes:
		if not keep_building.call() or not is_instance_valid(source):
			return false
		var mesh := source.mesh as ArrayMesh
		if not mesh or mesh.get_surface_count() == 0 or source.skin:
			return false
		var to_rig := _source_transform(source)
		var determinant := to_rig.basis.determinant()
		if not to_rig.is_finite() or not is_finite(determinant) or determinant == 0.0:
			return false
		var weighted: ArrayMesh = await _make_mesh(mesh, to_rig, frame_tree, keep_building, overrides)
		if not weighted or not keep_building.call() or not is_instance_valid(source):
			return false
		var copy := MeshInstance3D.new()
		copy.name = source.name
		copy.mesh = weighted
		copy.skin = skin
		copy.layers = source.layers
		copy.visible = source.is_visible_in_tree()
		copy.cast_shadow = source.cast_shadow
		copy.material_override = source.material_override
		copy.material_overlay = source.material_overlay
		add_child(copy)
		_meshes.append(copy)
		copy.skeleton = copy.get_path_to(skeleton)
		for surface in range(mesh.get_surface_count()):
			copy.set_surface_override_material(surface, source.get_surface_override_material(surface))
		for shape in range(mesh.get_blend_shape_count()):
			copy.set_blend_shape_value(shape, source.get_blend_shape_value(shape))
		_sources[source] = source.visible
	return not _sources.is_empty()


func show_preview() -> void:
	for source in _sources:
		if is_instance_valid(source):
			source.hide()


func restore_sources() -> void:
	for source in _sources:
		if is_instance_valid(source):
			source.visible = _sources[source]
	_sources.clear()
	hide()


func pose(joint: int, axis: Vector3, degrees: float) -> void:
	if _posed_joint >= 0:
		skeleton.set_bone_pose_rotation(_posed_joint, Quaternion.IDENTITY)
	_posed_joint = joint
	if joint >= 0:
		skeleton.set_bone_pose_rotation(joint, Quaternion(axis, deg_to_rad(degrees)))


func joint_point(joint: int) -> Vector3:
	return skeleton.get_bone_global_pose(joint).origin


func _make_mesh(source: ArrayMesh, to_rig: Transform3D,
		frame_tree: SceneTree, keep_building: Callable, overrides: Dictionary) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	mesh.blend_shape_mode = source.blend_shape_mode
	for shape in range(source.get_blend_shape_count()):
		mesh.add_blend_shape(source.get_blend_shape_name(shape))
	var deadline := Time.get_ticks_usec() + WORK_SLICE_USEC
	var indices := PackedInt32Array([0, 0, 0, 0])
	var distances := PackedFloat32Array([INF, INF, INF, INF])
	var normal_basis := to_rig.basis.inverse().transposed()
	if not normal_basis.is_finite():
		return null
	var mirrored := to_rig.basis.determinant() < 0.0
	for surface in range(source.get_surface_count()):
		var arrays := source.surface_get_arrays(surface)
		if arrays[Mesh.ARRAY_BONES] != null or arrays[Mesh.ARRAY_WEIGHTS] != null:
			return null
		# Bake node transforms into preview geometry so skinning uses a common
		# coordinate frame and mirrored or scaled nodes keep their original facing.
		_transform_geometry(arrays, to_rig, normal_basis, mirrored)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var primitive := source.surface_get_primitive_type(surface)
		if mirrored:
			_flip_winding(arrays, primitive, vertices.size())
		var shapes := source.surface_get_blend_shape_arrays(surface)
		var relative := source.blend_shape_mode == Mesh.BLEND_SHAPE_MODE_RELATIVE
		var shape_transform := Transform3D(to_rig.basis, Vector3.ZERO) if relative else to_rig
		for shape in shapes:
			_transform_geometry(shape, shape_transform, normal_basis, mirrored, relative)
		var bones := PackedInt32Array()
		var weights := PackedFloat32Array()
		bones.resize(vertices.size() * INFLUENCES)
		weights.resize(bones.size())
		for vertex in range(vertices.size()):
			indices.fill(0)
			distances.fill(INF)
			_nearest(vertices[vertex], indices, distances)
			var sum := 0.0
			var offset := vertex * INFLUENCES
			var count := mini(INFLUENCES, _starts.size())
			for influence in range(count):
				var ratio := (distances[0] + _softness) / (distances[influence] + _softness)
				bones[offset + influence] = indices[influence]
				weights[offset + influence] = ratio * ratio
				sum += ratio * ratio
			if not is_finite(sum) or sum <= 0.0:
				return null
			for influence in range(count):
				weights[offset + influence] /= sum
			if vertex % 64 == 0 and Time.get_ticks_usec() >= deadline:
				await frame_tree.process_frame
				if not keep_building.call():
					return null
				deadline = Time.get_ticks_usec() + WORK_SLICE_USEC
		var edits: Dictionary = overrides.get(Vector2i(_meshes.size(), surface), {})
		for index: int in edits:
			var edit: Dictionary = edits[index]
			for influence in range(INFLUENCES):
				var slot := index * INFLUENCES + influence
				bones[slot] = edit.bones[influence]
				weights[slot] = edit.weights[influence]
		arrays[Mesh.ARRAY_BONES] = bones
		arrays[Mesh.ARRAY_WEIGHTS] = weights
		var flags := source.surface_get_format(surface) & ~(Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS | Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES)
		mesh.add_surface_from_arrays(primitive, arrays, shapes, {}, flags)
		if mesh.get_surface_count() != surface + 1:
			return null
		mesh.surface_set_material(surface, source.surface_get_material(surface))
	return mesh


func pick_vertex(origin: Vector3, end: Vector3) -> Vector3i:
	var result := Vector3i(-1, -1, -1)
	var distance := INF
	for index in range(_meshes.size()):
		var instance := _meshes[index]
		if not instance.visible:
			continue
		var mesh: ArrayMesh = instance.mesh
		for surface in range(mesh.get_surface_count()):
			if mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var cache_key := Vector2i(index, surface)
			if not _pick_surfaces.has(cache_key):
				_pick_surfaces[cache_key] = _surface_picker(mesh, surface)
			var triangles := _pick_surfaces[cache_key]
			if not triangles:
				continue
			var hit := triangles.intersect_segment(origin, end)
			if hit.is_empty() or origin.distance_squared_to(hit.position) >= distance:
				continue
			var arrays := mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var first: int = hit.face_index * 3
			var vertex := -1
			var delta := INF
			for corner in range(first, first + 3):
				var candidate := indices[corner] if not indices.is_empty() else corner
				var squared := vertices[candidate].distance_squared_to(hit.position)
				if squared < delta:
					delta = squared
					vertex = candidate
			distance = origin.distance_squared_to(hit.position)
			result = Vector3i(index, surface, vertex)
	return result


static func _surface_picker(mesh: ArrayMesh, surface: int) -> TriangleMesh:
	var arrays := mesh.surface_get_arrays(surface)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var faces := vertices
	if not indices.is_empty():
		faces = PackedVector3Array()
		faces.resize(indices.size())
		for index in range(indices.size()):
			faces[index] = vertices[indices[index]]
	var triangles := TriangleMesh.new()
	return triangles if triangles.create_from_faces(faces) else null


func vertex_data(key: Vector3i) -> Dictionary:
	if key.x < 0 or key.x >= _meshes.size():
		return {}
	var mesh: ArrayMesh = _meshes[key.x].mesh
	if key.y < 0 or key.y >= mesh.get_surface_count() or key.z < 0 or key.z >= mesh.surface_get_array_len(key.y):
		return {}
	var arrays := mesh.surface_get_arrays(key.y)
	var first := key.z * INFLUENCES
	return {"point": arrays[Mesh.ARRAY_VERTEX][key.z], "bones": arrays[Mesh.ARRAY_BONES].slice(first, first + INFLUENCES),
		"weights": arrays[Mesh.ARRAY_WEIGHTS].slice(first, first + INFLUENCES)}


func edited_vertex(key: Vector3i, bone: int, weight: float) -> Dictionary:
	if _unmatched_weights.has(key):
		return {}
	var data := vertex_data(key)
	if data.is_empty() or bone < 0 or bone >= _starts.size() or not is_finite(weight) or weight < 0.0 or weight > 1.0:
		return {}
	var row_bones := PackedInt32Array([0, 0, 0, 0])
	var row_weights := PackedFloat32Array([0, 0, 0, 0])
	var remaining: Array[Vector2] = []
	for influence in range(INFLUENCES):
		if data.bones[influence] == bone or data.weights[influence] <= 0.0:
			continue
		remaining.append(Vector2(data.bones[influence], data.weights[influence]))
	remaining.sort_custom(func(a: Vector2, b: Vector2): return a.y > b.y)
	var slots := mini(remaining.size(), INFLUENCES - int(weight > 0.0))
	var total := 0.0
	for index in range(slots):
		row_bones[index] = int(remaining[index].x)
		row_weights[index] = remaining[index].y
		total += row_weights[index]
	if slots == 0 and weight < 1.0:
		if _starts.size() == 1:
			return {}
		var nearest := PackedInt32Array([0, 0, 0, 0])
		var distances := PackedFloat32Array([INF, INF, INF, INF])
		_nearest(data.point, nearest, distances)
		row_bones[0] = nearest[1] if nearest[0] == bone else nearest[0]
		row_weights[0] = 1.0
		total = 1.0
		slots = 1
	for influence in range(slots):
		row_weights[influence] *= (1.0 - weight) / total
	if weight > 0.0:
		row_bones[slots] = bone
		row_weights[slots] = weight
	var surface := Vector2i(key.x, key.y)
	var identity := _surface_identity(surface, _mesh_sources[key.x].mesh.surface_get_arrays(key.y)) \
			if not _surface_identities.has(surface) else _surface_identities[surface]
	return {"point": data.point, "bones": row_bones, "weights": row_weights, "identity": identity}


func apply_vertex(key: Vector3i, data: Dictionary) -> bool:
	if _unmatched_weights.has(key):
		return false
	var instance := _meshes[key.x]
	var source: ArrayMesh = instance.mesh
	var next := ArrayMesh.new()
	next.blend_shape_mode = source.blend_shape_mode
	var morph_values := PackedFloat32Array()
	for shape in range(source.get_blend_shape_count()):
		next.add_blend_shape(source.get_blend_shape_name(shape))
		morph_values.append(instance.get_blend_shape_value(shape))
	var materials: Array[Material] = []
	for surface in range(source.get_surface_count()):
		var arrays := source.surface_get_arrays(surface)
		if surface == key.y:
			for influence in range(INFLUENCES):
				var offset := key.z * INFLUENCES + influence
				arrays[Mesh.ARRAY_BONES][offset] = data.bones[influence]
				arrays[Mesh.ARRAY_WEIGHTS][offset] = data.weights[influence]
		next.add_surface_from_arrays(source.surface_get_primitive_type(surface), arrays,
			source.surface_get_blend_shape_arrays(surface), {}, source.surface_get_format(surface))
		if next.get_surface_count() != surface + 1:
			return false
		next.surface_set_material(surface, source.surface_get_material(surface))
		materials.append(instance.get_surface_override_material(surface))
	instance.mesh = next
	for surface in range(materials.size()):
		instance.set_surface_override_material(surface, materials[surface])
	for shape in range(morph_values.size()):
		instance.set_blend_shape_value(shape, morph_values[shape])
	_resolved_weights[key] = data
	return true


func unmatched_weight_count() -> int:
	return _unmatched_weights.size()


func has_unmatched_weight(key: Vector3i) -> bool:
	return _unmatched_weights.has(key)


func remapped_weight_count() -> int:
	return _remapped_count


func resolved_weights() -> Dictionary:
	return _resolved_weights.duplicate()


func discard_unmatched_weights() -> void:
	for key in _unmatched_weights:
		_resolved_weights.erase(key)
	_unmatched_weights.clear()


func _source_transform(source: MeshInstance3D) -> Transform3D:
	var transform := Transform3D.IDENTITY
	var ancestor: Node3D = source
	while ancestor and ancestor != _anchor and not ancestor.is_set_as_top_level():
		transform = ancestor.transform * transform
		ancestor = ancestor.get_parent_node_3d()
	if ancestor == _anchor:
		return transform
	return _anchor.global_transform.affine_inverse() * source.global_transform


func _surface_identity(key: Vector2i, arrays: Array) -> Dictionary:
	var source := _mesh_sources[key.x]
	var piece := str(_anchor.get_path_to(source))
	var material := source.mesh.surface_get_material(key.y)
	var surface := material.resource_name if material else ""
	# Include ordered attributes and topology. Position alone cannot distinguish UV seams.
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(var_to_bytes([source.mesh.surface_get_primitive_type(key.y), arrays]))
	var identity := {
		"piece": piece if piece.length() <= 4096 else piece.sha256_text(),
		"surface": surface if surface.length() <= 512 else surface.sha256_text(),
		"layout": digest.finish().hex_encode(),
	}
	_surface_identities[key] = identity
	return identity


func _resolve_weights(manual: Dictionary, frame_tree: SceneTree, keep_building: Callable) -> Variant:
	var positions := {}
	var layouts := {}
	for old: Vector3i in manual:
		var row: Dictionary = manual[old]
		positions[row.point] = {}
		var layout: String = row.get("identity", {}).get("layout", "")
		if not layout.is_empty():
			if not layouts.has(layout):
				layouts[layout] = []
			layouts[layout].append(old)
	var exact := {}
	var deadline := Time.get_ticks_usec() + WORK_SLICE_USEC
	for mesh_index in range(_mesh_sources.size()):
		var instance := _mesh_sources[mesh_index]
		if not keep_building.call() or not is_instance_valid(instance):
			return null
		var mesh := instance.mesh as ArrayMesh
		if not mesh:
			return null
		var transform := _source_transform(instance)
		for surface in range(mesh.get_surface_count()):
			var key := Vector2i(mesh_index, surface)
			var arrays := mesh.surface_get_arrays(surface)
			var identity := _surface_identity(key, arrays)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for old: Vector3i in layouts.get(identity.layout, []):
				var row: Dictionary = manual[old]
				if old.z < vertices.size() and _same_piece(row, identity) and transform * vertices[old.z] == row.point:
					if not exact.has(old):
						exact[old] = []
					if exact[old].size() < 2:
						exact[old].append(Vector3i(mesh_index, surface, old.z))
			for vertex in range(vertices.size()):
				var point := transform * vertices[vertex]
				if positions.has(point):
					var hits: Dictionary = positions[point]
					# One candidate and a capped multiplicity keep degenerate meshes bounded.
					var hit: Vector2i = hits.get(key, Vector2i(vertex, 0))
					if hit.y < 2:
						hits[key] = Vector2i(hit.x, hit.y + 1)
				if vertex % 64 == 0 and Time.get_ticks_usec() >= deadline:
					await frame_tree.process_frame
					if not keep_building.call():
						return null
					deadline = Time.get_ticks_usec() + WORK_SLICE_USEC
	return _rekey_weights(manual, positions, exact)


func _rekey_weights(manual: Dictionary, positions: Dictionary, exact: Dictionary) -> Dictionary:
	var proposed := {}
	var claims := {}
	for old: Vector3i in manual:
		var ordered: Array = exact.get(old, [])
		var target := Vector3i(-1, -1, -1)
		if ordered.size() == 1:
			target = ordered[0]
		elif ordered.is_empty():
			target = _unique_point(manual[old], positions[manual[old].point])
		if target.x >= 0:
			proposed[old] = target
			claims[target] = claims.get(target, 0) + 1

	var incoming := {}
	var protected: Array[Vector3i] = []
	for old: Vector3i in manual:
		if proposed.has(old) and claims[proposed[old]] == 1:
			incoming[proposed[old]] = old
		else:
			proposed.erase(old)
			protected.append(old)
	# An unresolved old key remains reserved. Propagate collisions through
	# chains while allowing safe permutations and swapped indices.
	while not protected.is_empty():
		var key: Vector3i = protected.pop_back()
		if incoming.has(key):
			var displaced: Vector3i = incoming[key]
			incoming.erase(key)
			proposed.erase(displaced)
			protected.append(displaced)

	for old: Vector3i in proposed:
		_resolved_weights.erase(old)
		_unmatched_weights.erase(old)
	var applied := {}
	for old: Vector3i in proposed:
		var target: Vector3i = proposed[old]
		var surface := Vector2i(target.x, target.y)
		var row: Dictionary = manual[old].duplicate()
		row["identity"] = _surface_identities[surface]
		_resolved_weights[target] = row
		if not applied.has(surface):
			applied[surface] = {}
		applied[surface][target.z] = row
		if old != target:
			_remapped_count += 1
	return applied


func _unique_point(row: Dictionary, hits: Dictionary) -> Vector3i:
	var result := Vector3i(-1, -1, -1)
	for key: Vector2i in hits:
		var hit: Vector2i = hits[key]
		if not _same_piece(row, _surface_identities[key]):
			continue
		if hit.y != 1 or result.x >= 0:
			return Vector3i(-1, -1, -1)
		result = Vector3i(key.x, key.y, hit.x)
	return result


static func _same_piece(row: Dictionary, identity: Dictionary) -> bool:
	var stored: Dictionary = row.get("identity", {})
	var piece: String = stored.get("piece", "")
	var surface: String = stored.get("surface", "")
	return (piece.is_empty() or piece == identity.piece) and (surface.is_empty() or surface == identity.surface)


static func _transform_geometry(arrays: Array, transform: Transform3D, normal_basis: Basis,
		mirrored: bool, relative := false) -> void:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for vertex in range(vertices.size()):
		vertices[vertex] = transform * vertices[vertex]
	arrays[Mesh.ARRAY_VERTEX] = vertices
	if arrays[Mesh.ARRAY_NORMAL] is PackedVector3Array:
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for index in range(normals.size()):
			var direction := normal_basis * normals[index]
			normals[index] = direction if relative else direction.normalized()
		arrays[Mesh.ARRAY_NORMAL] = normals
	if arrays[Mesh.ARRAY_TANGENT] is PackedFloat32Array:
		var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
		for index in range(0, tangents.size(), 4):
			var direction := transform.basis * Vector3(tangents[index], tangents[index + 1], tangents[index + 2])
			if not relative:
				direction = direction.normalized()
			tangents[index] = direction.x
			tangents[index + 1] = direction.y
			tangents[index + 2] = direction.z
			if mirrored:
				tangents[index + 3] = -tangents[index + 3]
		arrays[Mesh.ARRAY_TANGENT] = tangents


static func _flip_winding(arrays: Array, primitive: Mesh.PrimitiveType, count: int) -> void:
	if primitive != Mesh.PRIMITIVE_TRIANGLES and primitive != Mesh.PRIMITIVE_TRIANGLE_STRIP:
		return
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if indices.is_empty():
		indices.resize(count)
		for index in range(count):
			indices[index] = index
	if primitive == Mesh.PRIMITIVE_TRIANGLE_STRIP:
		indices.insert(0, indices[0])
	else:
		for index in range(0, indices.size(), 3):
			var next := indices[index + 1]
			indices[index + 1] = indices[index + 2]
			indices[index + 2] = next
	arrays[Mesh.ARRAY_INDEX] = indices


func _nearest(point: Vector3, indices: PackedInt32Array, distances: PackedFloat32Array) -> void:
	for bone in range(_starts.size()):
		var start := _starts[bone]
		var closest := point.distance_squared_to(start)
		for end in _ends[bone]:
			var on_segment := Geometry3D.get_closest_point_to_segment(point, start, end)
			closest = minf(closest, point.distance_squared_to(on_segment))
		for rank in range(INFLUENCES):
			if closest >= distances[rank]:
				continue
			for slot in range(INFLUENCES - 1, rank, -1):
				distances[slot] = distances[slot - 1]
				indices[slot] = indices[slot - 1]
			distances[rank] = closest
			indices[rank] = bone
			break
