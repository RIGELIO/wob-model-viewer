# Copyright 2026 RIGELIO Studio. SPDX-License-Identifier: MIT
extends RefCounted

const MAX_JOB_BYTES := 1024 * 1024
const MAX_ANALYSIS_SAMPLES := 900
const MAX_GIF_FRAMES := 240
const RESULT_PREFIX := "WOB_VIEWER_JOB_RESULT "


static func run(app: Node, input_path: String) -> int:
	var path := _local_path(input_path, _working_directory())
	if path.is_empty() or path.get_extension().to_lower() != "json":
		return _finish(_error(2, "invalid_input", "Use a local JSON job file."))
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _finish(_error(2, "invalid_input", "Could not open the job file."))
	if file.get_length() > MAX_JOB_BYTES:
		return _finish(_error(2, "invalid_input", "The job file exceeds 1 MiB."))
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	file.close()
	if parse_error != OK or not parser.data is Dictionary:
		return _finish(_error(2, "invalid_input", "The job must be a UTF-8 JSON object."))
	var job: Dictionary = parser.data
	var base := path.get_base_dir()
	var result_path := ""
	if job.has("result"):
		result_path = _local_path(job["result"], base)
		if result_path.is_empty() or result_path.get_extension().to_lower() != "json" or _same_path(result_path, path):
			return _finish(_error(2, "invalid_result", "Use a local result JSON path different from the job file."))
	var response := await _execute(app, job, base)
	return _finish(response, result_path)


static func _execute(app: Node, job: Dictionary, base: String) -> Dictionary:
	var kind: Variant = job.get("type")
	var version: Variant = job.get("version")
	if not _whole(version) or version != 1 or not kind is String or not kind in ["analyze", "gif"]:
		return _error(2, "invalid_input", "Expected version 1 and job type analyze or gif.")
	var model_path := _local_path(job.get("model"), base)
	if model_path.is_empty() or not model_path.get_extension().to_lower() in ["glb", "gltf", "fbx"]:
		return _error(2, "invalid_model", "Use a local GLB, glTF or FBX model.")
	var clip: Variant = job.get("clip", "")
	if not clip is String:
		return _error(2, "invalid_clip", "The clip name must be a string.")
	var start: Variant = job.get("start", 0.0)
	var finish: Variant = job.get("finish")
	if not _number(start) or float(start) < 0.0 or (job.has("finish") and not _number(finish)):
		return _error(2, "invalid_range", "Start and finish must be finite clip times in seconds.")
	if finish != null and float(finish) <= float(start):
		return _error(2, "invalid_range", "Finish must be later than start.")
	var fps: Variant = job.get("fps", 30)
	var maximum_fps := 60 if kind == "analyze" else 30
	if not _whole(fps) or float(fps) < 5.0 or float(fps) > maximum_fps:
		return _error(2, "invalid_fps", "FPS must be an integer from 5 to %d." % maximum_fps)
	var gif_path := ""
	var resolution := Vector2i.ZERO
	if kind == "gif":
		gif_path = _local_path(job.get("output"), base)
		if gif_path.is_empty() or gif_path.get_extension().to_lower() != "gif":
			return _error(2, "invalid_output", "GIF jobs require a local .gif output path.")
		var width: Variant = job.get("width", 640)
		var height: Variant = job.get("height", 360)
		if (not _whole(width) or not _whole(height)
				or float(width) < 1.0 or float(width) > 1280.0
				or float(height) < 1.0 or float(height) > 720.0):
			return _error(2, "invalid_resolution", "GIF dimensions must be positive integers up to 1280 × 720.")
		resolution = Vector2i(int(width), int(height))

	if kind == "gif" and DisplayServer.get_name() == "headless":
		return _error(5, "display_required", "GIF jobs require a graphical display.")
	if not await app.open_job_model(model_path, clip):
		return _error(4, "clip_unavailable", "Could not open the model or select the clip.")
	var player: AnimationPlayer = app.viewer.stage.animation_player
	if player == null:
		return _error(4, "clip_unavailable", "The model has no animation clip to process.")
	var duration := player.current_animation_length
	var last := duration if finish == null else float(finish)
	if not is_finite(duration) or last > duration or float(start) >= last:
		return _error(2, "invalid_range", "Use a non-empty interval within the selected clip.")
	var sample_limit := MAX_ANALYSIS_SAMPLES if kind == "analyze" else MAX_GIF_FRAMES
	if (last - float(start)) * float(fps) > sample_limit - 1:
		return _error(2, "frame_limit", "The interval would exceed the %d sample or frame limit." % sample_limit)

	var response := {"ok": true, "exit_code": 0, "code": "ok", "type": kind}
	if kind == "analyze":
		var report: Dictionary = await app.run_analysis(float(start), last, int(fps))
		if report.is_empty() or report.has("error"):
			return _error(5, "analysis_failed", str(report.get("error", "The clip could not be analyzed.")))
		response["report"] = report
	else:
		if not await app.run_gif(gif_path, float(start), last, int(fps), resolution):
			return _error(5, "gif_failed", "The GIF could not be rendered or written.")
		response["output"] = gif_path
	return response


static func _working_directory() -> String:
	var directory := DirAccess.open(".")
	return directory.get_current_dir() if directory else ""


static func _local_path(value: Variant, base: String) -> String:
	if not value is String or value.is_empty():
		return ""
	var path: String = value.replace("\\", "/")
	for byte in path.to_utf8_buffer():
		if byte < 32:
			return ""
	if path.begins_with("//") or path.contains("://"):
		return ""
	var colon := path.find(":")
	if colon >= 0:
		if (OS.get_name() != "Windows" or colon != 1 or path.length() < 3
				or not path.substr(0, 1).to_upper() in "ABCDEFGHIJKLMNOPQRSTUVWXYZ" or path[2] != "/"
				or path.find(":", colon + 1) >= 0):
			return ""
	if not path.is_absolute_path():
		if base.is_empty():
			return ""
		path = base.replace("\\", "/").path_join(path)
	path = path.simplify_path()
	if OS.get_name() == "Windows":
		for part in path.split("/", false):
			var stem := part.get_slice(".", 0).strip_edges().to_upper()
			if stem in ["CON", "PRN", "AUX", "NUL"]:
				return ""
			if stem.length() == 4 and (stem.begins_with("COM") or stem.begins_with("LPT")) and stem[3] in "123456789":
				return ""
	return path


static func _same_path(a: String, b: String) -> bool:
	return a.nocasecmp_to(b) == 0 if OS.get_name() == "Windows" else a == b


static func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))


static func _whole(value: Variant) -> bool:
	return _number(value) and floorf(float(value)) == float(value)


static func _error(exit_code: int, code: String, message: String) -> Dictionary:
	return {"ok": false, "exit_code": exit_code, "code": code, "message": message}


static func _finish(response: Dictionary, path := "") -> int:
	response["schema"] = 1
	if not path.is_empty():
		var status := _write_result(path, response)
		if status != OK:
			var failure := _error(6, "result_unwritable", "Could not write result JSON: " + error_string(status))
			failure["schema"] = 1
			failure["job_result"] = response
			response = failure
	print(RESULT_PREFIX + JSON.stringify(response, "", true, true))
	return response["exit_code"]


static func _write_result(path: String, response: Dictionary) -> Error:
	var temporary := path + ".tmp-" + Crypto.new().generate_random_bytes(12).hex_encode()
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	var wrote := file.store_string(JSON.stringify(response, "\t", true, true) + "\n")
	file.flush()
	var status := file.get_error()
	file.close()
	if not wrote and status == OK:
		status = ERR_FILE_CANT_WRITE
	if status == OK:
		status = DirAccess.rename_absolute(temporary, path)
	if status != OK:
		DirAccess.remove_absolute(temporary)
	return status
