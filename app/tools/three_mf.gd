extends RefCounted

const START_PART := "http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"
const UNITS := {"micron": 0.000001, "millimeter": 0.001, "centimeter": 0.01,
	"inch": 0.0254, "foot": 0.3048, "meter": 1.0}

var _parts: Dictionary


func read(path: String) -> Array[Dictionary]:
	var archive := ZIPReader.new()
	if archive.open(path) != OK:
		return []
	var first := _start_file(archive)
	var result: Array[Dictionary] = []
	if not first.is_empty():
		result = _build(archive, first)
	archive.close()
	return result


func _start_file(archive: ZIPReader) -> String:
	var parser := _read_xml(archive, "_rels/.rels")
	if not parser:
		return ""
	while parser.read() == OK:
		if parser.get_node_type() == XMLParser.NODE_ELEMENT and _name(parser.get_node_name()) == "Relationship" \
				and _attribute(parser, "Type") == START_PART and _attribute(parser, "TargetMode") != "External":
			return _part_path(_attribute(parser, "Target"), "")
	return ""


func _build(archive: ZIPReader, first: String) -> Array[Dictionary]:
	var root := _part(archive, first)
	if root.is_empty():
		return []
	var pending: Array[Dictionary] = []
	for item: Dictionary in root.build:
		pending.push_back({"item": item, "parent": Transform3D.IDENTITY, "ancestors": {}})
	var result: Array[Dictionary] = []
	while not pending.is_empty():
		var entry := pending.pop_front() as Dictionary
		var item: Dictionary = entry.item
		var identity := [item.part.to_lower(), item.id]
		var ancestors: Dictionary = entry.ancestors
		if ancestors.has(identity):
			return []
		var part := _part(archive, item.part)
		var objects: Dictionary = part.get("objects", {})
		var object: Dictionary = objects.get(item.id, {})
		if object.is_empty():
			return []
		var transform: Transform3D = entry.parent * item.transform
		if not transform.is_finite():
			return []
		if not object.faces.is_empty():
			result.append({"name": object.name, "points": object.points, "faces": object.faces,
				"transform": transform})
		if not object.components.is_empty():
			var chain := ancestors.duplicate()
			chain[identity] = true
			for component: Dictionary in object.components:
				pending.push_back({"item": component, "parent": transform, "ancestors": chain})
	return result


func _part(archive: ZIPReader, path: String) -> Dictionary:
	var key := path.to_lower()
	if _parts.has(key):
		return _parts[key]
	var parser := _read_xml(archive, path)
	if not parser:
		return {}
	var stack := PackedStringArray()
	var units := 0.0
	var objects := {}
	var build: Array[Dictionary] = []
	var current := {}
	var error := parser.read()
	while error == OK:
		var kind := parser.get_node_type()
		if kind == XMLParser.NODE_ELEMENT:
			var tag := _name(parser.get_node_name())
			var parent := stack[-1] if not stack.is_empty() else ""
			match tag:
				"model":
					if not parent.is_empty() or units != 0.0:
						return {}
					units = UNITS.get(_attribute(parser, "unit", "millimeter"), 0.0)
					if units <= 0.0:
						return {}
				"object":
					if parent == "resources":
						var id := _index(parser, "id")
						if id < 1 or objects.has(id):
							return {}
						current = {"name": _attribute(parser, "name", "3MF %d" % id), "points": PackedVector3Array(),
							"faces": PackedInt32Array(), "components": []}
						objects[id] = current
				"vertex":
					if parent == "vertices" and not current.is_empty():
						var point := Vector3(_number(parser, "x"), _number(parser, "y"), _number(parser, "z")) * units
						if not point.is_finite():
							return {}
						current.points.append(point)
				"triangle":
					if parent == "triangles" and not current.is_empty():
						for label in ["v1", "v2", "v3"]:
							var index := _index(parser, label)
							if index < 0 or index >= current.points.size():
								return {}
							current.faces.append(index)
				"component", "item":
					if (tag == "component" and parent == "components" and not current.is_empty()) \
							or (tag == "item" and parent == "build"):
						var ref := _reference(parser, path, units)
						if ref.is_empty():
							return {}
						if tag == "item":
							build.append(ref)
						else:
							current.components.append(ref)
			if not parser.is_empty():
				stack.append(tag)
		elif kind == XMLParser.NODE_ELEMENT_END:
			var tag := _name(parser.get_node_name())
			if stack.is_empty() or stack[-1] != tag:
				return {}
			stack.resize(stack.size() - 1)
			if tag == "object":
				current = {}
		error = parser.read()
	if error != ERR_FILE_EOF or not stack.is_empty() or units <= 0.0 or objects.is_empty():
		return {}
	var parsed := {"objects": objects, "build": build}
	_parts[key] = parsed
	return parsed


func _reference(parser: XMLParser, path: String, units: float) -> Dictionary:
	var object := _index(parser, "objectid")
	var relative := _local_attribute(parser, "path")
	var part := path if relative.is_empty() else _part_path(relative, path.get_base_dir())
	var matrix := _matrix(_attribute(parser, "transform"), units)
	if object < 1 or part.is_empty() or not matrix.is_finite():
		return {}
	return {"id": object, "part": part, "transform": matrix}


func _matrix(value: String, units: float) -> Transform3D:
	if value.is_empty():
		return Transform3D.IDENTITY
	var fields := value.replace("\t", " ").replace("\n", " ").replace("\r", " ").split(" ", false)
	if fields.size() != 12:
		return Transform3D(Basis.IDENTITY, Vector3.INF)
	var column: Array[Vector3] = []
	for index in range(0, 12, 3):
		if not fields[index].is_valid_float() or not fields[index + 1].is_valid_float() or not fields[index + 2].is_valid_float():
			return Transform3D(Basis.IDENTITY, Vector3.INF)
		column.append(Vector3(float(fields[index]), float(fields[index + 1]), float(fields[index + 2])))
	return Transform3D(Basis(column[0], column[1], column[2]), column[3] * units)


func _part_path(value: String, folder: String) -> String:
	var decoded := value.uri_decode()
	if decoded.contains(":") or decoded.contains("\\") or decoded.begins_with("//"):
		return ""
	var path := decoded.trim_prefix("/") if decoded.begins_with("/") else folder.path_join(decoded)
	path = path.simplify_path()
	return path if not path.begins_with("../") and not path.begins_with("/") and path.get_extension().to_lower() == "model" else ""


func _read_xml(archive: ZIPReader, path: String) -> XMLParser:
	if not archive.file_exists(path, false):
		return null
	var parser := XMLParser.new()
	return parser if parser.open_buffer(archive.read_file(path, false)) == OK else null


func _attribute(parser: XMLParser, name: String, fallback := "") -> String:
	return parser.get_named_attribute_value(name) if parser.has_attribute(name) else fallback


func _local_attribute(parser: XMLParser, name: String) -> String:
	for index in parser.get_attribute_count():
		if _name(parser.get_attribute_name(index)) == name:
			return parser.get_attribute_value(index)
	return ""


func _name(value: String) -> String:
	return value.get_slice(":", 1) if value.contains(":") else value


func _index(parser: XMLParser, attribute: String) -> int:
	var value := _attribute(parser, attribute)
	return value.to_int() if value.is_valid_int() else -1


func _number(parser: XMLParser, attribute: String) -> float:
	var value := _attribute(parser, attribute)
	return value.to_float() if value.is_valid_float() else INF
