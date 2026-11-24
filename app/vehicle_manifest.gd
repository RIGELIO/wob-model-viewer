class_name ViewerVehicleManifest
extends RefCounted

const GlbData = preload("res://glb_data.gd")
const MAX_BYTES := 4 * 1024 * 1024

var path: String
var object_id: String
var states: Dictionary
var textures: Dictionary
var tiled: bool


static func read(file_path: String) -> ViewerVehicleManifest:
	var file := FileAccess.open(file_path, FileAccess.READ)
	if not file or file.get_length() > MAX_BYTES:
		return null
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		return null
	var data: Dictionary = parser.data
	var id := str(data.get("objekt", ""))
	var definitions: Variant = data.get("stavy")
	var atlas: Variant = data.get("textury")
	if not RegEx.create_from_string("^vuz_[a-z0-9_]+$").search(id) or not definitions is Dictionary or not atlas is Dictionary:
		return null
	var manifest := ViewerVehicleManifest.new()
	manifest.path = file_path
	manifest.object_id = id
	manifest.textures = atlas
	manifest.tiled = data.get("dlazdice") is Dictionary
	for state in definitions:
		var definition: Variant = definitions[state]
		if not definition is Dictionary or not definition.get("lod") is Array:
			continue
		var levels: Array[Dictionary] = []
		for item: Variant in definition.lod:
			if not item is Dictionary:
				continue
			var name: Variant = item.get("soubor")
			var level: Variant = item.get("lod")
			if not name is String or name.get_extension().to_lower() != "glb" or not GlbData.relative_file(name):
				continue
			if not (level is float or level is int) or not is_finite(level) or level < 0 or level > 999:
				continue
			levels.append({"path": manifest.local_path(name), "level": int(level)})
		levels.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.level < b.level)
		if not levels.is_empty():
			manifest.states[str(state)] = levels
	return manifest if not manifest.states.is_empty() else null


static func for_model(model: String) -> ViewerVehicleManifest:
	if not model.get_file().begins_with("vuz_"):
		return null
	var folder := model.get_base_dir()
	for name in DirAccess.get_files_at(folder):
		if name.ends_with("_manifest.json"):
			var manifest := read(folder.path_join(name))
			if manifest and not manifest.state_for(model).is_empty():
				return manifest
	return null


func state_for(model: String) -> String:
	var normalized := _normalized(model)
	for state in states:
		for entry: Dictionary in states[state]:
			if _normalized(entry.path) == normalized:
				return state
	return ""


func local_path(relative: Variant) -> String:
	if not relative is String or relative.is_empty() or not GlbData.relative_file(relative):
		return ""
	return path.get_base_dir().path_join(relative.uri_decode().replace("\\", "/")).simplify_path()


func _normalized(value: String) -> String:
	var normalized := value.replace("\\", "/").simplify_path()
	return normalized.to_lower() if OS.has_feature("windows") else normalized
