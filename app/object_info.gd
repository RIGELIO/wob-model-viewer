extends RefCounted

const ATTRIBUTES := {
	Mesh.ARRAY_FORMAT_VERTEX: "POSITION", Mesh.ARRAY_FORMAT_NORMAL: "NORMAL",
	Mesh.ARRAY_FORMAT_TANGENT: "TANGENT", Mesh.ARRAY_FORMAT_COLOR: "COLOR_0",
	Mesh.ARRAY_FORMAT_TEX_UV: "TEXCOORD_0", Mesh.ARRAY_FORMAT_TEX_UV2: "TEXCOORD_1",
	Mesh.ARRAY_FORMAT_BONES: "JOINTS_0", Mesh.ARRAY_FORMAT_WEIGHTS: "WEIGHTS_0",
}
const PRIMITIVES := ["Body", "Čáry", "Pás čar", "Trojúhelníky", "Pás trojúhelníků"]
const SOURCE_GROUPS := {"nodes": "Uzly glTF", "images": "Obrázky glTF", "scenes": "Scény glTF"}
const TEXTURE_SLOTS := {
	"Albedo": BaseMaterial3D.TEXTURE_ALBEDO, "Normála": BaseMaterial3D.TEXTURE_NORMAL,
	"Drsnost": BaseMaterial3D.TEXTURE_ROUGHNESS, "Kovovost": BaseMaterial3D.TEXTURE_METALLIC,
	"AO": BaseMaterial3D.TEXTURE_AMBIENT_OCCLUSION, "Emise": BaseMaterial3D.TEXTURE_EMISSION,
}


func report(viewer: Control, kind: String, data: Variant) -> String:
	var stage: Control = viewer.stage
	if not stage.model:
		return tr("Otevři model a vyber objekt nebo vrstvu ve stromu scény.")
	var lines := PackedStringArray()
	match kind:
		"mesh":
			if is_instance_valid(data):
				_mesh(lines, stage, data)
		"material":
			var slot: Dictionary = viewer._editor_materials.targets[int(data)]
			_field(lines, "Název", slot.label)
			_field(lines, "Uzel", slot.node)
			_surface(lines, stage, slot.instance, slot.surface)
		"materials":
			_field(lines, "Materiálové sloty", viewer._editor_materials.targets.size())
			for slot: Dictionary in viewer._editor_materials.targets:
				lines.append("%s · %s" % [slot.label, slot.node])
		"skeleton":
			_skeletons(lines, stage)
		"animations", "clip":
			_clips(lines, stage, int(data) if kind == "clip" else -1)
		_:
			_model(lines, viewer)
	return "\n".join(lines)


func _model(lines: PackedStringArray, viewer: Control) -> void:
	var stage: Control = viewer.stage
	var path: String = viewer._path
	var byte_count: int = viewer._model_file_bytes()
	_field(lines, "Název", path.get_file())
	_field(lines, "Cesta", path)
	_field(lines, "Formát", path.get_extension().to_upper())
	_field(lines, "Velikost souboru", "%s (%d B)" % [viewer._file_size(byte_count), byte_count])
	var modified := FileAccess.get_modified_time(path)
	if modified > 0:
		_field(lines, "Změněno (UTC)", Time.get_datetime_string_from_unix_time(modified, true))
	_field(lines, "Rozměry importu", _meters(stage.bounds.size))
	_field(lines, "Střed importu", _meters(stage.bounds.get_center()))
	_counts(lines, stage.geometry)
	if viewer._display.selected == 6:
		var topology: Vector2i = stage.quad_statistics()
		lines.append(tr("Odvozené quady %d · zbývající troj. %d") % [topology.x, topology.y])
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
		_field(lines, "Atributy vrcholů (souhrn)", ", ".join(attribute_names))
	_field(lines, "Viditelné vrstvy", "%d / %d" % [visible_meshes, stage.geometry.x])
	var isolation: Dictionary = stage.isolation_state()
	if not isolation.is_empty():
		_field(lines, "Izolace", isolation.node)
	if viewer._lod_entries.size() > 1:
		_field(lines, "Úroveň detailu", viewer._lod_picker.get_item_text(viewer._lod_picker.selected))
	if not stage.model.vehicle_state.is_empty():
		_field(lines, "Stav vozu", stage.model.vehicle_state)
	if stage.model.source:
		var json: Dictionary = stage.model.source.json
		var asset: Dictionary = json.get("asset", {})
		var asset_labels := {"version": "Verze glTF", "generator": "Exportér", "copyright": "Copyright"}
		for key in asset_labels:
			if asset.has(key):
				_field(lines, asset_labels[key], asset[key])
		for section in SOURCE_GROUPS:
			var records: Variant = json.get(section)
			if records is Array:
				_field(lines, SOURCE_GROUPS[section], records.size())
		var extensions := PackedStringArray(json.get("extensionsUsed", []))
		if not extensions.is_empty():
			_field(lines, "Rozšíření glTF", ", ".join(extensions))
		_extras(lines, asset.get("extras"))
		_extras(lines, json.get("extras"))
	_field(lines, "Kostra", stage._skeletons.size())
	if not stage._skeletons.is_empty():
		var bones := 0
		for skeleton: Skeleton3D in stage._skeletons:
			bones += skeleton.get_bone_count()
		_field(lines, "Kostí", bones)
	_field(lines, "Klipy animace", stage.clips.size())
	for key: String in stage.model.counts:
		lines.append("%s × %d" % [key, stage.model.counts[key]])
	for folder: String in stage.model.texture_folders:
		_field(lines, "Textury", folder)
	if not stage.model.notes.is_empty():
		lines.append("\n" + tr("Materiály a diagnostika"))
		lines.append_array(stage.model.notes)


func _mesh(lines: PackedStringArray, stage: Control, instance: MeshInstance3D) -> void:
	_field(lines, "Název", instance.name)
	_field(lines, "Uzel", stage.model.root.get_path_to(instance))
	_field(lines, "Viditelnost vrstvy", tr("Zapnuto" if stage.is_part_visible(instance) else "Vypnuto"))
	_field(lines, "Lokální rozměry", _meters(instance.get_aabb().size))
	_field(lines, "Pozice uzlu", _meters(instance.position))
	_field(lines, "Rotace uzlu (°)", _vector(instance.rotation_degrees))
	_field(lines, "Měřítko uzlu", _vector(instance.scale))
	if stage.model.source:
		var nodes: Array = stage.model.source.json.get("nodes", [])
		var node_index := int(instance.get_meta(&"_wob_gltf_index", -1))
		if node_index >= 0 and node_index < nodes.size():
			_field(lines, "Index uzlu glTF", node_index)
			_extras(lines, nodes[node_index].get("extras"))
	var mesh := instance.mesh as ArrayMesh
	if not mesh:
		return
	if not instance.skeleton.is_empty() and instance.skin:
		_field(lines, "Vazby na kosti", instance.skin.get_bind_count())
	_field(lines, "Morph targety", mesh.get_blend_shape_count())
	for shape in mesh.get_blend_shape_count():
		lines.append(str(mesh.get_blend_shape_name(shape)))
	var total := Vector4i(1, mesh.get_surface_count(), 0, 0)
	for surface in mesh.get_surface_count():
		total.z += mesh.surface_get_array_len(surface)
		total.w += _triangles(mesh, surface)
	_counts(lines, total)
	for surface in mesh.get_surface_count():
		lines.append("")
		_surface(lines, stage, instance, surface)


func _surface(lines: PackedStringArray, stage: Control, instance: MeshInstance3D, surface: int) -> void:
	var mesh := instance.mesh as ArrayMesh
	if not mesh:
		return
	_field(lines, "Povrch", surface + 1)
	_field(lines, "Vrcholů", mesh.surface_get_array_len(surface))
	_field(lines, "Indexů", maxi(0, mesh.surface_get_array_index_len(surface)))
	_field(lines, "Trojúhelníky", _triangles(mesh, surface))
	var primitive := mesh.surface_get_primitive_type(surface)
	if primitive >= 0 and primitive < PRIMITIVES.size():
		_field(lines, "Primitiva", tr(PRIMITIVES[primitive]))
	_field(lines, "Atributy vrcholů", ", ".join(_attributes(stage, instance, surface)))
	var material := instance.get_active_material(surface)
	if not material:
		return
	_field(lines, "Materiál", stage.model.surface_material_name(instance, surface))
	_field(lines, "Typ materiálu", material.get_class())
	if material is BaseMaterial3D:
		_field(lines, "Základní barva", "#" + material.albedo_color.to_html())
		_field(lines, "Drsnost", "%.3f" % material.roughness)
		_field(lines, "Kovovost", "%.3f" % material.metallic)
		for slot in TEXTURE_SLOTS:
			_texture(lines, tr(slot), material.get_texture(TEXTURE_SLOTS[slot]))
		_texture(lines, tr("Výšková mapa"), material.heightmap_texture)
	elif material is ShaderMaterial and material.shader:
		if not material.shader.resource_path.is_empty():
			_field(lines, "Shader", material.shader.resource_path)
		for uniform in material.shader.get_shader_uniform_list():
			var value: Variant = material.get_shader_parameter(uniform.name)
			if value is Texture2D:
				_texture(lines, uniform.name, value)


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


func _skeletons(lines: PackedStringArray, stage: Control) -> void:
	_field(lines, "Kostra", stage._skeletons.size())
	for skeleton: Skeleton3D in stage._skeletons:
		_field(lines, "Uzel", stage.model.root.get_path_to(skeleton))
		_field(lines, "Kostí", skeleton.get_bone_count())
		for bone in skeleton.get_bone_count():
			lines.append(str(skeleton.get_bone_name(bone)))


func _clips(lines: PackedStringArray, stage: Control, selected: int) -> void:
	if selected < 0:
		_field(lines, "Klipy animace", stage.clips.size())
	for index in stage.clips.size():
		if selected >= 0 and selected != index:
			continue
		var clip: Dictionary = stage.clips[index]
		var animation: Animation = clip.player.get_animation(clip.name)
		_field(lines, "Klip", clip.name)
		_field(lines, "Délka", "%.3f s" % animation.length)
		_field(lines, "Stopy animace", animation.get_track_count())
		if selected >= 0:
			for track in animation.get_track_count():
				lines.append("%s · %s" % [animation.track_get_path(track),
					tr("%d klíčů") % animation.track_get_key_count(track)])


func _extras(lines: PackedStringArray, extras: Variant) -> void:
	if extras == null:
		return
	var metadata := JSON.stringify(extras)
	_field(lines, "Doplňková metadata glTF", metadata.left(4096) + ("…" if metadata.length() > 4096 else ""))


func _texture(lines: PackedStringArray, slot: String, texture: Texture2D) -> void:
	if texture:
		_field(lines, slot, "%d × %d px%s" % [
			texture.get_width(), texture.get_height(),
			" · " + texture.resource_path if not texture.resource_path.is_empty() else ""])


func _counts(lines: PackedStringArray, counts: Vector4i) -> void:
	_field(lines, "Sítí", counts.x)
	_field(lines, "Povrchů", counts.y)
	_field(lines, "Vrcholů", counts.z)
	_field(lines, "Trojúhelníky", counts.w)


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


func _meters(value: Vector3) -> String:
	return _vector(value) + " m"


func _vector(value: Vector3) -> String:
	return "%.3f × %.3f × %.3f" % [value.x, value.y, value.z]


func _field(lines: PackedStringArray, label: String, value: Variant) -> void:
	lines.append("%s  %s" % [tr(label), value])
