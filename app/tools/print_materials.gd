extends "res://materials.gd"

const PRINT_OBJ := "# WoB Model Viewer print mesh, millimeters, Z up"
const ThreeMF = preload("res://tools/three_mf.gd")

var file_bytes := 0
var _parts: Dictionary
var _obj_materials: Dictionary


class Part extends RefCounted:
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var uv := PackedVector2Array()
	var has_uv := false

	func triangle(a: Vector3, b: Vector3, c: Vector3) -> void:
		var normal := (b - a).cross(c - a).normalized()
		positions.append_array(PackedVector3Array([a, c, b]))
		normals.append_array(PackedVector3Array([normal, normal, normal]))


func prepare_model(path: String, _manifest: RefCounted = null) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return tr("Soubor nelze přečíst (%s).") % error_string(FileAccess.get_open_error())
	file_bytes = file.get_length()
	var valid := false
	match path.get_extension().to_lower():
		"3mf":
			file.close()
			valid = _read_3mf(path)
		"stl":
			valid = _read_stl(file)
			file.close()
		_:
			valid = _read_obj(file, path.get_base_dir())
			file.close()
	if not valid or _parts.is_empty():
		return tr("Soubor neobsahuje platnou síť OBJ, STL nebo 3MF.")
	return ""


func finish_model() -> String:
	root = Node3D.new()
	root.name = "Model"
	for key: Array in _parts:
		var part: Part = _parts[key]
		if part.positions.is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = part.positions
		arrays[Mesh.ARRAY_NORMAL] = part.normals
		if part.has_uv:
			arrays[Mesh.ARRAY_TEX_UV] = part.uv
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, _material(key[1]))
		var instance := MeshInstance3D.new()
		instance.name = str(key[0]).validate_node_name()
		instance.mesh = mesh
		root.add_child(instance, true)
		meshes.append(instance)
	_parts.clear()
	if meshes.is_empty():
		root.free()
		root = null
		return tr("Soubor neobsahuje zobrazitelnou síť.")
	return ""


func has_color_alpha(_instance: MeshInstance3D, _surface: int, _layer: String) -> bool:
	return false


func inspection_meshes(_color_layer: String) -> Dictionary[MeshInstance3D, ArrayMesh]:
	return {}


func _read_stl(file: FileAccess) -> bool:
	var part := Part.new()
	if file_bytes >= 84:
		file.seek(80)
		var count := file.get_32()
		if 84 + count * 50 == file_bytes:
			for facet in count:
				file.seek(84 + facet * 50 + 12)
				var corners := PackedVector3Array()
				for point in 3:
					corners.append(_from_print(Vector3(file.get_float(), file.get_float(), file.get_float())))
				if not _stl_triangle(part, corners):
					return false
			if not part.positions.is_empty():
				_parts[["STL", ""]] = part
			return file.get_error() == OK
	file.seek(0)
	if not file.get_line().strip_edges().begins_with("solid"):
		return false
	var corners := PackedVector3Array()
	while file.get_position() < file_bytes:
		var fields := _fields(file.get_line())
		if fields.is_empty():
			continue
		if fields[0] == "vertex":
			var value := _vector(fields)
			if not value.is_finite():
				return false
			corners.append(_from_print(value))
		elif fields[0] == "endfacet":
			if corners.size() != 3 or not _stl_triangle(part, corners):
				return false
			corners.clear()
	if not part.positions.is_empty():
		_parts[["STL", ""]] = part
	return corners.is_empty()


func _read_3mf(path: String) -> bool:
	var objects := ThreeMF.new().read(path)
	for index in objects.size():
		var object: Dictionary = objects[index]
		var part := Part.new()
		var points: PackedVector3Array = object.points
		var faces: PackedInt32Array = object.faces
		var transform: Transform3D = object.transform
		var mirrored := transform.basis.determinant() < 0.0
		for offset in range(0, faces.size(), 3):
			var a := _from_3mf(transform * points[faces[offset]])
			var b := _from_3mf(transform * points[faces[offset + 1]])
			var c := _from_3mf(transform * points[faces[offset + 2]])
			var triangle := PackedVector3Array([a, c, b] if mirrored else [a, b, c])
			if not _stl_triangle(part, triangle):
				return false
		if not part.positions.is_empty():
			_parts[[object.name, "", index]] = part
	return not _parts.is_empty()


func _stl_triangle(part: Part, corners: PackedVector3Array) -> bool:
	for point in corners:
		if not point.is_finite():
			return false
	if (corners[1] - corners[0]).cross(corners[2] - corners[0]).length_squared() > 0.0:
		part.triangle(corners[0], corners[1], corners[2])
	return true


func _read_obj(file: FileAccess, folder: String) -> bool:
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var uv := PackedVector2Array()
	var group := "OBJ"
	var material := ""
	var printing := false
	while file.get_position() < file_bytes:
		var line := file.get_line().strip_edges()
		if line == PRINT_OBJ and positions.is_empty():
			printing = true
		var fields := _fields(line.get_slice("#", 0))
		if fields.is_empty():
			continue
		var value := line.substr(fields[0].length()).get_slice("#", 0).strip_edges()
		match fields[0]:
			"v", "vn":
				var point := _vector(fields)
				if not point.is_finite():
					return false
				if fields[0] == "v":
					positions.append(_from_print(point) if printing else point)
				else:
					normals.append(Vector3(point.x, point.z, -point.y).normalized() if printing else point.normalized())
			"vt":
				if fields.size() < 3 or not fields[1].is_valid_float() or not fields[2].is_valid_float():
					return false
				var coordinate := Vector2(float(fields[1]), 1.0 - float(fields[2]))
				if not coordinate.is_finite():
					return false
				uv.append(coordinate)
			"o", "g":
				group = value if not value.is_empty() else "OBJ"
			"usemtl":
				material = value
			"mtllib":
				if GlbData.relative_file(value):
					_read_mtl(folder.path_join(GlbData.decode_file_uri(value)))
			"f":
				var key := [group, material]
				var part: Part = _parts.get(key)
				if not part:
					part = Part.new()
					_parts[key] = part
				if not _obj_face(part, fields, positions, uv, normals):
					return false
	return true


func _obj_face(part: Part, fields: PackedStringArray, positions: PackedVector3Array,
		uv: PackedVector2Array, normals: PackedVector3Array) -> bool:
	if fields.size() < 4:
		return false
	var points := PackedVector3Array()
	var corners: Array[Vector3i] = []
	for element in fields.slice(1):
		var tokens := element.split("/")
		var v := _obj_index(tokens[0], positions.size())
		var t := _obj_index(tokens[1], uv.size()) if tokens.size() > 1 and not tokens[1].is_empty() else -1
		var n := _obj_index(tokens[2], normals.size()) if tokens.size() > 2 and not tokens[2].is_empty() else -1
		if v < 0 or t == -2 or n == -2:
			return false
		points.append(positions[v])
		corners.append(Vector3i(v, t, n))
	var normal := Vector3.ZERO
	for index in points.size():
		normal += points[index].cross(points[(index + 1) % points.size()])
	if normal.length_squared() <= 0.0:
		return true
	var triangles := PackedInt32Array([0, 1, 2]) if points.size() == 3 else _triangulate(points, normal)
	if triangles.is_empty():
		return false
	for offset in range(0, triangles.size(), 3):
		var a := triangles[offset]
		var b := triangles[offset + 1]
		var c := triangles[offset + 2]
		if (points[b] - points[a]).cross(points[c] - points[a]).dot(normal) > 0.0:
			var swap := b
			b = c
			c = swap
		for corner in [corners[a], corners[b], corners[c]]:
			part.positions.append(positions[corner.x])
			part.has_uv = part.has_uv or corner.y >= 0
			part.uv.append(uv[corner.y] if corner.y >= 0 else Vector2.ZERO)
			part.normals.append(normals[corner.z] if corner.z >= 0 else normal.normalized())
	return true


func _triangulate(points: PackedVector3Array, normal: Vector3) -> PackedInt32Array:
	var projection := PackedVector2Array()
	var axis := normal.abs().max_axis_index()
	for point in points:
		projection.append(Vector2(point[(axis + 1) % 3], point[(axis + 2) % 3]))
	return Geometry2D.triangulate_polygon(projection)


func _obj_index(value: String, size: int) -> int:
	if not value.is_valid_int() or value.to_int() == 0:
		return -2
	var index := value.to_int() - 1 if value.to_int() > 0 else size + value.to_int()
	return index if index >= 0 and index < size else -2


func _read_mtl(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return
	var current := {}
	while file.get_position() < file.get_length():
		var line := file.get_line().get_slice("#", 0).strip_edges()
		var fields := _fields(line)
		if fields.is_empty():
			continue
		var value := line.substr(fields[0].length()).strip_edges()
		match fields[0]:
			"newmtl":
				current = {}
				_obj_materials[value] = current
			"Kd":
				var rgb := _vector(fields)
				if rgb.is_finite():
					current["color"] = Color(rgb.x, rgb.y, rgb.z)
			"map_Kd":
				if not value.begins_with("-") and GlbData.relative_file(value):
					current["albedo"] = path.get_base_dir().path_join(GlbData.decode_file_uri(value))


func _material(name: String) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.resource_name = name
	var definition: Dictionary = _obj_materials.get(name, {})
	material.albedo_color = definition.get("color", Color.WHITE)
	var path: String = definition.get("albedo", "")
	if not path.is_empty() and FileAccess.file_exists(path):
		var image := Image.load_from_file(path)
		if image and not image.is_empty():
			image.generate_mipmaps()
			material.albedo_texture = ImageTexture.create_from_image(image)
	return material


func _fields(line: String) -> PackedStringArray:
	return line.replace("\t", " ").split(" ", false)


func _vector(fields: PackedStringArray) -> Vector3:
	if fields.size() < 4 or not fields[1].is_valid_float() or not fields[2].is_valid_float() or not fields[3].is_valid_float():
		return Vector3.INF
	return Vector3(float(fields[1]), float(fields[2]), float(fields[3]))


func _from_print(point: Vector3) -> Vector3:
	return Vector3(point.x, point.z, -point.y) * 0.001


func _from_3mf(point: Vector3) -> Vector3:
	return Vector3(point.x, point.z, -point.y)
