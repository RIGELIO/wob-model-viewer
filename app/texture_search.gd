extends RefCounted

const GlbData = preload("res://glb_data.gd")
const TEXTURE_DIRS := ["textury_4k", "textury", "textures", "maps"]
const ANCESTOR_LEVELS := 2

var _model_directory: String
var _bases: PackedStringArray
var _directories: PackedStringArray
var _paths: Dictionary[String, String]
var _relative_paths: Dictionary[String, String]
var _pairs: Dictionary[String, PackedStringArray]


func _init(model_path: String, directory := "") -> void:
	var absolute := _absolute_path(model_path)
	_model_directory = absolute.get_base_dir() if not absolute.is_empty() else ""
	set_directory(directory)


func set_directory(path: String) -> void:
	_bases.clear()
	_directories.clear()
	_paths.clear()
	_relative_paths.clear()
	_pairs.clear()
	_add_directory(_model_directory)
	_add_directory(_absolute_path(path), false)
	var directory := _model_directory
	for level in range(ANCESTOR_LEVELS):
		if directory.begins_with("//") and directory.split("/", false).size() <= 2:
			break
		var parent := directory.get_base_dir()
		if parent.is_empty() or parent == directory:
			break
		_add_directory(parent)
		directory = parent


func find(uri: String) -> String:
	return _find(uri, true)


func find_relative(uri: String) -> String:
	return _find(uri, false)


func _find(uri: String, basename_fallback: bool) -> String:
	if uri.is_empty():
		return ""
	var cache := _paths if basename_fallback else _relative_paths
	if cache.has(uri):
		return cache[uri]
	if not GlbData.relative_file(uri):
		cache[uri] = ""
		return ""
	var relative := GlbData.decode_file_uri(uri)
	var filename := relative.get_file()
	if filename.is_empty() or filename == ".":
		return ""
	var resolved := _first_file(_bases, relative)
	if resolved.is_empty() and basename_fallback:
		resolved = _first_file(_directories, filename)
	cache[uri] = resolved
	return resolved


func find_atlas(stem: String) -> PackedStringArray:
	if stem.is_empty() or stem == "." or stem != stem.get_file() or "\\" in stem or not GlbData.relative_file(stem):
		return PackedStringArray()
	if not _pairs.has(stem):
		var pair := PackedStringArray()
		for directory in _directories:
			var atlas := _existing_file(directory, stem + "_atlas.png")
			if atlas.is_empty():
				continue
			var normal := _existing_file(directory, stem + "_normal.png")
			if not normal.is_empty():
				pair = PackedStringArray([atlas, normal])
				break
		_pairs[stem] = pair
	return _pairs[stem].duplicate()


func _add_directory(directory: String, include_texture_dirs := true) -> void:
	if directory.is_empty():
		return
	if not directory in _bases:
		_bases.append(directory)
	if not directory in _directories:
		_directories.append(directory)
	if include_texture_dirs:
		for name in TEXTURE_DIRS:
			var child := directory.path_join(name)
			if not child in _directories:
				_directories.append(child)


static func _first_file(directories: PackedStringArray, filename: String) -> String:
	for directory in directories:
		var path := _existing_file(directory, filename)
		if not path.is_empty():
			return path
	return ""


static func _absolute_path(path: String) -> String:
	var absolute := ProjectSettings.globalize_path(path).replace("\\", "/")
	return absolute.simplify_path() if absolute.is_absolute_path() else ""


static func _existing_file(directory: String, filename: String) -> String:
	var path := directory.path_join(filename).simplify_path()
	return path if FileAccess.file_exists(path) else ""
