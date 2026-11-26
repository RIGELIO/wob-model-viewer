# Copyright 2026 RIGELIO Studio. SPDX-License-Identifier: MIT
extends RefCounted

const FORMAT := "wob-rig"
const VERSION := 3
const MAX_JOINTS := 128
const MAX_BYTES := 8388608

var joints: Array[Dictionary] = []
var weights: Dictionary[Vector3i, Dictionary]


static func fit(kind: int, bounds: AABB) -> RefCounted:
	var draft := new()
	# Normalized model coordinates use +Y up and -Z forward.
	var layout := []
	match kind:
		0:
			layout = [
				["Pelvis", -1, 0.5, 0.51, 0.5], ["Spine", 0, 0.5, 0.65, 0.5],
				["Chest", 1, 0.5, 0.76, 0.5], ["Neck", 2, 0.5, 0.85, 0.5],
				["Head", 3, 0.5, 0.91, 0.5], ["HeadTip", 4, 0.5, 0.99, 0.5],
				["Shoulder_L", 2, 0.31, 0.79, 0.5], ["Elbow_L", 6, 0.18, 0.66, 0.52],
				["Hand_L", 7, 0.05, 0.55, 0.5], ["Shoulder_R", 2, 0.69, 0.79, 0.5],
				["Elbow_R", 9, 0.82, 0.66, 0.52], ["Hand_R", 10, 0.95, 0.55, 0.5],
				["Hip_L", 0, 0.39, 0.49, 0.5], ["Knee_L", 12, 0.39, 0.28, 0.45],
				["Foot_L", 13, 0.39, 0.05, 0.5], ["Toe_L", 14, 0.39, 0.02, 0.28],
				["Hip_R", 0, 0.61, 0.49, 0.5], ["Knee_R", 16, 0.61, 0.28, 0.45],
				["Foot_R", 17, 0.61, 0.05, 0.5], ["Toe_R", 18, 0.61, 0.02, 0.28],
			]
		1:
			layout = [
				["Pelvis", -1, 0.5, 0.66, 0.72], ["Spine", 0, 0.5, 0.69, 0.54],
				["Chest", 1, 0.5, 0.67, 0.34], ["Neck", 2, 0.5, 0.81, 0.23],
				["Head", 3, 0.5, 0.89, 0.14], ["Nose", 4, 0.5, 0.86, 0.03],
				["Tail", 0, 0.5, 0.7, 0.88], ["TailTip", 6, 0.5, 0.81, 0.98],
				["FrontShoulder_L", 2, 0.22, 0.64, 0.35], ["FrontElbow_L", 8, 0.22, 0.31, 0.4],
				["FrontFoot_L", 9, 0.22, 0.05, 0.31], ["FrontShoulder_R", 2, 0.78, 0.64, 0.35],
				["FrontElbow_R", 11, 0.78, 0.31, 0.4], ["FrontFoot_R", 12, 0.78, 0.05, 0.31],
				["HindHip_L", 0, 0.22, 0.64, 0.73], ["HindKnee_L", 14, 0.22, 0.38, 0.62],
				["HindHock_L", 15, 0.22, 0.19, 0.8], ["HindFoot_L", 16, 0.22, 0.05, 0.69],
				["HindHip_R", 0, 0.78, 0.64, 0.73], ["HindKnee_R", 18, 0.78, 0.38, 0.62],
				["HindHock_R", 19, 0.78, 0.19, 0.8], ["HindFoot_R", 20, 0.78, 0.05, 0.69],
			]
	for joint: Array in layout:
		var relative := Vector3(joint[2], joint[3], joint[4])
		draft.joints.append({"name": joint[0], "parent": joint[1], "point": bounds.position + bounds.size * relative})
	return draft


func add_joint(parent: int, point: Vector3) -> int:
	if joints.size() >= MAX_JOINTS or parent < -1 or parent >= joints.size() or not point.is_finite():
		return -1
	var number := joints.size() + 1
	while joints.any(func(joint: Dictionary): return joint.name == "Joint_%d" % number):
		number += 1
	joints.append({"name": "Joint_%d" % number, "parent": parent, "point": point})
	return joints.size() - 1


func rename_joint(index: int, label: String) -> bool:
	label = label.strip_edges()
	if index < 0 or index >= joints.size() or not _valid_name(label):
		return false
	for other in range(joints.size()):
		if other != index and joints[other].name == label:
			return false
	joints[index].name = label
	return true


func save(path: String, model_name: String) -> Error:
	var data := []
	for joint in joints:
		var point: Vector3 = joint.point
		data.append({"name": joint.name, "parent": joint.parent, "position": [point.x, point.y, point.z]})
	var edits := []
	for index in weights:
		var row: Dictionary = weights[index]
		var point: Vector3 = row.point
		var edit := {"vertex": [index.x, index.y, index.z], "point": [point.x, point.y, point.z],
			"bones": Array(row.bones), "weights": Array(row.weights)}
		if row.has("identity"):
			edit["identity"] = row.identity
		edits.append(edit)
	var contents := JSON.stringify({"format": FORMAT, "version": VERSION, "model": model_name,
		"joints": data, "vertex_weights": edits}, "\t", true, true)
	if contents.to_utf8_buffer().size() > MAX_BYTES:
		return ERR_OUT_OF_MEMORY
	var temporary := path + ".tmp-" + str(Time.get_ticks_usec())
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if not file:
		return FileAccess.get_open_error()
	file.store_string(contents)
	file.flush()
	var result := file.get_error()
	file.close()
	if result == OK:
		result = DirAccess.rename_absolute(temporary, path)
	if result != OK:
		DirAccess.remove_absolute(temporary)
	return result


static func read(path: String, model_name: String) -> RefCounted:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file or file.get_length() > MAX_BYTES:
		return null
	var data: Variant = JSON.parse_string(file.get_as_text())
	if not data is Dictionary or data.get("format") != FORMAT or data.get("model") != model_name:
		return null
	var version: Variant = data.get("version")
	if version != 1 and version != 2 and version != VERSION:
		return null
	var values: Variant = data.get("joints")
	if not values is Array or values.is_empty() or values.size() > MAX_JOINTS:
		return null
	var draft := new()
	var names := {}
	for joint: Variant in values:
		if not joint is Dictionary:
			return null
		var label: Variant = joint.get("name")
		var parent: Variant = joint.get("parent")
		var point: Variant = joint.get("position")
		if not label is String or not _valid_name(label) or names.has(label):
			return null
		if not _number(parent) or parent < -1 or parent >= draft.joints.size() or parent != floorf(parent):
			return null
		if not point is Array or point.size() != 3 or not point.all(_number):
			return null
		var position := Vector3(point[0], point[1], point[2])
		if not position.is_finite():
			return null
		draft.joints.append({"name": label, "parent": int(parent), "point": position})
		names[label] = true
	var edits: Variant = data.get("vertex_weights", [])
	if not edits is Array:
		return null
	for edit: Variant in edits:
		if not edit is Dictionary or not _read_weight_row(draft, edit):
			return null
	return draft


static func _read_weight_row(draft: RefCounted, row: Dictionary) -> bool:
	var vertex: Variant = row.get("vertex")
	var point: Variant = row.get("point")
	var bones: Variant = row.get("bones")
	var amounts: Variant = row.get("weights")
	if not _valid_indices(vertex, 3, 2147483647) or not _valid_indices(bones, 4, draft.joints.size()):
		return false
	if not point is Array or point.size() != 3 or not point.all(_number):
		return false
	if not amounts is Array or amounts.size() != 4 or not amounts.all(_number):
		return false
	var position := Vector3(point[0], point[1], point[2])
	var key := Vector3i(vertex[0], vertex[1], vertex[2])
	if not position.is_finite() or draft.weights.has(key):
		return false
	var sum := 0.0
	var used := {}
	for index in range(amounts.size()):
		var amount: float = amounts[index]
		if amount < 0.0 or amount > 1.0:
			return false
		if amount > 0.0:
			if used.has(bones[index]):
				return false
			used[bones[index]] = true
		sum += amount
	if absf(sum - 1.0) > 0.001:
		return false
	var entry := {"point": position, "bones": PackedInt32Array(bones), "weights": PackedFloat32Array(amounts)}
	if row.has("identity"):
		var identity: Variant = row.identity
		if not identity is Dictionary:
			return false
		var piece: Variant = identity.get("piece", "")
		var surface: Variant = identity.get("surface", "")
		var layout: Variant = identity.get("layout", "")
		if not piece is String or piece.length() > 4096 or not surface is String or surface.length() > 512 \
				or not layout is String or layout.length() != 64 or not layout.is_valid_hex_number():
			return false
		entry["identity"] = {"piece": piece, "surface": surface, "layout": layout.to_lower()}
	draft.weights[key] = entry
	return true


static func _valid_indices(values: Variant, count: int, limit: int) -> bool:
	if not values is Array or values.size() != count:
		return false
	return values.all(func(value: Variant): return _number(value) and value >= 0 and value < limit and value == floorf(value))


static func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(value)


static func _valid_name(label: String) -> bool:
	return not label.is_empty() and label.length() <= 64 and label == label.strip_edges() \
		and ":" not in label and "/" not in label and "\r" not in label and "\n" not in label and "\t" not in label
