extends RefCounted

const FORMAT := "wob-model-viewer"
const VERSION := 1


static func read(path: String, extensions := PackedStringArray(["glb", "gltf"])) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 1024 * 1024:
		return {}
	var data: Variant = JSON.parse_string(file.get_as_text())
	if not data is Dictionary or data.get("format") != FORMAT or data.get("version") != VERSION:
		return {}
	var model: Variant = data.get("model")
	if not model is String or not model.get_extension().to_lower() in extensions:
		return {}
	return data


static func write(path: String, state: Dictionary) -> Error:
	state["format"] = FORMAT
	state["version"] = VERSION
	var temporary := path + ".tmp-" + str(Time.get_ticks_usec())
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(state, "\t", true, true) + "\n")
	file.flush()
	var result := file.get_error()
	file.close()
	if result == OK:
		result = DirAccess.rename_absolute(temporary, path)
	if result != OK:
		DirAccess.remove_absolute(temporary)
	return result


static func pack_path(view_path: String, resource_path: String) -> String:
	var base := view_path.get_base_dir().replace("\\", "/") + "/"
	var resource := resource_path.replace("\\", "/")
	return resource.trim_prefix(base)


static func unpack_path(view_path: String, resource_path: String) -> String:
	if resource_path.is_empty() or resource_path.is_absolute_path():
		return resource_path
	return view_path.get_base_dir().path_join(resource_path).simplify_path()
