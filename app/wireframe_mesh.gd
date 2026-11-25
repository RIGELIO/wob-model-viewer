extends RefCounted


static func build(source: ArrayMesh) -> ArrayMesh:
	var has_triangles := false
	for surface in range(source.get_surface_count()):
		if source.surface_get_primitive_type(surface) == Mesh.PRIMITIVE_TRIANGLES:
			has_triangles = true
			break
	if not has_triangles:
		return null

	var result := ArrayMesh.new()
	result.blend_shape_mode = source.blend_shape_mode
	for shape in range(source.get_blend_shape_count()):
		result.add_blend_shape(source.get_blend_shape_name(shape))
	for surface in range(source.get_surface_count()):
		var primitive := source.surface_get_primitive_type(surface)
		var arrays := source.surface_get_arrays(surface)
		var shapes := source.surface_get_blend_shape_arrays(surface)
		var flags := source.surface_get_format(surface)
		if primitive == Mesh.PRIMITIVE_TRIANGLES:
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] else PackedInt32Array()
			arrays = _triangle_arrays(arrays, indices, flags)
			for shape in range(shapes.size()):
				var positions: Array = []
				positions.resize(Mesh.ARRAY_MAX)
				positions[Mesh.ARRAY_VERTEX] = _positions(shapes[shape][Mesh.ARRAY_VERTEX], indices)
				shapes[shape] = positions
			flags &= Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		result.add_surface_from_arrays(primitive, arrays, shapes, {}, flags)
	return result


static func _triangle_arrays(source: Array, indices: PackedInt32Array, flags: int) -> Array:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _positions(source[Mesh.ARRAY_VERTEX], indices)
	if source[Mesh.ARRAY_BONES] == null or source[Mesh.ARRAY_WEIGHTS] == null:
		return arrays
	if indices.is_empty():
		arrays[Mesh.ARRAY_BONES] = source[Mesh.ARRAY_BONES]
		arrays[Mesh.ARRAY_WEIGHTS] = source[Mesh.ARRAY_WEIGHTS]
		return arrays

	var influences := 8 if flags & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS else 4
	var original_bones: PackedInt32Array = source[Mesh.ARRAY_BONES]
	var original_weights: PackedFloat32Array = source[Mesh.ARRAY_WEIGHTS]
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	bones.resize(indices.size() * influences)
	weights.resize(bones.size())
	for corner in range(indices.size()):
		var original := indices[corner] * influences
		var target := corner * influences
		for influence in range(influences):
			bones[target + influence] = original_bones[original + influence]
			weights[target + influence] = original_weights[original + influence]
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	return arrays


static func _positions(source: PackedVector3Array, indices: PackedInt32Array) -> PackedVector3Array:
	if indices.is_empty():
		return source
	var result := PackedVector3Array()
	result.resize(indices.size())
	for corner in range(indices.size()):
		result[corner] = source[indices[corner]]
	return result
