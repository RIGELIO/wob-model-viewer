extends Control

const Stage = preload("res://stage.gd")
const ViewFile = preload("res://view_file.gd")
const OrientationGizmo = preload("res://orientation_gizmo.gd")
const LodCatalog = preload("res://lod_catalog.gd")
const APP_ICON = preload("res://art/icon.png")
const TITLE_FONT = preload("res://art/CormorantGaramond.ttf")
const INK := Color("#121315")
const PANEL := Color("#1a1b1e")
const BORDER := Color("#433c33")
const WHITE := Color("#f4eee2")
const MUTED := Color("#b8b1a6")
const GOLD := Color("#edbd7c")
const LOCALES := ["en", "cs"]
const SETTINGS := "user://viewer.cfg"
const VERSION := "1.0.0"
enum FileAction { OPEN, SAVE, SAVE_AS, CAPTURE, QUIT }

var stage: Stage
var _file_name: Label
var _status: Label
var _blank: CenterContainer
var _geometry: Label
var _lod_table: GridContainer
var _lod_picker: OptionButton
var _lod_entries: Array[Dictionary]
var _diagnostics: Label
var _hdri_name: Label
var _movie: OptionButton
var _play: Button
var _timeline: HSlider
var _time: Label
var _open_dialog: FileDialog
var _hdri_dialog: FileDialog
var _save_dialog: FileDialog
var _view_dialog: FileDialog
var _about: AcceptDialog
var _help: AcceptDialog
var _menu_file: MenuButton
var _menu_help: MenuButton
var _capture_button: Button
var _language: OptionButton
var _display: OptionButton
var _wire: CheckButton
var _wire_in_view: CheckBox
var _gizmo: OrientationGizmo
var _background_option: OptionButton
var _background_color: ColorPickerButton
var _options: Dictionary
var _headings: FontVariation
var _path := ""
var _view_path := ""
var _hdri_path := ""
var _azimuth := -35.0
var _elevation := 42.0


func _ready() -> void:
	TranslationServer.set_locale(_initial_locale())
	get_window().min_size = Vector2i(860, 640)
	_headings = FontVariation.new()
	_headings.base_font = TITLE_FONT
	_headings.variation_opentype = {"wght": 650}
	theme = _viewer_theme()
	var backdrop := ColorRect.new()
	backdrop.color = INK
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 13)
	margin.add_child(layout)
	_make_menu(layout)
	_make_header(layout)
	var split := HBoxContainer.new()
	split.size_flags_vertical = SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 13)
	layout.add_child(split)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = SIZE_EXPAND_FILL
	split.add_child(left)
	_make_viewport(left)
	_make_timeline(left)
	_make_inspector(split)
	_status = _label(layout, "Připraveno", 13, MUTED)
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

	_open_dialog = _dialog("Otevřít model", FileDialog.FILE_MODE_OPEN_FILE, "*.glb,*.gltf,*.wobview")
	_open_dialog.file_selected.connect(_open_path)
	_hdri_dialog = _dialog("Otevřít HDRI", FileDialog.FILE_MODE_OPEN_FILE, "*.hdr,*.exr ; Panorama HDRI")
	_hdri_dialog.file_selected.connect(_load_hdri)
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
	_refresh_menu()
	_refresh_dialogs()
	get_window().files_dropped.connect(_files_dropped)
	_process_arguments.call_deferred()


func _make_menu(layout: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	layout.add_child(row)
	_menu_file = MenuButton.new()
	_menu_file.text = "Soubor"
	_menu_file.get_popup().id_pressed.connect(_file_action)
	row.add_child(_menu_file)
	_menu_help = MenuButton.new()
	_menu_help.text = "Nápověda"
	_menu_help.get_popup().id_pressed.connect(func(id: int):
		if id == 0:
			_show_help()
		else:
			_show_about()
	)
	row.add_child(_menu_help)


func _refresh_menu() -> void:
	var menu := _menu_file.get_popup()
	menu.clear()
	menu.add_item(tr("Otevřít…"), FileAction.OPEN, KEY_MASK_CTRL | KEY_O)
	menu.add_separator()
	menu.add_item(tr("Uložit"), FileAction.SAVE, KEY_MASK_CTRL | KEY_S)
	menu.add_item(tr("Uložit jako…"), FileAction.SAVE_AS, KEY_MASK_CTRL | KEY_MASK_SHIFT | KEY_S)
	menu.add_item(tr("Uložit 4K PNG"), FileAction.CAPTURE, KEY_MASK_CTRL | KEY_E)
	menu.add_separator()
	menu.add_item(tr("Konec"), FileAction.QUIT, KEY_MASK_CTRL | KEY_Q)
	for id in [FileAction.SAVE, FileAction.SAVE_AS, FileAction.CAPTURE]:
		menu.set_item_disabled(menu.get_item_index(id), _path.is_empty())
	var help := _menu_help.get_popup()
	help.clear()
	help.add_item(tr("Ovládání"), 0, KEY_F1)
	help.add_separator()
	help.add_item(tr("O programu"), 1)


func _file_action(id: int) -> void:
	match id:
		FileAction.OPEN: _show_open()
		FileAction.SAVE: _save_view()
		FileAction.SAVE_AS: _show_view_save()
		FileAction.CAPTURE: _show_capture()
		FileAction.QUIT: get_tree().quit()


func _show_about() -> void:
	_about.title = tr("O programu")
	_about.dialog_text = "WoB Model Viewer %s\n© 2026 RIGELIO Studio\n\n%s" % [VERSION, tr(
		"Offline prohlížeč modelů GLB pro Wars of Bohemia.\nGodot 4.7.2 Forward+.\n\nLicence MIT. Licence přiložených prostředků jsou v balíčku aplikace."
	)]
	_about.popup_centered()


func _show_help() -> void:
	_help.title = tr("Ovládání WoB Model Viewer")
	_help.dialog_text = tr(
		"Přetáhni GLB, glTF, HDRI nebo uloženou relaci do okna.\n\nMyš: levé otáčí, pravé nebo prostřední posouvá, kolečko přibližuje.\nF / 1: zarámovat. 2: zepředu. 3: z boku. 4: shora.\nKlikni na osu XYZ pro pevný pohled.\n\nW: trojúhelníkový wireframe. Q: odhad quadů. P: body.\nG: mřížka. K: kostra. A: automatické otáčení.\nB: pozadí. O: ortografický pohled.\nPage Up / Page Down: předchozí / další LOD. Mezerník: animace.\n\nCtrl+O: otevřít. Ctrl+S: uložit. Ctrl+Shift+S: uložit jako.\nCtrl+E: snímek 4K. Ctrl+Q: konec. F1: nápověda."
	)
	_help.popup_centered()


func _make_header(layout: VBoxContainer) -> void:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	layout.add_child(header)
	_icon(header, 59)
	var title := VBoxContainer.new()
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(title)
	_heading(title, "WoB Model Viewer", 34, WHITE)
	_file_name = _label(title, "Žádný otevřený model", 13, MUTED)
	_file_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_button(header, "Otevřít model", _show_open, "Ctrl+O", true)
	_capture_button = _button(header, "Uložit 4K PNG", _show_capture, "Ctrl+E")
	_capture_button.disabled = true
	_language = OptionButton.new()
	_language.add_item("EN")
	_language.add_item("CS")
	_language.select(LOCALES.find(TranslationServer.get_locale()))
	_language.tooltip_text = "Language / Jazyk"
	_language.item_selected.connect(_change_locale)
	header.add_child(_language)


func _make_viewport(parent: VBoxContainer) -> void:
	var card := PanelContainer.new()
	card.size_flags_vertical = SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _box(PANEL, BORDER, 9, 7))
	parent.add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	card.add_child(column)
	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 5)
	column.add_child(toolbar)
	_button(toolbar, "Zarámovat", func(): stage.frame(), "F")
	_button(toolbar, "Zepředu", func(): stage.frame(Vector2.ZERO))
	_button(toolbar, "Z boku", func(): stage.frame(Vector2(PI / 2, 0.0)))
	_button(toolbar, "Shora", func(): stage.frame(Vector2(0.0, 1.555)))
	var spacer := Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	toolbar.add_child(spacer)
	_lod_picker = OptionButton.new()
	_lod_picker.item_selected.connect(_select_lod)
	_lod_picker.hide()
	toolbar.add_child(_lod_picker)
	_wire = CheckButton.new()
	_wire.text = "Wireframe"
	_wire.toggled.connect(func(value: bool): _set_display(1 if value else 0))
	toolbar.add_child(_wire)

	var area := Control.new()
	area.size_flags_vertical = SIZE_EXPAND_FILL
	area.clip_contents = true
	column.add_child(area)
	stage = Stage.new()
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	area.add_child(stage)
	_blank = CenterContainer.new()
	_blank.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_blank.mouse_filter = Control.MOUSE_FILTER_IGNORE
	area.add_child(_blank)
	var empty_box := VBoxContainer.new()
	empty_box.add_theme_constant_override("separation", 9)
	empty_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blank.add_child(empty_box)
	_icon(empty_box, 94).size_flags_horizontal = SIZE_SHRINK_CENTER
	_heading(empty_box, "Přetáhni sem GLB nebo glTF", 38, WHITE).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var choose := _button(empty_box, "Vybrat soubor", _show_open)
	choose.size_flags_horizontal = SIZE_SHRINK_CENTER
	_gizmo = OrientationGizmo.new()
	_gizmo.stage = stage
	_gizmo.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_gizmo.offset_left = -114
	_gizmo.offset_top = -114
	_gizmo.offset_right = -10
	_gizmo.offset_bottom = -10
	_gizmo.hide()
	area.add_child(_gizmo)
	var hint := _label(column, "  Levé tlačítko orbit  ·  Pravé nebo prostřední posun  ·  Kolečko zoom", 12, MUTED)
	hint.custom_minimum_size.y = 27
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


func _make_timeline(parent: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 41
	parent.add_child(row)
	_heading(row, "Animace", 23, GOLD).custom_minimum_size.x = 105
	_movie = OptionButton.new()
	_movie.custom_minimum_size.x = 162
	_movie.fit_to_longest_item = false
	_movie.item_selected.connect(_select_clip)
	row.add_child(_movie)
	_play = _button(row, "Přehrát", _toggle_play)
	_timeline = HSlider.new()
	_timeline.size_flags_horizontal = SIZE_EXPAND_FILL
	_timeline.step = 0.001
	_timeline.value_changed.connect(func(value: float):
		stage.seek(value)
		_time.text = "%.2f s" % value
	)
	row.add_child(_timeline)
	_time = _label(row, "0.00 s", 13, MUTED)
	_time.custom_minimum_size.x = 66
	_refresh_clips()


func _make_inspector(parent: HBoxContainer) -> void:
	var card := PanelContainer.new()
	card.custom_minimum_size.x = 340
	card.add_theme_stylebox_override("panel", _box(INK, BORDER, 10, 7))
	parent.add_child(card)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	var lighting := _section(list, "Osvětlení")
	_hdri_name = _label(lighting, "Lilienstein", 13, MUTED)
	_hdri_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var actions := HBoxContainer.new()
	lighting.add_child(actions)
	_button(actions, "Načíst HDRI", func(): _hdri_dialog.popup_centered_ratio(0.64))
	_button(actions, "Obnovit HDRI", _reset_hdri)
	var switches := HBoxContainer.new()
	lighting.add_child(switches)
	_toggle(switches, "hdri_on", "HDRI", true, stage.hdri_enabled)
	_toggle(switches, "light_on", "Přímé světlo", true, stage.light_enabled)
	_toggle(switches, "reflections", "Odrazy HDRI", true, stage.reflections_enabled)
	_slider(lighting, "hdri_intensity", "Intenzita HDRI", 0.0, 3.0, 0.05, 1.0, stage.hdri_intensity)
	_slider(lighting, "hdri_rotation", "Otočení HDRI", -180.0, 180.0, 1.0, 0.0,
		func(v: float): stage.hdri_orientation(v), "°")
	_slider(lighting, "intensity", "Intenzita světla", 0.0, 5.0, 0.05, 1.25,
		func(v: float): stage.sunlight.light_energy = v)
	_slider(lighting, "azimuth", "Azimut světla", -180.0, 180.0, 1.0, _azimuth, _set_azimuth, "°")
	_slider(lighting, "elevation", "Výška světla", -5.0, 90.0, 1.0, _elevation, _set_elevation, "°")

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
	for item in ["Materiály", "Wireframe", "Bez osvětlení", "Normály", "Overdraw", "Body", "Quady (odhad)"]:
		_display.add_item(item)
	_display.item_selected.connect(_set_display)
	viewing.add_child(_display)
	var aids := GridContainer.new()
	aids.columns = 2
	aids.add_theme_constant_override("h_separation", 16)
	viewing.add_child(aids)
	_toggle(aids, "background_on", "Zobrazit pozadí", true, stage.background_enabled)
	_toggle(aids, "auto_rotate", "Automatické otáčení", false, stage.auto_rotate_enabled)
	_wire_in_view = _toggle(aids, "", "Wireframe", false, func(value: bool): _set_display(1 if value else 0))
	_toggle(aids, "skeleton", "Kostra", false, stage.skeleton_visible)
	_toggle(aids, "grid", "Mřížka", false, stage.grid_visible)
	_toggle(aids, "floor", "Podlaha", false, stage.floor_visible)
	_toggle(aids, "screen_space_pan", "Posun v rovině pohledu", true, stage.screen_space_panning)
	_toggle(aids, "ortho", "Orto", false, stage.orthographic)
	_slider(viewing, "point_size", "Velikost bodu", 1.0, 12.0, 0.1, 4.2, stage.set_point_size)

	var geometry := _section(list, "Geometrie")
	_geometry = _label(geometry, "—", 14, MUTED)
	_geometry.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lod_table = GridContainer.new()
	_lod_table.columns = 4
	_lod_table.add_theme_constant_override("h_separation", 10)
	_lod_table.add_theme_constant_override("v_separation", 4)
	geometry.add_child(_lod_table)
	_lod_table.hide()
	_diagnostics = _label(_section(list, "Materiály a diagnostika"), "—", 13, MUTED)
	_diagnostics.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _section(parent: VBoxContainer, title: String, foldable := false) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(PANEL, BORDER, 7, 10))
	parent.add_child(panel)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 6)
	panel.add_child(layout)
	if not foldable:
		_heading(layout, title, 25, GOLD)
		return layout
	var heading := Button.new()
	heading.text = title + "  ▾"
	heading.alignment = HORIZONTAL_ALIGNMENT_LEFT
	heading.flat = true
	heading.add_theme_color_override("font_color", GOLD)
	heading.add_theme_font_override("font", _headings)
	heading.add_theme_font_size_override("font_size", 25)
	heading.add_theme_stylebox_override("normal", _box(Color.TRANSPARENT, Color.TRANSPARENT, 2, 0))
	heading.add_theme_stylebox_override("hover", _box(PANEL.lightened(0.06), BORDER, 4, 0))
	layout.add_child(heading)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	layout.add_child(content)
	heading.pressed.connect(func():
		content.visible = not content.visible
		heading.text = title + ("  ▾" if content.visible else "  ▸")
	)
	return content


func _toggle(parent: Container, id: String, title: String, initial: bool, action: Callable) -> CheckBox:
	var button := CheckBox.new()
	button.text = title
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_stylebox_override("normal", _box(Color("#232731"), BORDER, 5, 4))
	button.add_theme_stylebox_override("hover", _box(Color("#2e3036"), BORDER, 5, 4))
	button.add_theme_stylebox_override("pressed", _box(Color("#292721"), GOLD.darkened(0.25), 5, 4))
	button.set_pressed_no_signal(initial)
	button.toggled.connect(action)
	parent.add_child(button)
	if not id.is_empty():
		_options[id] = button
	return button


func _set_display(index: int) -> void:
	stage.display_mode(index)
	_display.select(index)
	_wire.set_pressed_no_signal(index == 1)
	_wire_in_view.set_pressed_no_signal(index == 1)
	if stage.model:
		_refresh_geometry()


func _set_background(index: int) -> void:
	stage.background(index)
	_background_option.select(index)


func _choose_background_color(color: Color) -> void:
	stage.custom_background(color)
	_set_background(4)


func _slider(parent: VBoxContainer, id: String, title: String, low: float, high: float, step: float,
		start: float, callback: Callable, unit := "") -> void:
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
	result.default_font_size = 15
	for control_type in ["Button", "OptionButton"]:
		result.set_color("font_color", control_type, WHITE)
		result.set_color("font_hover_color", control_type, WHITE)
		result.set_color("font_pressed_color", control_type, GOLD)
		result.set_color("font_disabled_color", control_type, MUTED.darkened(0.35))
		result.set_stylebox("normal", control_type, _box(Color("#232b38"), BORDER, 7, 8))
		result.set_stylebox("hover", control_type, _box(Color("#313a49"), BORDER.lightened(0.2), 7, 8))
		result.set_stylebox("pressed", control_type, _box(Color("#222835"), GOLD.darkened(0.25), 7, 8))
		result.set_stylebox("disabled", control_type, _box(PANEL, BORDER.darkened(0.2), 7, 8))
		result.set_stylebox("focus", control_type, _box(Color.TRANSPARENT, GOLD, 7, 8))
	result.set_stylebox("slider", "HSlider", _box(Color("#343d4b"), Color("#343d4b"), 2, 2))
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
	_open_dialog.popup_centered_ratio(0.64)


func _show_capture() -> void:
	if _path.is_empty() or stage.capture_in_progress:
		return
	_save_dialog.current_file = _path.get_file().get_basename() + "-4K.png"
	_save_dialog.popup_centered_ratio(0.64)


func _files_dropped(files: PackedStringArray) -> void:
	for path in files:
		match path.get_extension().to_lower():
			"glb", "gltf", "wobview":
				_open_path(path)
				return
			"hdr", "exr":
				_load_hdri(path)
				return
	_feedback("Podporované soubory jsou GLB, glTF, WOBVIEW, HDR a EXR.", true)


func _open_path(path: String) -> bool:
	if path.get_extension().to_lower() == "wobview":
		return _open_view(path)
	return _load_model(path)


func _load_model(path: String, keep_lod_family := false) -> bool:
	var error := stage.load_model(path)
	if not error.is_empty():
		_feedback(error, true)
		return false
	_path = path
	_view_path = ""
	_file_name.text = path.get_file()
	_file_name.tooltip_text = path
	_open_dialog.current_dir = path.get_base_dir()
	_blank.hide()
	_gizmo.show()
	_capture_button.disabled = false
	if not keep_lod_family:
		_lod_entries = LodCatalog.discover(path)
	_refresh_lod_options()
	_refresh_menu()
	_refresh_clips()
	_refresh_model_info()
	if DisplayServer.get_name() == "headless":
		print(path.get_file(), " ", stage.geometry, " ", stage.model.counts, " | ", stage.model.notes)
	return true


func _select_lod(index: int) -> void:
	var previous_camera := stage.camera_state()
	if _load_model(_lod_entries[index]["path"], true):
		stage.restore_camera(previous_camera)
	else:
		_refresh_lod_options()


func _refresh_lod_options() -> void:
	_lod_picker.clear()
	_lod_picker.tooltip_text = tr("Přepnout LOD při stejném pohledu")
	for child in _lod_table.get_children():
		_lod_table.remove_child(child)
		child.queue_free()
	var comparable := _lod_entries.size() > 1
	_lod_picker.visible = comparable
	_lod_table.visible = comparable
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
		"hdri": ViewFile.pack_path(path, _hdri_path),
		"options": options,
		"background": _background_option.selected,
		"background_color": _background_color.color.to_html(),
		"display": _display.selected,
		"camera": stage.camera_state(),
		"clip": str(stage.current_clip),
		"time": _timeline.value,
	}
	var status := ViewFile.write(path, state)
	if status == OK:
		_view_path = path
		_feedback(tr("Relace uložena · %s") % path.get_file())
	else:
		_feedback(tr("Relaci nelze uložit (%s).") % error_string(status), true)


func _open_view(path: String) -> bool:
	var state := ViewFile.read(path)
	if state.is_empty():
		_feedback("Soubor není platná relace WoB Model Viewer.", true)
		return false
	if not _load_model(ViewFile.unpack_path(path, state["model"])):
		return false
	_view_path = path
	var options: Variant = state.get("options", {})
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
	var back: Variant = state.get("background")
	if back is float or back is int:
		_set_background(clampi(int(back), 0, _background_option.item_count - 1))
	var display: Variant = state.get("display")
	if display is float or display is int:
		_set_display(clampi(int(display), 0, _display.item_count - 1))
	if state.get("camera") is Dictionary:
		stage.restore_camera(state["camera"])
	for index in range(stage.clips.size()):
		if str(stage.clips[index].name) == state.get("clip", ""):
			_movie.select(index)
			_select_clip(index)
			var seconds: Variant = state.get("time")
			if seconds is float or seconds is int:
				_timeline.value = float(seconds)
			break
	_reset_hdri()
	var hdri: Variant = state.get("hdri", "")
	if hdri is String and not hdri.is_empty():
		_load_hdri(ViewFile.unpack_path(path, hdri))
	return true


func _refresh_geometry() -> void:
	var metric := stage.geometry
	var extents := stage.bounds.size
	_geometry.text = tr("%s sítí   ·   %s povrchů\n%s vrcholů   ·   %s trojúhelníků\n%.3f × %.3f × %.3f m") % [
		metric.x, metric.y, metric.z, metric.w, extents.x, extents.y, extents.z,
	]
	_geometry.text += "\n" + (tr("Soubor %s · %s") % [
		_path.get_extension().to_upper(), _file_size(stage.model.source.bytes.size())
	])
	if _display.selected == 6:
		var topology := stage.quad_statistics()
		_geometry.text += "\n" + (tr("Odvozené quady %d · zbývající troj. %d") % [topology.x, topology.y])


func _refresh_model_info() -> void:
	_refresh_geometry()
	var report := PackedStringArray()
	for key: String in stage.model.counts:
		report.append("%s  ×  %d" % [key, stage.model.counts[key]])
	if report.is_empty():
		report.append(tr("Vykreslení podle materiálů GLB."))
	var notes := stage.model.notes
	if not notes.is_empty():
		report.append("")
		report.append_array(notes)
	_diagnostics.text = "\n".join(report)
	if notes.is_empty():
		_feedback("Model načten.")
	else:
		_feedback(tr("Model načten · upozornění (%d) v diagnostice.") % notes.size(), true)


func _refresh_clips() -> void:
	_movie.clear()
	var available := not stage.clips.is_empty()
	_movie.disabled = not available
	_play.disabled = not available
	_timeline.editable = available
	_play.text = "Přehrát"
	_time.text = "0.00 s"
	_timeline.set_value_no_signal(0.0)
	if not available:
		_movie.add_item("Bez animací")
		return
	for clip in stage.clips:
		_movie.add_item(str(clip.name))
	_movie.select(0)
	_select_clip(0)


func _select_clip(index: int) -> void:
	_timeline.max_value = stage.select_clip(index)
	_timeline.set_value_no_signal(0.0)
	_play.text = "Přehrát"


func _toggle_play() -> void:
	_play.text = "Pozastavit" if stage.toggle_play() else "Přehrát"


func _process(_delta: float) -> void:
	if not stage or not stage.animation_player:
		return
	var active := stage.animation_player.is_playing()
	_play.text = "Pozastavit" if active else "Přehrát"
	if active:
		_timeline.set_value_no_signal(stage.animation_player.current_animation_position)
	_time.text = "%.2f s" % _timeline.value


func _set_azimuth(value: float) -> void:
	_azimuth = value
	stage.light_direction(_azimuth, _elevation)


func _set_elevation(value: float) -> void:
	_elevation = value
	stage.light_direction(_azimuth, _elevation)


func _reset_hdri() -> void:
	_hdri_path = ""
	_hdri_name.tooltip_text = ""
	if stage.reset_hdri():
		_hdri_name.text = "Lilienstein"
	else:
		_hdri_name.text = "Vestavěné HDRI chybí"


func _load_hdri(path: String) -> void:
	var error := stage.set_hdri(path)
	if not error.is_empty():
		_feedback(error, true)
		return
	_hdri_name.text = path.get_file()
	_hdri_path = path
	_hdri_name.tooltip_text = path
	_feedback("HDRI načteno.")


func _capture(path: String) -> Error:
	if not path.to_lower().ends_with(".png"):
		path += ".png"
	_capture_button.disabled = true
	_feedback("Vykresluji snímek 4K…")
	var error := await stage.screenshot(path)
	_capture_button.disabled = false
	if error == OK:
		_feedback(tr("Snímek 3840 × 2160 uložen · %s") % path)
	else:
		_feedback(tr("Snímek nelze uložit (%s).") % error_string(error), true)
	return error


func _feedback(message: String, warning := false) -> void:
	_status.text = tr(message)
	_status.tooltip_text = _status.text
	_status.add_theme_color_override("font_color", GOLD if warning else MUTED)


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
	if stage.model:
		_refresh_lod_options()
		_refresh_model_info()


func _refresh_dialogs() -> void:
	_open_dialog.title = tr("Otevřít model")
	_open_dialog.filters = PackedStringArray(["*.glb,*.gltf,*.wobview ; " + tr("Model nebo relace")])
	_hdri_dialog.title = tr("Otevřít HDRI")
	_hdri_dialog.filters = PackedStringArray(["*.hdr,*.exr ; " + tr("Panorama HDRI")])
	_save_dialog.title = tr("Uložit snímek 3840 × 2160")
	_save_dialog.filters = PackedStringArray(["*.png ; " + tr("Obraz PNG")])
	_view_dialog.title = tr("Uložit relaci jako")
	_view_dialog.filters = PackedStringArray(["*.wobview ; " + tr("Relace WoB Model Viewer")])


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var key: Key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
	if key == KEY_F1:
		_show_help()
	elif event.ctrl_pressed and not event.alt_pressed:
		match key:
			KEY_O: _show_open()
			KEY_S:
				if event.shift_pressed:
					_show_view_save()
				else:
					_save_view()
			KEY_E: _show_capture()
			KEY_Q: get_tree().quit()
			_: return
	elif stage.model and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed:
		match key:
			KEY_F, KEY_1: stage.frame()
			KEY_2: stage.frame(Vector2.ZERO)
			KEY_3: stage.frame(Vector2(PI / 2, 0.0))
			KEY_4: stage.frame(Vector2(0.0, 1.555))
			KEY_W: _toggle_display(1)
			KEY_Q: _toggle_display(6)
			KEY_P: _toggle_display(5)
			KEY_G: _toggle_option("grid")
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
	_set_display(0 if _display.selected == mode else mode)


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
		elif not argument.begins_with("-") and argument.get_extension().to_lower() in ["glb", "gltf", "wobview"] \
				and model_path.is_empty():
			model_path = argument
	if model_path.is_empty():
		return
	var success := _open_path(model_path)
	if not success:
		printerr("WoB Model Viewer: ", _status.text)
	if not capture_path.is_empty():
		if not success:
			get_tree().quit(1)
			return
		var result := await _capture(capture_path)
		get_tree().quit(0 if result == OK else 1)
