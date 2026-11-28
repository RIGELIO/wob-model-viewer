extends RefCounted

const ATTRIBUTES := {
	Mesh.ARRAY_FORMAT_VERTEX: "POSITION", Mesh.ARRAY_FORMAT_NORMAL: "NORMAL",
	Mesh.ARRAY_FORMAT_TANGENT: "TANGENT", Mesh.ARRAY_FORMAT_COLOR: "COLOR_0",
	Mesh.ARRAY_FORMAT_TEX_UV: "TEXCOORD_0", Mesh.ARRAY_FORMAT_TEX_UV2: "TEXCOORD_1",
	Mesh.ARRAY_FORMAT_BONES: "JOINTS_0", Mesh.ARRAY_FORMAT_WEIGHTS: "WEIGHTS_0",
}
const PRIMITIVES := ["points", "lines", "line_strip", "triangles", "triangle_strip"]
const PRIMITIVE_LABELS := ["Body", "Čáry", "Pás čar", "Trojúhelníky", "Pás trojúhelníků"]
const SOURCE_GROUPS := {"nodes": "Uzly glTF", "images": "Obrázky glTF", "scenes": "Scény glTF"}
const ASSET_LABELS := {"version": "Verze glTF", "generator": "Exportér", "copyright": "Copyright"}
const TEXTURE_SLOTS := {
	"albedo": [BaseMaterial3D.TEXTURE_ALBEDO, "Albedo"],
	"normal": [BaseMaterial3D.TEXTURE_NORMAL, "Normála"],
	"roughness": [BaseMaterial3D.TEXTURE_ROUGHNESS, "Drsnost"],
	"metallic": [BaseMaterial3D.TEXTURE_METALLIC, "Kovovost"],
	"occlusion": [BaseMaterial3D.TEXTURE_AMBIENT_OCCLUSION, "AO"],
	"emission": [BaseMaterial3D.TEXTURE_EMISSION, "Emise"],
}


class Details extends RefCounted:
	var lines: Array[String]
	var values: Dictionary

	func field(key: String, label: String, value: Variant, formatted: Variant = null) -> void:
		values[key] = value
		lines.append("%s  %s" % [tr(label), value if formatted == null else formatted])

	func section(key: String) -> Details:
		var child := Details.new()
		child.lines = lines
		values[key] = child.values
		return child

	func item(key: String) -> Details:
		var child := Details.new()
		child.lines = lines
		if not values.has(key):
			values[key] = []
		values[key].append(child.values)
		return child


func report(viewer: Control, kind: String, data: Variant) -> String:
	if not viewer.stage.model:
		return tr("Otevři model a vyber objekt nebo vrstvu ve stromu scény.")
	return "\n".join(_inspect(viewer, kind, data).lines)


func write(viewer: Control, selection: Dictionary, path: String, overwrite: bool) -> Error:
	if not viewer.stage.model:
		return ERR_DOES_NOT_EXIST
	var extension := path.get_extension().to_lower()
	if not extension in ["json", "csv"]:
		return ERR_INVALID_PARAMETER
	var kind: String = selection.get("kind", "model")
	var details := _inspect(viewer, kind, selection.get("data"))
	var snapshot := {"schema_version": 1, "scope": kind, "source_path": viewer._path, "details": details.values}
	return _write_atomic(path, overwrite, _store_report.bind(snapshot, extension))


func write_inventory(path: String, rows: Array[Dictionary], overwrite: bool) -> Error:
	return _write_atomic(path, overwrite, _store_inventory.bind(rows))


func _write_atomic(path: String, overwrite: bool, store: Callable) -> Error:
	if not overwrite and (FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path)):
		return ERR_ALREADY_EXISTS
	var temporary := path + ".tmp-" + Crypto.new().generate_random_bytes(12).hex_encode()
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if not file:
		return FileAccess.get_open_error()
	var written: bool = store.call(file)
	file.flush()
	var error := file.get_error()
	file.close()
	if not written and error == OK:
		error = ERR_FILE_CANT_WRITE
	if error == OK:
		error = DirAccess.rename_absolute(temporary, path)
	if error != OK:
		DirAccess.remove_absolute(temporary)
	return error


func _store_report(file: FileAccess, snapshot: Dictionary, extension: String) -> bool:
	if extension == "json":
		return file.store_string(JSON.stringify(snapshot, "\t", true, true) + "\n")
	return _csv_header(file, ["field", "value"]) and _csv(file, "", snapshot)


func _store_inventory(file: FileAccess, rows: Array[Dictionary]) -> bool:
	if not _csv_header(file, ["path", "triangles", "status"]):
		return false
	for row in rows:
		var triangles := str(row.triangles) if row.has("triangles") else ""
		if not file.store_csv_line(PackedStringArray([row.source, triangles, row.code])):
			return false
	return true


func _csv_header(file: FileAccess, columns: PackedStringArray) -> bool:
	# A UTF-8 marker lets spreadsheet applications preserve non-ASCII text.
	return file.store_buffer(PackedByteArray([0xEF, 0xBB, 0xBF])) and file.store_csv_line(columns)


func _csv(file: FileAccess, pointer: String, value: Variant) -> bool:
	if value is Dictionary and not value.is_empty():
		for key in value:
			var token := str(key).replace("~", "~0").replace("/", "~1")
			if not _csv(file, pointer + "/" + token, value[key]):
				return false
		return true
	if value is Array and not value.is_empty():
		for index in value.size():
			if not _csv(file, pointer + "/" + str(index), value[index]):
				return false
		return true
	var cell := str(value) if value is String else JSON.stringify(value, "", true, true)
	if value is String:
		var start := cell.strip_edges().left(1)
		# Keep imported names and metadata as text when opening the CSV in a spreadsheet.
		if start in ["=", "+", "-", "@", "＝", "＋", "－", "＠"] \
				or cell.begins_with("\t") or cell.begins_with("\r") or cell.begins_with("\n"):
			cell = "'" + cell
	return file.store_csv_line(PackedStringArray([pointer, cell]))


func _inspect(viewer: Control, kind: String, data: Variant) -> Details:
	var stage: Control = viewer.stage
	var result := Details.new()
	match kind:
		"mesh":
			if is_instance_valid(data):
				_mesh(result, stage, data)
		"material":
			var slot: Dictionary = viewer._editor_materials.targets[int(data)]
			result.field("name", "Název", slot.label)
			result.field("node_path", "Uzel", slot.node)
			_surface(result.section("surface"), stage, slot.instance, slot.surface)
		"materials":
			result.field("material_slot_count", "Materiálové sloty", viewer._editor_materials.targets.size())
			for slot: Dictionary in viewer._editor_materials.targets:
				result.lines.append("%s · %s" % [slot.label, slot.node])
				result.item("material_slots").values.merge({"name": slot.label, "node_path": slot.node, "surface_index": slot.surface})
		"skeleton":
			_skeletons(result, stage)
		"animations", "clip":
			_clips(result, stage, int(data) if kind == "clip" else -1)
		_:
			_model(result, viewer)
	return result


func _model(result: Details, viewer: Control) -> void:
	var stage: Control = viewer.stage
	var path: String = viewer._path
	var file := result.section("file")
	var byte_count: int = viewer._model_file_bytes()
	file.field("name", "Název", path.get_file())
	result.lines.append("%s  %s" % [tr("Cesta"), path])
	file.field("format", "Formát", path.get_extension().to_upper())
	file.field("bytes", "Velikost souboru", byte_count, "%s (%d B)" % [viewer._file_size(byte_count), byte_count])
	var modified := FileAccess.get_modified_time(path)
	if modified > 0:
		file.field("modified_utc", "Změněno (UTC)", Time.get_datetime_string_from_unix_time(modified) + "Z")
	var geometry := result.section("geometry")
	_vector_field(geometry, "dimensions_m", "Rozměry importu", stage.bounds.size, " m")
	_vector_field(geometry, "center_m", "Střed importu", stage.bounds.get_center(), " m")
	_counts(geometry, stage.geometry)
	if viewer._display.selected == 6:
		var topology: Vector2i = stage.quad_statistics()
		geometry.values["inferred_quad_count"] = topology.x
		geometry.values["remaining_triangle_count"] = topology.y
		result.lines.append(tr("Odvozené quady %d · zbývající troj. %d") % [topology.x, topology.y])
	var visible_meshes := 0
	var attributes := {}
	for instance: MeshInstance3D in stage.model.meshes:
		visible_meshes += int(stage.is_part_visible(instance))
		var mesh := instance.mesh as ArrayMesh
		if mesh:
			for surface in mesh.get_surface_count():
				for name in _attributes(stage, instance, surface):
					attributes[name] = true
	var attribute_names := PackedStringArray(attributes.keys())
	attribute_names.sort()
	if not attribute_names.is_empty():
		geometry.field("vertex_attributes", "Atributy vrcholů (souhrn)", Array(attribute_names), ", ".join(attribute_names))
	geometry.field("visible_mesh_count", "Viditelné vrstvy", visible_meshes, "%d / %d" % [visible_meshes, stage.geometry.x])
	var isolation: Dictionary = stage.isolation_state()
	if not isolation.is_empty():
		result.field("isolation", "Izolace", isolation, isolation.node)
	if viewer._lod_entries.size() > 1 and viewer._lod_picker.selected >= 0:
		var lod: Dictionary = viewer._lod_entries[viewer._lod_picker.selected]
		result.field("lod_level", "Úroveň detailu", lod.level, lod.label)
	if not stage.model.vehicle_state.is_empty():
		result.field("vehicle_state", "Stav vozu", stage.model.vehicle_state)
	if stage.model.source:
		_source(result.section("gltf"), stage.model.source.json)
	result.field("skeleton_count", "Kostra", stage._skeletons.size())
	if not stage._skeletons.is_empty():
		var bones := 0
		for skeleton: Skeleton3D in stage._skeletons:
			bones += skeleton.get_bone_count()
		result.field("bone_count", "Kostí", bones)
	result.field("clip_count", "Klipy animace", stage.clips.size())
	result.values["material_counts"] = stage.model.counts
	for key: String in stage.model.counts:
		result.lines.append("%s × %d" % [key, stage.model.counts[key]])
	result.values["texture_folders"] = Array(stage.model.texture_folders)
	for folder: String in stage.model.texture_folders:
		result.lines.append("%s  %s" % [tr("Textury"), folder])
	var notes: PackedStringArray = stage.model.notes
	result.values["diagnostics"] = Array(notes)
	if not notes.is_empty():
		result.lines.append("\n" + tr("Materiály a diagnostika"))
		result.lines.append_array(notes)


func _source(result: Details, json: Dictionary) -> void:
	var asset: Dictionary = json.get("asset", {})
	for key in ASSET_LABELS:
		if asset.has(key):
			result.field(key, ASSET_LABELS[key], asset[key])
	for section in SOURCE_GROUPS:
		var records: Variant = json.get(section)
		if records is Array:
			result.field(section + "_count", SOURCE_GROUPS[section], records.size())
	var extensions := PackedStringArray(json.get("extensionsUsed", []))
	if not extensions.is_empty():
		result.field("extensions_used", "Rozšíření glTF", Array(extensions), ", ".join(extensions))
	_extras(result, "asset_extras", asset.get("extras"))
	_extras(result, "extras", json.get("extras"))


func _mesh(result: Details, stage: Control, instance: MeshInstance3D) -> void:
	result.field("name", "Název", str(instance.name))
	result.field("node_path", "Uzel", str(stage.model.root.get_path_to(instance)))
	var visible_layer: bool = stage.is_part_visible(instance)
	result.field("visible", "Viditelnost vrstvy", visible_layer, tr("Zapnuto" if visible_layer else "Vypnuto"))
	_vector_field(result, "dimensions_m", "Lokální rozměry", instance.get_aabb().size, " m")
	var transform := result.section("transform")
	_vector_field(transform, "position_m", "Pozice uzlu", instance.position, " m")
	_vector_field(transform, "rotation_deg", "Rotace uzlu (°)", instance.rotation_degrees)
	_vector_field(transform, "scale", "Měřítko uzlu", instance.scale)
	if stage.model.source:
		var nodes: Array = stage.model.source.json.get("nodes", [])
		var node_index := int(instance.get_meta(&"_wob_gltf_index", -1))
		if node_index >= 0 and node_index < nodes.size():
			result.field("gltf_node_index", "Index uzlu glTF", node_index)
			_extras(result, "gltf_extras", nodes[node_index].get("extras"))
	var mesh := instance.mesh as ArrayMesh
	if not mesh:
		return
	if not instance.skeleton.is_empty() and instance.skin:
		result.field("skin_bind_count", "Vazby na kosti", instance.skin.get_bind_count())
	result.field("morph_target_count", "Morph targety", mesh.get_blend_shape_count())
	var morph_names: Array[String] = []
	for shape in mesh.get_blend_shape_count():
		morph_names.append(str(mesh.get_blend_shape_name(shape)))
	result.values["morph_targets"] = morph_names
	result.lines.append_array(morph_names)
	var total := Vector4i(1, mesh.get_surface_count(), 0, 0)
	for surface in mesh.get_surface_count():
		total.z += mesh.surface_get_array_len(surface)
		total.w += _triangles(mesh, surface)
	_counts(result.section("geometry"), total)
	for surface in mesh.get_surface_count():
		result.lines.append("")
		_surface(result.item("surfaces"), stage, instance, surface)


func _surface(result: Details, stage: Control, instance: MeshInstance3D, surface: int) -> void:
	var mesh := instance.mesh as ArrayMesh
	if not mesh:
		return
	result.field("surface_index", "Povrch", surface, surface + 1)
	result.field("vertex_count", "Vrcholů", mesh.surface_get_array_len(surface))
	result.field("index_count", "Indexů", maxi(0, mesh.surface_get_array_index_len(surface)))
	result.field("triangle_count", "Trojúhelníky", _triangles(mesh, surface))
	var primitive := mesh.surface_get_primitive_type(surface)
	if primitive >= 0 and primitive < PRIMITIVES.size():
		result.field("primitive", "Primitiva", PRIMITIVES[primitive], tr(PRIMITIVE_LABELS[primitive]))
	var attributes := _attributes(stage, instance, surface)
	result.field("vertex_attributes", "Atributy vrcholů", Array(attributes), ", ".join(attributes))
	var material := instance.get_active_material(surface)
	if not material:
		return
	var surface_material := result.section("material")
	surface_material.field("name", "Materiál", stage.model.surface_material_name(instance, surface))
	surface_material.field("type", "Typ materiálu", material.get_class())
	if material is BaseMaterial3D:
		surface_material.field("base_color", "Základní barva", "#" + material.albedo_color.to_html())
		surface_material.field("roughness", "Drsnost", material.roughness, "%.3f" % material.roughness)
		surface_material.field("metallic", "Kovovost", material.metallic, "%.3f" % material.metallic)
		for key in TEXTURE_SLOTS:
			var slot: Array = TEXTURE_SLOTS[key]
			_texture(surface_material, key, slot[1], material.get_texture(slot[0]))
		_texture(surface_material, "height", "Výšková mapa", material.heightmap_texture)
	elif material is ShaderMaterial and material.shader:
		if not material.shader.resource_path.is_empty():
			surface_material.field("shader_path", "Shader", material.shader.resource_path)
		for uniform in material.shader.get_shader_uniform_list():
			var value: Variant = material.get_shader_parameter(uniform.name)
			if value is Texture2D:
				_texture(surface_material, uniform.name, uniform.name, value)


func _attributes(stage: Control, instance: MeshInstance3D, surface: int) -> PackedStringArray:
	var names: PackedStringArray = stage.model.source_attributes(instance, surface)
	var mesh := instance.mesh as ArrayMesh
	if names.is_empty():
		var format := mesh.surface_get_format(surface)
		for bit in ATTRIBUTES:
			if format & bit:
				names.append(ATTRIBUTES[bit])
	names.sort()
	return names


func _skeletons(result: Details, stage: Control) -> void:
	result.field("skeleton_count", "Kostra", stage._skeletons.size())
	for skeleton: Skeleton3D in stage._skeletons:
		var record := result.item("skeletons")
		record.field("node_path", "Uzel", str(stage.model.root.get_path_to(skeleton)))
		record.field("bone_count", "Kostí", skeleton.get_bone_count())
		var names: Array[String] = []
		for bone in skeleton.get_bone_count():
			names.append(str(skeleton.get_bone_name(bone)))
		record.values["bones"] = names
		record.lines.append_array(names)


func _clips(result: Details, stage: Control, selected: int) -> void:
	if selected < 0:
		result.field("clip_count", "Klipy animace", stage.clips.size())
	for index in stage.clips.size():
		if selected >= 0 and selected != index:
			continue
		var record := result.item("clips") if selected < 0 else result
		var clip: Dictionary = stage.clips[index]
		var animation: Animation = clip.player.get_animation(clip.name)
		record.field("name", "Klip", str(clip.name))
		record.field("duration_s", "Délka", animation.length, "%.3f s" % animation.length)
		record.field("track_count", "Stopy animace", animation.get_track_count())
		if selected >= 0:
			for track in animation.get_track_count():
				var track_path := str(animation.track_get_path(track))
				var keys := animation.track_get_key_count(track)
				record.item("tracks").values.merge({"path": track_path, "key_count": keys})
				record.lines.append("%s · %s" % [track_path, tr("%d klíčů") % keys])


func _extras(result: Details, key: String, extras: Variant) -> void:
	if extras != null:
		var text := JSON.stringify(extras)
		result.field(key, "Doplňková metadata glTF", extras, text.left(4096) + ("…" if text.length() > 4096 else ""))


func _texture(result: Details, key: String, label: String, texture: Texture2D) -> void:
	if not texture:
		return
	var preview := "%d × %d px" % [texture.get_width(), texture.get_height()]
	if not texture.resource_path.is_empty():
		preview += " · " + texture.resource_path
	result.values.get_or_add("textures", {})[key] = {
		"width_px": texture.get_width(), "height_px": texture.get_height(), "path": texture.resource_path}
	result.lines.append("%s  %s" % [tr(label), preview])


func _counts(result: Details, counts: Vector4i) -> void:
	result.field("mesh_count", "Sítí", counts.x)
	result.field("surface_count", "Povrchů", counts.y)
	result.field("vertex_count", "Vrcholů", counts.z)
	result.field("triangle_count", "Trojúhelníky", counts.w)


func _triangles(mesh: ArrayMesh, surface: int) -> int:
	var count := mesh.surface_get_array_index_len(surface)
	if count <= 0:
		count = mesh.surface_get_array_len(surface)
	match mesh.surface_get_primitive_type(surface):
		Mesh.PRIMITIVE_TRIANGLES:
			@warning_ignore("integer_division")
			return count / 3
		Mesh.PRIMITIVE_TRIANGLE_STRIP:
			return maxi(0, count - 2)
	return 0


func _vector_field(result: Details, key: String, label: String, value: Vector3, suffix := "") -> void:
	result.field(key, label, [value.x, value.y, value.z],
		("%.3f × %.3f × %.3f" % [value.x, value.y, value.z]) + suffix)
