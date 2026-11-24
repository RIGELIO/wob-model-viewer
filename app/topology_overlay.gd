extends RefCounted

const MIN_NORMAL_ALIGNMENT := 0.9659258 # Cosine of 15 degrees.
const MAX_CORNER_ALIGNMENT := 0.92

static func build(source: ArrayMesh) -> Dictionary:
	var lines := ArrayMesh.new()
	lines.blend_shape_mode = source.blend_shape_mode
	for shape in range(source.get_blend_shape_count()):
		lines.add_blend_shape(source.get_blend_shape_name(shape))
	var statistics := Vector2i.ZERO
	for surface in range(source.get_surface_count()):
		if source.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var original := source.surface_get_arrays(surface)
		var result := infer(original[Mesh.ARRAY_VERTEX], original[Mesh.ARRAY_INDEX] if original[Mesh.ARRAY_INDEX] else PackedInt32Array())
		statistics += result.statistics
		if result.indices.is_empty():
			continue
		var vertices := _positions(original)
		vertices[Mesh.ARRAY_INDEX] = result.indices
		vertices[Mesh.ARRAY_BONES] = original[Mesh.ARRAY_BONES]
		vertices[Mesh.ARRAY_WEIGHTS] = original[Mesh.ARRAY_WEIGHTS]
		var shapes: Array[Array] = []
		for shape in source.surface_get_blend_shape_arrays(surface):
			shapes.append(_positions(shape))
		var flags := source.surface_get_format(surface) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		lines.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, vertices, shapes, {}, flags)
	return {"mesh": lines, "statistics": statistics}


static func _positions(source: Array) -> Array:
	var result: Array = []
	result.resize(Mesh.ARRAY_MAX)
	result[Mesh.ARRAY_VERTEX] = source[Mesh.ARRAY_VERTEX]
	return result


static func infer(points: PackedVector3Array, source_indices: PackedInt32Array) -> Dictionary:
	var edges: Dictionary[Vector2i, PackedInt32Array]
	var count := points.size() if source_indices.is_empty() else source_indices.size()
	@warning_ignore("integer_division")
	var triangles := count / 3
	for triangle in range(triangles):
		var start := triangle * 3
		var a := start if source_indices.is_empty() else source_indices[start]
		var b := start + 1 if source_indices.is_empty() else source_indices[start + 1]
		var c := start + 2 if source_indices.is_empty() else source_indices[start + 2]
		if a == b or b == c or c == a:
			continue
		_record(edges, triangle, a, b, c)
		_record(edges, triangle, b, c, a)
		_record(edges, triangle, c, a, b)

	var candidates: Array[Dictionary] = []
	for key in edges:
		var adjacency := edges[key]
		# Require exactly two faces with opposite winding along the edge.
		if (adjacency.size() != 8 or adjacency[1] != adjacency[6]
				or adjacency[2] != adjacency[5] or adjacency[3] == adjacency[7]):
			continue
		var quality := _quality(points[adjacency[1]], points[adjacency[2]], points[adjacency[3]], points[adjacency[7]])
		if quality >= 0.0:
			candidates.append({"edge": key, "quality": quality, "first": adjacency[0], "second": adjacency[4]})
	candidates.sort_custom(_prefer_pair)

	var matched := PackedByteArray()
	matched.resize(triangles)
	var pairs := 0
	for candidate in candidates:
		var first: int = candidate.first
		var second: int = candidate.second
		if matched[first] or matched[second]:
			continue
		matched[first] = 1
		matched[second] = 1
		edges.erase(candidate.edge)
		pairs += 1
	var indices := PackedInt32Array()
	indices.resize(edges.size() * 2)
	var cursor := 0
	for key in edges:
		indices[cursor] = key.x
		indices[cursor + 1] = key.y
		cursor += 2
	return {"indices": indices, "statistics": Vector2i(pairs, triangles - pairs * 2)}


static func _record(edges: Dictionary[Vector2i, PackedInt32Array], triangle: int, a: int, b: int, tip: int) -> void:
	var key := Vector2i(mini(a, b), maxi(a, b))
	var record: PackedInt32Array = edges.get(key, PackedInt32Array())
	if record.size() >= 8:
		if record.size() == 8:
			record.append(-1) # A non-manifold edge stays visible.
			edges[key] = record
		return
	record.append_array(PackedInt32Array([triangle, a, b, tip]))
	edges[key] = record


static func _quality(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> float:
	# The order c, a, d, b traces the exterior of the pair.
	var side_a := a - c
	var side_b := d - a
	var side_c := b - d
	var side_d := c - b
	var diagonal := b - a
	var longest := maxf(maxf(side_a.length_squared(), side_b.length_squared()), maxf(side_c.length_squared(), side_d.length_squared()))
	if longest == 0.0 or diagonal.length_squared() < longest * 0.90:
		return -1.0
	var normal := diagonal.cross(c - a)
	var other_normal := (a - b).cross(d - b)
	var tolerance := longest * 0.00001
	if normal.length_squared() <= tolerance * tolerance or other_normal.length_squared() <= tolerance * tolerance:
		return -1.0
	normal = normal.normalized()
	if normal.dot(other_normal.normalized()) < MIN_NORMAL_ALIGNMENT:
		return -1.0
	var sides := [side_a, side_b, side_c, side_d]
	var penalty := 0.0
	for corner in range(4):
		var previous: Vector3 = sides[corner]
		var next: Vector3 = sides[(corner + 1) % 4]
		if previous.cross(next).dot(normal) <= tolerance:
			return -1.0
		var alignment := absf(previous.normalized().dot(next.normalized()))
		if alignment > MAX_CORNER_ALIGNMENT:
			return -1.0
		penalty += alignment
	return 1.0 - penalty * 0.25


static func _prefer_pair(a: Dictionary, b: Dictionary) -> bool:
	if a.quality != b.quality:
		return a.quality > b.quality
	var first: Vector2i = a.edge
	var second: Vector2i = b.edge
	return first.x < second.x or (first.x == second.x and first.y < second.y)
