extends VBoxContainer

const UiGlyphs = preload("res://ui_glyphs.gd")

signal item_chosen(kind: String, data: Variant)
signal visibility_changed_for_mesh(mesh: MeshInstance3D, visible_mesh: bool)

var tree: Tree


func _ready() -> void:
	var heading := HBoxContainer.new()
	add_child(heading)
	var icon := TextureRect.new()
	icon.texture = UiGlyphs.texture("scene", Color("#d7af75"), 21)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	heading.add_child(icon)
	var caption := Label.new()
	caption.text = "Scéna"
	caption.add_theme_color_override("font_color", Color("#e7c68d"))
	caption.size_flags_horizontal = SIZE_EXPAND_FILL
	heading.add_child(caption)
	var fold := Button.new()
	fold.text = "⌄"
	fold.tooltip_text = "Sbalit nebo rozbalit scénu"
	fold.flat = true
	fold.pressed.connect(func():
		var root_item := tree.get_root()
		if root_item:
			root_item.collapsed = not root_item.collapsed
	)
	heading.add_child(fold)
	tree = Tree.new()
	tree.columns = 2
	tree.set_column_expand(1, false)
	tree.set_column_custom_minimum_width(1, 26)
	tree.size_flags_vertical = SIZE_EXPAND_FILL
	tree.allow_reselect = true
	tree.select_mode = Tree.SELECT_ROW
	tree.item_selected.connect(_select_item)
	tree.item_edited.connect(_edit_item)
	add_child(tree)


func rebuild(stage: Control, path: String, surfaces: Array[Dictionary]) -> void:
	tree.clear()
	var root := tree.create_item()
	if not stage.model:
		root.set_text(0, tr("Bez modelu"))
		root.set_selectable(0, false)
		return
	root.set_text(0, path.get_file().get_basename())
	root.set_icon(0, UiGlyphs.texture("cube", Color("#e3c38d"), 22))
	root.set_tooltip_text(0, path)
	root.set_metadata(0, {"kind": "model"})
	var meshes := _item(root, tr("Síť"), "mesh_group")
	meshes.collapsed = true
	for instance: MeshInstance3D in stage.model.meshes:
		var row := _item(meshes, str(instance.name), "mesh", instance)
		row.set_cell_mode(1, TreeItem.CELL_MODE_CHECK)
		row.set_checked(1, stage.is_part_visible(instance))
		row.set_editable(1, true)
		row.set_tooltip_text(1, tr("Viditelnost vrstvy"))
	var materials := _item(root, "%s (%d)" % [tr("Materiálové sloty"), surfaces.size()], "materials")
	materials.collapsed = true
	for index in surfaces.size():
		_item(materials, surfaces[index].label, "material", index)
	var skeleton := _item(root, tr("Kostra"), "skeleton")
	skeleton.set_selectable(0, not stage._skeletons.is_empty())
	var animations := _item(root, "%s (%d)" % [tr("Klipy animace"), stage.clips.size()], "animations")
	animations.collapsed = true
	for index in stage.clips.size():
		_item(animations, str(stage.clips[index].name), "clip", index)
	root.select(0)


func _item(parent: TreeItem, title: String, kind: String, data: Variant = null) -> TreeItem:
	var row := tree.create_item(parent)
	row.set_text(0, title)
	var glyph: String = {"mesh_group": "mesh", "mesh": "mesh", "materials": "layers", "material": "layers",
		"skeleton": "bone", "animations": "clip", "clip": "clip"}.get(kind, "")
	if not glyph.is_empty():
		row.set_icon(0, UiGlyphs.texture(glyph, Color("#c4b4a2"), 19))
	row.set_metadata(0, {"kind": kind, "data": data})
	return row


func _select_item() -> void:
	var data := selection()
	if not data.is_empty():
		item_chosen.emit(data.kind, data.get("data"))


func selection() -> Dictionary:
	var row := tree.get_selected()
	var data: Variant = row.get_metadata(0) if row else null
	return data if data is Dictionary else {}


func _edit_item() -> void:
	var row := tree.get_edited()
	var data: Variant = row.get_metadata(0) if row else null
	if data is Dictionary and data.kind == "mesh":
		visibility_changed_for_mesh.emit(data.data, row.is_checked(1))
