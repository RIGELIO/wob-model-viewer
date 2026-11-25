extends RefCounted

const GlbData = preload("res://glb_data.gd")
const VehicleManifest = preload("res://vehicle_manifest.gd")
const GameMaterials = preload("res://game_materials.gd")
const TextureSearch = preload("res://texture_search.gd")
const VEHICLE_DIR := "res://production/vehicles/"
const SHADER_DIR := "res://production/shaders/"
const TEXTURE_DIR := "res://production/textures/"
const IMPORT_FLAGS := GLTFDocument.IMPORT_FLAG_FORCE_DISABLE_MESH_COMPRESSION \
	| GLTFDocument.IMPORT_FLAG_GENERATE_TANGENT_ARRAYS
const ALIASES := {
	"kuze": "kuze", "kůže": "kuze", "wob_skin": "kuze",
	"odev": "odev", "oděv": "odev", "wob_cloth": "odev", "vlasy_podklad": "odev",
	"oci": "oko", "oči": "oko", "oko": "oko", "wob_eye": "oko",
	"vlasy_karty": "vlasy_karty", "vousy_karty": "vlasy_karty",
	"rasy_karty": "vlasy_karty", "oboci_karty": "vlasy_karty",
	"vlasy_mikro_4k": "vlasy_mikro_4k", "vousy_mikro_v2_4k": "vlasy_mikro_4k",
	"vousy_strniste_shell": "vousy_strniste_shell", "stubble_shell": "vousy_strniste_shell",
}

class SourceNodes extends GLTFDocumentExtension:
	var indices: Dictionary

	func _import_post_parse(state: GLTFState) -> Error:
		var nodes := state.get_nodes()
		for index in range(nodes.size()):
			indices[nodes[index]] = index
		return OK

	func _import_node(_state: GLTFState, gltf_node: GLTFNode, _json: Dictionary, node: Node) -> Error:
		if gltf_node.mesh >= 0:
			node.set_meta(&"_wob_gltf_index", indices[gltf_node])
		return OK

var notes: PackedStringArray:
	get:
		var localized := PackedStringArray()
		for entry in _notes:
			var message := tr(entry[1])
			if not entry[2].is_empty():
				message = message % entry[2]
			localized.append("%s · %s" % [entry[0], message] if not entry[0].is_empty() else message)
		return localized
var counts: Dictionary
var texture_folders := PackedStringArray()
var meshes: Array[MeshInstance3D]
var source: GlbData
var root: Node
var vehicle: RefCounted
var vehicle_state := ""
var texture_directory := ""
var _pairs: Dictionary
var _resources: Dictionary
var _model_path: String
var _sidecar: Dictionary
var _notes: Array[Array]
var _catalog_hair := false
var _guide_catalog := false
var _texture_search: TextureSearch
var _guide_shader_code := ""
var _guide_head: Array[Material]
var _game: GameMaterials
var _used_game_slots: Dictionary[String, bool]
var _document: GLTFDocument
var _state: GLTFState
var _images: Dictionary[String, Image]


func import_model(path: String, manifest: RefCounted = null) -> String:
	var error := prepare_model(path, manifest)
	return finish_model() if error.is_empty() else error


# Prepare glTF resources and decode external maps before building the live scene.
func prepare_model(path: String, manifest: RefCounted = null) -> String:
	_model_path = path
	_texture_search = TextureSearch.new(path, texture_directory)
	source = GlbData.new(path)
	if not source.error.is_empty():
		return source.error
	var original: Dictionary = source.json
	var mesh_defs: Variant = original.get("meshes", [])
	var nodes: Variant = original.get("nodes", [])
	var mat_defs: Variant = original.get("materials", [])
	if not mesh_defs is Array or not nodes is Array or not mat_defs is Array:
		return tr("GLB má neplatnou strukturu uzlů, sítí nebo materiálů.")
	vehicle = manifest if manifest else VehicleManifest.for_model(path)
	if vehicle:
		vehicle_state = vehicle.state_for(path)
	else:
		_game = GameMaterials.find(path, _file_texture)
	_read_sidecar()
	var rewritten := original.duplicate(true)
	var remapped := _restore_missing_images(rewritten)
	var node_groups := {}
	for node_index: int in range(nodes.size()):
		if not nodes[node_index] is Dictionary:
			return tr("GLB má neplatný uzel.")
		var node_tag := str(nodes[node_index].get("name", "")).to_lower()
		_catalog_hair = _catalog_hair or node_tag == "vlasy_mikro_swept"
		_guide_catalog = _guide_catalog or node_tag.begins_with("vlasy_guideclump_")
		var mesh_index := int(nodes[node_index].get("mesh", -1))
		if mesh_index >= 0:
			if mesh_index >= mesh_defs.size():
				return tr("GLB odkazuje na chybějící síť.")
			if not node_groups.has(mesh_index):
				node_groups[mesh_index] = []
			node_groups[mesh_index].append(node_index)
	for mesh_index: int in node_groups:
		var mesh_def: Variant = mesh_defs[mesh_index]
		if not mesh_def is Dictionary or not mesh_def.get("primitives", []) is Array:
			return tr("GLB má neplatnou síť.")
		var primitives: Array = mesh_def.get("primitives", [])
		for surface: int in range(primitives.size()):
			var primitive: Variant = primitives[surface]
			if not primitive is Dictionary or not primitive.get("attributes", {}) is Dictionary:
				return tr("GLB má neplatný povrch sítě.")
			var attrs: Dictionary = primitive.get("attributes", {})
			var mat_index := int(primitive.get("material", -1))
			var material_name := ""
			if mat_index >= 0 and mat_index < mat_defs.size() and mat_defs[mat_index] is Dictionary:
				material_name = str(mat_defs[mat_index].get("name", ""))
			var tag := material_name.to_lower()
			var semantics := {}
			for node_index: int in node_groups[mesh_index]:
				var node_name := str(nodes[node_index].get("name", mesh_def.get("name", "Síť")))
				var profile := _profile(node_name, tag, surface)
				if vehicle and tag == vehicle.object_id:
					profile["shader"] = "vuz"
				profile["attributes"] = attrs
				profile["material_name"] = material_name
				_pairs[Vector2i(node_index, surface)] = profile
				var semantic := str(profile.get("color", "COLOR_0"))
				semantics[semantic if attrs.has(semantic) else "COLOR_0"] = true
			if semantics.size() > 1:
				for node_index: int in node_groups[mesh_index]:
					var profile: Dictionary = _pairs[Vector2i(node_index, surface)]
					if profile.get("color", "COLOR_0") != "COLOR_0":
						profile["blocked"] = true
			elif not semantics.is_empty():
				var semantic: String = semantics.keys()[0]
				if semantic != "COLOR_0":
					rewritten["meshes"][mesh_index]["primitives"][surface]["attributes"]["COLOR_0"] = attrs[semantic]
					remapped = true

	var source_nodes := SourceNodes.new()
	_document = GLTFDocument.new()
	_state = GLTFState.new()
	_state.filename = path.get_file().get_basename()
	var payload: PackedByteArray = source.with_json(rewritten) \
		if remapped or path.get_extension().to_lower() == "gltf" else source.bytes
	GLTFDocument.register_gltf_document_extension(source_nodes)
	var result := _document.append_from_buffer(payload, path, _state, IMPORT_FLAGS)
	GLTFDocument.unregister_gltf_document_extension(source_nodes)
	if result != OK:
		return tr("Godot model nenačetl (%s).") % error_string(result)
	if _guide_catalog:
		_prepare_guide_companions()
	_prepare_external_images()
	return ""


func finish_model() -> String:
	root = _document.generate_scene(_state)
	_document = null
	_state = null
	if root == null:
		return tr("Z GLB se nepodařilo vytvořit scénu.")
	_bind_scene(root)
	_images.clear()
	if _game:
		for issue in _game.notes:
			_note("", issue[0], issue[1] if issue.size() > 1 else [])
		if _used_game_slots.is_empty() and _game.notes.is_empty():
			_note("", "Balík neobsahuje herní materiál pro názvy povrchů v tomto modelu.")
	if meshes.is_empty():
		root.free()
		root = null
		return tr("Soubor neobsahuje zobrazitelnou síť.")
	return ""


func _prepare_external_images() -> void:
	var paths := PackedStringArray()
	if vehicle:
		for key in ["albedo", "normal", "orm"]:
			paths.append(vehicle.local_path(vehicle.textures.get(key)))
	var slots := {}
	for profile: Dictionary in _pairs.values():
		slots[profile.material_name] = true
		if profile.textures is Dictionary:
			for uri: Variant in profile.textures.values():
				paths.append(_local_texture_path(str(uri)))
		if not str(profile.atlas).is_empty():
			paths.append_array(_texture_search.find_atlas(str(profile.atlas)))
		elif profile.shader == "vlasy_karty":
			paths.append(_texture_search.find("vlasy_atlas.png"))
	if _game:
		paths.append_array(_game.texture_files(slots))
	for path in paths:
		if not path.is_empty() and not _images.has(path):
			_images[path] = _decode_texture(path)


func _restore_missing_images(json: Dictionary) -> bool:
	var changed := false
	var mime_types := {"png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "webp": "image/webp"}
	for image: Dictionary in json.get("images", []):
		var uri := str(image.get("uri", ""))
		if uri.is_empty() or uri.begins_with("data:") or not GlbData.relative_file(uri):
			continue
		var relative := GlbData.decode_file_uri(uri)
		var original := _model_path.get_base_dir().path_join(relative)
		if relative == uri.uri_decode().replace("\\", "/") and FileAccess.file_exists(original):
			continue
		var found := _texture_search.find(uri)
		var mime: String = mime_types.get(found.get_extension().to_lower(), "")
		if found.is_empty() or mime.is_empty():
			_note("", "Chybí odkazovaná textura %s. Zvol Načíst textury…", [relative])
			continue
		var file := FileAccess.open(found, FileAccess.READ)
		if not file or file.get_length() > 32 * 1024 * 1024:
			continue
		var data := file.get_buffer(file.get_length())
		if data.is_empty():
			continue
		image["uri"] = "data:" + mime + ";base64," + Marshalls.raw_to_base64(data)
		_record_texture_folder(found)
		changed = true
	return changed


func _prepare_guide_companions() -> void:
	var shader_path := _texture_search.find_relative("shadery_godot4/vlasy_mikro_4k.gdshader")
	if not shader_path.is_empty():
		var file := FileAccess.open(shader_path, FileAccess.READ)
		if file and file.get_length() <= 64 * 1024:
			_guide_shader_code = file.get_as_text()
	var head_path := _texture_search.find_relative("rozpracovane/podklad_hlavy/keenface_hlava2.glb")
	if head_path.is_empty():
		return
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_file(head_path, state, IMPORT_FLAGS) != OK:
		return
	var materials := state.get_materials()
	var expected := ["Head_Skin", "Eye_L", "Eye_R", "Teeth", "Cornea_L", "Cornea_R"]
	if materials.size() != expected.size():
		return
	for index in range(materials.size()):
		if not materials[index] or materials[index].resource_name != expected[index]:
			return
	_guide_head = materials
	_record_texture_folder(head_path)


func _bind_scene(node: Node) -> void:
	if node is MeshInstance3D and node.mesh:
		meshes.append(node)
		var node_index := _node_index(node)
		for surface: int in range(node.mesh.get_surface_count()):
			var profile: Dictionary = _pairs.get(Vector2i(node_index, surface), {})
			if not _bind_game(node, surface, str(profile.get("material_name", ""))) and not profile.is_empty():
				_bind(node, surface, profile)
		if node_index < 0:
			_note(str(node.name), "Godot nepřiřadil síti původní uzel GLB.")
	for child in node.get_children():
		_bind_scene(child)


func _bind_game(instance: MeshInstance3D, surface: int, slot: String) -> bool:
	if not _game:
		return false
	if not _game.has_slot(slot):
		var imported := instance.mesh.surface_get_material(surface)
		slot = imported.resource_name if imported else ""
	if slot.is_empty() and instance.mesh is ArrayMesh:
		slot = instance.mesh.surface_get_name(surface)
	if not _game.has_slot(slot):
		return false
	var material := _game.material(slot)
	if material:
		instance.set_surface_override_material(surface, material)
		_used_game_slots[slot] = true
		var name := material.resource_name if not material.resource_name.is_empty() else slot
		counts[name] = int(counts.get(name, 0)) + 1
	return true


func color_layers() -> PackedStringArray:
	var layers := PackedStringArray()
	for profile: Dictionary in _pairs.values():
		for attribute: String in profile.attributes:
			if attribute.begins_with("COLOR_") and not layers.has(attribute):
				layers.append(attribute)
	layers.sort()
	return layers


func surface_material_name(instance: MeshInstance3D, surface: int) -> String:
	var material := instance.mesh.surface_get_material(surface)
	if not material or material.resource_name.is_empty():
		material = instance.get_active_material(surface)
	return material.resource_name if material else ""


func has_color_alpha(instance: MeshInstance3D, surface: int, layer: String) -> bool:
	var attrs: Dictionary = _pairs.get(Vector2i(_node_index(instance), surface), {}).get("attributes", {})
	var index := int(attrs.get(layer, -1))
	var accessors: Array = source.json.get("accessors", [])
	return index >= 0 and index < accessors.size() and accessors[index].get("type") == "VEC4"


# Import a geometry-only copy with the requested source attribute as COLOR_0.
# The production mesh and its material remapping stay intact.
func inspection_meshes(color_layer: String) -> Dictionary[MeshInstance3D, ArrayMesh]:
	var json := source.json.duplicate(true)
	for property in ["materials", "textures", "images", "samplers"]:
		json.erase(property)
	for definition: Dictionary in json.get("meshes", []):
		for primitive: Dictionary in definition.get("primitives", []):
			primitive.erase("material")
			var attributes: Dictionary = primitive.get("attributes", {})
			var accessor: Variant = attributes.get(color_layer)
			attributes.erase("COLOR_0")
			if accessor != null:
				attributes["COLOR_0"] = accessor
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	state.filename = _model_path.get_file().get_basename()
	var result: Dictionary[MeshInstance3D, ArrayMesh]
	if document.append_from_buffer(source.with_json(json), _model_path, state, IMPORT_FLAGS) != OK:
		return result
	var nodes := state.get_nodes()
	var imported := state.get_meshes()
	var converted: Dictionary[int, ArrayMesh]
	for instance in meshes:
		var index := _node_index(instance)
		if index < 0 or index >= nodes.size():
			continue
		var mesh_index := nodes[index].mesh
		if mesh_index < 0 or mesh_index >= imported.size():
			continue
		if not converted.has(mesh_index):
			converted[mesh_index] = imported[mesh_index].mesh.get_mesh()
		result[instance] = converted[mesh_index]
	return result


func _node_index(instance: MeshInstance3D) -> int:
	return int(instance.get_meta(&"_wob_gltf_index", -1))


func _read_sidecar() -> void:
	var path := _model_path.get_basename() + ".wob.json"
	if not FileAccess.file_exists(path):
		return
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if value is Dictionary and value.get("surfaces", {}) is Dictionary:
		_sidecar = value.get("surfaces", {})
	else:
		_note("", "Neplatné mapování v %s.", [path.get_file()])


func _profile(node_name: String, tag: String, surface: int) -> Dictionary:
	var name := node_name.to_lower()
	var role: String = ALIASES.get(tag, "")
	var atlas := ""
	var color := "COLOR_0"
	var parameters := {}
	var detail := ""
	if name.begins_with("stubbleshell") or role == "vousy_strniste_shell":
		role = "vousy_strniste_shell"
		var legacy := name.begins_with("stubbleshell_")
		atlas = "strniste_shell_2k" if legacy else "strniste_shell_4k"
		# Both catalog generations inherit the two head masks. The LOD generator exports
		# BeardDensity first, with the inherited masks shifted to COLOR_1 and COLOR_2.
		color = "COLOR_2" if legacy or ((_catalog_hair or _guide_catalog) and name.begins_with("stubbleshell4k_")) else "COLOR_0"
		parameters = _shell_parameters(name, legacy)
	elif _guide_catalog and name.ends_with("_lod3_opaque") and (
			(name.begins_with("vlasy_guideclump_") or name.begins_with("vousy_hrube_v3_"))):
		detail = "Neprůhledná silueta LOD3 nemá v exportu produkční materiál."
	elif name.begins_with("vlasy_lod3_opaque"):
		detail = "HairShade v COLOR_0. Pro neprůhlednou čepici LOD3 chybí odpovídající produkční shader nebo vložený materiál."
	elif _guide_catalog and (name.begins_with("vlasy_guideclump_") or name.begins_with("vousy_hrube_v3_")
			or name == "vousy_stredni_1419_huste_v5" or name.begins_with("oboci_3d_") or name.begins_with("rasy_3d_")):
		role = "vlasy_mikro_4k"
		if name.begins_with("vlasy_guideclump_"):
			atlas = "vlasy_mikro_4k"
		elif name.begins_with("oboci_3d_") or name.begins_with("rasy_3d_"):
			atlas = "oboci_rasy_mikro_4k"
		else:
			atlas = "vousy_hrube_v3_4k"
		if name.contains("_lod1") and name.begins_with("vlasy_guideclump_"):
			parameters["alfa_boost"] = 1.32
		if name.ends_with("_lod2"):
			parameters.merge({"alfa_boost": 1.8, "normala_sila": 0.0, "anizotropie": 0.0})
	elif name.begins_with("vlasy_mikro") or name.begins_with("vlasy_lod") \
			or name.begins_with("vousy_wiry") or role == "vlasy_mikro_4k":
		role = "vlasy_mikro_4k"
		atlas = "vlasy_mikro_4k"
		if name.begins_with("vousy_wiry") or tag == "vousy_mikro_v2_4k":
			atlas = "vousy_mikro_v2_4k" if "v2" in name or "v2" in tag else "vousy_mikro_4k"
		if name.begins_with("vlasy_lod1"):
			parameters["alfa_boost"] = 1.32
		elif name.begins_with("vlasy_lod2"):
			parameters.merge({"alfa_boost": 1.8, "normala_sila": 0.0, "anizotropie": 0.0})
	elif name == "head_shorthair" and role.is_empty():
		detail = "KeenFace export bez materiálu kůže. ScalpMask a případná BeardTintMask mají jiný význam než vstupy shaderu kuze."
	elif role.is_empty() and tag != "usta_vnitrek":
		detail = "Pro tento povrch není známé mapování produkčního shaderu. Zobrazení podle GLB."

	var override: Variant = _sidecar.get("%s:%d" % [node_name, surface], {})
	if override is Dictionary:
		if override.has("shader"):
			role = str(override["shader"])
			detail = ""
		color = str(override.get("color", color))
		atlas = str(override.get("atlas", atlas))
		if override.get("parameters", {}) is Dictionary:
			parameters.merge(override.get("parameters", {}), true)
	return {
		"shader": role, "tag": tag, "label": node_name, "atlas": atlas,
		"color": color, "parameters": parameters, "detail": detail,
		"textures": override.get("textures", {}) if override is Dictionary else {},
	}


func _shell_parameters(name: String, legacy: bool) -> Dictionary:
	if name.ends_with("_lod2"):
		return {"rez_min": 0.0, "rez_max": 1.1, "alfa_boost": 1.8}
	var suffix := name.get_slice("_", name.get_slice_count("_") - 1)
	if not suffix.is_valid_int():
		return {}
	var index := suffix.to_int()
	var cuts := [Vector3(0.0, 0.62, 1.0), Vector3(0.28, 0.84, 0.95), Vector3(0.54, 1.08, 0.88)]
	var is_lod1 := "_lod1" in _model_path.get_file().to_lower()
	# The catalog also uses the two-shell recipe for its first three presets.
	var nodes: Array = source.json.get("nodes", [])
	var two_shells := is_lod1 or not nodes.any(
		func(node: Variant) -> bool:
			return node is Dictionary and str(node.get("name", "")).to_lower() == "stubbleshell4k_2"
	)
	if legacy:
		cuts = [Vector3(0.0, 0.75, 1.0), Vector3(0.22, 0.92, 0.92), Vector3(0.48, 1.1, 0.80)]
	elif two_shells:
		cuts = [Vector3(0.0, 0.72, 1.0), Vector3(0.34, 1.06, 0.94)]
	if index < 0 or index >= cuts.size():
		return {}
	var cut: Vector3 = cuts[index]
	return {
		"rez_min": cut.x, "rez_max": cut.y, "hustota_skala": cut.z,
		"alfa_boost": 1.32 if is_lod1 else 1.0,
	}


func _bind(instance: MeshInstance3D, surface: int, profile: Dictionary) -> void:
	var label := str(profile.label)
	var role := str(profile.shader)
	if role == "vuz":
		_bind_vehicle(instance, surface, profile.attributes)
		return
	var original := instance.mesh.surface_get_material(surface) as BaseMaterial3D
	if role.is_empty():
		if (label.to_lower() == "head_shorthair" and str(profile.material_name).is_empty()
				and not _guide_head.is_empty() and instance.mesh.get_surface_count() == _guide_head.size()):
			var companion := _guide_head[surface]
			instance.set_surface_override_material(surface, companion)
			counts[companion.resource_name] = int(counts.get(companion.resource_name, 0)) + 1
			return
		if not str(profile.detail).is_empty():
			_note(label, profile.detail)
		if (label.to_lower() == "head_shorthair" or label.to_lower().begins_with("vlasy_lod3_opaque")
				or (_guide_catalog and label.to_lower().ends_with("_lod3_opaque"))):
			_neutral_placeholder(instance, surface, original)
		return
	var attrs: Dictionary = profile.attributes
	var missing := PackedStringArray()
	for key in ["NORMAL", "TEXCOORD_0", profile.color]:
		if not attrs.has(key):
			missing.append(key)
	var color_index: int = int(attrs.get(profile.color, -1))
	var accessors: Array = source.json.get("accessors", [])
	if color_index >= 0 and color_index < accessors.size():
		var component_type := str(accessors[color_index].get("type", ""))
		if component_type != "VEC3" and component_type != "VEC4":
			missing.append("%s (VEC3 / VEC4)" % profile.color)
		elif (role == "kuze" or role == "odev" or role == "vlasy_karty") and component_type != "VEC4":
			missing.append("%s (A)" % profile.color)
	if profile.has("blocked"):
		_note(label, "%s · sdílená síť používá odlišné barevné vstupy v jednotlivých instancích.", [role])
		return
	if not missing.is_empty():
		_note(label, "%s · chybí nebo nesouhlasí atributy %s.", [role, ", ".join(missing)])
		return
	if not role in ALIASES.values():
		_note(label, "Produkční shader %s není součástí balíčku.", [role])
		return
	var shader := _resource(SHADER_DIR + role + ".gdshader") as Shader
	if role == "vlasy_mikro_4k" and not _guide_shader_code.is_empty():
		if not _resources.has("guide_shader"):
			var project_shader := Shader.new()
			project_shader.code = _guide_shader_code
			_resources["guide_shader"] = project_shader
		shader = _resources["guide_shader"]
	if shader == null:
		_note(label, "Chybí produkční shader %s.", [role])
		return
	var material := ShaderMaterial.new()
	material.shader = shader
	material.resource_name = role
	var textures := {}
	match role:
		"kuze", "odev", "oko":
			textures["albedo_tex"] = original.albedo_texture if original else null
			if role != "oko":
				textures["normal_tex"] = original.normal_texture if original else null
			if role == "kuze":
				textures["pory_tex"] = _resource(TEXTURE_DIR + "kuze_pory_n.png")
			if role == "odev":
				var orm: Texture2D
				if original:
					orm = original.roughness_texture
					if orm == null:
						orm = original.metallic_texture if original.metallic_texture else original.ao_texture
				textures["orm_tex"] = orm
		"vlasy_karty":
			textures["atlas_tex"] = _file_texture(_texture_search.find("vlasy_atlas.png"))
			if textures["atlas_tex"] == null:
				textures["atlas_tex"] = _resource(TEXTURE_DIR + "vlasy_atlas.png")
		"vlasy_mikro_4k", "vousy_strniste_shell":
			var atlas := str(profile.atlas)
			if atlas == atlas.get_file():
				var pair := _texture_search.find_atlas(atlas)
				if pair.size() == 2:
					textures["atlas_tex"] = _file_texture(pair[0])
					textures["normal_tex"] = _file_texture(pair[1])
				else:
					textures["atlas_tex"] = _resource(TEXTURE_DIR + atlas + "_atlas.png")
					textures["normal_tex"] = _resource(TEXTURE_DIR + atlas + "_normal.png")
	var overrides: Variant = profile.textures
	if overrides is Dictionary:
		for uniform: String in overrides:
			if textures.has(uniform):
				textures[uniform] = _local_texture(str(overrides[uniform]))
	for uniform: String in textures:
		if textures[uniform] == null:
			missing.append(uniform)
		else:
			material.set_shader_parameter(uniform, textures[uniform])
	if not missing.is_empty():
		_note(label, "%s · chybí textury %s.", [role, ", ".join(missing)])
		return
	var parameters: Dictionary = profile.parameters
	if profile.tag == "vlasy_podklad":
		parameters.merge({"jas": 0.7, "drsnost_min": 0.85, "odlesk": 0.25, "kov_sila": 0.0})
	elif profile.tag == "rasy_karty":
		parameters.merge({
			"barva_koren": Color(0.08, 0.062, 0.048), "barva_konec": Color(0.17, 0.14, 0.115),
			"alfa_prah": 0.55, "vrstva_stin": 0.0, "drsnost": 0.5, "anizotropie": 0.3,
		})
	for parameter: String in parameters:
		var value: Variant = parameters[parameter]
		if value is Array and value.size() == 4:
			value = Color(float(value[0]), float(value[1]), float(value[2]), float(value[3]))
		if value is float or value is int or value is bool or value is Color:
			material.set_shader_parameter(parameter, value)
	instance.set_surface_override_material(surface, material)
	counts[role] = int(counts.get(role, 0)) + 1


func _bind_vehicle(instance: MeshInstance3D, surface: int, attrs: Dictionary) -> void:
	if not attrs.has("NORMAL") or not attrs.has("TEXCOORD_0"):
		_note(vehicle.object_id, "vuz · chybí nebo nesouhlasí atributy %s.", ["NORMAL / TEXCOORD_0"])
		return
	var preset := _resource(VEHICLE_DIR + vehicle.object_id + "_material.tres") as ShaderMaterial
	if preset == null or preset.shader == null:
		_note(vehicle.object_id, "Chybí produkční shader %s.", ["vuz"])
		return
	var material := preset.duplicate() as ShaderMaterial
	var missing := PackedStringArray()
	for key: String in ["albedo", "normal", "orm"]:
		var texture := _file_texture(vehicle.local_path(vehicle.textures.get(key)))
		if texture:
			material.set_shader_parameter(key + "_tex", texture)
		else:
			missing.append(str(vehicle.textures.get(key, key)))
	if not missing.is_empty():
		_note(vehicle.object_id, "vuz · chybí textury %s.", [", ".join(missing)])
		return
	if not vehicle.tiled or (not attrs.has("COLOR_0") or not attrs.has("TEXCOORD_1")):
		if vehicle.tiled:
			_note(vehicle.object_id, "Vůz používá atlas, protože chybí UV2 nebo COLOR_0 pro dlaždice.")
		material.set_shader_parameter("pouzit_dlazdice", false)
	instance.set_surface_override_material(surface, material)
	counts["vuz"] = int(counts.get("vuz", 0)) + 1


func _neutral_placeholder(instance: MeshInstance3D, surface: int, original: BaseMaterial3D) -> void:
	if original and original.albedo_texture:
		return
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#8b8582")
	material.roughness = 0.8
	instance.set_surface_override_material(surface, material)


func _note(label: String, message: String, arguments := []) -> void:
	var entry := [label, message, arguments]
	if not entry in _notes:
		_notes.append(entry)


func _resource(path: String) -> Resource:
	if not _resources.has(path):
		_resources[path] = ResourceLoader.load(path) if ResourceLoader.exists(path) else null
	return _resources[path]


func _local_texture(uri: String) -> Texture2D:
	return _file_texture(_local_texture_path(uri))


func _local_texture_path(uri: String) -> String:
	return _texture_search.find(uri)


func _file_texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if _resources.has(path):
		return _resources[path] as Texture2D
	var image: Image = _images[path] if _images.has(path) else _decode_texture(path)
	if not image:
		return null
	var texture := ImageTexture.create_from_image(image)
	_resources[path] = texture
	_record_texture_folder(path)
	return texture


func _record_texture_folder(path: String) -> void:
	var folder := path.get_base_dir()
	if not folder in texture_folders:
		texture_folders.append(folder)


static func _decode_texture(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	if image.load(path) != OK:
		return null
	if not image.has_mipmaps():
		image.generate_mipmaps()
	return image
