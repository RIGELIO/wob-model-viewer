extends Window

const USAGE := [
	"help", "clear", "open <path>", "reload", "info [model]",
	"frame [front|side|top]", "view <shaded|wireframe|points|quads>",
	"grid <on|off>", "floor <on|off>", "clips", "clip <name>",
	"play", "pause", "seek <seconds>", "speed <0–2>", "loop <on|off>",
	"cut <start> <end> | cut off", "screenshot <path.png>",
]
const VIEWS := {"shaded": 0, "wireframe": 1, "points": 5, "quads": 6}
const DIRECTIONS := {"front": Vector2.ZERO, "side": Vector2(PI / 2.0, 0.0), "top": Vector2(0.0, 1.555)}
const HISTORY_LIMIT := 80

var viewer: Control
var _output: TextEdit
var _command: LineEdit
var _history: PackedStringArray
var _lines: PackedStringArray
var _cursor := 0
var _draft := ""
var _running := false


func _ready() -> void:
	hide()
	size = Vector2i(740, 420)
	min_size = Vector2i(380, 240)
	close_requested.connect(hide)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)
	_output = TextEdit.new()
	_output.editable = false
	_output.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_output)
	var row := HBoxContainer.new()
	column.add_child(row)
	_command = LineEdit.new()
	_command.placeholder_text = "Napiš help a stiskni Enter"
	_command.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_command.max_length = 8192
	_command.text_submitted.connect(_submit)
	_command.gui_input.connect(_history_key)
	row.add_child(_command)
	var run := Button.new()
	run.text = "Spustit příkaz"
	run.pressed.connect(func(): _submit(_command.text))
	row.add_child(run)


func open() -> void:
	title = tr("Terminál prohlížeče")
	if _lines.is_empty():
		_append(tr("Příkazy Vieweru. Napiš help pro seznam."))
	if not visible:
		popup_centered()
	_command.grab_focus()


func _append(line: String) -> void:
	_lines.append(line)
	if _lines.size() > HISTORY_LIMIT:
		_lines.remove_at(0)
	_output.text = "\n\n".join(_lines)
	_output.set_caret_line(_output.get_line_count() - 1)


func _history_key(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.keycode not in [KEY_UP, KEY_DOWN]:
		return
	if _cursor == _history.size():
		_draft = _command.text
	_cursor = clampi(_cursor + (-1 if event.keycode == KEY_UP else 1), 0, _history.size())
	_command.text = _history[_cursor] if _cursor < _history.size() else _draft
	_command.caret_column = _command.text.length()
	_command.accept_event()


func _submit(line: String) -> void:
	line = line.strip_edges()
	if _running or line.is_empty():
		return
	_history.append(line)
	if _history.size() > HISTORY_LIMIT:
		_history.remove_at(0)
	_cursor = _history.size()
	_draft = ""
	_command.clear()
	if line == "clear":
		_lines.clear()
		_output.clear()
		_command.grab_focus()
		return
	_running = true
	_append("> " + line)
	_append(await execute(line))
	_running = false
	if visible:
		_command.grab_focus()


static func _tokens(line: String) -> PackedStringArray:
	var result := PackedStringArray()
	var current := ""
	var quote := ""
	for character in line:
		if character == quote:
			quote = ""
		elif not quote.is_empty():
			current += character
		elif character in ['"', "'"] and current.is_empty():
			quote = character
		elif character in [" ", "\t"]:
			if not current.is_empty():
				result.append(current)
				current = ""
		else:
			current += character
	if not quote.is_empty():
		return []
	if not current.is_empty():
		result.append(current)
	return result


func execute(line: String) -> String:
	var words := _tokens(line)
	if words.is_empty():
		return tr("Zkontroluj uvozovky v příkazu.")
	var action := words[0].to_lower()
	var args := words.slice(1)
	var count := args.size()
	var value := args[0] if count else ""
	if action == "help" and count == 0:
		return "\n".join(USAGE)
	var stage: Control = viewer.stage
	if viewer._loading or stage.capture_in_progress:
		return tr("Počkej na dokončení probíhající operace.")
	if action == "open" and count == 1:
		var path := _path(value)
		if path.is_empty() or not FileAccess.file_exists(path):
			return tr("Soubor nebyl nalezen.")
		if not path.get_extension().to_lower() in ["glb", "gltf", "fbx", "wobview", "json"]:
			return tr("Podporované vstupy jsou GLB, glTF, FBX, WOBVIEW a manifest vozu.")
		await viewer._open_path(path)
		return viewer._status.text
	if not stage.model:
		return tr("Nejdříve otevři model příkazem open \"cesta k souboru\".")
	match action:
		"info":
			if count == 0 or (count == 1 and value == "model"):
				var selection: Dictionary = viewer._outline.selection() if count == 0 else {}
				return viewer._info_report.report(viewer, selection.get("kind", "model"), selection.get("data"))
		"reload":
			if count == 0:
				await viewer._reload_model()
				return viewer._status.text
		"frame":
			if count == 0:
				stage.frame()
				return "OK"
			if count == 1 and DIRECTIONS.has(value):
				stage.frame(DIRECTIONS[value])
				return "OK"
		"view":
			if count == 1 and VIEWS.has(value):
				await viewer._choose_display(VIEWS[value])
				return "OK"
		"grid", "floor":
			if count == 1 and value in ["on", "off"]:
				viewer._options[action].button_pressed = value == "on"
				return "OK"
		"screenshot":
			if count == 1:
				var path := _path(value)
				if path.get_extension().to_lower() != "png":
					return tr("Zadej cestu k souboru .png.")
				await viewer._capture(path)
				return viewer._status.text
		"clips":
			if count == 0:
				var names := PackedStringArray()
				for clip: Dictionary in stage.clips:
					names.append(str(clip.name))
				return "\n".join(names) if not names.is_empty() else tr("Bez animací")
		"clip", "play", "pause", "seek", "speed", "loop", "cut":
			return _animation(action, args, stage.animation_player)
	return tr("Neplatný příkaz nebo argument. Příkaz help zobrazí dostupné použití.")


func _animation(action: String, args: PackedStringArray, player: AnimationPlayer) -> String:
	if not player:
		return tr("Bez animací")
	var count := args.size()
	var value := args[0] if count else ""
	match action:
		"clip":
			if count == 1:
				for index in viewer.stage.clips.size():
					if viewer.stage.clips[index].name == value:
						viewer._choose_clip(index)
						return "OK"
				return tr("Klip nebyl nalezen. Použij clips.")
		"play", "pause":
			if count == 0:
				if (action == "play") != player.is_playing():
					viewer._toggle_play()
				return "OK"
		"seek":
			if count == 1 and _in_range(value, 0.0, player.current_animation_length):
				viewer._timeline.value = float(value)
				return "OK"
		"speed":
			if count == 1 and _in_range(value, 0.0, 2.0):
				viewer._set_animation_speed(float(value))
				return "OK"
		"loop":
			if count == 1 and value in ["on", "off"]:
				viewer._loop.button_pressed = value == "on"
				return "OK"
		"cut":
			if count == 1 and value == "off":
				viewer._set_cut_enabled(false)
				return "OK"
			var duration := player.current_animation_length
			if count == 2 and _in_range(value, 0.0, duration) and _in_range(args[1], 0.0, duration) \
					and float(args[1]) - float(value) >= 0.001:
				viewer._apply_cut(Vector2(float(value), float(args[1])))
				return "OK"
	return tr("Neplatný argument animace. Zkontroluj délku klipu nebo příkaz help.")


static func _in_range(text: String, low: float, high: float) -> bool:
	return text.is_valid_float() and is_finite(float(text)) and float(text) >= low and float(text) <= high


func _path(value: String) -> String:
	var path := value.replace("\\", "/")
	if path.is_empty() or path.contains("://") or path.begins_with("//"):
		return ""
	if path.is_absolute_path():
		return path.simplify_path()
	var dir := DirAccess.open(".")
	return dir.get_current_dir().path_join(path).simplify_path() if dir else ""
