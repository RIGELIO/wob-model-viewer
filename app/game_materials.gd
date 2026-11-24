class_name ViewerGameMaterials
extends RefCounted

const GlbData = preload("res://glb_data.gd")
const BUNDLE := "_materialy-z-hry"
const MAX_METADATA := 4 * 1024 * 1024
const TEXTURES := ["albedo_texture", "normal_texture", "orm_texture", "ao_texture",
	"metallic_texture", "roughness_texture", "emission_texture"]
const VALUES := ["resource_name", "albedo_color", "ao_enabled", "ao_light_affect", "ao_texture_channel",
	"cull_mode", "emission", "emission_enabled", "emission_energy_multiplier", "metallic", "metallic_specular",
	"metallic_texture_channel", "normal_enabled", "normal_scale", "roughness", "roughness_texture_channel",
	"texture_filter", "texture_repeat", "transparency", "uv1_offset", "uv1_scale", "uv2_offset", "uv2_scale",
	"vertex_color_is_srgb", "vertex_color_use_as_albedo"]

var notes: Array[Array]
var _root: String
var _slots: Dictionary[String, String]
var _materials: Dictionary[String, BaseMaterial3D]
var _load_texture: Callable


static func find(model: String, load_texture: Callable) -> ViewerGameMaterials:
	var path := model.replace("\\", "/").simplify_path()
	if not path.is_absolute_path():
		var local := DirAccess.open("." if path.get_base_dir().is_empty() else path.get_base_dir())
		if not local:
			return null
		path = local.get_current_dir().path_join(path.get_file())
	var folder := path.get_base_dir()
	while not folder.is_empty():
		var directory := folder.path_join(BUNDLE)
		if DirAccess.dir_exists_absolute(directory):
			var bundle := ViewerGameMaterials.new()
			bundle._root = directory
			bundle._load_texture = load_texture
			var prefix := folder if folder.ends_with("/") else folder + "/"
			return bundle if bundle._read_catalog(directory.path_join("index.json"), path.trim_prefix(prefix)) else null
		var parent := folder.get_base_dir()
		if parent == folder:
			break
		folder = parent
	return null


func _read_catalog(index: String, relative_path: String) -> bool:
	var catalog: Variant = JSON.parse_string(_small_file(index))
	if not catalog is Dictionary or not catalog.get("modely") is Array:
		notes.append(["Balík herních materiálů má neplatný index.json."])
		return true
	for item: Variant in catalog.modely:
		if not item is Dictionary or not item.get("model") is String:
			continue
		var key: String = item.model
		if (key.to_lower() != relative_path.to_lower() if OS.has_feature("windows") else key != relative_path):
			continue
		var configurations: Variant = item.get("konfigurace")
		if configurations is Array:
			for source: Variant in configurations:
				if source is String and source.ends_with(".glb.import"):
					_read_import(source)
			for source: Variant in configurations:
				if source is String and source.begins_with("assets/prefaby/") and source.ends_with(".tscn"):
					_read_prefab(source)
		if _slots.is_empty():
			notes.append(["V balíku chybí přiřazení herních materiálů pro tento model."])
		return true
	return false


func _read_import(path: String) -> void:
	var text := _configuration(path)
	var entries := RegEx.create_from_string('(?m)^\\s*"([^"]+)"\\s*:\\s*\\{([^{}]*)\\}')
	for entry in entries.search_all(text):
		var block := entry.get_string(2)
		if not RegEx.create_from_string('"use_external/enabled"\\s*:\\s*true\\b').search(block):
			continue
		var link := RegEx.create_from_string('"use_external/path"\\s*:\\s*"res://([^"]+)"').search(block)
		if not link:
			link = RegEx.create_from_string('"use_external/fallback_path"\\s*:\\s*"res://([^"]+)"').search(block)
		if link:
			_slots[entry.get_string(1)] = link.get_string(1)


func _read_prefab(path: String) -> void:
	var text := _configuration(path)
	var names := RegEx.create_from_string('(?m)^MaterialSloty\\s*=\\s*PackedStringArray\\((.*)\\)\\s*$').search(text)
	if not names:
		return
	var refs := RegEx.create_from_string('(?m)^MaterialyNahrady\\s*=\\s*Array\\[Material\\]\\(\\[(.*)\\]\\)\\s*$').search(text)
	var slots: Variant = JSON.parse_string("[" + names.get_string(1) + "]")
	if not refs or not slots is Array:
		notes.append(["Neplatné přiřazení povrchů v herním prefabu %s.", [path.get_file()]])
		return
	var assignments := refs.get_string(1).split(",")
	if assignments.size() != slots.size():
		notes.append(["Neplatné přiřazení povrchů v herním prefabu %s.", [path.get_file()]])
		return
	var resources := _external_resources(text, ["Material", "StandardMaterial3D", "ORMMaterial3D"])
	var reference := RegEx.create_from_string('^ExtResource\\("([^"]+)"\\)$')
	for index in range(slots.size()):
		var match_id := reference.search(assignments[index].strip_edges())
		if slots[index] is String and match_id:
			var target: String = resources.get(match_id.get_string(1), "")
			if not target.is_empty():
				_slots[slots[index]] = target


func has_slot(slot: String) -> bool:
	return _slots.has(slot)


func material(slot: String) -> BaseMaterial3D:
	var path: String = _slots.get(slot, "")
	if not _materials.has(path):
		_materials[path] = _read_material(path)
	return _materials[path]


func _read_material(path: String) -> BaseMaterial3D:
	var text := _configuration(path)
	if text.is_empty():
		return null
	var header := text.get_slice("\n", 0)
	var type := _field(header, "type")
	var material: BaseMaterial3D
	match type:
		"ORMMaterial3D": material = ORMMaterial3D.new()
		"StandardMaterial3D": material = StandardMaterial3D.new()
		_:
			notes.append(["Nepodporovaný typ herního materiálu v %s.", [path.get_file()]])
			return null
	var texture_paths := _external_resources(text, ["Texture2D"])
	var properties := text.find("[resource]")
	if properties < 0:
		notes.append(["Herní materiál %s nemá část [resource].", [path.get_file()]])
		return null
	var reference := RegEx.create_from_string('^ExtResource\\("([^"]+)"\\)$')
	for line in text.substr(properties + "[resource]".length()).split("\n", false):
		var entry := line.strip_edges()
		if entry.is_empty() or entry.begins_with(";"):
			continue
		var pair := entry.split("=", true, 1)
		var key := pair[0].strip_edges()
		var value := pair[1].strip_edges() if pair.size() == 2 else ""
		if key in TEXTURES:
			var match_id := reference.search(value)
			var uri: String = texture_paths.get(match_id.get_string(1), "") if match_id else ""
			var full := _asset_path(uri, ["png", "jpg", "jpeg", "webp", "tga", "dds", "exr", "hdr"])
			var texture: Texture2D = _load_texture.call(full) if not full.is_empty() else null
			if not texture:
				notes.append(["Herní materiál %s · chybí textura %s.", [path.get_file(), uri if not uri.is_empty() else key]])
				return null
			if key in material:
				material.set(key, texture)
				continue
		elif key in VALUES and key in material:
			var parsed: Variant = _parse_value(value, typeof(material.get(key)))
			if parsed != null:
				material.set(key, parsed)
				continue
		notes.append(["Herní materiál %s · nepodporovaná vlastnost %s.", [path.get_file(), key]])
		return null
	return material


static func _parse_value(text: String, type: int) -> Variant:
	var constructor: String = {TYPE_COLOR: "Color", TYPE_VECTOR3: "Vector3"}.get(type, "")
	if not constructor.is_empty():
		if not text.begins_with(constructor + "(") or not text.ends_with(")"):
			return null
		var values: Variant = JSON.parse_string("[" + text.substr(constructor.length() + 1).trim_suffix(")") + "]")
		if not values is Array or values.size() != (4 if type == TYPE_COLOR else 3):
			return null
		for value: Variant in values:
			if not (value is float or value is int) or not is_finite(float(value)):
				return null
		return Color(values[0], values[1], values[2], values[3]) if type == TYPE_COLOR else Vector3(values[0], values[1], values[2])
	var value: Variant = JSON.parse_string(text)
	if typeof(value) == type:
		return value
	if type == TYPE_FLOAT and value is int:
		return float(value)
	if type == TYPE_INT and value is float and is_finite(value) and value == floor(value):
		return int(value)
	return null


func _configuration(uri: String) -> String:
	var path := _asset_path(uri, ["tscn", "import", "tres"])
	var text := _small_file(path)
	if text.is_empty():
		notes.append(["Chybí nebo nelze přečíst herní soubor %s.", [uri]])
	return text


func _asset_path(uri: String, extensions: Array) -> String:
	if not uri.begins_with("assets/") or not GlbData.relative_file(uri) or uri.contains("%"):
		return ""
	if not uri.get_extension().to_lower() in extensions:
		return ""
	return _root.path_join(uri)


static func _small_file(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ) if not path.is_empty() else null
	return file.get_as_text() if file and file.get_length() <= MAX_METADATA else ""


static func _external_resources(text: String, types: Array) -> Dictionary:
	var resources := {}
	for line in text.split("\n"):
		if not line.begins_with("[ext_resource ") or not _field(line, "type") in types:
			continue
		var path := _field(line, "path")
		if path.begins_with("res://"):
			resources[_field(line, "id")] = path.trim_prefix("res://")
	return resources


static func _field(line: String, key: String) -> String:
	var field := RegEx.create_from_string('\\b' + key + '="([^"]+)"').search(line)
	return field.get_string(1) if field else ""
