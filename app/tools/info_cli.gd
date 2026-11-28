extends RefCounted

const INPUT := "--export-info"
const OUTPUT := "--output-dir"
const FORMAT := "--format"
const OVERWRITE := "--overwrite"
const RESULT_PREFIX := "WOB_VIEWER_INFO_RESULT "
const USAGE := "--headless -- --export-info=<model or folder> --output-dir=<folder> [--format=json|csv] [--overwrite]"


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
	var output := _absolute_path(options[OUTPUT])
	var format: String = options.get(FORMAT, "json")
	if input.is_empty() or output.is_empty() or not format in ["json", "csv"]:
		return _invalid("Provide filesystem paths and format json or csv.")
	var paths := _models(input, viewer._model_extensions())
	if paths.is_empty():
		return _invalid("No GLB, glTF or FBX input files were found.")
	var error := DirAccess.make_dir_recursive_absolute(output)
	if error != OK and not DirAccess.dir_exists_absolute(output):
		return _finish(2, {"code": "output_unavailable", "output_dir": output, "message": error_string(error)})
	var results: Array[Dictionary] = []
	var succeeded := 0
	var overwrite := options.has(OVERWRITE)
	for source in paths:
		var target := output.path_join(source.get_file() + "." + format)
		var item := {"source": source, "output": target}
		if not overwrite and (FileAccess.file_exists(target) or DirAccess.dir_exists_absolute(target)):
			item["code"] = "output_exists"
		elif not await viewer._load_model(source, false, null, "", true):
			item["code"] = "load_failed"
			item["message"] = viewer._status.text
		else:
			error = viewer._info_report.write(viewer, {}, target, overwrite)
			item["code"] = "ok" if error == OK else "write_failed"
			if error == OK:
				succeeded += 1
			else:
				item["message"] = error_string(error)
		results.append(item)
	var failed := results.size() - succeeded
	return _finish(int(failed > 0), {
		"input": input, "output_dir": output, "format": format,
		"exported": succeeded, "failed": failed, "results": results,
	})


static func _options(args: PackedStringArray) -> Dictionary:
	var options := {}
	for argument in args:
		var flag := argument.get_slice("=", 0)
		if flag == "--language" or argument == "--debug-load":
			continue
		if options.has(flag):
			return {}
		if argument == OVERWRITE:
			options[flag] = true
		elif flag in [INPUT, OUTPUT, FORMAT] and argument.length() > flag.length() + 1:
			options[flag] = argument.substr(flag.length() + 1)
		else:
			return {}
	return options if options.has(INPUT) and options.has(OUTPUT) else {}


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


static func _models(input: String, extensions: PackedStringArray) -> PackedStringArray:
	var directory := DirAccess.open(input)
	if not directory:
		return PackedStringArray([input]) if input.get_extension().to_lower() in extensions \
			and FileAccess.file_exists(input) else PackedStringArray()
	directory.include_hidden = true
	var result := PackedStringArray()
	for filename in directory.get_files():
		if filename.get_extension().to_lower() in extensions:
			result.append(input.path_join(filename))
	return result


static func _invalid(message: String) -> int:
	return _finish(2, {"code": "invalid_arguments", "message": message, "usage": USAGE})


static func _finish(status: int, payload: Dictionary) -> int:
	payload.merge({"schema_version": 1, "ok": status == 0, "exit_code": status})
	print(RESULT_PREFIX + JSON.stringify(payload, "", true, true))
	return status
