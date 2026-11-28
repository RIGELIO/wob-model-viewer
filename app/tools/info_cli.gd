extends RefCounted

const INPUT := "--export-info"
const OUTPUT := "--output-dir"
const FORMAT := "--format"
const OVERWRITE := "--overwrite"
const RECURSIVE := "--recursive"
const SUMMARY := "--summary-csv"
const RESULT_PREFIX := "WOB_VIEWER_INFO_RESULT "
const USAGE := "--headless -- --export-info=<model or folder> [--output-dir=<folder>] [--summary-csv=<file.csv>] [--recursive] [--format=json|csv] [--overwrite]"


static func requested(args: PackedStringArray) -> bool:
	for argument in args:
		if argument == INPUT or argument.begins_with(INPUT + "="):
			return true
	return false


static func run(viewer: Control, args: PackedStringArray) -> int:
	if DisplayServer.get_name() != "headless":
		return _invalid("Pass --headless before the argument separator.")
	var options := _options(args)
	if options.is_empty():
		return _invalid("Invalid, missing or repeated arguments.")
	var input := _absolute_path(options[INPUT])
	var output := _absolute_path(options[OUTPUT]) if options.has(OUTPUT) else ""
	var summary := _absolute_path(options[SUMMARY]) if options.has(SUMMARY) else ""
	var format: String = options.get(FORMAT, "json")
	if input.is_empty() or (options.has(OUTPUT) and output.is_empty()) or not format in ["json", "csv"]:
		return _invalid("Provide filesystem paths and format json or csv.")
	if options.has(SUMMARY) and summary.get_extension().to_lower() != "csv":
		return _invalid("The summary path must end with .csv.")
	var overwrite := options.has(OVERWRITE)
	if not summary.is_empty() and not overwrite and _exists(summary):
		return _finish(2, {"code": "output_exists", "summary_csv": summary})
	var paths: PackedStringArray
	var unreadable: PackedStringArray
	_models(input, viewer._model_extensions(), options.has(RECURSIVE), paths, unreadable)
	if paths.is_empty():
		return _invalid("No GLB, glTF or FBX input files were found.")
	var root := input if DirAccess.dir_exists_absolute(input) else input.get_base_dir()
	var targets := PackedStringArray()
	if not output.is_empty():
		for source in paths:
			var target := output.path_join(source.trim_prefix(root.trim_suffix("/") + "/") + "." + format)
			if not summary.is_empty() and _same_path(target, summary):
				return _invalid("Choose a summary path distinct from the individual reports.")
			targets.append(target)
	for folder in [output, summary.get_base_dir() if not summary.is_empty() else ""]:
		if folder.is_empty():
			continue
		var error := _ensure_folder(folder)
		if error != OK:
			return _finish(2, {"code": "output_unavailable", "directory": folder, "message": error_string(error)})
	var results: Array[Dictionary] = []
	var succeeded := 0
	for index in paths.size():
		var target := targets[index] if not targets.is_empty() else ""
		var item := await _process_model(viewer, paths[index], target, overwrite, not summary.is_empty())
		results.append(item)
		succeeded += int(item.code == "ok")
	var failed := results.size() - succeeded
	var payload := {
		"input": input, "output_dir": output, "format": format,
		"exported": succeeded, "failed": failed, "results": results,
	}
	if not unreadable.is_empty():
		payload["unreadable_directories"] = Array(unreadable)
	if not summary.is_empty():
		payload["summary_csv"] = summary
		var error: Error = viewer._info_report.write_inventory(summary, results, overwrite)
		if error != OK:
			payload["code"] = "summary_write_failed"
			payload["message"] = error_string(error)
			return _finish(2, payload)
	return _finish(int(failed > 0 or not unreadable.is_empty()), payload)


static func _process_model(viewer: Control, source: String, target: String, overwrite: bool, inventory: bool) -> Dictionary:
	var item := {"source": source, "code": "ok"}
	if not target.is_empty():
		item["output"] = target
	var skip := not target.is_empty() and not overwrite and _exists(target)
	if skip and not inventory:
		item["code"] = "output_exists"
		return item
	if not await viewer._load_model(source, false, null, "", true):
		item["code"] = "load_failed"
		item["message"] = viewer._status.text
		return item
	if inventory:
		item["triangles"] = viewer.stage.geometry.w
	if skip:
		item["code"] = "output_exists"
	elif not target.is_empty():
		var error := _ensure_folder(target.get_base_dir())
		if error == OK:
			error = viewer._info_report.write(viewer, {}, target, overwrite)
		if error != OK:
			item["code"] = "write_failed"
			item["message"] = error_string(error)
	return item


static func _options(args: PackedStringArray) -> Dictionary:
	var options := {}
	for argument in args:
		var flag := argument.get_slice("=", 0)
		if flag == "--language" or argument == "--debug-load":
			continue
		if options.has(flag):
			return {}
		if argument in [OVERWRITE, RECURSIVE]:
			options[flag] = true
		elif flag in [INPUT, OUTPUT, FORMAT, SUMMARY] and argument.length() > flag.length() + 1:
			options[flag] = argument.substr(flag.length() + 1)
		else:
			return {}
	return options if options.has(INPUT) and (options.has(OUTPUT) or options.has(SUMMARY)) else {}


static func _absolute_path(path: String) -> String:
	path = path.replace("\\", "/")
	if path.contains("://"):
		return ""
	if not path.is_absolute_path():
		var current := DirAccess.open(".")
		if not current:
			return ""
		path = current.get_current_dir().path_join(path)
	return path.simplify_path()


static func _models(input: String, extensions: PackedStringArray, recursive: bool,
		paths: PackedStringArray, unreadable: PackedStringArray) -> void:
	if FileAccess.file_exists(input):
		if input.get_extension().to_lower() in extensions:
			paths.append(input)
		return
	var pending := [input]
	while not pending.is_empty():
		var folder: String = pending.pop_back()
		var directory := DirAccess.open(folder)
		if not directory:
			unreadable.append(folder)
			continue
		directory.include_hidden = true
		for filename in directory.get_files():
			if filename.get_extension().to_lower() in extensions:
				paths.append(folder.path_join(filename))
		if recursive:
			for child in directory.get_directories():
				if not directory.is_link(child):
					pending.append(folder.path_join(child))
	paths.sort()


static func _ensure_folder(path: String) -> Error:
	if DirAccess.dir_exists_absolute(path):
		return OK
	var error := DirAccess.make_dir_recursive_absolute(path)
	return OK if error == ERR_ALREADY_EXISTS and DirAccess.dir_exists_absolute(path) else error


static func _exists(path: String) -> bool:
	return FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path)


static func _same_path(a: String, b: String) -> bool:
	return a.nocasecmp_to(b) == 0 if OS.get_name() == "Windows" else a == b


static func _invalid(message: String) -> int:
	return _finish(2, {"code": "invalid_arguments", "message": message, "usage": USAGE})


static func _finish(status: int, payload: Dictionary) -> int:
	payload.merge({"schema_version": 1, "ok": status == 0, "exit_code": status})
	print(RESULT_PREFIX + JSON.stringify(payload, "", true, true))
	return status
