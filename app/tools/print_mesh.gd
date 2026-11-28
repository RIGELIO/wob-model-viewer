extends RefCounted

const EXTENSIONS := ["stl", "3mf", "obj"]
const MODEL_PART := "3D/3dmodel.model"
const CONTENT_TYPES := '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="model" ContentType="application/vnd.ms-package.3dmanufacturing-3dmodel+xml"/></Types>'
const RELATIONSHIPS := '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Target="/3D/3dmodel.model" Id="model" Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"/></Relationships>'


class Geometry extends RefCounted:
	var vertices := PackedVector3Array()
	var faces := PackedInt32Array()
	var _by_position: Dictionary[Vector3, int]

	func vertex(point: Vector3) -> int:
		if _by_position.has(point):
			return _by_position[point]
		var index := vertices.size()
		vertices.append(point)
		_by_position[point] = index
		return index

	func release_lookup() -> void:
		_by_position.clear()


static func rest_state(stage: Control) -> Dictionary:
	var state := {}
	var inverse: Transform3D = stage._model_anchor.global_transform.affine_inverse()
	for instance: MeshInstance3D in stage.model.meshes:
		state[instance] = {"transform": inverse * instance.global_transform, "weights": _weights(instance)}
	return state


static func capture(stage: Control, current_pose: bool, scale_percent: float) -> Geometry:
	var result := Geometry.new()
	if not stage.model or not is_finite(scale_percent) or scale_percent <= 0.0:
		return result
	var multiplier := 10.0 * scale_percent
	for instance: MeshInstance3D in stage.model.meshes:
		if not stage.is_part_visible(instance) or (stage._isolated and instance != stage._isolated):
			continue
		var mesh := instance.mesh as ArrayMesh
		if not mesh:
			continue
		var transform := instance.global_transform
		var weights := _weights(instance)
		if not current_pose:
			var rest: Dictionary = stage.print_rest_state[instance]
			transform = stage._model_placement.global_transform * rest.transform
			weights = rest.weights
		var bones := _bone_transforms(instance, current_pose)
		var only_surface: int = stage._isolated_surface if stage._isolated == instance else -1
		for surface in mesh.get_surface_count():
			if only_surface >= 0 and surface != only_surface:
				continue
			_capture_surface(result, mesh, surface, transform, weights, bones, multiplier)
	result.release_lookup()
	if not result.vertices.is_empty():
		var bottom := result.vertices[0].z
		for point in result.vertices:
			bottom = minf(bottom, point.z)
		for index in result.vertices.size():
			var point := result.vertices[index]
			point.z -= bottom
			result.vertices[index] = point
	return result


static func _weights(instance: MeshInstance3D) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	for index in instance.get_blend_shape_count():
		result.append(instance.get_blend_shape_value(index))
	return result


static func _bone_transforms(instance: MeshInstance3D, current_pose: bool) -> Array[Transform3D]:
	var transforms: Array[Transform3D] = []
	if instance.skeleton.is_empty():
		return transforms
	var skeleton := instance.get_node_or_null(instance.skeleton) as Skeleton3D
	var reference := instance.get_skin_reference()
	if not skeleton or not reference:
		return transforms
	var skin := reference.get_skin()
	if current_pose:
		skeleton.force_update_all_bone_transforms()
	for index in skin.get_bind_count():
		var bone := skin.get_bind_bone(index)
		var name := skin.get_bind_name(index)
		if not name.is_empty():
			bone = skeleton.find_bone(name)
		var transform := Transform3D.IDENTITY
		if bone >= 0 and bone < skeleton.get_bone_count():
			var pose := skeleton.get_bone_global_pose(bone) if current_pose else skeleton.get_bone_global_rest(bone)
			transform = pose * skin.get_bind_pose(index)
		transforms.append(transform)
	return transforms


static func _capture_surface(result: Geometry, mesh: ArrayMesh, surface: int, transform: Transform3D,
		weights: PackedFloat32Array, bones: Array[Transform3D], multiplier: float) -> void:
	var primitive := mesh.surface_get_primitive_type(surface)
	if primitive not in [Mesh.PRIMITIVE_TRIANGLES, Mesh.PRIMITIVE_TRIANGLE_STRIP]:
		return
	var arrays := mesh.surface_get_arrays(surface)
	var base: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var points := base.duplicate()
	var shapes := mesh.surface_get_blend_shape_arrays(surface)
	var normalized := mesh.blend_shape_mode == Mesh.BLEND_SHAPE_MODE_NORMALIZED
	for shape in mini(shapes.size(), weights.size()):
		if is_zero_approx(weights[shape]):
			continue
		var changed: PackedVector3Array = shapes[shape][Mesh.ARRAY_VERTEX]
		if changed.size() != points.size():
			continue
		for vertex in points.size():
			var delta := changed[vertex] - base[vertex] if normalized else changed[vertex]
			points[vertex] += delta * weights[shape]
	if not bones.is_empty() and arrays[Mesh.ARRAY_BONES] is PackedInt32Array and arrays[Mesh.ARRAY_WEIGHTS] is PackedFloat32Array:
		_skin(points, arrays[Mesh.ARRAY_BONES], arrays[Mesh.ARRAY_WEIGHTS], bones)
	for vertex in points.size():
		var point := transform * points[vertex]
		points[vertex] = Vector3(point.x, -point.z, point.y) * multiplier
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var length := points.size() if indices.is_empty() else indices.size()
	var mirrored := transform.basis.determinant() < 0.0
	var stride := 3 if primitive == Mesh.PRIMITIVE_TRIANGLES else 1
	for offset in range(0, length - 2, stride):
		var a := offset if indices.is_empty() else indices[offset]
		var b := offset + 1 if indices.is_empty() else indices[offset + 1]
		var c := offset + 2 if indices.is_empty() else indices[offset + 2]
		var flip := (not mirrored) != (stride == 1 and offset % 2 == 1)
		_triangle(result, points[a], points[c] if flip else points[b], points[b] if flip else points[c])


static func _skin(points: PackedVector3Array, bindings: PackedInt32Array, weights: PackedFloat32Array,
		bones: Array[Transform3D]) -> void:
	var stride := 8 if bindings.size() == points.size() * 8 else 4
	if bindings.size() != points.size() * stride or bindings.size() != weights.size():
		return
	for index in points.size():
		var original := points[index]
		var deformed := original
		for influence in range(index * stride, (index + 1) * stride):
			var bone := bindings[influence]
			var weight := weights[influence]
			if weight > 0.0 and bone >= 0 and bone < bones.size():
				deformed += (bones[bone] * original - original) * weight
		points[index] = deformed


static func _triangle(result: Geometry, a: Vector3, b: Vector3, c: Vector3) -> void:
	if not a.is_finite() or not b.is_finite() or not c.is_finite() or (b - a).cross(c - a).length_squared() <= 0.0:
		return
	result.faces.append(result.vertex(a))
	result.faces.append(result.vertex(b))
	result.faces.append(result.vertex(c))


static func write(geometry: Geometry, path: String) -> Dictionary:
	if geometry.faces.is_empty():
		return {"error": ERR_DOES_NOT_EXIST}
	var extension := path.get_extension().to_lower()
	if not extension in EXTENSIONS:
		return {"error": ERR_INVALID_PARAMETER}
	var temporary := path + ".tmp-" + Crypto.new().generate_random_bytes(12).hex_encode()
	var error := _write_3mf(geometry, temporary) if extension == "3mf" else _write_file(geometry, temporary, extension)
	if error == OK:
		error = DirAccess.rename_absolute(temporary, path)
	if error != OK:
		if FileAccess.file_exists(temporary):
			DirAccess.remove_absolute(temporary)
		return {"error": error}
	@warning_ignore("integer_division")
	return {"error": OK, "triangles": geometry.faces.size() / 3, "problem_edges": _problem_edges(geometry.faces)}


static func _write_file(geometry: Geometry, path: String, extension: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		return FileAccess.get_open_error()
	var written := _write_stl(geometry, file) if extension == "stl" else _write_obj(geometry, file)
	file.flush()
	var error := file.get_error()
	file.close()
	return ERR_FILE_CANT_WRITE if error == OK and not written else error


static func _write_stl(geometry: Geometry, file: FileAccess) -> bool:
	var header := "WoB Model Viewer · millimetres".to_utf8_buffer()
	header.resize(80)
	var triangle := PackedByteArray()
	triangle.resize(50)
	@warning_ignore("integer_division")
	if not file.store_buffer(header) or not file.store_32(geometry.faces.size() / 3):
		return false
	for index in range(0, geometry.faces.size(), 3):
		var a := geometry.vertices[geometry.faces[index]]
		var b := geometry.vertices[geometry.faces[index + 1]]
		var c := geometry.vertices[geometry.faces[index + 2]]
		var values := PackedVector3Array([(b - a).cross(c - a).normalized(), a, b, c])
		for vector in values.size():
			for axis in 3:
				triangle.encode_float(vector * 12 + axis * 4, values[vector][axis])
		if not file.store_buffer(triangle):
			return false
	return true


static func _write_obj(geometry: Geometry, file: FileAccess) -> bool:
	if not file.store_line("# WoB Model Viewer print mesh, millimeters, Z up"):
		return false
	for point in geometry.vertices:
		if not file.store_line("v %.8f %.8f %.8f" % [point.x, point.y, point.z]):
			return false
	for index in range(0, geometry.faces.size(), 3):
		if not file.store_line("f %d %d %d" % [geometry.faces[index] + 1, geometry.faces[index + 1] + 1, geometry.faces[index + 2] + 1]):
			return false
	return true


static func _write_3mf(geometry: Geometry, path: String) -> Error:
	var pack := ZIPPacker.new()
	var error := pack.open(path)
	if error != OK:
		return error
	error = _zip_text(pack, "[Content_Types].xml", CONTENT_TYPES)
	if error == OK:
		error = _zip_text(pack, "_rels/.rels", RELATIONSHIPS)
	if error == OK:
		var xml := PackedStringArray([
			'<?xml version="1.0" encoding="UTF-8"?>',
			'<model unit="millimeter" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02"><resources><object id="1" type="model"><mesh><vertices>',
		])
		for point in geometry.vertices:
			xml.append('<vertex x="%.8f" y="%.8f" z="%.8f"/>' % [point.x, point.y, point.z])
		xml.append("</vertices><triangles>")
		for index in range(0, geometry.faces.size(), 3):
			xml.append('<triangle v1="%d" v2="%d" v3="%d"/>' % [
				geometry.faces[index], geometry.faces[index + 1], geometry.faces[index + 2]])
		xml.append('</triangles></mesh></object></resources><build><item objectid="1"/></build></model>')
		error = _zip_text(pack, MODEL_PART, "\n".join(xml))
	var closed := pack.close()
	return closed if error == OK else error


static func _zip_text(pack: ZIPPacker, name: String, data: String) -> Error:
	var error := pack.start_file(name)
	if error != OK:
		return error
	error = pack.write_file(data.to_utf8_buffer())
	var closed := pack.close_file()
	return closed if error == OK else error


static func _problem_edges(faces: PackedInt32Array) -> int:
	var edges := {}
	for index in range(0, faces.size(), 3):
		for edge in 3:
			var a := faces[index + edge]
			var b := faces[index + (edge + 1) % 3]
			var key := Vector2i(mini(a, b), maxi(a, b))
			edges[key] = int(edges.get(key, 0)) + 1
	var issues := 0
	for count: int in edges.values():
		issues += int(count != 2)
	return issues
