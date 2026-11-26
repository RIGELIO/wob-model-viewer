extends Control

const UiGlyphs = preload("res://ui_glyphs.gd")
const SceneOutline = preload("res://scene_outline.gd")
const MaterialInspector = preload("res://material_inspector.gd")
const Tutorial = preload("res://tutorial.gd")
const AnimationTools = preload("res://tools/animation_tools.gd")
const FbxMaterials = preload("res://tools/fbx_materials.gd")
const Stage = preload("res://stage.gd")
const ViewFile = preload("res://view_file.gd")
const OrientationGizmo = preload("res://orientation_gizmo.gd")
const LodCatalog = preload("res://lod_catalog.gd")
const VehicleManifest = preload("res://vehicle_manifest.gd")
const APP_ICON = preload("res://art/icon.png")
const TITLE_FONT = preload("res://art/CormorantGaramond.ttf")
const INK := Color("#1d1d1c")
const PANEL := Color("#1e1e1e")
const BORDER := Color("#434143")
const WHITE := Color("#efeae5")
const MUTED := Color("#b2aaa2")
const GOLD := Color("#d7af75")
const LOCALES := ["en", "cs"]
const HDRI_NAMES := ["Lilienstein", "Kloppenheim 06 · Pure Sky", "Moonlit Golf"]
const LOG_LIMIT := 200
const SETTINGS := "user://viewer.cfg"
const PANEL_CLOSE_DELAY_MSEC := 420
enum FileAction { OPEN, RELOAD, SAVE, SAVE_AS, CAPTURE, QUIT }
enum PanelMode { PINNED, AUTO_HIDE, HIDDEN }

class LoadingArtwork extends TextureRect:
	const ART = preload("res://art/startup.png")
	const ORBIT = preload("res://loading_orbit.gdshader")

	func _init(compact: bool) -> void:
		texture = ART
		expand_mode = EXPAND_IGNORE_SIZE
		mouse_filter = MOUSE_FILTER_IGNORE
		stretch_mode = STRETCH_SCALE if compact else STRETCH_KEEP_ASPECT_CENTERED
		if compact:
			custom_minimum_size = Vector2(90, 90)
			var image := ART.get_image()
			var half_size := Vector2i(ART.get_size() * 0.5)
			image.resize(half_size.x, half_size.y, Image.INTERPOLATE_LANCZOS)
			image.generate_mipmaps()
			texture = ImageTexture.create_from_image(image)
			texture_filter = TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		var orbit := ShaderMaterial.new()
		orbit.shader = ORBIT
		orbit.set_shader_parameter("source_size", ART.get_size())
		orbit.set_shader_parameter("compact", compact)
		material = orbit


class ViewAxes extends Control:
	var stage: Control
	var axes := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	var colors := [Color("#e87873"), Color("#a1c77c"), Color("#7299e4")]

	func _ready() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		if not stage.camera:
			return
		var basis: Basis = stage.orientation_display_basis().transposed()
		var center := Vector2(30, 38)
		for axis in axes.size():
			var point: Vector3 = basis * axes[axis]
			var offset := Vector2(point.x, -point.y) * 31.0
			if offset.length() > 5.0:
				draw_line(center, center + offset, colors[axis], 1.8, true)
				var end := center + offset
				var back := offset.normalized() * 6.0
				draw_colored_polygon(PackedVector2Array([end, end - back + back.orthogonal() * 0.5,
					end - back - back.orthogonal() * 0.5]), colors[axis])
				draw_string(get_theme_default_font(), end + offset.normalized() * 8.0 + Vector2(-3, 4),
					["X", "Y", "Z"][axis], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, colors[axis])


class LightDirectionDial extends Control:
	signal moved(azimuth: float, elevation: float)

	var azimuth := -35.0
	var elevation := 42.0
	var dragging := false

	func _ready() -> void:
		custom_minimum_size = Vector2(85.0, 85.0)
		mouse_default_cursor_shape = CURSOR_POINTING_HAND

	func update_direction(new_azimuth: float, new_elevation: float) -> void:
		azimuth = new_azimuth
		elevation = new_elevation
		queue_redraw()

	func _draw() -> void:
		var center := size * 0.5
		var radius := minf(center.x, center.y) - 5.0
		draw_circle(center, radius, Color("#201e1d"), true, -1.0, true)
		var highlight := center + Vector2(0.17, -0.26) * radius
		for band in range(35, 0, -1):
			var fraction := band / 35.0
			var shade := Color("#201e1d").lerp(Color("#57504a"), pow(1.0 - fraction, 1.6))
			draw_circle(highlight, radius * 0.72 * fraction, shade, true, -1.0, true)
		draw_arc(center, radius, 0.0, TAU, 64, Color("#6c6054"), 1.0, true)
		var angle := deg_to_rad(azimuth - 90.0)
		var distance := radius * clampf(1.0 - elevation / 90.0, 0.0, 1.0)
		var dot := center + Vector2.from_angle(angle) * distance
		draw_circle(dot + Vector2.ONE, 7.0, Color("#161514"), true, -1.0, true)
		draw_circle(dot, 6.5, Color("#c49b61"), true, -1.0, true)
		draw_circle(dot - Vector2(0.6, 0.9), 5.1, Color("#ecc78f"), true, -1.0, true)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			dragging = event.pressed
			if dragging:
				_apply_pointer(event.position)
			accept_event()
		elif event is InputEventMouseMotion and dragging:
			_apply_pointer(event.position)
			accept_event()

	func _apply_pointer(point: Vector2) -> void:
		var relative := point - size * 0.5
		var radius := minf(size.x, size.y) * 0.5 - 5.0
		var angle := wrapf(rad_to_deg(relative.angle()) + 90.0, -180.0, 180.0)
		moved.emit(angle, clampf((1.0 - relative.length() / radius) * 90.0, 0.0, 90.0))


class TimelineRuler extends Control:
	var duration := 0.0:
		set(value):
			duration = value
			queue_redraw()

	func _ready() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE
		custom_minimum_size.y = 36.0
		resized.connect(queue_redraw)

	func _draw() -> void:
		if duration <= 0.0 or size.x < 12.0:
			return
		var width := size.x - 6.0
		var mark_count := clampi(floori(width / 190.0), 2, 6)
		var rough_interval := duration / mark_count
		var unit := pow(10.0, floorf(log(rough_interval) / log(10.0)))
		var interval := unit
		for multiple: float in [1.0, 2.0, 5.0, 10.0]:
			interval = unit * multiple
			if interval >= rough_interval:
				break
		var minor := interval / 4.0
		var marks := floori(duration / minor)
		var font := get_theme_default_font()
		var tick_color := Color("#c6baac")
		for index in range(marks + 1):
			var seconds := index * minor
			var x := 3.0 + seconds / duration * width
			var major := index % 4 == 0
			draw_line(Vector2(x, 0.0), Vector2(x, 18.0 if major else 9.0), tick_color)
			if major and width - x > 58.0:
				draw_string(font, Vector2(x, 30.0), String.num(seconds, 2) + " s", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, WHITE)
		draw_line(Vector2(size.x - 3.0, 0.0), Vector2(size.x - 3.0, 7.0), tick_color)
		draw_string(font, Vector2(0.0, 30.0), String.num(duration, 2) + " s",
			HORIZONTAL_ALIGNMENT_RIGHT, width, 15, WHITE)


class ViewerPanel extends RefCounted:
	var body: Control
	var slot: Container
	var overlay: PanelContainer
	var handle: Button
	var hover_zone: Control
	var id: String
	var caption: String
	var mode := PanelMode.PINNED
	var close_after := 0

var stage: Stage
var _status: Button
var _open_log: Button
var _log_dialog: AcceptDialog
var _log_text: TextEdit
var _log_copy: Button
var _log_entries := PackedStringArray()
var _geometry: Label
var _lod_table: GridContainer
var _lod_picker: OptionButton
var _vehicle_picker: OptionButton
var _lod_entries: Array[Dictionary]
var _diagnostics: Label
var _hdri_name: Label
var _hdri_picker: OptionButton
var _sky_picker: OptionButton
var _aim_light: Button
var _cycle_controls: VBoxContainer
var _cycle_clock: HSlider
var _cycle_time: Label
var _movie: OptionButton
var _play: Button
var _loop: CheckBox
var _in_place: CheckBox
var _speed: SpinBox
var _timeline: HSlider
var _time: Label
var _ruler: TimelineRuler
var _transport_clip: OptionButton
var _transport_play: Button
var _transport_previous: Button
var _transport_next: Button
var _transport_speed: SpinBox
var _transport_loop: Button
var _open_dialog: FileDialog
var _hdri_dialog: FileDialog
var _textures_dialog: FileDialog
var _textures_button: Button
var _save_dialog: FileDialog
var _view_dialog: FileDialog
var _about: AcceptDialog
var _help: AcceptDialog
var _menu_file: MenuButton
var _menu_help: MenuButton
var _menu_view: MenuButton
var _menu_animation: MenuButton
var _menu_window: MenuButton
var _window_commands: Array[Callable]
var _scene_panel: PanelContainer
var _outline: SceneOutline
var _editor_materials: MaterialInspector
var _material_section: VBoxContainer
var _lighting_section: VBoxContainer
var _inspector_tabs: Array[Button]
var _light_dial: LightDirectionDial
var _light_azimuth: SpinBox
var _light_elevation: SpinBox
var _parts_section: VBoxContainer
var _viewport_tools: Array[Button]
var _viewport_projection: OptionButton
var _viewport_fullscreen: Button
var _view_commands: Array[Callable]
var _animation_commands: Array[Callable]
var _tutorial: Tutorial
var _inspector_scroll: ScrollContainer
var _inspector_list: VBoxContainer
var _animation_controls: HFlowContainer
var _model_section: Control
var _toolbar_panel: ViewerPanel
var _inspector_panel: ViewerPanel
var _floating_toolbar_slot: HBoxContainer
var _panel_menu_layer: Control
var _panel_menu: PanelContainer
var _panel_menu_owner: ViewerPanel
var _panel_menu_items: Array[CheckButton]
var _header_row: HBoxContainer
var _pointer_in_window := true
var _display: OptionButton
var _color_controls: HBoxContainer
var _color_layer: OptionButton
var _color_channel: OptionButton
var _attribute_hint: Label
var _parts: Tree
var _isolate_button: Button
var _show_all_button: Button
var _part_rows: Dictionary
var _wire_in_view: CheckBox
var _gizmo: OrientationGizmo
var _background_option: OptionButton
var _background_color: ColorPickerButton
var _floor_color: ColorPickerButton
var _floor_offset: SpinBox
var _floor_height_row: HBoxContainer
var _options: Dictionary
var _headings: FontVariation
var _path := ""
var _view_path := ""
var _hdri_path := ""
var _texture_directory := ""
var _azimuth := -35.0
var _elevation := 42.0
var _point_size_row: HBoxContainer
var _wireframe_width_row: HBoxContainer
var _windowed_mode := Window.MODE_WINDOWED
var _loading_mask: ColorRect
var _loading_title: Label
var _loading_name: Label
var _workers: Array[Thread]
var _loading := false
var _texture_cache := Stage.Materials.TextureCache.new()
var _quit_after_load := false


func _ready() -> void:
	TranslationServer.set_locale(_initial_locale())
	get_tree().auto_accept_quit = false
	get_window().min_size = Vector2i(860, 640)
	_headings = FontVariation.new()
	_headings.base_font = TITLE_FONT
	_headings.variation_opentype = {"wght": 650}
	theme = _viewer_theme()
	var backdrop := ColorRect.new()
	backdrop.color = INK
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("separation", 0)
	add_child(layout)
	_header_row = HBoxContainer.new()
	_header_row.add_theme_constant_override("separation", 0)
	layout.add_child(_header_row)
	var header_slot := HBoxContainer.new()
	header_slot.size_flags_horizontal = SIZE_EXPAND_FILL
	_header_row.add_child(header_slot)
	var header := _make_header(header_slot)
	var split := HBoxContainer.new()
	split.size_flags_vertical = SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 4)
	layout.add_child(split)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = SIZE_EXPAND_FILL
	split.add_child(left)
	var workspace := HSplitContainer.new()
	workspace.size_flags_vertical = SIZE_EXPAND_FILL
	left.add_child(workspace)
	_make_scene_panel(workspace)
	var center := VBoxContainer.new()
	center.size_flags_horizontal = SIZE_EXPAND_FILL
	workspace.add_child(center)
	_make_viewport(center)
	_make_timeline(left)
	var inspector_slot := VBoxContainer.new()
	split.add_child(inspector_slot)
	var inspector := _make_inspector(inspector_slot)
	var edge := VBoxContainer.new()
	split.add_child(edge)
	_floating_toolbar_slot = HBoxContainer.new()
	_floating_toolbar_slot.hide()
	edge.add_child(_floating_toolbar_slot)
	var inspector_edge := VBoxContainer.new()
	inspector_edge.size_flags_vertical = SIZE_EXPAND_FILL
	edge.add_child(inspector_edge)
	_make_panels(header, header_slot, inspector, inspector_edge, inspector_slot)
	_outline.rebuild(stage, "", [])
	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 8)
	layout.add_child(status_row)
	_open_log = _button(status_row, "Protokol", _show_log, "Ctrl+L")
	_open_log.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_status = _button(status_row, "Připraveno", _show_log)
	_status.size_flags_horizontal = SIZE_EXPAND_FILL
	_status.flat = true
	_status.clip_text = true
	_status.disabled = true
	_status.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_status.add_theme_font_size_override("font_size", 13)
	_status.add_theme_stylebox_override("disabled", StyleBoxEmpty.new())
	_status.add_theme_color_override("font_disabled_color", MUTED)
	_status.add_theme_color_override("font_color", GOLD)
	_status.add_theme_color_override("font_hover_color", WHITE)
	_status.add_theme_color_override("font_focus_color", GOLD)
	_make_loading_mask()

	_open_dialog = _dialog("Otevřít model", FileDialog.FILE_MODE_OPEN_FILE, "*.glb,*.gltf,*.wobview,*.json")
	_open_dialog.file_selected.connect(_open_path)
	_hdri_dialog = _dialog("Otevřít HDRI", FileDialog.FILE_MODE_OPEN_FILE, "*.hdr,*.exr ; Panorama HDRI")
	_hdri_dialog.file_selected.connect(func(path: String): _load_hdri(path, true))
	_textures_dialog = _dialog("Vyber složku s texturami", FileDialog.FILE_MODE_OPEN_DIR, "")
	_textures_dialog.dir_selected.connect(_reload_model)
	_save_dialog = _dialog("Uložit snímek 3840 × 2160", FileDialog.FILE_MODE_SAVE_FILE, "*.png ; Obraz PNG")
	_save_dialog.file_selected.connect(_capture)
	_view_dialog = _dialog("Uložit relaci jako", FileDialog.FILE_MODE_SAVE_FILE, "*.wobview")
	_view_dialog.file_selected.connect(_save_view_to)
	_about = AcceptDialog.new()
	_about.exclusive = true
	add_child(_about)
	_help = AcceptDialog.new()
	_help.exclusive = true
	add_child(_help)
	_tutorial = Tutorial.new()
	add_child(_tutorial)
	_make_log_dialog()
	_refresh_menu()
	_refresh_dialogs()
	get_window().files_dropped.connect(_files_dropped)
	get_window().size_changed.connect(_sync_fullscreen)
	get_window().mouse_entered.connect(func(): _pointer_in_window = true)
	get_window().mouse_exited.connect(func(): _pointer_in_window = false)
	_start_viewer.call_deferred()


func _make_menu(row: HBoxContainer) -> void:
	_menu_file = MenuButton.new()
	_menu_file.text = "Soubor"
	_menu_file.get_popup().id_pressed.connect(_file_action)
	row.add_child(_menu_file)
	_menu_view = MenuButton.new()
	_menu_view.text = "Pohled"
	_menu_view.about_to_popup.connect(_refresh_view_menu)
	_menu_view.get_popup().id_pressed.connect(func(id: int): _view_commands[id].call())
	row.add_child(_menu_view)
	_menu_animation = MenuButton.new()
	_menu_animation.text = "Animace"
	_menu_animation.about_to_popup.connect(_refresh_animation_menu)
	_menu_animation.get_popup().id_pressed.connect(func(id: int): _animation_commands[id].call())
	row.add_child(_menu_animation)
	_menu_window = MenuButton.new()
	_menu_window.text = "Okno"
	_menu_window.about_to_popup.connect(_refresh_window_menu)
	_menu_window.get_popup().id_pressed.connect(func(id: int): _window_commands[id].call())
	row.add_child(_menu_window)
	_menu_help = MenuButton.new()
	_menu_help.text = "Nápověda"
	_menu_help.get_popup().id_pressed.connect(func(id: int):
		match id:
			0: _show_help()
			1: _show_about()
			2: _show_log()
			3: _tutorial.open_guide()
	)
	row.add_child(_menu_help)


func _refresh_window_menu() -> void:
	var menu := _menu_window.get_popup()
	menu.clear()
	_window_commands.clear()
	_menu_command(menu, _window_commands, tr("Panel scény"), _toggle_scene_panel,
		true, KEY_NONE, int(_scene_panel.visible))
	_menu_command(menu, _window_commands, tr("Inspektor"), _show_or_hide_inspector,
		true, KEY_NONE, int(_inspector_panel.mode == PanelMode.PINNED))
	_menu_command(menu, _window_commands, tr("Automaticky skrývat inspektor"),
		_set_panel_mode.bind(_inspector_panel, PanelMode.AUTO_HIDE), true, KEY_NONE,
		int(_inspector_panel.mode == PanelMode.AUTO_HIDE))
	_menu_command(menu, _window_commands, tr("Skrýt horní lištu"),
		_set_panel_mode.bind(_toolbar_panel, PanelMode.HIDDEN), true)
	_menu_command(menu, _window_commands, tr("Automaticky skrývat lištu"),
		_set_panel_mode.bind(_toolbar_panel, PanelMode.AUTO_HIDE), true, KEY_NONE,
		int(_toolbar_panel.mode == PanelMode.AUTO_HIDE))
	menu.add_separator()
	_menu_command(menu, _window_commands, tr("English"), _change_locale.bind(0), true,
		KEY_NONE, int(TranslationServer.get_locale() == "en"))
	_menu_command(menu, _window_commands, tr("Čeština"), _change_locale.bind(1), true,
		KEY_NONE, int(TranslationServer.get_locale() == "cs"))


func _toggle_scene_panel() -> void:
	_scene_panel.visible = not _scene_panel.visible


func _show_or_hide_inspector() -> void:
	var mode := PanelMode.HIDDEN if _inspector_panel.mode == PanelMode.PINNED else PanelMode.PINNED
	_set_panel_mode(_inspector_panel, mode)


func _refresh_menu() -> void:
	var menu := _menu_file.get_popup()
	menu.clear()
	menu.add_item(tr("Otevřít…"), FileAction.OPEN, KEY_MASK_CTRL | KEY_O)
	menu.add_item(tr("Znovu načíst model"), FileAction.RELOAD, KEY_MASK_CTRL | KEY_R)
	menu.add_separator()
	menu.add_item(tr("Uložit"), FileAction.SAVE, KEY_MASK_CTRL | KEY_S)
	menu.add_item(tr("Uložit jako…"), FileAction.SAVE_AS, KEY_MASK_CTRL | KEY_MASK_SHIFT | KEY_S)
	menu.add_item(tr("Uložit 4K PNG"), FileAction.CAPTURE, KEY_MASK_CTRL | KEY_E)
	menu.add_separator()
	menu.add_item(tr("Konec"), FileAction.QUIT, KEY_MASK_CTRL | KEY_Q)
	for id in [FileAction.RELOAD, FileAction.SAVE, FileAction.SAVE_AS, FileAction.CAPTURE]:
		menu.set_item_disabled(menu.get_item_index(id), _path.is_empty())
	var help := _menu_help.get_popup()
	help.clear()
	help.add_item(tr("Průvodce krok za krokem"), 3)
	help.add_item(tr("Ovládání"), 0, KEY_F1)
	help.add_item(tr("Protokol"), 2, KEY_MASK_CTRL | KEY_L)
	help.add_separator()
	help.add_item(tr("O programu"), 1)


static func _menu_command(menu: PopupMenu, commands: Array[Callable], label: String,
		action: Callable, enabled: bool, shortcut := KEY_NONE, check := -1) -> void:
	var id := commands.size()
	commands.append(action)
	if check < 0:
		menu.add_item(label, id, shortcut)
	else:
		menu.add_check_item(label, id, shortcut)
		menu.set_item_checked(menu.item_count - 1, check == 1)
	menu.set_item_disabled(menu.item_count - 1, not enabled)


func _refresh_view_menu() -> void:
	var menu := _menu_view.get_popup()
	menu.clear()
	_view_commands.clear()
	var ready := stage.model != null and not _loading
	_menu_command(menu, _view_commands, tr("Zarámovat"), stage.frame, ready, KEY_F)
	_menu_command(menu, _view_commands, tr("Zepředu"), stage.frame.bind(Vector2.ZERO), ready, KEY_2)
	_menu_command(menu, _view_commands, tr("Z boku"), stage.frame.bind(Vector2(PI / 2.0, 0.0)), ready, KEY_3)
	_menu_command(menu, _view_commands, tr("Shora"), stage.frame.bind(Vector2(0.0, 1.555)), ready, KEY_4)
	menu.add_separator()
	_menu_command(menu, _view_commands, tr("Předchozí LOD"), _step_lod.bind(-1),
		ready and _lod_picker.selected > 0, KEY_PAGEUP)
	_menu_command(menu, _view_commands, tr("Další LOD"), _step_lod.bind(1),
		ready and _lod_picker.selected >= 0 and _lod_picker.selected + 1 < _lod_entries.size(), KEY_PAGEDOWN)
	for option in ["grid", "floor", "skeleton", "model_axes", "ortho"]:
		var control: CheckBox = _options[option]
		_menu_command(menu, _view_commands, tr(control.text), _toggle_option.bind(option),
			not _loading, KEY_NONE, int(control.button_pressed))
	menu.add_separator()
	_menu_command(menu, _view_commands, tr("Otevřít inspektor"),
		focus_inspector.bind(_inspector_list), not _loading)
	_menu_command(menu, _view_commands, tr(_fullscreen_caption()), _toggle_fullscreen, true, KEY_F11)


func _refresh_animation_menu() -> void:
	var menu := _menu_animation.get_popup()
	menu.clear()
	_animation_commands.clear()
	var player: AnimationPlayer = stage.animation_player
	var ready := player != null and not _loading
	var playback := "Pozastavit" if player and player.is_playing() else "Přehrát"
	_menu_command(menu, _animation_commands, tr(playback), _toggle_play, ready, KEY_SPACE)
	_menu_command(menu, _animation_commands, tr("Předchozí snímek"), _step_preview_frame.bind(-1), ready)
	_menu_command(menu, _animation_commands, tr("Následující snímek"), _step_preview_frame.bind(1), ready)
	menu.add_separator()
	_menu_command(menu, _animation_commands, tr("Smyčka"), _toggle_option.bind("animation_loop"),
		ready, KEY_NONE, int(_loop.button_pressed))
	_menu_command(menu, _animation_commands, tr("Na místě"), _toggle_option.bind("animation_in_place"),
		ready, KEY_NONE, int(_in_place.button_pressed))
	menu.add_separator()
	_menu_command(menu, _animation_commands, tr("Přehrávání animace"),
		focus_inspector.bind(_animation_controls), not _loading)


func _animation_frame_step(clip: Animation) -> float:
	return clip.step if clip.step > 0.0 else 1.0 / 30.0


func _step_preview_frame(direction: int) -> void:
	var player: AnimationPlayer = stage.animation_player
	if not player:
		return
	var step := _animation_frame_step(player.get_animation(stage.current_clip))
	var position := player.current_animation_position / step
	var frame := floori(position + 0.000001) + 1 if direction > 0 else ceili(position - 0.000001) - 1
	player.pause()
	stage.seek(clampf(frame * step, 0.0, player.current_animation_length))
	_sync_play_buttons(false)
	_sync_timeline_readout(player.current_animation_position)


func _file_action(id: int) -> void:
	match id:
		FileAction.OPEN: _show_open()
		FileAction.RELOAD: _reload_model()
		FileAction.SAVE: _save_view()
		FileAction.SAVE_AS: _show_view_save()
		FileAction.CAPTURE: _show_capture()
		FileAction.QUIT: _request_quit()


func _show_about() -> void:
	_about.title = tr("O programu")
	_about.dialog_text = "WoB Model Viewer %s\n© 2026 RIGELIO Studio\n\n%s" % [ProjectSettings.get_setting("application/config/version"), tr(
		"Offline prohlížeč modelů GLB pro Wars of Bohemia.\nGodot 4.7.2 Forward+.\n\nLicence MIT. Licence přiložených prostředků jsou v balíčku aplikace."
	)]
	_about.popup_centered()


func _show_help() -> void:
	_help.title = tr("Ovládání WoB Model Viewer")
	_help.dialog_text = tr(
		"Přetáhni GLB, glTF, FBX, HDRI nebo uloženou relaci do okna.\n\nMyš: levé otáčí, pravé nebo prostřední posouvá, kolečko přibližuje.\nF / 1: zarámovat. 2: zepředu. 3: z boku. 4: shora.\nKlikni na stěnu orientační kostky nebo ji tažením otoč.\nM: osy modelu. Táhni šipku pro posun nebo kruh pro otočení.\n\nW: trojúhelníkový wireframe. Q: odhad quadů. P: body.\nG: mřížka. K: kostra. A: automatické otáčení.\nB: pozadí. O: ortografický pohled.\nPage Up / Page Down: předchozí / další LOD. Mezerník: animace.\n\nCtrl+O: otevřít. Ctrl+S: uložit. Ctrl+Shift+S: uložit jako.\nCtrl+E: snímek 4K. Ctrl+L: protokol. Ctrl+Q: konec. F1: nápověda.\nF11: celá obrazovka. Esc: návrat do okna."
	)
	_help.dialog_text += "\n\n" + tr(
		"Ctrl+R znovu načte model se stejným pohledem, světly a LOD. V části Díly a materiály můžeš izolovat síť nebo povrch. Vertex barvy a UV šachovnici najdeš v Zobrazení."
	)
	_help.dialog_text += "\n\n" + tr(
		"Lištu a inspektor můžeš připnout, skrýt nebo nastavit automatické skrývání. Skryté panely obnovíš z jejich okrajových nabídek."
	)
	_help.popup_centered()


func _make_log_dialog() -> void:
	_log_dialog = AcceptDialog.new()
	_log_dialog.exclusive = true
	add_child(_log_dialog)
	_log_text = TextEdit.new()
	_log_text.editable = false
	_log_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_log_text.custom_minimum_size = Vector2(600, 330)
	_log_dialog.add_child(_log_text)
	_log_copy = _log_dialog.add_button("", true, "copy")
	_log_dialog.custom_action.connect(func(action: StringName):
		if action == &"copy":
			DisplayServer.clipboard_set(_log_text.text)
	)


func _show_log() -> void:
	_show_log_dialog.call_deferred()


func _show_log_dialog() -> void:
	if _log_dialog.visible:
		_log_dialog.grab_focus()
		return
	_log_copy.disabled = _log_entries.is_empty()
	_log_text.text = tr("Protokol je prázdný.") if _log_entries.is_empty() else "\n\n".join(_log_entries)
	_log_text.set_caret_line(0)
	_log_text.scroll_vertical = 0.0
	_log_dialog.popup_centered()
	_log_dialog.grab_focus()


func _make_header(layout: HBoxContainer) -> HBoxContainer:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	header.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_theme_constant_override("separation", 7)
	layout.add_child(header)
	header.custom_minimum_size.y = 34
	_make_menu(header)
	return header


func _make_panels(header: HBoxContainer, header_slot: HBoxContainer,
		inspector: PanelContainer, edge: VBoxContainer, inspector_slot: VBoxContainer) -> void:
	var layer := Control.new()
	layer.mouse_filter = MOUSE_FILTER_IGNORE
	layer.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(layer)
	var top_edge := Control.new()
	top_edge.mouse_filter = MOUSE_FILTER_IGNORE
	top_edge.set_anchors_and_offsets_preset(PRESET_TOP_WIDE)
	top_edge.offset_left = 12
	top_edge.offset_right = -12
	top_edge.offset_bottom = 10
	layer.add_child(top_edge)
	_toolbar_panel = _make_panel(layer, header, header_slot, _header_row, top_edge, "toolbar", "Horní lišta")
	_inspector_panel = _make_panel(layer, inspector, inspector_slot, edge, edge, "inspector", "Inspektor")
	_make_panel_menu(layer)
	var settings := ConfigFile.new()
	settings.load(SETTINGS)
	for panel: ViewerPanel in [_toolbar_panel, _inspector_panel]:
		var mode: Variant = settings.get_value("panels", panel.id, PanelMode.PINNED)
		_set_panel_mode(panel, mode if mode is int else PanelMode.PINNED, false)
	var timer := Timer.new()
	timer.wait_time = 0.10
	timer.timeout.connect(_update_auto_panels)
	add_child(timer)
	timer.start()


func _make_panel(layer: Control, body: Control, slot: Container, handle_parent: Container,
		hover_zone: Control, id: String, caption: String) -> ViewerPanel:
	var panel := ViewerPanel.new()
	panel.body = body
	panel.slot = slot
	panel.hover_zone = hover_zone
	panel.id = id
	panel.caption = caption
	panel.overlay = PanelContainer.new()
	var cover: StyleBox = _box(INK, BORDER, 7, 4) if id == "toolbar" else StyleBoxEmpty.new()
	panel.overlay.add_theme_stylebox_override("panel", cover)
	panel.overlay.hide()
	layer.add_child(panel.overlay)
	panel.handle = Button.new()
	panel.handle.custom_minimum_size.x = 31
	handle_parent.add_child(panel.handle)
	panel.handle.pressed.connect(_show_panel_menu.bind(panel))
	return panel


func _make_panel_menu(layer: Control) -> void:
	# A menu inside the viewer keeps the handle and its choices in the same input window.
	_panel_menu_layer = Control.new()
	_panel_menu_layer.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_panel_menu_layer.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			_dismiss_panel_menu()
	)
	layer.add_child(_panel_menu_layer)
	_panel_menu = PanelContainer.new()
	_panel_menu.custom_minimum_size.x = 218
	_panel_menu.add_theme_stylebox_override("panel", _box(INK, BORDER, 7, 5))
	_panel_menu_layer.add_child(_panel_menu)
	var choices := VBoxContainer.new()
	choices.add_theme_constant_override("separation", 2)
	_panel_menu.add_child(choices)
	var group := ButtonGroup.new()
	for mode in range(PanelMode.PINNED, PanelMode.HIDDEN + 1):
		var item := CheckButton.new()
		item.button_group = group
		item.custom_minimum_size.y = 34
		item.pressed.connect(_choose_panel_mode.bind(mode))
		choices.add_child(item)
		_panel_menu_items.append(item)
	for index in range(_panel_menu_items.size()):
		var item := _panel_menu_items[index]
		var previous := item.get_path_to(_panel_menu_items[posmod(index - 1, _panel_menu_items.size())])
		var next := item.get_path_to(_panel_menu_items[(index + 1) % _panel_menu_items.size()])
		item.focus_previous = previous
		item.focus_neighbor_top = previous
		item.focus_next = next
		item.focus_neighbor_bottom = next
	_panel_menu_layer.resized.connect(_place_panel_menu)
	get_window().focus_exited.connect(_dismiss_panel_menu.bind(false))
	_panel_menu_layer.hide()


func _show_panel_menu(panel: ViewerPanel) -> void:
	_panel_menu_owner = panel
	for mode in range(_panel_menu_items.size()):
		var item := _panel_menu_items[mode]
		item.text = _panel_mode_title(mode)
		item.set_pressed_no_signal(mode == panel.mode)
	_panel_menu_layer.show()
	_place_panel_menu()
	_panel_menu_items[panel.mode].grab_focus()


func _place_panel_menu() -> void:
	if _panel_menu_owner == null:
		return
	var anchor := _panel_menu_owner.handle.get_global_rect()
	var bounds := _panel_menu_layer.get_global_rect()
	_panel_menu.size = _panel_menu.get_combined_minimum_size()
	var x := clampf(anchor.end.x - _panel_menu.size.x, bounds.position.x, bounds.end.x - _panel_menu.size.x)
	var y := anchor.end.y + 4.0
	if y + _panel_menu.size.y > bounds.end.y:
		y = maxf(bounds.position.y, anchor.position.y - _panel_menu.size.y - 4.0)
	_panel_menu.global_position = Vector2(x, y)


func _dismiss_panel_menu(restore_focus := true) -> void:
	if _panel_menu_owner == null:
		return
	var panel := _panel_menu_owner
	_panel_menu_owner = null
	_panel_menu_layer.hide()
	if restore_focus:
		panel.handle.grab_focus()


func _choose_panel_mode(mode: int) -> void:
	var panel := _panel_menu_owner
	if panel == null:
		return
	_dismiss_panel_menu()
	_set_panel_mode(panel, mode)


func _panel_mode_title(mode: int) -> String:
	match mode:
		PanelMode.AUTO_HIDE: return tr("Automaticky skrývat")
		PanelMode.HIDDEN: return tr("Skrýt")
	return tr("Připnout")


func _refresh_panel_handle(panel: ViewerPanel) -> void:
	if panel == _toolbar_panel:
		panel.handle.text = tr("Lišta") + " ▾" if panel.mode == PanelMode.PINNED else "▾"
	else:
		panel.handle.text = "▶" if panel.mode == PanelMode.PINNED else "◀"
	panel.handle.tooltip_text = "%s · %s" % [tr(panel.caption), _panel_mode_title(panel.mode)]


func _set_panel_mode(panel: ViewerPanel, mode: int, persist := true) -> void:
	if mode < PanelMode.PINNED or mode > PanelMode.HIDDEN:
		mode = PanelMode.PINNED
	var pinned := mode == PanelMode.PINNED
	var parent: Control = panel.slot if pinned else panel.overlay
	var moving := panel.body.get_parent() != parent
	if moving or panel.overlay.visible:
		_focus_panel_handle_if_needed(panel)
	if moving:
		panel.body.reparent(parent, false)
	panel.mode = mode as PanelMode
	panel.close_after = 0
	panel.overlay.hide()
	if panel == _toolbar_panel:
		var handle_parent: Container = _header_row if pinned else _floating_toolbar_slot
		if panel.handle.get_parent() != handle_parent:
			var had_focus := panel.handle.has_focus()
			panel.handle.reparent(handle_parent, false)
			if had_focus:
				panel.handle.grab_focus.call_deferred()
		_header_row.visible = pinned
		_floating_toolbar_slot.visible = not pinned
		panel.handle.visible = not pinned
	else:
		panel.slot.visible = pinned
		panel.handle.visible = not pinned
	_refresh_panel_handle(panel)
	if persist:
		var settings := ConfigFile.new()
		settings.load(SETTINGS)
		settings.set_value("panels", panel.id, mode)
		settings.save(SETTINGS)


func _focus_panel_handle_if_needed(panel: ViewerPanel) -> void:
	var focused := get_viewport().gui_get_focus_owner()
	if is_instance_valid(focused) and panel.body.is_ancestor_of(focused):
		panel.handle.grab_focus()


func _update_auto_panels() -> void:
	if _loading or not is_visible_in_tree():
		return
	var pointer := get_global_mouse_position()
	var now := Time.get_ticks_msec()
	for panel: ViewerPanel in [_toolbar_panel, _inspector_panel]:
		if panel.mode == PanelMode.AUTO_HIDE:
			_update_auto_panel(panel, pointer, now)


func _update_auto_panel(panel: ViewerPanel, pointer: Vector2, now: int) -> void:
	var on_handle := _pointer_in_window and (panel.hover_zone.get_global_rect().has_point(pointer)
		or panel.handle.get_global_rect().has_point(pointer))
	var over_panel := _pointer_in_window and panel.overlay.visible \
		and panel.overlay.get_global_rect().has_point(pointer)
	if on_handle or over_panel:
		panel.close_after = now + PANEL_CLOSE_DELAY_MSEC
		panel.overlay.show()
	elif panel.overlay.visible and now >= panel.close_after and not _panel_has_popup(panel) \
			and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_focus_panel_handle_if_needed(panel)
		panel.overlay.hide()
	if panel.overlay.visible:
		_place_panel_overlay(panel)


func _place_panel_overlay(panel: ViewerPanel) -> void:
	var rail := panel.hover_zone.get_global_rect()
	if panel == _toolbar_panel:
		panel.overlay.global_position = rail.position + Vector2(0.0, 8.0)
		panel.overlay.size = Vector2(rail.size.x - _floating_toolbar_slot.size.x - 7.0,
			panel.body.get_combined_minimum_size().y + 8.0)
	else:
		var width := panel.body.get_combined_minimum_size().x
		var top := rail.position.y
		if _toolbar_panel.overlay.visible:
			top = maxf(top, _toolbar_panel.overlay.get_global_rect().end.y + 6.0)
		panel.overlay.global_position = Vector2(rail.position.x - width - 7.0, top)
		panel.overlay.size = Vector2(width, rail.end.y - top)


func _panel_has_popup(panel: ViewerPanel) -> bool:
	if _panel_menu_owner == panel:
		return true
	for popup: Popup in panel.body.find_children("*", "Popup", true, false):
		if popup.visible:
			return true
	return false


func _toggle_fullscreen() -> void:
	var window := get_window()
	if window.mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN]:
		window.mode = _windowed_mode
	else:
		_windowed_mode = Window.MODE_MAXIMIZED if window.mode == Window.MODE_MAXIMIZED else Window.MODE_WINDOWED
		window.mode = Window.MODE_FULLSCREEN
	_sync_fullscreen()


func _fullscreen_caption() -> String:
	return "Zpět do okna" if get_window().mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN] else "Celá obrazovka"


func _sync_fullscreen() -> void:
	_viewport_fullscreen.tooltip_text = tr(_fullscreen_caption()) + " · F11"


func _make_viewport(parent: VBoxContainer) -> void:
	var card := PanelContainer.new()
	card.size_flags_vertical = SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _box(PANEL, BORDER, 2, 1))
	parent.add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	card.add_child(column)
	var tool_strip := HBoxContainer.new()
	tool_strip.custom_minimum_size.y = 48.0
	column.add_child(tool_strip)
	var area := Control.new()
	area.size_flags_vertical = SIZE_EXPAND_FILL
	area.clip_contents = true
	column.add_child(area)
	stage = Stage.new()
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	area.add_child(stage)
	_setup_viewport_tools(tool_strip)
	_vehicle_picker = OptionButton.new()
	_vehicle_picker.item_selected.connect(_select_vehicle_state)
	_vehicle_picker.hide()
	_lod_picker = OptionButton.new()
	_lod_picker.item_selected.connect(_select_lod)
	_lod_picker.hide()
	_gizmo = OrientationGizmo.new()
	_gizmo.stage = stage
	_gizmo.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_gizmo.offset_left = -124
	_gizmo.offset_top = 6
	_gizmo.offset_right = -6
	_gizmo.offset_bottom = 124
	area.add_child(_gizmo)
	var axes := ViewAxes.new()
	axes.stage = stage
	area.add_child(axes)
	axes.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	axes.offset_left = 14
	axes.offset_right = 100
	axes.offset_top = -100
	axes.offset_bottom = -14
	area.tooltip_text = tr("Levé tlačítko orbit · Pravé nebo prostřední posun · Kolečko zoom")


func _setup_viewport_tools(toolbar: HBoxContainer) -> void:
	var selected_style := UiGlyphs.tool_surface()
	for tool in range(3):
		var tip: String = ["Výběr", "Posun modelu", "Otočení modelu"][tool]
		var glyph: String = ["select", "move", "rotate"][tool]
		var button := _icon_button(toolbar, glyph, _choose_viewport_tool.bind(tool), tip, Color("#e4bc80") if tool == 0 else MUTED)
		button.toggle_mode = true
		button.flat = tool != 0
		button.add_theme_stylebox_override("pressed", selected_style)
		button.add_theme_stylebox_override("hover_pressed", selected_style)
		_viewport_tools.append(button)
	_viewport_tools[0].set_pressed_no_signal(true)
	toolbar.add_child(VSeparator.new())
	_icon_button(toolbar, "frame", stage.frame, "Zarámovat").flat = true
	_icon_button(toolbar, "grid", _toggle_option.bind("grid"), "Mřížka").flat = true
	var spacer := Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	toolbar.add_child(spacer)
	_viewport_projection = OptionButton.new()
	_viewport_projection.add_item("Perspektiva")
	_viewport_projection.add_item("Orto")
	_viewport_projection.item_selected.connect(func(mode: int): _options.ortho.button_pressed = mode == 1)
	toolbar.add_child(_viewport_projection)
	_viewport_fullscreen = _icon_button(toolbar, "fullscreen", _toggle_fullscreen, "Celá obrazovka")
	_viewport_fullscreen.flat = true


func _choose_viewport_tool(tool: int) -> void:
	for index in _viewport_tools.size():
		_viewport_tools[index].set_pressed_no_signal(index == tool)
		_viewport_tools[index].flat = index != tool
		_viewport_tools[index].icon = UiGlyphs.texture(["select", "move", "rotate"][index], Color("#e4bc80") if index == tool else MUTED, 22)
	stage.model_gizmo_tool(tool)
	_options.model_axes.button_pressed = tool != 0


func _icon_button(parent: Container, name: String, action: Callable, title: String, color := MUTED) -> Button:
	var button := _button(parent, "", action, title)
	button.icon = UiGlyphs.texture(name, color, 22)
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.custom_minimum_size = Vector2(46, 34)
	button.size_flags_vertical = SIZE_SHRINK_CENTER
	return button


func _make_scene_panel(parent: Container) -> void:
	_scene_panel = PanelContainer.new()
	_scene_panel.custom_minimum_size.x = 210.0
	_scene_panel.add_theme_stylebox_override("panel", _box(INK, BORDER, 2, 8))
	parent.add_child(_scene_panel)
	_outline = SceneOutline.new()
	_outline.item_chosen.connect(_scene_item_selected)
	_scene_panel.add_child(_outline)
	_outline.visibility_changed_for_mesh.connect(func(mesh: MeshInstance3D, state: bool):
		if stage:
			stage.set_part_visible(mesh, state)
	)


func _scene_item_selected(kind: String, data: Variant) -> void:
	match kind:
		"mesh":
			for index in _editor_materials.targets.size():
				if _editor_materials.targets[index].instance == data:
					_editor_materials.select_slot(index)
					break
			focus_inspector(_material_section)
		"material":
			_editor_materials.select_slot(int(data))
			focus_inspector(_material_section)
		"materials":
			focus_inspector(_material_section)
		"skeleton":
			_options.skeleton.button_pressed = true
		"animations":
			focus_inspector(_animation_controls)
		"clip":
			_choose_clip(int(data))


func _start_viewer() -> void:
	if DisplayServer.get_name() != "headless":
		var splash := ColorRect.new()
		splash.color = Color("#111214")
		splash.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		add_child(splash)
		var artwork := LoadingArtwork.new(false)
		artwork.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		splash.add_child(artwork)
		await get_tree().create_timer(0.85).timeout
		splash.queue_free()
	var tools := AnimationTools.new()
	add_child(tools)
	tools.attach(self)


func _make_loading_mask() -> void:
	_loading_mask = ColorRect.new()
	_loading_mask.color = Color("#111216ab")
	_loading_mask.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_loading_mask)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_loading_mask.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(PANEL, BORDER, 10, 15))
	center.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	row.add_child(LoadingArtwork.new(true))
	var text := VBoxContainer.new()
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(text)
	_loading_title = _label(text, "Načítám…", 17, WHITE)
	_loading_name = _label(text, "", 13, MUTED)
	_loading_name.custom_minimum_size.x = 215
	_loading_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_loading_mask.hide()


func _begin_loading(details: String, tooltip := "", title := "Načítám…") -> bool:
	if _loading or _quit_after_load or stage.capture_in_progress:
		return false
	_dismiss_panel_menu(false)
	_loading = true
	_loading_title.text = title
	_loading_name.text = details
	_loading_name.tooltip_text = tooltip
	_loading_mask.show()
	return true


func _with_loading(details: String, action: Callable) -> void:
	if not _begin_loading(details):
		return
	await _paint_loading()
	await action.call()
	await _paint_loading()
	_finish_loading()


func _paint_loading() -> void:
	# A full frame between these signals lets the overlay draw before a render update.
	await get_tree().process_frame
	await get_tree().process_frame


func _finish_loading() -> void:
	_loading_mask.hide()
	_loading = false
	if _quit_after_load:
		get_tree().quit()


func _request_quit() -> void:
	if _loading:
		_quit_after_load = true
	else:
		get_tree().quit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_request_quit()


func _exit_tree() -> void:
	for worker: Thread in _workers:
		worker.wait_to_finish()
	_workers.clear()


func _run_worker(task: Callable) -> Variant:
	var worker := Thread.new()
	if worker.start(task) != OK:
		return null
	_workers.append(worker)
	while worker.is_alive():
		await get_tree().process_frame
	if not _workers.has(worker):
		return null
	_workers.erase(worker)
	return worker.wait_to_finish()


static func make_animation_speed_control(changed: Callable, initial := Stage.ANIMATION_SPEED_DEFAULT) -> SpinBox:
	var control := SpinBox.new()
	control.min_value = Stage.ANIMATION_SPEED_MIN
	control.max_value = Stage.ANIMATION_SPEED_MAX
	control.step = Stage.ANIMATION_SPEED_STEP
	control.value = Stage.normalized_animation_speed(initial)
	control.custom_minimum_size.x = 88.0
	control.select_all_on_focus = true
	control.suffix = "×"
	control.tooltip_text = "Rychlost přehrávání animace"
	var field := control.get_line_edit()
	field.text_changed.connect(func(text: String):
		if "," in text:
			var caret := field.caret_column
			field.text = text.replace(",", ".")
			field.caret_column = caret
	)
	control.value_changed.connect(changed)
	return control


func _make_timeline(parent: VBoxContainer) -> void:
	var controls := HFlowContainer.new()
	_animation_controls = controls
	_movie = OptionButton.new()
	_movie.custom_minimum_size.x = 76
	_movie.size_flags_horizontal = SIZE_EXPAND_FILL
	_movie.fit_to_longest_item = false
	_movie.item_selected.connect(_choose_clip)
	controls.add_child(_movie)
	_play = _button(controls, "Přehrát", _toggle_play)
	_loop = _toggle(controls, "animation_loop", "Smyčka", true, stage.animation_loop)
	_in_place = _toggle(controls, "animation_in_place", "Na místě", false, stage.animation_in_place)
	_in_place.tooltip_text = "Potlačí vodorovný posun kořene animace."
	_speed = make_animation_speed_control(_set_animation_speed)
	controls.add_child(_speed)
	_make_transport(parent)
	_refresh_clips()


func _make_transport(parent: VBoxContainer) -> void:
	var dock := PanelContainer.new()
	dock.add_theme_stylebox_override("panel", _box(PANEL, GOLD.darkened(0.36), 5, 18))
	dock.custom_minimum_size.y = 214
	parent.add_child(dock)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 9)
	dock.add_child(layout)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 18)
	row.alignment = FlowContainer.ALIGNMENT_BEGIN
	row.add_theme_constant_override("v_separation", 6)
	layout.add_child(row)

	var clip_group := HBoxContainer.new()
	clip_group.add_theme_constant_override("separation", 13)
	clip_group.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(clip_group)
	var clip_icon := TextureRect.new()
	clip_icon.texture = UiGlyphs.texture("clip", GOLD, 25)
	clip_icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	clip_group.add_child(clip_icon)
	var clip_label := _label(clip_group, "Klip", 15, WHITE)
	clip_label.uppercase = true
	clip_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_transport_clip = OptionButton.new()
	_transport_clip.custom_minimum_size.x = 230
	_transport_clip.size_flags_horizontal = SIZE_EXPAND_FILL
	_transport_clip.fit_to_longest_item = false
	_transport_clip.item_selected.connect(_choose_clip)
	clip_group.add_child(_transport_clip)

	row.add_child(VSeparator.new())
	var transport := HBoxContainer.new()
	transport.add_theme_constant_override("separation", 10)
	row.add_child(transport)
	_transport_previous = _icon_button(transport, "previous", _step_preview_frame.bind(-1), "Předchozí snímek")
	_transport_play = _icon_button(transport, "play", _toggle_play, "Přehrát", INK)
	_transport_next = _icon_button(transport, "next", _step_preview_frame.bind(1), "Následující snímek")
	for control: Button in [_transport_previous, _transport_play, _transport_next]:
		control.custom_minimum_size = Vector2(46, 42)
		control.size_flags_vertical = SIZE_SHRINK_CENTER
		control.add_theme_font_size_override("font_size", 21)
	_transport_play.custom_minimum_size = Vector2(58, 58)
	_transport_play.add_theme_stylebox_override("normal", UiGlyphs.play_surface())
	_transport_play.add_theme_stylebox_override("hover", UiGlyphs.play_surface(0.12))
	_transport_play.add_theme_stylebox_override("pressed", _box(GOLD.darkened(0.15), GOLD, 29, 8.0))
	_transport_play.add_theme_stylebox_override("disabled", _box(Color("#3c3732"), BORDER, 29, 8.0))
	_transport_play.add_theme_color_override("font_color", INK)
	_transport_play.add_theme_color_override("font_hover_color", INK)
	_transport_play.add_theme_color_override("font_pressed_color", INK)

	row.add_child(VSeparator.new())
	_time = _label(row, "", 18, WHITE)
	var digits := SystemFont.new()
	digits.font_names = PackedStringArray(["Cascadia Mono", "Liberation Mono", "DejaVu Sans Mono"])
	_time.add_theme_font_override("font", digits)
	_time.custom_minimum_size.x = 206
	_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_time.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var speed_group := HBoxContainer.new()
	speed_group.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(speed_group)
	_label(speed_group, "Rychlost", 14, MUTED).vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_transport_speed = make_animation_speed_control(_set_animation_speed)
	speed_group.add_child(_transport_speed)
	_transport_loop = Button.new()
	_transport_loop.icon = UiGlyphs.texture("loop", GOLD, 26)
	_transport_loop.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_transport_loop.size_flags_vertical = SIZE_SHRINK_CENTER
	_transport_loop.tooltip_text = "Smyčka"
	_transport_loop.toggle_mode = true
	_transport_loop.custom_minimum_size = Vector2(40, 32)
	_transport_loop.set_pressed_no_signal(_loop.button_pressed)
	_transport_loop.toggled.connect(func(value: bool): _loop.button_pressed = value)
	_loop.toggled.connect(_transport_loop.set_pressed_no_signal)
	row.add_child(VSeparator.new())
	row.add_child(_transport_loop)
	layout.add_child(HSeparator.new())
	var timeline_margin := MarginContainer.new()
	timeline_margin.add_theme_constant_override("margin_left", 24)
	timeline_margin.add_theme_constant_override("margin_right", 24)
	timeline_margin.add_theme_constant_override("margin_top", 13)
	layout.add_child(timeline_margin)
	var timeline_controls := VBoxContainer.new()
	timeline_controls.add_theme_constant_override("separation", 0)
	timeline_margin.add_child(timeline_controls)

	_timeline = HSlider.new()
	_timeline.step = 0.001
	_timeline.custom_minimum_size.y = 36.0
	_timeline.add_theme_stylebox_override("slider", _box(Color("#3a3738"), Color("#686465"), 3, 7))
	_timeline.add_theme_stylebox_override("grabber_area", _box(Color("#936a40"), Color("#c6a06b"), 3, 7))
	_timeline.add_theme_stylebox_override("grabber_area_highlight", _box(Color("#a87b4b"), Color("#e0bc80"), 3, 7))
	var thumb := UiGlyphs.playhead()
	_timeline.add_theme_icon_override("grabber", thumb)
	_timeline.add_theme_icon_override("grabber_highlight", thumb)
	_timeline.value_changed.connect(func(value: float):
		stage.seek(value)
		_sync_timeline_readout(value)
	)
	timeline_controls.add_child(_timeline)

	_ruler = TimelineRuler.new()
	timeline_controls.add_child(_ruler)
	dock.resized.connect(func():
		var compact := dock.size.x < 930.0
		_transport_clip.custom_minimum_size.x = 125.0 if compact else 247.0
		_time.custom_minimum_size.x = 124.0 if compact else 210.0
	)


func _make_inspector(parent: VBoxContainer) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size.x = 340
	card.size_flags_vertical = SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _box(INK, BORDER, 2, 1))
	parent.add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 7)
	card.add_child(column)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 0)
	tabs.custom_minimum_size.y = 49.0
	column.add_child(tabs)
	var group := ButtonGroup.new()
	var active := UiGlyphs.active_tab()
	for index in 2:
		var tab := Button.new()
		tab.text = ["Materiál", "Osvětlení"][index]
		tab.icon = UiGlyphs.texture(["layers", "sun"][index], GOLD, 23)
		tab.alignment = HORIZONTAL_ALIGNMENT_LEFT
		tab.size_flags_horizontal = SIZE_EXPAND_FILL
		tab.size_flags_stretch_ratio = 0.76 if index == 0 else 1.0
		tab.toggle_mode = true
		tab.button_group = group
		tab.add_theme_font_size_override("font_size", 16)
		tab.add_theme_constant_override("h_separation", 10)
		tab.add_theme_stylebox_override("normal", _box(INK, BORDER, 1, 10))
		tab.add_theme_stylebox_override("hover", _box(Color("#282522"), BORDER, 1, 10))
		tab.add_theme_stylebox_override("pressed", active)
		tab.add_theme_stylebox_override("hover_pressed", active)
		tab.add_theme_color_override("font_pressed_color", Color("#eed398"))
		tab.pressed.connect(func(): focus_inspector(_material_section if index == 0 else _lighting_section))
		_inspector_tabs.append(tab)
		tabs.add_child(tab)
	_inspector_tabs[0].set_pressed_no_signal(true)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	column.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	_inspector_scroll = scroll
	_inspector_list = list
	_material_section = _section(list, "Materiál", true, true)
	_editor_materials = MaterialInspector.new()
	_material_section.add_child(_editor_materials)
	var model := _section(list, "Model a LOD")
	var model_options := HFlowContainer.new()
	model.add_child(model_options)
	model_options.add_child(_vehicle_picker)
	model_options.add_child(_lod_picker)
	_model_section = model.get_parent() as Control
	_model_section.hide()
	var lighting := _section(list, "Osvětlení", false, true, "sun")
	_lighting_section = lighting
	var preset := HBoxContainer.new()
	lighting.add_child(preset)
	_label(preset, "Předvolba", 14, WHITE).custom_minimum_size.x = 84
	_hdri_picker = OptionButton.new()
	_hdri_picker.size_flags_horizontal = SIZE_EXPAND_FILL
	for label in ["Venku · zataženo", "Čistá obloha", "Měsíční světlo"]:
		_hdri_picker.add_item(label)
	_hdri_picker.select(0)
	_hdri_picker.tooltip_text = "Vestavěná panoramata Poly Haven"
	_hdri_picker.item_selected.connect(_choose_hdri)
	preset.add_child(_hdri_picker)
	_primary_light(lighting, "intensity", "Klíčové světlo", 5.0, 1.0, stage.light_intensity)
	_primary_light(lighting, "fill", "Výplňové světlo", 3.0, 0.30, stage.fill_intensity)
	_primary_light(lighting, "rim", "Obrysové světlo", 3.0, 0.15, stage.rim_intensity)
	_make_light_direction(lighting)
	lighting = _section(list, "Rozšířené osvětlení", true, false)
	_hdri_name = _label(lighting, "", 13, MUTED)
	_hdri_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_hdri_name.hide()
	var actions := HBoxContainer.new()
	lighting.add_child(actions)
	_button(actions, "Načíst HDRI", func(): _hdri_dialog.popup_centered_ratio(0.64))
	_button(actions, "Obnovit HDRI", func(): _with_loading(HDRI_NAMES[0], _reset_hdri))
	var sky := HBoxContainer.new()
	lighting.add_child(sky)
	_sky_picker = OptionButton.new()
	_sky_picker.size_flags_horizontal = SIZE_EXPAND_FILL
	for name in ["Obloha HDRI", "Den · Slunce", "Noc · Měsíc", "Cyklus dne a noci"]:
		_sky_picker.add_item(name)
	_sky_picker.select(0)
	_sky_picker.item_selected.connect(func(index: int):
		_with_loading(tr(_sky_picker.get_item_text(index)), _select_sky.bind(index, true))
	)
	sky.add_child(_sky_picker)
	_aim_light = _button(sky, "Ukázat zdroj", _aim_at_light)
	_aim_light.disabled = true
	_make_day_cycle_controls(lighting)
	_toggle(lighting, "sky_source", "Zobrazit zdroj světla", true, stage.source_visible)
	var switches := HBoxContainer.new()
	lighting.add_child(switches)
	_toggle(switches, "hdri_on", "HDRI", true, stage.hdri_enabled)
	_toggle(switches, "light_on", "Přímé světlo", true, stage.light_enabled)
	_toggle(switches, "reflections", "Odrazy HDRI", true, stage.reflections_enabled)
	_slider(lighting, "hdri_intensity", "Intenzita HDRI", 0.0, 3.0, 0.05, 1.0, stage.hdri_intensity)
	_slider(lighting, "hdri_rotation", "Otočení HDRI", -180.0, 180.0, 1.0, 0.0,
		func(v: float): stage.hdri_orientation(v), "°")
	_slider(lighting, "azimuth", "Azimut světla", -180.0, 180.0, 1.0, _azimuth, _set_azimuth, "°")
	_slider(lighting, "elevation", "Výška světla", -5.0, 90.0, 1.0, _elevation, _set_elevation, "°")

	_section(list, "Přehrávání animace").add_child(_animation_controls)
	_parts_section = _section(list, "Díly a materiály", true, false)
	_make_parts(_parts_section)
	var viewing := _section(list, "Zobrazení", true)
	var background := HBoxContainer.new()
	viewing.add_child(background)
	_background_option = OptionButton.new()
	_background_option.size_flags_horizontal = SIZE_EXPAND_FILL
	for item in ["Neutrální", "Tmavé", "Světlé", "Panorama HDRI", "Vlastní barva"]:
		_background_option.add_item(item)
	_background_option.item_selected.connect(_set_background)
	background.add_child(_background_option)
	_background_color = ColorPickerButton.new()
	_background_color.color = Color("#55575c")
	_background_color.edit_alpha = false
	_background_color.custom_minimum_size.x = 42
	_background_color.color_changed.connect(_choose_background_color)
	background.add_child(_background_color)
	_display = OptionButton.new()
	for item in ["Materiály", "Wireframe", "Bez osvětlení", "Normály", "Overdraw", "Body", "Quady (odhad)",
		"Vertex barvy", "UV0 · šachovnice", "UV2 · šachovnice"]:
		_display.add_item(item)
	_display.item_selected.connect(_choose_display)
	viewing.add_child(_display)
	_color_controls = HBoxContainer.new()
	viewing.add_child(_color_controls)
	_color_layer = OptionButton.new()
	_color_layer.tooltip_text = "Zdrojová vrstva vertex barev"
	_color_layer.size_flags_horizontal = SIZE_EXPAND_FILL
	_color_layer.add_item("COLOR_0")
	_color_layer.select(0)
	_color_layer.item_selected.connect(func(index: int):
		_with_loading(_color_layer.get_item_text(index), _update_color_preview)
	)
	_color_controls.add_child(_color_layer)
	_color_channel = OptionButton.new()
	_color_channel.tooltip_text = "Barevný kanál"
	for channel in ["RGB", "R", "G", "B", "A"]:
		_color_channel.add_item(channel)
	_color_channel.select(0)
	_color_channel.item_selected.connect(func(index: int):
		_with_loading(tr(_color_channel.get_item_text(index)), _update_color_preview)
	)
	_color_controls.add_child(_color_channel)
	_color_controls.hide()
	_attribute_hint = _label(viewing, "Pruhy označují plochy bez vybraného atributu.", 12, MUTED)
	_attribute_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_attribute_hint.hide()
	var aids := GridContainer.new()
	aids.columns = 2
	aids.add_theme_constant_override("h_separation", 16)
	viewing.add_child(aids)
	_toggle(aids, "background_on", "Zobrazit pozadí", true, stage.background_enabled)
	_toggle(aids, "auto_rotate", "Automatické otáčení", false, stage.auto_rotate_enabled)
	_wire_in_view = _toggle(aids, "", "Wireframe", false,
		func(value: bool): _choose_display(Stage.WIREFRAME_MODE if value else 0))
	_toggle(aids, "skeleton", "Kostra", false, stage.skeleton_visible)
	var grid_toggle := _toggle(aids, "grid", "Mřížka", true, stage.grid_visible)
	stage.grid_visible(true)
	var floor_row := HBoxContainer.new()
	aids.add_child(floor_row)
	var floor_toggle := _toggle(floor_row, "floor", "Podlaha", true, stage.floor_visible)
	stage.floor_visible(true)
	floor_toggle.size_flags_horizontal = SIZE_EXPAND_FILL
	_floor_color = ColorPickerButton.new()
	_floor_color.color = Stage.DEFAULT_FLOOR_COLOR
	_floor_color.edit_alpha = false
	_floor_color.custom_minimum_size.x = 36
	_floor_color.color_changed.connect(stage.set_floor_color)
	floor_row.add_child(_floor_color)
	_toggle(aids, "screen_space_pan", "Posun v rovině pohledu", true, stage.screen_space_panning)
	var projection_toggle := _toggle(aids, "ortho", "Orto", false, stage.orthographic)
	projection_toggle.toggled.connect(func(ortho: bool): _viewport_projection.select(int(ortho)))
	var placement := HBoxContainer.new()
	viewing.add_child(placement)
	var model_axes := _toggle(placement, "model_axes", "Osy modelu", false, stage.set_model_gizmo_enabled)
	model_axes.size_flags_horizontal = SIZE_EXPAND_FILL
	model_axes.tooltip_text = "Tažením šipky model posuneš, tažením kruhu jej otočíš."
	var reset_placement := _button(placement, "Obnovit polohu", stage.reset_model_transform)
	reset_placement.hide()
	model_axes.toggled.connect(reset_placement.set_visible)
	_floor_height_row = HBoxContainer.new()
	viewing.add_child(_floor_height_row)
	var floor_height_caption := _label(_floor_height_row, "Posun podlahy", 13, MUTED)
	floor_height_caption.size_flags_horizontal = SIZE_EXPAND_FILL
	_floor_offset = SpinBox.new()
	_floor_offset.min_value = -1000.0
	_floor_offset.max_value = 1000.0
	_floor_offset.step = 0.01
	_floor_offset.suffix = "m"
	_floor_offset.custom_minimum_size.x = 112
	_floor_offset.value_changed.connect(stage.set_floor_offset)
	_floor_height_row.add_child(_floor_offset)
	_floor_height_row.hide()
	floor_toggle.toggled.connect(func(_enabled: bool): _refresh_floor_height())
	grid_toggle.toggled.connect(func(_enabled: bool): _refresh_floor_height())
	_point_size_row = _slider(viewing, "point_size", "Velikost bodů", 1.0, 12.0, 0.1, 4.2, stage.set_point_size, " px")
	_wireframe_width_row = _slider(viewing, "wireframe_width", "Tloušťka čar",
		Stage.WIREFRAME_WIDTH_MIN, Stage.WIREFRAME_WIDTH_MAX, 0.1, Stage.WIREFRAME_WIDTH_DEFAULT,
		stage.set_wireframe_width, " px")
	_point_size_row.hide()
	_wireframe_width_row.hide()

	var geometry := _section(list, "Geometrie")
	_geometry = _label(geometry, "—", 14, MUTED)
	_geometry.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lod_table = GridContainer.new()
	_lod_table.columns = 4
	_lod_table.add_theme_constant_override("h_separation", 10)
	_lod_table.add_theme_constant_override("v_separation", 4)
	geometry.add_child(_lod_table)
	_lod_table.hide()
	var materials := _section(list, "Materiály a diagnostika")
	_textures_button = _button(materials, "Načíst textury…", _choose_texture_directory)
	_textures_button.disabled = true
	_diagnostics = _label(materials, "—", 13, MUTED)
	_diagnostics.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return card


func _refresh_floor_height() -> void:
	_floor_height_row.visible = _options["floor"].button_pressed or _options["grid"].button_pressed


func _primary_light(parent: VBoxContainer, id: String, title: String, maximum: float,
		initial: float, changed: Callable) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	_label(row, title, 14, MUTED).size_flags_horizontal = SIZE_EXPAND_FILL
	var input := SpinBox.new()
	input.min_value = 0.0
	input.max_value = maximum
	input.step = 0.01
	input.value = initial
	row.add_child(input)
	var slider := HSlider.new()
	slider.max_value = maximum
	slider.step = 0.01
	slider.value = initial
	slider.custom_minimum_size.y = 22.0
	parent.add_child(slider)
	_options[id] = slider
	input.value_changed.connect(func(value: float): slider.value = value)
	slider.value_changed.connect(func(value: float):
		input.set_value_no_signal(value)
		changed.call(value)
	)


func _make_light_direction(parent: VBoxContainer) -> void:
	_label(parent, "Směr", 14, WHITE)
	var row := HBoxContainer.new()
	parent.add_child(row)
	_light_dial = LightDirectionDial.new()
	row.add_child(_light_dial)
	_light_dial.update_direction(_azimuth, _elevation)
	var values := VBoxContainer.new()
	values.size_flags_horizontal = SIZE_EXPAND_FILL
	values.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(values)
	_light_azimuth = _make_direction_number(values, "Azimut", -180.0, 180.0, _azimuth, _set_azimuth)
	_light_elevation = _make_direction_number(values, "Výška", -5.0, 90.0, _elevation, _set_elevation)
	_light_dial.moved.connect(func(azimuth: float, elevation: float):
		_light_azimuth.value = azimuth
		_light_elevation.value = elevation
	)


func _make_direction_number(parent: VBoxContainer, title: String, low: float, high: float,
		value: float, callback: Callable) -> SpinBox:
	var row := HBoxContainer.new()
	parent.add_child(row)
	_label(row, title, 14, MUTED).size_flags_horizontal = SIZE_EXPAND_FILL
	var control := SpinBox.new()
	control.min_value = low
	control.max_value = high
	control.step = 0.1
	control.value = value
	control.suffix = "°"
	control.value_changed.connect(callback)
	row.add_child(control)
	return control


func add_inspector_tool_group(title: String, controls: Container) -> VBoxContainer:
	var group := VBoxContainer.new()
	_inspector_list.add_child(group)
	_inspector_list.move_child(group, 0)
	_section(group, title).add_child(controls)
	group.hide()
	return group


func focus_inspector(control: Control) -> void:
	if control == _material_section or control == _lighting_section:
		for index in _inspector_tabs.size():
			_inspector_tabs[index].set_pressed_no_signal(index == int(control == _lighting_section))
		control.show()
	if _inspector_panel.mode != PanelMode.PINNED:
		_set_panel_mode(_inspector_panel, PanelMode.PINNED, false)
	_inspector_scroll.ensure_control_visible.call_deferred(control)


func _section(parent: VBoxContainer, title: String, foldable := false, expanded := true, glyph := "") -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(PANEL, BORDER, 2, 10))
	parent.add_child(panel)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 6)
	panel.add_child(layout)
	if not foldable:
		if glyph.is_empty():
			_label(layout, title, 16, GOLD)
		else:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 10)
			layout.add_child(row)
			var icon := TextureRect.new()
			icon.texture = UiGlyphs.texture(glyph, GOLD, 21)
			icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
			row.add_child(icon)
			_label(row, title, 16, Color("#ead4ad"))
		return layout
	var heading := Button.new()
	heading.text = title
	heading.icon = UiGlyphs.texture("chevron_down" if expanded else "chevron_right", GOLD, 14)
	heading.alignment = HORIZONTAL_ALIGNMENT_LEFT
	heading.flat = true
	heading.add_theme_constant_override("h_separation", 8)
	heading.add_theme_color_override("font_color", GOLD)
	heading.add_theme_font_size_override("font_size", 16)
	heading.add_theme_stylebox_override("normal", _box(Color.TRANSPARENT, Color.TRANSPARENT, 2, 0))
	heading.add_theme_stylebox_override("hover", _box(PANEL.lightened(0.06), BORDER, 4, 0))
	layout.add_child(heading)
	var content := VBoxContainer.new()
	content.visible = expanded
	content.add_theme_constant_override("separation", 6)
	layout.add_child(content)
	heading.pressed.connect(func():
		content.visible = not content.visible
		heading.icon = UiGlyphs.texture("chevron_down" if content.visible else "chevron_right", GOLD, 14)
	)
	return content


func _toggle(parent: Container, id: String, title: String, initial: bool, action: Callable) -> CheckBox:
	var button := CheckBox.new()
	button.text = title
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_stylebox_override("normal", _box(Color("#262526"), BORDER, 5, 4))
	button.add_theme_stylebox_override("hover", _box(Color("#333132"), BORDER, 5, 4))
	button.add_theme_stylebox_override("pressed", _box(Color("#292721"), GOLD.darkened(0.25), 5, 4))
	button.set_pressed_no_signal(initial)
	button.toggled.connect(action)
	parent.add_child(button)
	if not id.is_empty():
		_options[id] = button
	return button


func _choose_display(index: int) -> void:
	if stage.model and (index == Stage.WIREFRAME_MODE or index >= Stage.POINTS_MODE):
		_with_loading(tr(_display.get_item_text(index)), _set_display.bind(index))
	else:
		_set_display(index)


func _set_display(index: int) -> void:
	stage.display_mode(index)
	_display.select(index)
	_color_controls.visible = index == Stage.COLOR_MODE
	_attribute_hint.visible = index >= Stage.COLOR_MODE
	var wireframe := index == Stage.WIREFRAME_MODE
	_wire_in_view.set_pressed_no_signal(wireframe)
	_wireframe_width_row.visible = wireframe
	_point_size_row.visible = index == Stage.POINTS_MODE
	if stage.model:
		_refresh_geometry()


func _refresh_color_layers(requested := "COLOR_0") -> void:
	_color_layer.clear()
	var layers := stage.model.color_layers()
	if layers.is_empty():
		layers.append("COLOR_0")
	for layer in layers:
		_color_layer.add_item(layer)
	_color_layer.select(maxi(0, layers.find(requested)))
	_update_color_preview()


func _update_color_preview() -> void:
	stage.color_preview(_color_layer.get_item_text(_color_layer.selected), _color_channel.selected)


func _make_parts(panel: VBoxContainer) -> void:
	_parts = Tree.new()
	_parts.hide_root = true
	_parts.custom_minimum_size.y = 152
	_parts.item_selected.connect(_refresh_part_actions)
	_parts.item_activated.connect(_isolate_selected)
	panel.add_child(_parts)
	var buttons := HBoxContainer.new()
	panel.add_child(buttons)
	_isolate_button = _button(buttons, "Izolovat", _isolate_selected)
	_show_all_button = _button(buttons, "Zobrazit vše", _show_all_parts)
	_refresh_part_actions()


func _refresh_parts() -> void:
	_parts.clear()
	var slots: Array[Dictionary]
	_part_rows.clear()
	var root := _parts.create_item()
	for instance in stage.model.meshes:
		var path := str(stage.model.root.get_path_to(instance))
		var row := _add_part_row(root, str(instance.name), path, -1, instance)
		for surface in range(instance.mesh.get_surface_count()):
			var material := stage.model.surface_material_name(instance, surface)
			var name := material if not material.is_empty() else tr("Bez názvu")
			_add_part_row(row, "%d · %s" % [surface + 1, name], path, surface, instance, material)
			slots.append({"label": name, "node": path, "instance": instance, "surface": surface})
		row.collapsed = true
	_editor_materials.set_slots(slots)
	_outline.rebuild(stage, _path, slots)
	_refresh_part_actions()


func _add_part_row(parent: TreeItem, label: String, path: String, surface: int, instance: MeshInstance3D, material := "") -> TreeItem:
	var item := _parts.create_item(parent)
	item.set_text(0, label)
	item.set_tooltip_text(0, path if surface < 0 else "%s · %s" % [path, label])
	item.set_metadata(0, {"node": path, "surface": surface, "instance": instance, "material": material})
	if not _part_rows.has(path):
		_part_rows[path] = {}
	_part_rows[path][surface] = item
	return item


func _part_row(state: Variant) -> TreeItem:
	if not state is Dictionary or not state.get("node") is String:
		return null
	var surface: Variant = state.get("surface")
	if not (surface is int or surface is float) or not is_finite(float(surface)) or surface < -1:
		return null
	var rows: Dictionary = _part_rows.get(state.node, {})
	var row := rows.get(int(surface)) as TreeItem
	var material: Variant = state.get("material", "")
	if surface < 0 or not material is String or material.is_empty():
		return row
	if row and row.get_metadata(0).material == material:
		return row
	var match_row: TreeItem
	for index: int in rows:
		if index >= 0 and rows[index].get_metadata(0).material == material:
			if match_row:
				return null
			match_row = rows[index]
	return match_row


func _restore_part_selection(selected: Variant, isolated: Variant) -> void:
	var isolation := _part_row(isolated)
	if isolation:
		var data: Dictionary = isolation.get_metadata(0)
		stage.isolate(data.instance, data.surface)
	var row := _part_row(selected)
	if row:
		row.get_parent().collapsed = false
		row.select(0)
	_refresh_part_actions()


func _refresh_part_actions() -> void:
	_isolate_button.disabled = _parts.get_selected() == null
	_show_all_button.disabled = stage.isolation_state().is_empty()


func _isolate_selected() -> void:
	var row := _parts.get_selected()
	if row:
		var data: Dictionary = row.get_metadata(0)
		stage.isolate(data.instance, data.surface)
		_refresh_part_actions()


func _show_all_parts() -> void:
	stage.isolate(null)
	_refresh_part_actions()


func _set_background(index: int) -> void:
	stage.background(index)
	_background_option.select(index)


func _choose_background_color(color: Color) -> void:
	stage.custom_background(color)
	_set_background(4)


func _make_day_cycle_controls(parent: VBoxContainer) -> void:
	_cycle_controls = VBoxContainer.new()
	parent.add_child(_cycle_controls)
	_toggle(_cycle_controls, "cycle_play", "Přehrávat cyklus", false, stage.sky_cycle_play)
	_slider(_cycle_controls, "cycle_seconds", "Délka cyklu", 10.0, 180.0, 1.0, 45.0, stage.sky_cycle_duration, " s")
	var row := HBoxContainer.new()
	_cycle_controls.add_child(row)
	_label(row, "Čas dne", 13, MUTED).custom_minimum_size.x = 111
	_cycle_clock = HSlider.new()
	_cycle_clock.max_value = 1439.0 / 60.0
	_cycle_clock.step = 1.0 / 60.0
	_cycle_clock.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(_cycle_clock)
	_cycle_time = _label(row, "", 13, WHITE)
	_cycle_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_cycle_time.custom_minimum_size.x = 44
	_cycle_clock.value_changed.connect(func(hour: float):
		stage.sky_cycle_seek(hour)
		_refresh_cycle_clock()
	)
	_options["cycle_hour"] = _cycle_clock
	_refresh_cycle_clock()
	_cycle_controls.hide()


func _refresh_cycle_clock() -> void:
	var minutes := roundi(stage.cycle_hour * 60.0) % 1440
	_cycle_clock.set_value_no_signal(float(minutes) / 60.0)
	_cycle_time.text = "%02d:%02d" % [floori(minutes / 60.0), minutes % 60]


func _slider(parent: VBoxContainer, id: String, title: String, low: float, high: float, step: float,
		start: float, callback: Callable, unit := "") -> HBoxContainer:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var caption := _label(row, title, 13, MUTED)
	caption.custom_minimum_size.x = 111
	var slider := HSlider.new()
	slider.size_flags_horizontal = SIZE_EXPAND_FILL
	slider.min_value = low
	slider.max_value = high
	slider.step = step
	slider.value = start
	row.add_child(slider)
	var value := _label(row, _number(start, step, unit), 13, WHITE)
	value.custom_minimum_size.x = 44
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	slider.value_changed.connect(func(d: float):
		value.text = _number(d, step, unit)
		callback.call(d)
	)
	_options[id] = slider
	return row


func _number(value: float, step: float, unit: String) -> String:
	return (("%.0f" if step >= 1.0 else "%.2f") % value) + unit


func _label(parent: Container, title: String, size_px: int, text_color: Color) -> Label:
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", text_color)
	parent.add_child(label)
	return label


func _heading(parent: Container, title: String, size_px: int, text_color: Color) -> Label:
	var label := _label(parent, title, size_px, text_color)
	label.add_theme_font_override("font", _headings)
	return label


func _icon(parent: Container, extent: int) -> TextureRect:
	var art := TextureRect.new()
	art.texture = APP_ICON
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.custom_minimum_size = Vector2.ONE * extent
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(art)
	return art


func _button(parent: Container, title: String, clicked: Callable, tip := "", primary := false) -> Button:
	var button := Button.new()
	button.text = title
	button.tooltip_text = tip
	if primary:
		button.add_theme_stylebox_override("normal", _box(GOLD, GOLD, 7, 9))
		button.add_theme_stylebox_override("hover", _box(Color("#f7ce95"), GOLD, 7, 9))
		button.add_theme_stylebox_override("pressed", _box(Color("#d6a561"), GOLD, 7, 9))
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			button.add_theme_color_override(state, INK)
	button.pressed.connect(clicked)
	parent.add_child(button)
	return button


func _viewer_theme() -> Theme:
	var result := Theme.new()
	var ui_font := SystemFont.new()
	ui_font.font_names = PackedStringArray(["Segoe UI", "Inter", "Noto Sans", "DejaVu Sans"])
	result.default_font = ui_font
	result.default_font_size = 15
	result.set_stylebox("scroll", "VScrollBar", _box(INK, Color.TRANSPARENT, 0, 2))
	result.set_stylebox("grabber", "VScrollBar", _box(Color("#4d4946"), Color.TRANSPARENT, 3, 3))
	result.set_stylebox("grabber_highlight", "VScrollBar", _box(Color("#6d655c"), Color.TRANSPARENT, 3, 3))
	result.set_icon("grabber", "HSlider", UiGlyphs.texture("dot", GOLD, 15))
	result.set_icon("grabber_highlight", "HSlider", UiGlyphs.texture("dot", GOLD.lightened(0.12), 15))
	result.set_stylebox("panel", "Tree", _box(INK, Color.TRANSPARENT, 0, 2))
	result.set_stylebox("selected", "Tree", _box(Color("#473c33"), Color.TRANSPARENT, 4, 3))
	result.set_stylebox("selected_focus", "Tree", _box(Color("#473c33"), Color.TRANSPARENT, 4, 3))
	result.set_color("font_color", "Tree", WHITE)
	result.set_color("font_selected_color", "Tree", WHITE)
	result.set_constant("item_margin", "Tree", 20)
	result.set_constant("v_separation", "Tree", 5)
	for control_type in ["Button", "OptionButton"]:
		result.set_color("font_color", control_type, WHITE)
		result.set_color("font_hover_color", control_type, WHITE)
		result.set_color("font_pressed_color", control_type, GOLD)
		result.set_color("font_disabled_color", control_type, MUTED.darkened(0.35))
		result.set_stylebox("normal", control_type, _box(Color("#262526"), BORDER, 7, 8))
		result.set_stylebox("hover", control_type, _box(Color("#333132"), BORDER.lightened(0.2), 7, 8))
		result.set_stylebox("pressed", control_type, _box(Color("#4a3d30"), GOLD.darkened(0.25), 7, 8))
		result.set_stylebox("disabled", control_type, _box(PANEL, BORDER.darkened(0.2), 7, 8))
		result.set_stylebox("focus", control_type, _box(Color.TRANSPARENT, GOLD, 7, 8))
	result.set_stylebox("slider", "HSlider", _box(Color("#454242"), Color("#454242"), 2, 2))
	result.set_stylebox("grabber_area", "HSlider", _box(GOLD.darkened(0.28), GOLD.darkened(0.28), 2, 2))
	result.set_stylebox("grabber_area_highlight", "HSlider", _box(GOLD, GOLD, 2, 2))
	return result


func _box(fill: Color, outline: Color, radius: int, margin: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = outline
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(margin)
	return style


func _dialog(title: String, mode: FileDialog.FileMode, filter: String) -> FileDialog:
	var dialog := FileDialog.new()
	dialog.title = title
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = mode
	dialog.use_native_dialog = true
	dialog.filters = PackedStringArray([filter])
	add_child(dialog)
	return dialog


func _show_open() -> void:
	if not _loading:
		_open_dialog.popup_centered_ratio(0.64)


func _choose_texture_directory() -> void:
	if _path.is_empty() or _loading or stage.capture_in_progress:
		return
	var folder := _path.get_base_dir()
	var parent := folder.get_base_dir()
	_textures_dialog.current_dir = parent if DirAccess.dir_exists_absolute(parent) else folder
	_textures_dialog.popup_centered_ratio(0.64)


func _show_capture() -> void:
	if _path.is_empty() or _loading or stage.capture_in_progress:
		return
	_save_dialog.current_file = _path.get_file().get_basename() + "-4K.png"
	_save_dialog.popup_centered_ratio(0.64)


func _files_dropped(files: PackedStringArray) -> void:
	if _loading or stage.capture_in_progress:
		return
	for path in files:
		var extension := path.get_extension().to_lower()
		if extension in _model_extensions() or extension in ["wobview", "json"]:
			_open_path(path)
			return
		if extension in ["hdr", "exr"]:
			_load_hdri(path, true)
			return
	_feedback(_unsupported_drop_message(), true)


func _model_extensions() -> PackedStringArray:
	return PackedStringArray(["glb", "gltf", "fbx"])


func _picker_model_extensions() -> PackedStringArray:
	return _model_extensions()


func _unsupported_drop_message() -> String:
	return "Otevři GLB, glTF, FBX, WOBVIEW, manifest vozu, HDR nebo EXR."


func _model_importer(path: String) -> Stage.Materials:
	return FbxMaterials.new() if path.get_extension().to_lower() == "fbx" else Stage.Materials.new()


func _model_file_bytes() -> int:
	if stage.model is FbxMaterials:
		return stage.model.file_bytes
	return stage.model.source.bytes.size()


func _original_materials_description() -> String:
	if stage.model is FbxMaterials:
		return tr("Vykreslení podle importovaných materiálů FBX.")
	return tr("Vykreslení podle materiálů GLB.")


func _open_path(path: String) -> bool:
	if _loading or stage.capture_in_progress:
		return false
	if path.get_extension().to_lower() == "wobview":
		return await _open_view(path)
	if path.get_extension().to_lower() == "json":
		if path.get_file().to_lower().ends_with("_atlas.json"):
			_feedback("Atlasové JSON obsahuje rozložení UV. Otevři manifest vozu nebo GLB.", true)
			return false
		var manifest := VehicleManifest.read(path)
		if not manifest:
			_feedback("JSON není platný manifest vozu Wars of Bohemia.", true)
			return false
		var state := "cely" if manifest.states.has("cely") else str(manifest.states.keys()[0])
		return await _load_model(manifest.states[state][0].path, false, manifest)
	return await _load_model(path)


func _load_model(path: String, keep_lod_family := false, manifest: RefCounted = null,
		texture_directory := "") -> bool:
	if not _begin_loading(path.get_file(), path):
		return false
	var load_started := Time.get_ticks_msec()
	var importer := _model_importer(path)
	importer.texture_directory = texture_directory
	importer.texture_cache = _texture_cache
	var loaded: Variant = await _run_worker(_prepare_model.bind(importer, path, manifest, not keep_lod_family))
	var prepare_ms := Time.get_ticks_msec() - load_started
	var error := tr("Načítání se nepodařilo spustit.")
	if loaded is Dictionary:
		error = stage.apply_prepared_model(loaded.model) if loaded.error.is_empty() else loaded.error
	if not error.is_empty():
		_finish_loading()
		_feedback(error, true, PackedStringArray([path.get_file()]))
		return false
	_path = path
	_texture_directory = texture_directory
	_textures_button.disabled = not path.get_extension().to_lower() in ["glb", "gltf"]
	_view_path = ""
	_open_dialog.current_dir = path.get_base_dir()
	if not keep_lod_family:
		_lod_entries = loaded.lods
		for entry: Dictionary in _lod_entries:
			if entry.path == path:
				entry.merge({"vertices": stage.geometry.z, "triangles": stage.geometry.w,
					"bytes": _model_file_bytes()}, true)
		if _lod_entries.size() > 1:
			_complete_lod_stats.call_deferred(_lod_entries)
	_refresh_vehicle_options()
	_refresh_lod_options()
	_refresh_menu()
	_refresh_clips()
	_refresh_parts()
	_refresh_color_layers(_color_layer.get_item_text(_color_layer.selected))
	_refresh_model_info()
	_finish_loading()
	if "--debug-load" in OS.get_cmdline_user_args():
		print("LOAD_TIMING ", path.get_file(), " total=", Time.get_ticks_msec() - load_started,
			" ms prepare=", prepare_ms, " ms phases=", importer.load_timings)
	if DisplayServer.get_name() == "headless":
		print(path.get_file(), " ", stage.geometry, " ", stage.model.counts, " | ", stage.model.notes)
	return true


static func _prepare_model(pending: Stage.Materials, path: String, manifest: RefCounted, scan_lods: bool) -> Dictionary:
	var error := pending.prepare_model(path, manifest)
	var lods: Array[Dictionary]
	if error.is_empty() and scan_lods:
		var vehicle: RefCounted = pending.vehicle
		var state := pending.vehicle_state
		lods = LodCatalog.from_manifest(vehicle.states[state]) if vehicle and not state.is_empty() else LodCatalog.discover(path)
	return {"model": pending, "error": error, "lods": lods}


func _complete_lod_stats(entries: Array[Dictionary]) -> void:
	var pending := PackedStringArray()
	for entry: Dictionary in entries:
		if entry.bytes < 0:
			pending.append(entry.path)
	if pending.is_empty() or not is_same(entries, _lod_entries):
		return
	var stats: Variant = await _run_worker(_read_lod_stats.bind(pending))
	if not stats is Dictionary or not is_same(entries, _lod_entries):
		return
	for entry: Dictionary in entries:
		if stats.has(entry.path):
			entry.merge(stats[entry.path], true)
	_refresh_lod_options()


static func _read_lod_stats(paths: PackedStringArray) -> Dictionary:
	var stats := {}
	for path: String in paths:
		stats[path] = LodCatalog.read_stats(path)
	return stats


func _reload_model(selected_texture_directory: Variant = null) -> void:
	if _path.is_empty() or _loading or stage.capture_in_progress:
		return
	var camera := stage.camera_state()
	var placement := stage.model_transform_state()
	var isolation := stage.isolation_state()
	var hidden := stage.hidden_parts_state()
	var previews := _editor_materials.snapshot(_path)
	var row := _parts.get_selected()
	var selection: Variant = row.get_metadata(0) if row else null
	var view_path := _view_path
	var clip := str(stage.current_clip)
	var seconds := _timeline.value
	var playing := stage.animation_player != null and stage.animation_player.is_playing()
	var manifest: RefCounted
	if stage.model.vehicle:
		manifest = VehicleManifest.read(stage.model.vehicle.path)
		if not manifest or manifest.state_for(_path).is_empty():
			_feedback("Manifest vozu nelze načíst nebo už neobsahuje aktuální LOD.", true)
			return
	_texture_cache.clear()
	var folder := _texture_directory if selected_texture_directory == null else str(selected_texture_directory)
	if not await _load_model(_path, false, manifest, folder):
		return
	_view_path = view_path
	stage.restore_model_transform(placement)
	stage.restore_camera(camera, false)
	_restore_part_selection(selection, isolation)
	stage.restore_hidden_parts(hidden)
	_editor_materials.restore(previews, _path)
	_outline.rebuild(stage, _path, _editor_materials.targets)
	if _restore_clip(clip, seconds) and playing:
		_toggle_play()
	var notes := stage.model.notes.size()
	if notes:
		_set_status(tr("Model znovu načten · upozornění (%d) v diagnostice.") % notes, true)
	else:
		_set_status("Model znovu načten.", false)


func _select_lod(index: int) -> void:
	if _loading:
		return
	var previous_camera := stage.camera_state()
	var placement := stage.model_transform_state()
	if await _load_model(_lod_entries[index]["path"], true, stage.model.vehicle, _texture_directory):
		stage.restore_model_transform(placement)
		stage.restore_camera(previous_camera)
	else:
		_refresh_lod_options()


func _refresh_vehicle_options() -> void:
	_vehicle_picker.clear()
	var manifest: RefCounted = stage.model.vehicle
	_vehicle_picker.visible = manifest != null and manifest.states.size() > 1
	if not _vehicle_picker.visible:
		return
	_vehicle_picker.tooltip_text = tr("Stav vozu")
	var names := {
		"cely": "Celý", "poniceny": "Poškozený", "zniceny": "Zničený",
		"hori": "Hořící", "ohoreli": "Ohořelý",
	}
	for state in manifest.states:
		_vehicle_picker.add_item(tr(names.get(state, state)))
		if state == stage.model.vehicle_state:
			_vehicle_picker.select(_vehicle_picker.item_count - 1)


func _select_vehicle_state(index: int) -> void:
	if _loading:
		return
	var manifest: RefCounted = stage.model.vehicle
	var state: String = manifest.states.keys()[index]
	var levels: Array = manifest.states[state]
	var path: String = levels[0].path
	if _lod_picker.selected >= 0:
		var level: int = _lod_entries[_lod_picker.selected].level
		for entry: Dictionary in levels:
			if entry.level == level:
				path = entry.path
				break
	var camera := stage.camera_state()
	var placement := stage.model_transform_state()
	if await _load_model(path, false, manifest):
		stage.restore_model_transform(placement)
		stage.restore_camera(camera)
	else:
		_refresh_vehicle_options()


func _refresh_lod_options() -> void:
	_lod_picker.clear()
	_lod_picker.tooltip_text = tr("Přepnout LOD při stejném pohledu")
	for child in _lod_table.get_children():
		_lod_table.remove_child(child)
		child.queue_free()
	var comparable := _lod_entries.size() > 1
	_lod_picker.visible = comparable
	_lod_table.visible = comparable
	_model_section.visible = comparable or _vehicle_picker.visible
	if not comparable:
		return
	for title in ["LOD", "Vrcholů", "Troj.", "Soubor"]:
		_lod_cell(tr(title), GOLD)
	for index in range(_lod_entries.size()):
		var entry := _lod_entries[index]
		var title := str(entry["label"])
		_lod_picker.add_item(title)
		_lod_picker.get_popup().set_item_tooltip(index, str(entry["path"]).get_file())
		var current := str(entry["path"]).replace("\\", "/").simplify_path() \
			== _path.replace("\\", "/").simplify_path()
		var color := GOLD if current else MUTED
		if current:
			_lod_picker.select(index)
		_lod_cell(title, color)
		_lod_cell(_lod_number(int(entry["vertices"])), color)
		_lod_cell(_lod_number(int(entry["triangles"])), color)
		_lod_cell(_file_size(int(entry["bytes"])), color)


func _lod_cell(value: String, color: Color) -> void:
	var cell := _label(_lod_table, value, 12, color)
	cell.size_flags_horizontal = SIZE_EXPAND_FILL


func _lod_number(value: int) -> String:
	return str(value) if value >= 0 else "—"


func _file_size(bytes: int) -> String:
	if bytes < 0:
		return "—"
	if bytes >= 1024 * 1024:
		return "%.2f MiB" % (float(bytes) / (1024.0 * 1024.0))
	return "%.1f KiB" % (float(bytes) / 1024.0)


func _save_view() -> void:
	if _view_path.is_empty():
		_show_view_save()
	else:
		_save_view_to(_view_path)


func _show_view_save() -> void:
	if _path.is_empty():
		return
	_view_dialog.current_file = _path.get_file().get_basename() + ".wobview"
	_view_dialog.popup_centered_ratio(0.64)


func _save_view_to(path: String) -> void:
	if _path.is_empty():
		return
	if not path.to_lower().ends_with(".wobview"):
		path += ".wobview"
	var options := {}
	for key in _options:
		var control: Control = _options[key]
		options[key] = control.value if control is HSlider else control.button_pressed
	var state := {
		"model": ViewFile.pack_path(path, _path),
		"texture_directory": ViewFile.pack_path(path, _texture_directory),
		"hdri": ViewFile.pack_path(path, _hdri_path),
		"hdri_preset": _hdri_picker.selected,
		"sky_mode": _sky_picker.selected,
		"options": options,
		"background": _background_option.selected,
		"background_color": _background_color.color.to_html(),
		"floor_color": _floor_color.color.to_html(false),
		"floor_offset": _floor_offset.value,
		"display": _display.selected,
		"vertex_layer": _color_layer.get_item_text(_color_layer.selected),
		"vertex_channel": _color_channel.selected,
		"isolation": stage.isolation_state(),
		"hidden_parts": stage.hidden_parts_state(),
		"material_previews": _editor_materials.snapshot(path),
		"camera": stage.camera_state(),
		"model_transform": stage.model_transform_state(),
		"clip": str(stage.current_clip),
		"time": _timeline.value,
		"animation_speed": _speed.value,
	}
	var status := ViewFile.write(path, state)
	if status == OK:
		_view_path = path
		_feedback(tr("Relace uložena · %s") % path.get_file())
	else:
		_feedback(tr("Relaci nelze uložit (%s).") % error_string(status), true)


func _open_view(path: String) -> bool:
	var state := ViewFile.read(path, _model_extensions())
	if state.is_empty():
		_feedback("Soubor není platná relace WoB Model Viewer.", true)
		return false
	var folder: Variant = state.get("texture_directory", "")
	var texture_directory := ViewFile.unpack_path(path, folder) if folder is String else ""
	if not await _load_model(ViewFile.unpack_path(path, state["model"]), false, null, texture_directory):
		return false
	stage.restore_hidden_parts(state.get("hidden_parts", []))
	_editor_materials.restore(state.get("material_previews", []), path)
	_outline.rebuild(stage, _path, _editor_materials.targets)
	_view_path = path
	var options: Variant = state.get("options", {})
	if not options is Dictionary or not options.get("model_axes") is bool:
		_options["model_axes"].button_pressed = false
	if options is Dictionary:
		for key in _options:
			var control: Control = _options[key]
			var value: Variant = options.get(key)
			if control is HSlider and (value is float or value is int) and is_finite(float(value)):
				control.value = float(value)
			elif control is CheckBox and value is bool:
				control.button_pressed = value
	var color: Variant = state.get("background_color")
	if color is String and Color.html_is_valid(color):
		_background_color.color = Color.html(color)
		stage.custom_background(_background_color.color)
	var floor_color: Variant = state.get("floor_color")
	if floor_color is String and Color.html_is_valid(floor_color):
		_floor_color.color = Color.html(floor_color)
		stage.set_floor_color(_floor_color.color)
	var floor_offset: Variant = state.get("floor_offset")
	if (floor_offset is float or floor_offset is int) and is_finite(float(floor_offset)):
		_floor_offset.value = float(floor_offset)
	var back: Variant = state.get("background")
	if back is float or back is int:
		_set_background(clampi(int(back), 0, _background_option.item_count - 1))
	var display: Variant = state.get("display")
	var channel: Variant = state.get("vertex_channel")
	if (channel is float or channel is int) and is_finite(float(channel)):
		_color_channel.select(clampi(int(channel), 0, _color_channel.item_count - 1))
	var layer: Variant = state.get("vertex_layer", "COLOR_0")
	_refresh_color_layers(layer if layer is String else "COLOR_0")
	if (display is float or display is int) and is_finite(float(display)):
		_set_display(clampi(int(display), 0, _display.item_count - 1))
	var isolation: Variant = state.get("isolation")
	_restore_part_selection(isolation, isolation)
	var placement: Variant = state.get("model_transform")
	if placement is Dictionary:
		stage.restore_model_transform(placement)
	if state.get("camera") is Dictionary:
		stage.restore_camera(state["camera"])
	_set_animation_speed(state.get("animation_speed", Stage.ANIMATION_SPEED_DEFAULT))
	_restore_clip(str(state.get("clip", "")), state.get("time"))
	var mode: Variant = state.get("sky_mode", 0)
	_select_sky(clampi(int(mode), 0, _sky_picker.item_count - 1) if mode is float or mode is int else 0)
	_reset_hdri()
	var preset: Variant = state.get("hdri_preset", 0)
	if (preset is float or preset is int) and preset >= 0 and preset < HDRI_NAMES.size():
		_select_hdri(int(preset))
	var hdri: Variant = state.get("hdri", "")
	if hdri is String and not hdri.is_empty():
		await _load_hdri(ViewFile.unpack_path(path, hdri))
	return true


func _restore_clip(name: String, seconds: Variant) -> bool:
	for index in range(stage.clips.size()):
		if str(stage.clips[index].name) == name:
			_movie.select(index)
			_select_clip(index)
			if (seconds is float or seconds is int) and is_finite(float(seconds)):
				_timeline.set_value_no_signal(float(seconds))
				stage.seek(_timeline.value)
			return true
	return false


func _refresh_geometry() -> void:
	var metric := stage.geometry
	var extents := stage.bounds.size
	_geometry.text = tr("%s sítí   ·   %s povrchů\n%s vrcholů   ·   %s trojúhelníků\n%.3f × %.3f × %.3f m") % [
		metric.x, metric.y, metric.z, metric.w, extents.x, extents.y, extents.z,
	]
	_geometry.text += "\n" + (tr("Soubor %s · %s") % [
		_path.get_extension().to_upper(), _file_size(_model_file_bytes())
	])
	if _display.selected == 6:
		var topology := stage.quad_statistics()
		_geometry.text += "\n" + (tr("Odvozené quady %d · zbývající troj. %d") % [topology.x, topology.y])


func _refresh_model_info(announce := true) -> void:
	_refresh_geometry()
	var report := PackedStringArray()
	for key: String in stage.model.counts:
		report.append("%s  ×  %d" % [key, stage.model.counts[key]])
	if report.is_empty():
		report.append(_original_materials_description())
	for folder in stage.model.texture_folders:
		report.append(tr("Textury: %s") % folder)
	var notes := stage.model.notes
	if not notes.is_empty():
		report.append("")
		report.append_array(notes)
	_diagnostics.text = "\n".join(report)
	if not announce:
		return
	var details := PackedStringArray([_path.get_file()])
	details.append_array(notes)
	if notes.is_empty():
		_feedback("Model načten.", false, details)
	else:
		_feedback(tr("Model načten · upozornění (%d) v diagnostice.") % notes.size(), true, details)


func _refresh_clips() -> void:
	_movie.clear()
	_transport_clip.clear()
	_movie.tooltip_text = ""
	_transport_clip.tooltip_text = ""
	var available := not stage.clips.is_empty()
	_timeline.visible = available
	_ruler.visible = available
	_movie.disabled = not available
	_transport_clip.disabled = not available
	for control: BaseButton in [_play, _loop, _in_place, _transport_play, _transport_previous,
			_transport_next, _transport_loop]:
		control.disabled = not available
	_speed.editable = available
	_transport_speed.editable = available
	_timeline.editable = available
	_sync_play_buttons(false)
	_timeline.set_value_no_signal(0.0)
	if not available:
		_timeline.max_value = 0.0
		_ruler.duration = 0.0
		_movie.add_item("Bez animací")
		_transport_clip.add_item("Bez animací")
		_sync_timeline_readout(0.0)
		return
	for clip in stage.clips:
		_movie.add_item(str(clip.name))
		_transport_clip.add_item(str(clip.name))
	_select_clip(0)


func _choose_clip(index: int) -> void:
	if index < 0 or index >= stage.clips.size():
		return
	var clip := stage.clips[index]
	if stage.animation_player == clip.player and stage.current_clip == clip.name:
		return
	var playing := stage.animation_player != null and stage.animation_player.is_playing()
	_select_clip(index, playing)


func _select_clip(index: int, keep_playing := false) -> void:
	_timeline.max_value = stage.select_clip(index, keep_playing)
	_ruler.duration = _timeline.max_value
	_movie.select(index)
	_transport_clip.select(index)
	var clip_name := _movie.get_item_text(index)
	_movie.tooltip_text = clip_name
	_transport_clip.tooltip_text = clip_name
	_timeline.set_value_no_signal(0.0)
	_sync_timeline_readout(0.0)
	_sync_play_buttons(keep_playing)


func _toggle_play() -> void:
	_sync_play_buttons(stage.toggle_play())


func _sync_play_buttons(playing: bool) -> void:
	var action := "Pozastavit" if playing else "Přehrát"
	_play.text = action
	_transport_play.icon = UiGlyphs.texture("pause" if playing else "play", INK, 24)
	_transport_play.tooltip_text = tr(action) + " · " + tr("Mezerník")


func _sync_timeline_readout(seconds: float) -> void:
	_time.text = "%.2f / %.2f s" % [seconds, _timeline.max_value]


func _set_animation_speed(value: Variant) -> void:
	var speed := stage.animation_speed(value)
	_speed.set_value_no_signal(speed)
	_transport_speed.set_value_no_signal(speed)


func _process(_delta: float) -> void:
	if not stage:
		return
	if _sky_picker.selected == Stage.CYCLE_SKY_MODE:
		_refresh_cycle_clock()
	if not stage.animation_player:
		return
	var active := stage.animation_player.is_playing()
	_sync_play_buttons(active)
	_transport_loop.set_pressed_no_signal(_loop.button_pressed)
	_timeline.set_value_no_signal(stage.animation_player.current_animation_position)
	_sync_timeline_readout(_timeline.value)


func _set_azimuth(value: float) -> void:
	_azimuth = value
	_light_azimuth.set_value_no_signal(value)
	_options.azimuth.set_value_no_signal(value)
	_light_dial.update_direction(_azimuth, _elevation)
	stage.light_direction(_azimuth, _elevation)


func _set_elevation(value: float) -> void:
	_elevation = value
	_light_elevation.set_value_no_signal(value)
	_options.elevation.set_value_no_signal(value)
	_light_dial.update_direction(_azimuth, _elevation)
	stage.light_direction(_azimuth, _elevation)


func _reset_hdri() -> void:
	_hdri_path = ""
	_hdri_picker.select(0)
	_hdri_name.tooltip_text = ""
	if stage.reset_hdri():
		_hdri_name.hide()
	else:
		_hdri_name.text = "Vestavěné HDRI chybí"
		_hdri_name.show()


func _select_hdri(index: int, show_panorama := false) -> void:
	if not stage.select_hdri(index):
		_feedback("Vestavěné HDRI chybí", true)
		return
	_hdri_picker.select(index)
	_hdri_name.hide()
	_hdri_path = ""
	if show_panorama:
		_show_panorama()


func _choose_hdri(index: int) -> void:
	_with_loading(HDRI_NAMES[index], func():
		await stage.preload_hdri(index)
		_select_hdri(index, true)
	)


func _select_sky(index: int, show_panorama := false) -> void:
	_sky_picker.select(index)
	stage.sky_mode(index)
	_aim_light.disabled = index == 0
	_cycle_controls.visible = index == Stage.CYCLE_SKY_MODE
	_options["elevation"].editable = index != Stage.CYCLE_SKY_MODE
	if show_panorama:
		_show_panorama()


func _show_panorama() -> void:
	_options["background_on"].button_pressed = true
	_set_background(3)


func _aim_at_light() -> void:
	_show_panorama()
	_options["sky_source"].button_pressed = true
	_options["light_on"].button_pressed = true
	stage.aim_at_light()


func _load_hdri(path: String, show_panorama := false) -> void:
	if not _begin_loading(path.get_file(), path):
		return
	var decoded: Variant = await _run_worker(Stage.decode_hdri.bind(path))
	var error := stage.apply_hdri(decoded)
	_finish_loading()
	if not error.is_empty():
		_feedback(error, true, PackedStringArray([path.get_file()]))
		return
	_hdri_name.text = path.get_file()
	_hdri_name.show()
	_hdri_picker.select(-1)
	_hdri_path = path
	_hdri_name.tooltip_text = path
	if show_panorama:
		_show_panorama()
	_feedback("HDRI načteno.")


func _capture(path: String) -> Error:
	if not path.to_lower().ends_with(".png"):
		path += ".png"
	if not _begin_loading(path.get_file(), path, "Vykresluji snímek 4K…"):
		return ERR_BUSY
	_feedback("Vykresluji snímek 4K…")
	await _paint_loading()
	var error := await stage.screenshot(path)
	_finish_loading()
	if error == OK:
		_feedback(tr("Snímek 3840 × 2160 uložen · %s") % path)
	else:
		_feedback(tr("Snímek nelze uložit (%s).") % error_string(error), true)
	return error


func _set_status(message: String, warning: bool) -> void:
	_status.text = tr(message)
	_status.disabled = not warning
	_status.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if warning else Control.CURSOR_ARROW
	_status.tooltip_text = _status.text + ("\n" + tr("Kliknutím otevřeš protokol.") if warning else "")


func _feedback(message: String, warning := false, details := PackedStringArray()) -> void:
	_set_status(message, warning)
	var entry := "[%s] %s" % [Time.get_time_string_from_system(), _status.text]
	if not details.is_empty():
		entry += "\n" + "\n".join(details)
	_log_entries.insert(0, entry)
	if _log_entries.size() > LOG_LIMIT:
		_log_entries.resize(LOG_LIMIT)


func _initial_locale() -> String:
	var settings := ConfigFile.new()
	settings.load(SETTINGS)
	var default := "cs" if OS.get_locale_language() == "cs" else "en"
	var language := str(settings.get_value("ui", "language", default))
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--language="):
			language = argument.trim_prefix("--language=")
	return language if language in LOCALES else default


func _change_locale(index: int) -> void:
	TranslationServer.set_locale(LOCALES[index])
	var settings := ConfigFile.new()
	settings.load(SETTINGS)
	settings.set_value("ui", "language", LOCALES[index])
	settings.save(SETTINGS)
	_refresh_menu()
	_refresh_dialogs()
	_refresh_panel_handle(_toolbar_panel)
	_refresh_panel_handle(_inspector_panel)
	if stage.model:
		var row := _parts.get_selected()
		var selection: Variant = row.get_metadata(0) if row else null
		var isolation := stage.isolation_state()
		_refresh_parts()
		_restore_part_selection(selection, isolation)
		_refresh_vehicle_options()
		_refresh_lod_options()
		_refresh_model_info(false)


func _refresh_dialogs() -> void:
	_log_dialog.title = tr("Protokol prohlížeče")
	_log_dialog.ok_button_text = tr("Zavřít")
	_log_copy.text = tr("Zkopírovat protokol")
	_open_dialog.title = tr("Otevřít model")
	var model_patterns := PackedStringArray()
	for extension in _picker_model_extensions():
		model_patterns.append("*." + extension)
	model_patterns.append_array(PackedStringArray(["*.wobview", "*_manifest.json"]))
	_open_dialog.filters = PackedStringArray([",".join(model_patterns) + " ; " + tr("Model, relace nebo manifest vozu")])
	_hdri_dialog.title = tr("Otevřít HDRI")
	_textures_dialog.title = tr("Vyber složku s texturami")
	_floor_color.tooltip_text = tr("Barva podlahy")
	_floor_offset.tooltip_text = tr("Posun podlahy a mřížky od základní výšky modelu")
	_hdri_dialog.filters = PackedStringArray(["*.hdr,*.exr ; " + tr("Panorama HDRI")])
	_save_dialog.title = tr("Uložit snímek 3840 × 2160")
	_save_dialog.filters = PackedStringArray(["*.png ; " + tr("Obraz PNG")])
	_view_dialog.title = tr("Uložit relaci jako")
	_view_dialog.filters = PackedStringArray(["*.wobview ; " + tr("Relace WoB Model Viewer")])


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var key: Key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
	if key == KEY_ESCAPE and _panel_menu_owner != null:
		_dismiss_panel_menu()
	elif key == KEY_F11 or (key == KEY_ESCAPE and get_window().mode == Window.MODE_FULLSCREEN):
		if DisplayServer.get_name() != "headless":
			_toggle_fullscreen()
	elif _loading:
		if event.ctrl_pressed and key == KEY_Q:
			_request_quit()
		else:
			return
	elif key == KEY_F1:
		_show_help()
	elif event.ctrl_pressed and not event.alt_pressed:
		match key:
			KEY_O: _show_open()
			KEY_R: _reload_model()
			KEY_S:
				if event.shift_pressed:
					_show_view_save()
				else:
					_save_view()
			KEY_E: _show_capture()
			KEY_L: _show_log()
			KEY_Q: _request_quit()
			_: return
	elif stage.model and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed:
		match key:
			KEY_F, KEY_1: stage.frame()
			KEY_2: stage.frame(Vector2.ZERO)
			KEY_3: stage.frame(Vector2(PI / 2, 0.0))
			KEY_4: stage.frame(Vector2(0.0, 1.555))
			KEY_W: _toggle_display(Stage.WIREFRAME_MODE)
			KEY_Q: _toggle_display(6)
			KEY_P: _toggle_display(5)
			KEY_G: _toggle_option("grid")
			KEY_M: _toggle_option("model_axes")
			KEY_K: _toggle_option("skeleton")
			KEY_A: _toggle_option("auto_rotate")
			KEY_B: _toggle_option("background_on")
			KEY_O: _toggle_option("ortho")
			KEY_PAGEUP: _step_lod(-1)
			KEY_PAGEDOWN: _step_lod(1)
			KEY_SPACE: _toggle_play()
			_: return
	else:
		return
	get_viewport().set_input_as_handled()


func _toggle_display(mode: int) -> void:
	_choose_display(0 if _display.selected == mode else mode)


func _toggle_option(name: String) -> void:
	var control: CheckBox = _options[name]
	control.button_pressed = not control.button_pressed


func _step_lod(direction: int) -> void:
	var next := _lod_picker.selected + direction
	if _lod_entries.size() > 1 and next >= 0 and next < _lod_entries.size():
		_select_lod(next)


func _process_arguments() -> void:
	var model_path := ""
	var capture_path := ""
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		var standard := OS.get_cmdline_args()
		if standard.size() == 1 and not standard[0].begins_with("-"):
			args = standard
	for argument in args:
		if argument.begins_with("--screenshot="):
			capture_path = argument.trim_prefix("--screenshot=")
		elif not argument.begins_with("-") and model_path.is_empty():
			var extension := argument.get_extension().to_lower()
			if extension in _model_extensions() or extension in ["wobview", "json"]:
				model_path = argument
	if model_path.is_empty():
		return
	var success := await _open_path(model_path)
	if not success:
		printerr("WoB Model Viewer: ", _status.text)
	if not capture_path.is_empty():
		if not success:
			get_tree().quit(1)
			return
		var result := await _capture(capture_path)
		get_tree().quit(0 if result == OK else 1)
