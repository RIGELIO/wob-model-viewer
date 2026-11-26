# Copyright 2026 RIGELIO Studio. SPDX-License-Identifier: MIT
extends "res://materials.gd"

var file_bytes := 0


func prepare_model(path: String, _manifest: RefCounted = null) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return tr("Soubor FBX nelze otevřít (%s).") % error_string(FileAccess.get_open_error())
	file_bytes = file.get_length()
	file.close()
	_document = FBXDocument.new()
	_state = FBXState.new()
	var result := _document.append_from_file(path, _state, IMPORT_FLAGS)
	if result != OK:
		return tr("Godot model FBX nenačetl (%s).") % error_string(result)
	return ""


func finish_model() -> String:
	root = _document.generate_scene(_state)
	_document = null
	_state = null
	if root == null:
		return tr("Z FBX se nepodařilo vytvořit scénu.")
	_collect_meshes(root)
	if meshes.is_empty():
		root.free()
		root = null
		return tr("Soubor neobsahuje zobrazitelnou síť.")
	return ""


func _collect_meshes(node: Node) -> void:
	if node is MeshInstance3D and node.mesh:
		meshes.append(node)
	for child in node.get_children():
		_collect_meshes(child)


func color_layers() -> PackedStringArray:
	for instance in meshes:
		for surface in range(instance.mesh.get_surface_count()):
			if has_color_alpha(instance, surface, "COLOR_0"):
				return PackedStringArray(["COLOR_0"])
	return PackedStringArray()


func has_color_alpha(instance: MeshInstance3D, surface: int, layer: String) -> bool:
	return layer == "COLOR_0" and instance.mesh is ArrayMesh \
		and (instance.mesh.surface_get_format(surface) & Mesh.ARRAY_FORMAT_COLOR) != 0


func inspection_meshes(color_layer: String) -> Dictionary[MeshInstance3D, ArrayMesh]:
	var result: Dictionary[MeshInstance3D, ArrayMesh]
	if color_layer == "COLOR_0":
		for instance in meshes:
			if instance.mesh is ArrayMesh:
				result[instance] = instance.mesh
	return result
