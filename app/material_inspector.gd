extends VBoxContainer

const UiGlyphs = preload("res://ui_glyphs.gd")
const ViewFile = preload("res://view_file.gd")

signal surface_preview_changed(instance: MeshInstance3D, surface: int)

var targets: Array[Dictionary]
var _picker: OptionButton
var _name: Label
var _type: Label
var _color: ColorPickerButton
var _sampler: Button
var _solid_color: CheckBox
var _roughness: SpinBox
var _metallic: SpinBox
var _normal: Button
var _normal_file: FileDialog
var _sphere: MeshInstance3D
var _preview: SubViewport


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	_picker = OptionButton.new()
	_picker.fit_to_longest_item = false
	_picker.size_flags_horizontal = SIZE_EXPAND_FILL
	_picker.item_selected.connect(_show_selected)
	_row("Slot", _picker)
	var summary := HBoxContainer.new()
	add_child(summary)
	summary.add_theme_constant_override("separation", 14)
	var border := PanelContainer.new()
	var surface := StyleBoxFlat.new()
	surface.bg_color = Color("#201f1e")
	surface.border_color = Color("#5d554c")
	surface.set_border_width_all(1)
	surface.set_corner_radius_all(4)
	border.add_theme_stylebox_override("panel", surface)
	summary.add_child(border)
	var frame := SubViewportContainer.new()
	frame.custom_minimum_size = Vector2(74, 74)
	frame.mouse_filter = MOUSE_FILTER_IGNORE
	border.add_child(frame)
	_preview = SubViewport.new()
	_preview.size = Vector2i(74, 74)
	_preview.own_world_3d = true
	_preview.transparent_bg = true
	_preview.render_target_update_mode = SubViewport.UPDATE_DISABLED
	frame.add_child(_preview)
	_sphere = MeshInstance3D.new()
	_sphere.mesh = SphereMesh.new()
	_preview.add_child(_sphere)
	var camera := Camera3D.new()
	camera.position.z = 2.55
	camera.fov = 27.0
	_preview.add_child(camera)
	camera.make_current()
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-34, -26, 0)
	light.light_energy = 1.75
	_preview.add_child(light)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-1, 0, 2)
	fill.light_energy = 0.6
	_preview.add_child(fill)
	var labels := VBoxContainer.new()
	labels.size_flags_horizontal = SIZE_EXPAND_FILL
	labels.alignment = BoxContainer.ALIGNMENT_CENTER
	summary.add_child(labels)
	_name = Label.new()
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	labels.add_child(_name)
	_type = Label.new()
	_type.add_theme_color_override("font_color", Color("#a9a29b"))
	labels.add_child(_type)
	_color = ColorPickerButton.new()
	_color.edit_alpha = false
	_color.size_flags_horizontal = SIZE_EXPAND_FILL
	_color.color_changed.connect(_apply_color)
	var color_row := HBoxContainer.new()
	color_row.add_theme_constant_override("separation", 2)
	color_row.add_child(_color)
	_sampler = Button.new()
	_sampler.toggle_mode = true
	_sampler.icon = UiGlyphs.texture("dropper", Color("#d8c7ad"), 19)
	_sampler.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sampler.custom_minimum_size.x = 34
	_sampler.tooltip_text = "Vzít barvu z náhledu"
	_sampler.toggled.connect(func(armed: bool):
		Input.set_default_cursor_shape(Input.CURSOR_CROSS if armed else Input.CURSOR_ARROW)
	)
	color_row.add_child(_sampler)
	_row("Základní barva", color_row)
	_solid_color = CheckBox.new()
	_solid_color.text = "Plná barva"
	_solid_color.tooltip_text = "V náhledu použije barvu bez míchání s albedem a vertex barvami."
	_solid_color.toggled.connect(_set_solid_color)
	add_child(_solid_color)
	get_window().focus_exited.connect(_cancel_sample)
	_roughness = _number("Drsnost")
	_roughness.value_changed.connect(func(value: float):
		var material := _editable()
		if material:
			material.roughness = value
			_update_preview(material)
	)
	_metallic = _number("Kovovost")
	_metallic.value_changed.connect(func(value: float):
		var material := _editable()
		if material:
			material.metallic = value
			_update_preview(material)
	)
	_normal = Button.new()
	_normal.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_normal.icon = UiGlyphs.texture("folder", Color("#cdbca6"), 20)
	_normal.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_normal.tooltip_text = "Vybrat normálovou mapu"
	_normal.pressed.connect(func(): _normal_file.popup_centered_ratio(0.65))
	_row("Normála", _normal)
	_normal_file = FileDialog.new()
	_normal_file.use_native_dialog = true
	_normal_file.access = FileDialog.ACCESS_FILESYSTEM
	_normal_file.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_normal_file.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp, *.tga ; Image"])
	_normal_file.file_selected.connect(_load_normal)
	add_child(_normal_file)
	set_slots([])


func set_slots(rows: Array[Dictionary]) -> void:
	targets = rows
	_picker.clear()
	_picker.disabled = rows.is_empty()
	for slot: Dictionary in targets:
		_picker.add_item(slot.label)
	if targets.is_empty():
		_picker.add_item(tr("Bez materiálu"))
	select_slot(0)


func select_slot(index: int) -> void:
	_picker.select(index)
	_show_selected(index)


func _row(title: String, control: Control) -> void:
	var row := HBoxContainer.new()
	add_child(row)
	var caption := Label.new()
	caption.text = title
	caption.custom_minimum_size.x = 125.0
	row.add_child(caption)
	control.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(control)


func _number(title: String) -> SpinBox:
	var control := SpinBox.new()
	control.max_value = 1.0
	control.step = 0.01
	_row(title, control)
	return control


func _target() -> Dictionary:
	var index := _picker.selected
	return targets[index] if index >= 0 and index < targets.size() else {}


func _show_selected(_index: int) -> void:
	var slot := _target()
	var material: Material = slot.instance.get_active_material(slot.surface) if not slot.is_empty() else null
	var pbr := material as BaseMaterial3D
	_name.text = slot.get("label", tr("Bez materiálu"))
	_type.text = tr("Materiál PBR") if pbr else (tr("Produkční shader") if material else "")
	_cancel_sample()
	_color.disabled = not pbr
	_sampler.disabled = not pbr
	_color.color = pbr.albedo_color if pbr else Color("#6b645b")
	_solid_color.disabled = not pbr
	_solid_color.set_pressed_no_signal(slot.get("solid_color", false))
	_roughness.editable = pbr != null
	_metallic.editable = pbr != null
	_roughness.set_value_no_signal(pbr.roughness if pbr else 0.0)
	_metallic.set_value_no_signal(pbr.metallic if pbr else 0.0)
	_normal.disabled = not pbr
	_normal.text = tr("Normálová mapa") if pbr and pbr.normal_texture else tr("(žádná)")
	_update_preview(pbr)


func _cancel_sample() -> void:
	if _sampler.button_pressed:
		_sampler.button_pressed = false


func _input(event: InputEvent) -> void:
	if not is_instance_valid(_sampler) or not _sampler.button_pressed:
		return
	if event.is_action_pressed("ui_cancel"):
		_cancel_sample()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var viewport := get_viewport()
		viewport.set_input_as_handled()
		_cancel_sample()
		var image := viewport.get_texture().get_image()
		var position := Vector2i(event.position)
		if image and Rect2i(Vector2i.ZERO, image.get_size()).has_point(position):
			_color.color = image.get_pixelv(position)
			_apply_color(_color.color)


func _apply_color(color: Color) -> void:
	var material := _editable()
	if material:
		var slot := _target()
		material.albedo_color = color
		var original: BaseMaterial3D = slot.source_material
		if not slot.has("solid_color") and (original.albedo_texture or original.vertex_color_use_as_albedo):
			_apply_color_mode(slot, true)
			_solid_color.set_pressed_no_signal(true)
		_update_preview(material)


func _set_solid_color(enabled: bool) -> void:
	var material := _editable()
	if material:
		_apply_color_mode(_target(), enabled)
		_update_preview(material)


func _apply_color_mode(slot: Dictionary, enabled: bool) -> void:
	var preview: BaseMaterial3D = slot.preview_material
	var original: BaseMaterial3D = slot.source_material
	slot["solid_color"] = enabled
	preview.albedo_texture = null if enabled else original.albedo_texture
	preview.vertex_color_use_as_albedo = not enabled and original.vertex_color_use_as_albedo


func _editable() -> BaseMaterial3D:
	var slot := _target()
	if slot.is_empty() or not is_instance_valid(slot.instance):
		return null
	if not slot.has("preview_material"):
		var instance: MeshInstance3D = slot.instance
		var material := instance.get_active_material(slot.surface) as BaseMaterial3D
		if not material:
			return null
		slot.source_material = material
		slot.preview_material = material.duplicate()
		if instance.material_override:
			# Keep the effective material on every other surface when enabling slot edits.
			for surface in instance.mesh.get_surface_count():
				instance.set_surface_override_material(surface, instance.material_override)
			instance.material_override = null
		instance.set_surface_override_material(slot.surface, slot.preview_material)
		surface_preview_changed.emit(instance, slot.surface)
	return slot.preview_material


func _load_normal(path: String) -> void:
	var image := Image.load_from_file(path)
	if image == null or image.is_empty():
		_normal.tooltip_text = tr("Texturu se nepodařilo načíst.")
		return
	var material := _editable()
	if material:
		image.generate_mipmaps()
		material.normal_texture = ImageTexture.create_from_image(image)
		material.normal_enabled = true
		_target()["normal_path"] = path
		_normal.text = path.get_file()
		_update_preview(material)


func snapshot(view_path: String) -> Array[Dictionary]:
	var records: Array[Dictionary]
	for slot: Dictionary in targets:
		var material := slot.get("preview_material") as BaseMaterial3D
		if material:
			records.append({
				"node": slot.node,
				"surface": slot.surface,
				"color": material.albedo_color.to_html(),
				"solid_color": slot.get("solid_color", false),
				"roughness": material.roughness,
				"metallic": material.metallic,
				"normal": ViewFile.pack_path(view_path, slot.get("normal_path", "")),
			})
	return records


func restore(records: Variant, view_path: String) -> void:
	if not records is Array or records.is_empty():
		return
	var by_slot := {}
	for record: Variant in records:
		if record is Dictionary and record.get("node") is String:
			var surface: Variant = record.get("surface")
			if surface is int or surface is float:
				by_slot[[record.node, float(surface)]] = record
	var previous := _picker.selected
	for index in targets.size():
		var slot: Dictionary = targets[index]
		var record: Dictionary = by_slot.get([slot.node, float(slot.surface)], {})
		if record.is_empty():
			continue
		_picker.select(index)
		var material := _editable()
		if not material:
			continue
		var color: Variant = record.get("color")
		if color is String and Color.html_is_valid(color):
			material.albedo_color = Color.html(color)
		if record.get("solid_color") is bool:
			_apply_color_mode(slot, record.solid_color)
		for key in ["roughness", "metallic"]:
			var value: Variant = record.get(key)
			if (value is float or value is int) and is_finite(float(value)):
				material.set(key, clampf(float(value), 0.0, 1.0))
		var normal: Variant = record.get("normal")
		if normal is String and not normal.is_empty():
			_load_normal(ViewFile.unpack_path(view_path, normal))
	select_slot(previous)


func _update_preview(material: BaseMaterial3D) -> void:
	var surface := material
	if not surface:
		surface = StandardMaterial3D.new()
		surface.albedo_color = Color("#766859")
		surface.roughness = 0.82
	_sphere.material_override = surface
	_preview.render_target_update_mode = SubViewport.UPDATE_ONCE
