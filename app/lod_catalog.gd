extends RefCounted

const LodPattern := "^(.+)(?i:_lod)([0-9]+)(_[a-zA-Z0-9][a-zA-Z0-9_-]*)?(?i:\\.glb)$"
const GlbMagic := 0x46546C67
const JsonChunk := 0x4E4F534A
const MaxJsonSize := 64 * 1024 * 1024


static func discover(path: String) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var pattern := RegEx.create_from_string(LodPattern)
	var name := path.get_file()
	var selected := pattern.search(name)
	if selected == null:
		return entries
	var folder := path.get_base_dir()
	var dir := DirAccess.open(folder)
	var names := dir.get_files() if dir else PackedStringArray([name])
	for candidate in names:
		var match_result := pattern.search(candidate)
		if match_result == null or match_result.get_string(1) != selected.get_string(1):
			continue
		var level := match_result.get_string(2).to_int()
		var variant := match_result.get_string(3)
		var candidate_path := path if candidate == name else folder.path_join(candidate)
		var entry := _read_stats(candidate_path)
		entry["path"] = candidate_path
		entry["label"] = "LOD%d%s" % [level, variant]
		entry["level"] = level
		entries.append(entry)
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["level"] < b["level"] if a["level"] != b["level"] else a["label"] < b["label"]
	)
	return entries


static func _read_stats(path: String) -> Dictionary:
	var result := {"bytes": -1, "triangles": -1, "vertices": -1}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return result
	var size := file.get_length()
	result["bytes"] = size
	if size < 20:
		return result
	var header := file.get_buffer(20)
	if header.size() != 20 or header.decode_u32(0) != GlbMagic or header.decode_u32(4) != 2 \
			or header.decode_u32(8) != size or header.decode_u32(16) != JsonChunk:
		return result
	var json_size := header.decode_u32(12)
	if json_size < 2 or json_size % 4 != 0 or json_size > size - 20 or json_size > MaxJsonSize:
		return result
	var chunk := file.get_buffer(json_size)
	if chunk.size() != json_size:
		return result
	var parser := JSON.new()
	if parser.parse(chunk.get_string_from_utf8()) != OK or not parser.data is Dictionary:
		return result
	var geometry := _scene_geometry(parser.data)
	if not geometry.is_empty():
		result["vertices"] = geometry[0]
		result["triangles"] = geometry[1]
	return result


static func _scene_geometry(document: Dictionary) -> Array[int]:
	var scenes: Variant = document.get("scenes", [])
	var nodes: Variant = document.get("nodes", [])
	var meshes: Variant = document.get("meshes", [])
	var accessors: Variant = document.get("accessors", [])
	if not (scenes is Array and nodes is Array and meshes is Array and accessors is Array):
		return []
	if scenes.is_empty():
		return [0, 0]
	var scene_index := _index(document.get("scene", 0), scenes.size())
	if scene_index < 0 or not scenes[scene_index] is Dictionary:
		return []
	var roots: Variant = scenes[scene_index].get("nodes", [])
	if not roots is Array:
		return []
	var pending: Array = roots.duplicate()
	var visited := {}
	var mesh_counts := {}
	var vertices := 0
	var triangles := 0
	while not pending.is_empty():
		var node_index := _index(pending.pop_back(), nodes.size())
		if node_index < 0 or not nodes[node_index] is Dictionary:
			return []
		if visited.has(node_index):
			continue
		visited[node_index] = true
		var node: Dictionary = nodes[node_index]
		var children: Variant = node.get("children", [])
		if not children is Array:
			return []
		pending.append_array(children)
		if not node.has("mesh"):
			continue
		var mesh_index := _index(node["mesh"], meshes.size())
		if mesh_index < 0 or not meshes[mesh_index] is Dictionary:
			return []
		if not mesh_counts.has(mesh_index):
			var counts := _mesh_geometry(meshes[mesh_index], accessors)
			if counts.is_empty():
				return []
			mesh_counts[mesh_index] = counts
		vertices += int(mesh_counts[mesh_index][0])
		triangles += int(mesh_counts[mesh_index][1])
	return [vertices, triangles]


static func _mesh_geometry(mesh: Dictionary, accessors: Array) -> Array[int]:
	var primitives: Variant = mesh.get("primitives")
	if not primitives is Array or primitives.is_empty():
		return []
	var vertices := 0
	var triangles := 0
	for primitive: Variant in primitives:
		if not primitive is Dictionary or not primitive.get("attributes") is Dictionary:
			return []
		var position_count := _accessor_count(accessors, primitive["attributes"].get("POSITION"))
		var length := _accessor_count(accessors, primitive["indices"]) if primitive.has("indices") else position_count
		var mode := _index(primitive.get("mode", 4), 7)
		if position_count < 0 or length < 0 or mode < 0:
			return []
		vertices += position_count
		match mode:
			4:
				@warning_ignore("integer_division")
				triangles += length / 3
			5, 6:
				triangles += maxi(length - 2, 0)
	return [vertices, triangles]


static func _accessor_count(accessors: Array, value: Variant) -> int:
	var accessor_index := _index(value, accessors.size())
	if accessor_index < 0 or not accessors[accessor_index] is Dictionary:
		return -1
	return _index(accessors[accessor_index].get("count"), 0x100000000)


static func _index(value: Variant, limit: int) -> int:
	if not (value is int or value is float) or value < 0 or value >= limit or value != floor(value):
		return -1
	return int(value)
