# Copyright 2026 RIGELIO Studio. SPDX-License-Identifier: MIT
extends Node

const MotionEditor = preload("res://tools/motion_editor.gd")
const MotionReview = preload("res://tools/motion_review.gd")
const Jobs = preload("res://tools/agent_jobs.gd")
const InfoCli = preload("res://tools/info_cli.gd")
const RigEditor = preload("res://tools/rig_editor.gd")
const RigGlbExport = preload("res://tools/rig_glb_export.gd")
enum Action { EDIT, RANGE, ANALYZE, FINDINGS, GIF, REPORT, RIG }

var viewer: Control
var _menu: MenuButton
var _editor: MotionEditor
var _rig_editor: RigEditor
var _rig_tools: HFlowContainer
var _rig_selection: Label
var _rig_file: FileDialog
var _rig_preview_button: Button
var _rig_pose_controls: HBoxContainer
var _rig_motion_options: OptionButton
var _rig_motion_play: Button
var _rig_motion_slider: HSlider
var _rig_motion_speed: SpinBox
var _rig_motion_time: Label
var _rig_motion_step: HBoxContainer
var _rig_weight_toggle: CheckButton
var _rig_weight_controls: HBoxContainer
var _rig_weight_bone: OptionButton
var _rig_weight_value: SpinBox
var _rig_weight_apply: Button
var _rig_export_file: FileDialog
var _rig_export_motion := false
var _rig: Skeleton3D
var _model: RefCounted
var _findings_summary: Label
var _clip_player: AnimationPlayer
var _clip := &""
var _busy := false
var _toolbar: HFlowContainer
var _motion_group: VBoxContainer
var _rig_group: VBoxContainer
var _selection: Label
var _preview: CheckButton
var _range: AcceptDialog
var _start: SpinBox
var _finish: SpinBox
var _fps: SpinBox
var _resolution: OptionButton
var _findings: ConfirmationDialog
var _list: ItemList
var _report: Dictionary
var _save: FileDialog
var _save_kind := Action.GIF


func attach(target: Control) -> void:
	viewer = target
	_make_controls()
	_start_cli.call_deferred()


func _helper() -> String:
	var file := "wob-gif.exe" if OS.get_name() == "Windows" else "wob-gif"
	return OS.get_executable_path().get_base_dir().path_join(file)


func _start_cli() -> void:
	var args := OS.get_cmdline_user_args()
	if InfoCli.requested(args):
		get_tree().quit(await InfoCli.run(viewer, args))
		return
	for argument in args:
		if argument.begins_with("--viewer-job="):
			get_tree().quit(await Jobs.run(self, argument.trim_prefix("--viewer-job=")))
			return
	await viewer._process_arguments()


func open_job_model(model_path: String, clip: String) -> bool:
	if not await viewer._open_path(model_path):
		return false
	if not clip.is_empty() and not viewer._restore_clip(clip, 0.0):
		return false
	_sync_model()
	return viewer.stage.animation_player != null


func _make_controls() -> void:
	_menu = MenuButton.new()
	_menu.text = "Model"
	var header: Control = viewer._menu_help.get_parent()
	header.add_child(_menu)
	header.move_child(_menu, viewer._menu_window.get_index())
	_menu.about_to_popup.connect(_refresh_menu)
	_menu.get_popup().id_pressed.connect(_dispatch)

	var viewport_area: Control = viewer.stage.get_parent()
	_editor = MotionEditor.new()
	_editor.stage = viewer.stage
	_editor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport_area.add_child(_editor)
	_editor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_toolbar = HFlowContainer.new()
	_motion_group = viewer.add_inspector_tool_group("Editor pohybu", _toolbar)
	_button(_toolbar, "−1 snímek", func(): _editor.step(-1))
	_button(_toolbar, "+1 snímek", func(): _editor.step(1))
	var tools := OptionButton.new()
	for item in ["Výběr", "Tečka", "Čára", "Šipka", "Kruh"]:
		tools.add_item(tr(item))
	tools.item_selected.connect(func(index: int): _editor.tool = index)
	tools.tooltip_text = "Klik vybere kost, tažení vybere oblast, Ctrl+klik přidá nebo odebere kost."
	_toolbar.add_child(tools)
	_button(_toolbar, "Rotace snímku", _edit_pose)
	_button(_toolbar, "Přichytit končetinu", _pin_limb)
	_button(_toolbar, "Upravit cíl IK", _edit_pin_target)
	_button(_toolbar, "Uvolnit IK", _editor.clear_ik)
	_button(_toolbar, "Smazat značku", _editor.remove_mark)
	_preview = CheckButton.new()
	_preview.text = "Náhled úprav"
	_preview.button_pressed = true
	_preview.toggled.connect(func(enabled: bool): _editor.set_preview_enabled(enabled))
	_toolbar.add_child(_preview)
	_selection = Label.new()
	_toolbar.add_child(_selection)
	_motion_group.hide()

	_range = _dialog("Rozsah animace")
	var ranges := VBoxContainer.new()
	_range.add_child(ranges)
	_start = _spin(ranges, "Od (s)", 0.0, 120.0, 0.001, 0.0)
	_finish = _spin(ranges, "Do (s)", 0.0, 120.0, 0.001, 0.0)
	_fps = _spin(ranges, "FPS", 5.0, 60.0, 1.0, 24.0)
	_editor.fps = int(_fps.value)
	_fps.value_changed.connect(func(fps: float): _editor.fps = int(fps))
	var duration := _spin(ranges, "Značka (s)", 0.05, 30.0, 0.05, 1.0)
	duration.value_changed.connect(func(seconds: float): _editor.mark_seconds = seconds)
	_resolution = OptionButton.new()
	for item in ["640 × 360", "960 × 540", "1280 × 720"]:
		_resolution.add_item(item)
	_resolution.select(1)
	ranges.add_child(_resolution)

	_findings = ConfirmationDialog.new()
	_findings.title = tr("Rozbor pohybu")
	_findings.ok_button_text = tr("Náhled korekce")
	_findings.cancel_button_text = tr("Zavřít")
	_findings.dialog_hide_on_ok = false
	_findings.confirmed.connect(_preview_selected)
	_findings.add_button(tr("Zobrazit nález"), true, "locate")
	_findings.custom_action.connect(func(action: StringName):
		if action == &"locate" and not _list.get_selected_items().is_empty():
			_findings.hide()
	)
	add_child(_findings)
	var results := VBoxContainer.new()
	_findings.add_child(results)
	_findings_summary = Label.new()
	results.add_child(_findings_summary)
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(630, 285)
	_list.item_selected.connect(_show_finding)
	_list.item_activated.connect(func(_index: int): _findings.hide())
	results.add_child(_list)

	_save = FileDialog.new()
	_save.use_native_dialog = true
	_save.access = FileDialog.ACCESS_FILESYSTEM
	_save.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_save.file_selected.connect(_save_file)
	add_child(_save)
	_make_rig_controls(viewport_area)


func _refresh_menu() -> void:
	_sync_model()
	var list := _menu.get_popup()
	var player: AnimationPlayer = viewer.stage.animation_player
	var busy: bool = _busy or viewer._loading
	list.clear()
	list.add_item(tr("Editor pohybu"), Action.EDIT)
	list.add_item(tr("Rozsah animace"), Action.RANGE)
	list.add_item(tr("Analyzovat pohyb"), Action.ANALYZE)
	list.add_item(tr("Nálezy na časové ose"), Action.FINDINGS)
	if FileAccess.file_exists(_helper()):
		list.add_item(tr("Export animace GIF"), Action.GIF)
	list.add_item(tr("Export reportu a úprav"), Action.REPORT)
	list.add_separator()
	list.add_item(tr("Navrhnout novou kostru"), Action.RIG)
	for id in [Action.EDIT, Action.RANGE, Action.ANALYZE, Action.FINDINGS, Action.GIF, Action.REPORT]:
		var index := list.get_item_index(id)
		if index >= 0:
			list.set_item_disabled(index, busy or player == null)
	list.set_item_disabled(list.get_item_index(Action.RIG), busy or not viewer.stage.model)


func _dispatch(id: int) -> void:
	match id:
		Action.EDIT: _toggle_editor()
		Action.RANGE: _range.popup_centered()
		Action.ANALYZE:
			var output := await run_analysis(_start.value, _selected_finish(), int(_fps.value))
			if output.has("error"):
				_show_message("Rozbor pohybu", output.error)
			else:
				_show_findings()
		Action.FINDINGS: _show_findings()
		Action.GIF: _choose_save(Action.GIF, "*.gif", "gif")
		Action.REPORT: _choose_save(Action.REPORT, "*.json", "json")
		Action.RIG:
			if viewer.stage._skeletons.is_empty():
				_set_rig_mode(not _rig_editor.visible)
			else:
				_show_message("Navrhnout novou kostru", tr("Model už má kostru. Pro výběr a úpravy jeho kostí použij Editor pohybu."))


func _sync_model() -> void:
	if _model != viewer.stage.model:
		_model = viewer.stage.model
		_set_rig_mode(false)
		_motion_group.hide()
		_editor.set_editing(false)
		_clip_player = null
		_rig_editor.set_model(viewer._path if _model else "")
		_report = {}
		_clip = &""
	var player: AnimationPlayer = viewer.stage.animation_player
	if _clip != viewer.stage.current_clip or _clip_player != player:
		_clip = viewer.stage.current_clip
		_clip_player = player
		_rig = _find_active_skeleton(player)
		_editor.update_model(_rig)
		_report = {}
		if player:
			var rounded_end := ceilf(player.current_animation_length * 1000.0) / 1000.0
			_start.max_value = rounded_end
			_finish.max_value = rounded_end
			_start.value = 0.0
			_finish.value = rounded_end
		_editor.finding = {}
		_editor.clear_selection()


func _find_active_skeleton(player: AnimationPlayer) -> Skeleton3D:
	if not player or not player.has_animation(_clip):
		return null
	var root := player.get_node_or_null(player.root_node)
	if not root:
		return null
	var clip := player.get_animation(_clip)
	var scores: Dictionary[Skeleton3D, int]
	for track in range(clip.get_track_count()):
		if not clip.track_is_enabled(track):
			continue
		var path := clip.track_get_path(track)
		if path.get_subname_count() != 1:
			continue
		var skeleton := root.get_node_or_null(NodePath(path.get_concatenated_names())) as Skeleton3D
		if skeleton and skeleton.find_bone(path.get_subname(0)) >= 0:
			scores[skeleton] = scores.get(skeleton, 0) + 1
	var best: Skeleton3D
	for skeleton in scores:
		if not best or scores[skeleton] > scores[best]:
			best = skeleton
	return best


func _selected_finish() -> float:
	var player: AnimationPlayer = viewer.stage.animation_player
	return minf(_finish.value, player.current_animation_length) if player else 0.0


func _process(_delta: float) -> void:
	_sync_model()
	if _rig_motion_slider.visible and _rig_editor.motion_playing:
		_update_rig_motion_time()
	if _motion_group.visible:
		if _editor.selected.size() == 1 and _rig:
			_selection.text = _rig.get_bone_name(_editor.selected[0])
		else:
			_selection.text = str(_editor.selected.size())


func _toggle_editor() -> void:
	if not _rig:
		_show_message("Editor pohybu", tr("Tato animace neobsahuje kostru, jejíž klouby lze upravit."))
		return
	_set_rig_mode(false)
	_motion_group.visible = not _motion_group.visible
	_editor.set_editing(_motion_group.visible)
	if _motion_group.visible:
		viewer.focus_inspector(_motion_group)


func _make_rig_controls(viewport_area: Control) -> void:
	_rig_editor = RigEditor.new()
	_rig_editor.stage = viewer.stage
	_rig_editor.hide()
	viewport_area.add_child(_rig_editor)
	_rig_editor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_rig_tools = HFlowContainer.new()
	_rig_group = viewer.add_inspector_tool_group("Návrh kostry", _rig_tools)
	var templates := MenuButton.new()
	templates.text = "Šablona kostry"
	templates.get_popup().about_to_popup.connect(func():
		var list := templates.get_popup()
		list.clear()
		list.add_item(tr("Člověk"), 0)
		list.add_item(tr("Čtyřnožec"), 1)
		list.add_item(tr("Prázdná kostra"), 2)
	)
	templates.get_popup().id_pressed.connect(_choose_rig_template)
	_rig_tools.add_child(templates)
	_button(_rig_tools, "Přidat kloub", _rig_editor.toggle_placement)
	var draft_menu := MenuButton.new()
	draft_menu.text = "Návrh kostry"
	draft_menu.about_to_popup.connect(func():
		var list := draft_menu.get_popup()
		list.clear()
		list.add_item(tr("Otevřít návrh kostry"), 0)
		list.add_item(tr("Uložit návrh kostry"), 1)
		list.add_item(tr("Přejmenovat kloub"), 2)
		list.add_item(tr("Exportovat nové GLB s kostrou"), 3)
		list.set_item_disabled(1, not _rig_editor.has_joints())
		list.set_item_disabled(2, _rig_editor.selected < 0)
		list.set_item_disabled(3, not _rig_editor.has_skin_preview())
		if _rig_editor.has_motion_profile():
			list.add_item(tr("Exportovat nové GLB s kostrou a pohyby"), 5)
		if _rig_editor.unmatched_weight_count() > 0:
			list.add_item(tr("Odstranit nepřiřazené váhy"), 4)
	)
	draft_menu.get_popup().id_pressed.connect(func(id: int):
		match id:
			2: _rename_rig_joint()
			3: _choose_rig_glb()
			4: _discard_unmatched_rig_weights()
			5: _choose_rig_glb(true)
			_: _choose_rig_file(id == 1)
	)
	_rig_tools.add_child(draft_menu)
	_rig_preview_button = Button.new()
	_rig_preview_button.text = "Zkušební póza"
	_rig_preview_button.pressed.connect(_toggle_rig_preview)
	_rig_tools.add_child(_rig_preview_button)
	_make_rig_motion_controls()
	_rig_pose_controls = HBoxContainer.new()
	_rig_pose_controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rig_pose_controls.hide()
	_rig_tools.add_child(_rig_pose_controls)
	var axis := OptionButton.new()
	axis.tooltip_text = "Osa zkušební rotace"
	for label in ["X", "Y", "Z"]:
		axis.add_item(label)
	axis.item_selected.connect(_rig_editor.set_pose_axis)
	_rig_pose_controls.add_child(axis)
	var angle := SpinBox.new()
	angle.min_value = -90.0
	angle.max_value = 90.0
	angle.step = 1.0
	angle.value = 30.0
	angle.suffix = "°"
	angle.tooltip_text = "Úhel zkušební rotace"
	angle.value_changed.connect(_rig_editor.set_pose_degrees)
	_rig_pose_controls.add_child(angle)
	_button(_rig_pose_controls, "Výchozí póza", func(): angle.value = 0.0)
	_rig_editor.preview_changed.connect(_refresh_rig_preview)
	_make_weight_controls()
	_rig_selection = Label.new()
	_rig_selection.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rig_selection.custom_minimum_size.x = 200
	_rig_selection.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rig_tools.add_child(_rig_selection)
	_rig_editor.selection_changed.connect(_refresh_rig_selection)

	_rig_file = FileDialog.new()
	_rig_file.use_native_dialog = true
	_rig_file.access = FileDialog.ACCESS_FILESYSTEM
	_rig_file.filters = PackedStringArray(["*.wobrig"])
	_rig_file.file_selected.connect(_select_rig_file)
	add_child(_rig_file)

	_rig_export_file = FileDialog.new()
	_rig_export_file.use_native_dialog = true
	_rig_export_file.access = FileDialog.ACCESS_FILESYSTEM
	_rig_export_file.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_rig_export_file.filters = PackedStringArray(["*.glb"])
	_rig_export_file.file_selected.connect(_export_rig_glb)
	add_child(_rig_export_file)

func _make_rig_motion_controls() -> void:
	_rig_motion_options = OptionButton.new()
	_rig_motion_options.tooltip_text = "Náhled pohybu na vytvořené kostře"
	for label in ["Ruční póza", "Chůze na místě", "Běh / klus na místě"]:
		_rig_motion_options.add_item(label)
	_rig_motion_options.hide()
	_rig_motion_options.item_selected.connect(func(index: int):
		_rig_editor.set_motion(index)
		_refresh_rig_preview()
	)
	_rig_tools.add_child(_rig_motion_options)
	_rig_motion_play = Button.new()
	_rig_motion_play.hide()
	_rig_motion_play.pressed.connect(func():
		_rig_editor.toggle_motion_playback()
		_refresh_rig_preview()
	)
	_rig_tools.add_child(_rig_motion_play)
	_rig_motion_slider = HSlider.new()
	_rig_motion_slider.custom_minimum_size.x = 115.0
	_rig_motion_slider.max_value = 1.0
	_rig_motion_slider.step = 0.0
	_rig_motion_slider.tooltip_text = "Poloha ve smyčce pohybu"
	_rig_motion_slider.hide()
	_rig_motion_slider.value_changed.connect(_rig_editor.seek_motion)
	_rig_tools.add_child(_rig_motion_slider)
	_rig_motion_speed = viewer.make_animation_speed_control(_rig_editor.set_motion_speed)
	_rig_motion_speed.hide()
	_rig_tools.add_child(_rig_motion_speed)
	_rig_motion_time = Label.new()
	_rig_motion_time.custom_minimum_size.x = 96
	_rig_motion_time.hide()
	_rig_tools.add_child(_rig_motion_time)
	_rig_motion_step = HBoxContainer.new()
	_rig_motion_step.hide()
	_rig_tools.add_child(_rig_motion_step)
	_rig_step_button(_rig_motion_step, "◀₁", "Předchozí snímek (30 FPS)", _rig_editor.step_motion_frame.bind(-1))
	_rig_step_button(_rig_motion_step, "₁▶", "Následující snímek (30 FPS)", _rig_editor.step_motion_frame.bind(1))

	_rig_editor.timeline_changed.connect(_refresh_rig_motion_timeline)


func _rig_step_button(parent: HBoxContainer, text: String, hint: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.tooltip_text = hint
	button.pressed.connect(action)
	parent.add_child(button)


func _update_rig_motion_time() -> void:
	var length := _rig_editor.motion_length()
	_rig_motion_slider.set_value_no_signal(_rig_editor.motion_phase)
	_rig_motion_time.text = "%.3f / %.3f s" % [_rig_editor.motion_phase * length, length]


func _refresh_rig_motion_timeline() -> void:
	var active := _rig_editor.motion != RigEditor.Motion.TEST_POSE
	_rig_motion_play.visible = active
	_rig_motion_play.text = "Pozastavit pohyb" if _rig_editor.motion_playing else "Přehrát pohyb"
	_rig_motion_slider.visible = active
	_rig_motion_speed.visible = active
	_rig_motion_time.visible = active
	_rig_motion_step.visible = active
	if active:
		_update_rig_motion_time()


func _make_weight_controls() -> void:
	_rig_weight_toggle = CheckButton.new()
	_rig_weight_toggle.text = "Váhy vrcholu"
	_rig_weight_toggle.hide()
	_rig_weight_toggle.toggled.connect(_set_weight_mode)
	_rig_tools.add_child(_rig_weight_toggle)
	_rig_weight_controls = HBoxContainer.new()
	_rig_weight_controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rig_weight_controls.hide()
	_rig_tools.add_child(_rig_weight_controls)
	_rig_weight_bone = OptionButton.new()
	_rig_weight_bone.tooltip_text = "Kost pro ruční úpravu váhy"
	_rig_weight_bone.item_selected.connect(_rig_editor.choose_weight_bone)
	_rig_weight_controls.add_child(_rig_weight_bone)
	_rig_weight_value = SpinBox.new()
	_rig_weight_value.min_value = 0
	_rig_weight_value.max_value = 100
	_rig_weight_value.step = 0.1
	_rig_weight_value.suffix = "%"
	_rig_weight_controls.add_child(_rig_weight_value)
	_rig_weight_apply = Button.new()
	_rig_weight_apply.text = "Použít váhu"
	_rig_weight_apply.pressed.connect(func():
		if not _rig_editor.set_vertex_weight(_rig_weight_value.value / 100.0):
			viewer._feedback("Váhu tohoto vrcholu nelze změnit.", true)
	)
	_rig_weight_controls.add_child(_rig_weight_apply)
	_rig_editor.weight_selection_changed.connect(_refresh_weight_selection)


func _set_weight_mode(enabled: bool) -> void:
	_rig_editor.set_weight_mode(enabled)
	if _rig_editor.weight_mode:
		_rig_weight_bone.clear()
		for label in _rig_editor.weight_bones():
			_rig_weight_bone.add_item(label)
		_rig_weight_bone.select(_rig_editor.selected)
	_refresh_rig_preview()
	_refresh_weight_selection()


func _refresh_weight_selection() -> void:
	var has_vertex := _rig_editor.selected_vertex.x >= 0
	_rig_weight_value.editable = has_vertex
	_rig_weight_apply.disabled = not has_vertex or _rig_editor.selected_weight_conflicts()
	_rig_weight_value.value = _rig_editor.selected_weight() * 100.0
	_refresh_rig_selection()


func _set_rig_mode(enabled: bool) -> void:
	if enabled:
		_motion_group.hide()
		_editor.set_editing(false)
	else:
		_rig_editor.stop_skin_preview()
	_rig_editor.visible = enabled
	_rig_group.visible = enabled
	_refresh_rig_selection()
	if enabled:
		viewer.focus_inspector(_rig_group)


func _toggle_rig_preview() -> void:
	if _rig_editor.has_skin_preview():
		_rig_editor.stop_skin_preview()
		return
	if not _rig_editor.has_joints():
		viewer._feedback("Nejprve přidej klouby nebo zvol šablonu.", true)
		return
	if not _rig_editor.can_preview_skin():
		viewer._feedback("Zkušební póza vyžaduje statický model bez kostry, zobrazení Materiály a vypnutou izolaci.", true)
		return
	if not viewer._begin_loading(tr("Přiřazuji váhy vrcholům…")):
		return
	await viewer._paint_loading()
	var success := await _rig_editor.start_skin_preview(func(): return not viewer._quit_after_load)
	viewer._finish_loading()
	if not success and _rig_editor.visible:
		viewer._feedback("Pro tento model se nepodařilo připravit náhled vah.", true)
	elif success:
		var notes := PackedStringArray()
		var remapped := _rig_editor.remapped_weight_count()
		var unmatched := _rig_editor.unmatched_weight_count()
		if remapped > 0:
			notes.append(tr("Obnovené ruční váhy: %d.") % remapped)
		if unmatched > 0:
			notes.append(tr("Ruční váhy pro %d vrcholů se neshodují s touto sítí.") % unmatched)
		if not notes.is_empty():
			viewer._feedback(" ".join(notes), unmatched > 0)


func _discard_unmatched_rig_weights() -> void:
	if _rig_editor.unmatched_weight_count() == 0:
		return
	var preview = _rig_editor._preview
	var dialog := ConfirmationDialog.new()
	dialog.title = tr("Odstranit nepřiřazené váhy")
	dialog.dialog_text = tr("Odstranit nepřiřazené ruční váhy z rozpracovaného návrhu?")
	dialog.confirmed.connect(func():
		if _rig_editor._preview == preview:
			_rig_editor.discard_unmatched_weights()
			viewer._feedback("Nepřiřazené ruční váhy byly odstraněny.")
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()


func _refresh_rig_preview() -> void:
	var active := _rig_editor.has_skin_preview()
	_rig_weight_toggle.visible = active
	_rig_weight_toggle.set_pressed_no_signal(_rig_editor.weight_mode)
	_rig_weight_controls.visible = active and _rig_editor.weight_mode
	var evaluating_motion := _rig_editor.motion != RigEditor.Motion.TEST_POSE
	_rig_motion_options.visible = _rig_editor.has_motion_profile() and not _rig_editor.weight_mode
	_rig_motion_options.select(_rig_editor.motion)
	_refresh_rig_motion_timeline()
	_rig_pose_controls.visible = active and not _rig_editor.weight_mode and not evaluating_motion
	_rig_preview_button.text = "Ukončit zkušební pózu" if active else "Zkušební póza"


func _refresh_rig_selection() -> void:
	if _rig_editor.placing:
		_rig_selection.text = tr("Klikni do pohledu a umísti kloub.")
	elif _rig_editor.weight_mode and _rig_editor.selected_vertex.x < 0:
		_rig_selection.text = tr("Klikni na plochu a vyber nejbližší vrchol.")
	elif _rig_editor.selected_weight_conflicts():
		_rig_selection.text = tr("Vrchol má konflikt s uloženou váhou. Zkontroluj návrh kostry.")
	else:
		_rig_selection.text = _rig_editor.selection_label()


func _choose_rig_template(kind: int) -> void:
	_confirm_rig_replacement("Nahradit rozpracovanou kostru zvolenou šablonou?",
		_rig_editor.reset_template.bind(kind))


func _confirm_rig_replacement(message: String, replace: Callable) -> void:
	if not _rig_editor.has_joints():
		replace.call()
		return
	var dialog := ConfirmationDialog.new()
	dialog.dialog_text = tr(message)
	add_child(dialog)
	var model: RefCounted = viewer.stage.model
	dialog.confirmed.connect(func():
		if _rig_editor.visible and viewer.stage.model == model:
			replace.call()
	)
	dialog.visibility_changed.connect(func():
		if not dialog.visible:
			dialog.queue_free()
	)
	dialog.popup_centered()


func _rename_rig_joint() -> void:
	if _rig_editor.selected < 0:
		viewer._feedback("Nejprve vyber kloub.", true)
		return
	var dialog := _dialog("Přejmenovat kloub")
	var name_field := LineEdit.new()
	name_field.text = _rig_editor.selection_label()
	name_field.max_length = 64
	dialog.add_child(name_field)
	dialog.confirmed.connect(func():
		if not _rig_editor.rename_selected(name_field.text):
			viewer._feedback("Název kloubu je neplatný nebo už existuje.", true)
	)
	dialog.visibility_changed.connect(func():
		if not dialog.visible:
			dialog.queue_free()
	)
	dialog.popup_centered()
	name_field.grab_focus()
	name_field.select_all()


func _choose_rig_file(saving: bool) -> void:
	if saving and not _rig_editor.has_joints():
		viewer._feedback("Nejprve přidej klouby nebo zvol šablonu.", true)
		return
	_rig_file.file_mode = FileDialog.FILE_MODE_SAVE_FILE if saving else FileDialog.FILE_MODE_OPEN_FILE
	_rig_file.current_dir = viewer._path.get_base_dir()
	_rig_file.current_file = viewer._path.get_file().get_basename() + ".wobrig"
	_rig_file.popup_centered_ratio(0.6)


func _select_rig_file(path: String) -> void:
	if not _rig_editor.visible or not viewer.stage.model:
		return
	if _rig_file.file_mode == FileDialog.FILE_MODE_SAVE_FILE:
		var target := path if path.get_extension().to_lower() == "wobrig" else path + ".wobrig"
		if _rig_editor.save(target) == OK:
			viewer._feedback(tr("Uloženo · %s") % target.get_file())
		else:
			viewer._feedback("Soubor nelze uložit.", true)
	else:
		_confirm_rig_replacement("Nahradit rozpracovanou kostru uloženým návrhem?",
			_open_rig_draft.bind(path))


func _open_rig_draft(path: String) -> void:
	if not _rig_editor.load_draft(path):
		viewer._feedback("Neplatný návrh kostry nebo jiný model.", true)


func _rig_preview_id() -> int:
	return _rig_editor._preview.get_instance_id() if _rig_editor.has_skin_preview() else 0


func _choose_rig_glb(with_motion := false) -> void:
	if not _rig_editor.has_skin_preview() or (with_motion and not _rig_editor.has_motion_profile()):
		return
	_rig_export_motion = with_motion
	_rig_export_file.current_dir = viewer._path.get_base_dir()
	var suffix := "-rig-motion.glb" if with_motion else "-rig.glb"
	_rig_export_file.current_file = viewer._path.get_file().get_basename() + suffix
	_rig_export_file.popup_centered_ratio(0.6)


func _export_rig_glb(path: String) -> void:
	if not _rig_editor.has_skin_preview():
		return
	var target := path if path.get_extension().to_lower() == "glb" else path + ".glb"
	var with_motion := _rig_export_motion
	var warnings := PackedStringArray()
	var unmatched := _rig_editor.unmatched_weight_count()
	if unmatched > 0:
		warnings.append(tr("Ruční váhy pro %d vrcholů se neshodují s touto sítí.") % unmatched)
	if RigGlbExport.has_nonportable_materials(_rig_editor._preview):
		warnings.append(tr("GLB neumí uložit některé materiály projektu."))
	if warnings.is_empty():
		_write_rig_glb(target, with_motion)
		return
	var dialog := ConfirmationDialog.new()
	warnings.append(tr("Exportovat současný náhled do nového GLB?"))
	dialog.dialog_text = "\n".join(warnings)
	add_child(dialog)
	var preview: Node3D = _rig_editor._preview
	dialog.confirmed.connect(func():
		if _rig_editor._preview == preview:
			_write_rig_glb(target, with_motion)
	)
	dialog.visibility_changed.connect(func():
		if not dialog.visible:
			dialog.queue_free()
	)
	dialog.popup_centered()


func _write_rig_glb(target: String, with_motion := false) -> void:
	if not _rig_editor.has_skin_preview() or not viewer._begin_loading(tr("Exportuji GLB s kostrou…")):
		return
	var preview_id := _rig_preview_id()
	await viewer._paint_loading()
	var result := ERR_BUSY
	if _rig_preview_id() == preview_id and not viewer._quit_after_load:
		result = RigGlbExport.save(_rig_editor._preview, target, viewer._path, with_motion)
	viewer._finish_loading()
	if result == OK:
		viewer._feedback(tr("Uloženo · %s") % target.get_file())
	elif result == ERR_ALREADY_EXISTS:
		viewer._feedback("Pro export vyber nový soubor GLB.", true)
	elif result != ERR_BUSY:
		viewer._feedback(tr("Export GLB selhal (%s).") % error_string(result), true)


func _pin_limb() -> void:
	if _editor.selected.size() != 1:
		viewer._feedback("Vyber jednu koncovou kost.", true)
		return
	if not _editor.pin_selected():
		viewer._feedback("Tato kost netvoří platnou dvoučlánkovou končetinu.", true)


func _edit_pin_target() -> void:
	var pin := _editor.current_pin()
	if pin.is_empty() or not _rig:
		viewer._feedback("Nejprve připni končetinu v aktuálním klipu.", true)
		return
	viewer.stage.animation_player.pause()
	var rig := _rig
	var goal: Array = pin.goal
	var dialog := _dialog("Upravit cíl IK")
	var fields := VBoxContainer.new()
	dialog.add_child(fields)
	var x := _spin(fields, "X (m)", goal[0] - 10.0, goal[0] + 10.0, 0.001, goal[0])
	var y := _spin(fields, "Y (m)", goal[1] - 10.0, goal[1] + 10.0, 0.001, goal[1])
	var z := _spin(fields, "Z (m)", goal[2] - 10.0, goal[2] + 10.0, 0.001, goal[2])
	dialog.confirmed.connect(func():
		if _rig != rig or _editor.current_pin() != pin:
			return
		viewer.stage.seek(pin.start)
		if not _editor.pin_for_interval(rig.find_bone(pin.bone), Vector3(x.value, y.value, z.value), pin.start, pin.end):
			viewer._feedback("Tato kost netvoří platnou dvoučlánkovou končetinu.", true)
	)
	dialog.visibility_changed.connect(func():
		if not dialog.visible:
			dialog.queue_free()
	)
	dialog.popup_centered()


func _edit_pose() -> void:
	if not _rig or _editor.selected.is_empty():
		viewer._feedback("Vyber kost nebo oblast kostí.", true)
		return
	viewer.stage.animation_player.pause()
	var time: float = viewer.stage.animation_player.current_animation_position
	var selected := _editor.selected.duplicate()
	var dialog := _dialog("Rotace snímku")
	var fields := VBoxContainer.new()
	dialog.add_child(fields)
	var x := _spin(fields, "X (°)", -180.0, 180.0, 0.5, 0.0)
	var y := _spin(fields, "Y (°)", -180.0, 180.0, 0.5, 0.0)
	var z := _spin(fields, "Z (°)", -180.0, 180.0, 0.5, 0.0)
	dialog.confirmed.connect(func():
		var delta := Quaternion.from_euler(Vector3(x.value, y.value, z.value) * PI / 180.0)
		for bone in selected:
			_editor.put_key(bone, time, delta)
	)
	dialog.visibility_changed.connect(func():
		if not dialog.visible:
			dialog.queue_free()
	)
	dialog.popup_centered()


func _range_valid(start: float, finish: float, fps: int) -> bool:
	var player: AnimationPlayer = viewer.stage.animation_player
	return player != null and is_finite(start) and is_finite(finish) and start >= 0.0 \
		and finish > start and finish <= player.current_animation_length + 0.0001 and fps >= 5 and fps <= 60


func run_analysis(start: float, finish: float, fps: int) -> Dictionary:
	_sync_model()
	if not _rig:
		return {"error": tr("Tato animace neobsahuje kostru, jejíž klouby lze upravit.")}
	if not _range_valid(start, finish, fps) or ceili((finish - start) * fps) + 1 > 900:
		return {"error": tr("Zvol platný rozsah do 900 vzorků v nabídce Rozsah animace.")}
	if _busy or not viewer._begin_loading(tr("Rozbor pohybu")):
		return {"error": tr("Prohlížeč právě zpracovává jinou operaci.")}
	_busy = true
	await viewer._paint_loading()
	var stage: Control = viewer.stage
	var ground_y: float = stage.bounds.position.y + stage._floor_offset
	var preview := _editor.preview_enabled
	_editor.set_preview_enabled(false)
	_report = MotionReview.sample(stage, _rig, start, finish, fps, ground_y)
	_editor.set_preview_enabled(preview)
	_report.model = viewer._path.get_file()
	_report.merge(_editor.exported_edits())
	_busy = false
	viewer._finish_loading()
	return _report


func _show_findings() -> void:
	_list.clear()
	if _report.is_empty() or _report.clip != str(viewer.stage.current_clip):
		viewer._feedback("Nejprve spusť rozbor aktuálního klipu.", true)
		return
	_findings_summary.text = tr("%s · %.3f–%.3f s · %d FPS · %d nálezů") % [
		_report.clip, _report.from, _report.to, _report.fps, _report.findings.size()]
	for entry: Dictionary in _report.findings:
		_list.add_item("%.2f s · %s · %s · %.3f %s" % [entry.start, entry.bone, _finding_name(entry.type), entry.value, entry.unit])
	if _list.item_count == 0:
		_list.add_item(tr("V nastaveném rozsahu nebyl nalezen žádný problém."))
		_list.set_item_selectable(0, false)
	_findings.get_ok_button().disabled = true
	_findings.popup_centered()


func _finding_name(kind: String) -> String:
	return tr({"foot_slide": "Prokluz chodidla", "ground_penetration": "Průnik chodidla podlahou",
		"rotation_spike": "Skok rotace", "loop_seam": "Návaznost smyčky"}.get(kind, kind))


func _show_finding(index: int) -> void:
	var entry: Dictionary = _report.findings[index]
	_findings.get_ok_button().disabled = not (entry.has("correction") or entry.has("ik_goal"))
	viewer.stage.animation_player.pause()
	viewer.stage.seek(entry.start)
	_editor.finding = entry.duplicate()
	_editor.finding.clip = _report.clip


func _preview_selected() -> void:
	var selection := _list.get_selected_items()
	if not selection.is_empty() and _preview_correction(selection[0]):
		_findings.hide()


func _preview_correction(index: int) -> bool:
	if _report.is_empty() or index < 0 or index >= _report.findings.size() or _report.clip != str(viewer.stage.current_clip):
		return false
	var issue: Dictionary = _report.findings[index]
	if not _rig or not (issue.has("correction") or issue.has("ik_goal")):
		return false
	var bone := _rig.find_bone(issue.bone)
	if bone < 0:
		return false
	viewer.stage.animation_player.pause()
	viewer.stage.seek(issue.start)
	if issue.has("ik_goal"):
		var point: Array = issue.ik_goal
		if not _editor.pin_for_interval(bone, Vector3(point[0], point[1], point[2]), issue.start, issue.end):
			viewer._feedback("Tato kost netvoří platnou dvoučlánkovou končetinu.", true)
			return false
		_editor.selected = PackedInt32Array([bone])
	else:
		var authored := _rig.get_bone_pose_rotation(bone)
		var value: Array = issue.correction
		var target := Quaternion(value[0], value[1], value[2], value[3])
		_editor.put_key(bone, float(issue.start), authored.inverse() * target)
	_editor.finding = issue.duplicate()
	_editor.finding.clip = _report.clip
	return true


func _choose_save(kind: int, filter: String, extension: String) -> void:
	_save_kind = kind
	_save.filters = PackedStringArray([filter])
	_save.current_file = str(viewer.stage.current_clip) + "." + extension
	_save.popup_centered_ratio(0.55)


func _save_file(path: String) -> void:
	if _save_kind == Action.GIF:
		var resolutions := [Vector2i(640, 360), Vector2i(960, 540), Vector2i(1280, 720)]
		var filename := path if path.to_lower().ends_with(".gif") else path + ".gif"
		if not await run_gif(filename, _start.value, _selected_finish(), int(_fps.value), resolutions[_resolution.selected]):
			viewer._feedback("Export GIF selhal. Ověř rozsah, FPS a cílový soubor.", true)
		return
	var report := _report.duplicate()
	if _save_kind == Action.REPORT:
		if report.is_empty():
			report = {"schema": 1, "model": viewer._path.get_file(), "clip": str(viewer.stage.current_clip)}
		report.merge(_editor.exported_edits(), true)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		viewer._feedback("Soubor nelze uložit.", true)
		return
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	viewer._feedback(tr("Uloženo · %s") % path.get_file())


func run_gif(path: String, start: float, finish: float, fps: int, resolution: Vector2i) -> bool:
	if _busy or DisplayServer.get_name() == "headless" or not _range_valid(start, finish, fps):
		return false
	var count := ceili((finish - start) * fps)
	if count < 1 or count > 240 or fps > 30 or resolution.x < 1 or resolution.x > 1280 or resolution.y < 1 or resolution.y > 720:
		return false
	var work := ProjectSettings.globalize_path("user://gif-" + Crypto.new().generate_random_bytes(12).hex_encode())
	if not viewer._begin_loading(path.get_file(), path, tr("Vykresluji animaci GIF…")):
		return false
	if DirAccess.make_dir_absolute(work) != OK:
		viewer._finish_loading()
		return false
	_busy = true
	await viewer._paint_loading()
	var stage: Control = viewer.stage
	stage.capture_in_progress = true
	var player: AnimationPlayer = stage.animation_player
	var restore_time := player.current_animation_position
	var restore_play := player.is_playing()
	player.pause()
	var capture := _capture_viewport(stage, resolution)
	var capture_camera := capture.get_camera_3d()
	var annotations := Node2D.new()
	capture.add_child(annotations)
	annotations.draw.connect(func(): _editor.draw_annotations(annotations, capture_camera))
	var saved := 0
	for index in range(count):
		stage.seek(start + float(index) / fps)
		viewer._loading_name.text = "%s · %d/%d" % [path.get_file(), index + 1, count]
		annotations.queue_redraw()
		await get_tree().process_frame
		capture.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		var image := capture.get_texture().get_image()
		if not image or image.is_empty() or image.save_png(work.path_join("frame-%04d.png" % index)) != OK:
			break
		saved += 1
	capture.queue_free()
	stage.seek(restore_time)
	if restore_play:
		stage.resume_preview()
	stage.capture_in_progress = false
	var success := false
	if saved == count:
		viewer._loading_title.text = tr("Komprimuji GIF…")
		var helper := _helper()
		var args := PackedStringArray([work, str(fps), path])
		var status: Variant = await viewer._run_worker(_encode.bind(helper, args))
		success = status is int and status == 0
	for index in range(mini(saved + 1, count)):
		DirAccess.remove_absolute(work.path_join("frame-%04d.png" % index))
	DirAccess.remove_absolute(work)
	_busy = false
	viewer._finish_loading()
	if success:
		viewer._feedback(tr("GIF uložen · %s") % path.get_file())
	return success


static func _encode(helper: String, args: PackedStringArray) -> int:
	return OS.execute(helper, args, [], true)


func _capture_viewport(stage: Control, resolution: Vector2i) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = resolution
	viewport.world_3d = stage.viewport_3d.find_world_3d()
	viewport.msaa_3d = stage.viewport_3d.msaa_3d
	viewport.screen_space_aa = stage.viewport_3d.screen_space_aa
	viewport.debug_draw = stage.viewport_3d.debug_draw
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	stage.viewport_3d.add_child(viewport)
	var camera := Camera3D.new()
	camera.projection = stage.camera.projection
	camera.fov = stage.camera.fov
	camera.size = stage.camera.size
	camera.near = stage.camera.near
	camera.far = stage.camera.far
	viewport.add_child(camera)
	camera.global_transform = stage.camera.global_transform
	camera.make_current()
	return viewport


func _show_message(title: String, message: String) -> void:
	var dialog := _dialog(title)
	dialog.dialog_text = message
	dialog.visibility_changed.connect(func():
		if not dialog.visible:
			dialog.queue_free()
	)
	dialog.popup_centered()


func _dialog(title: String) -> AcceptDialog:
	var dialog := AcceptDialog.new()
	dialog.title = tr(title)
	dialog.exclusive = true
	add_child(dialog)
	return dialog


func _button(parent: Container, label: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = label
	button.pressed.connect(callback)
	parent.add_child(button)


func _spin(parent: VBoxContainer, label: String, minimum: float, maximum: float, step_value: float, initial: float) -> SpinBox:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var caption := Label.new()
	caption.text = label
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(caption)
	var input := SpinBox.new()
	input.min_value = minimum
	input.max_value = maximum
	input.step = step_value
	input.value = initial
	row.add_child(input)
	return input
