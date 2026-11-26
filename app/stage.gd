extends SubViewportContainer

const Materials = preload("res://materials.gd")
const TopologyOverlay = preload("res://topology_overlay.gd")
const WireframeMesh = preload("res://wireframe_mesh.gd")
const ModelGizmo = preload("res://model_gizmo.gd")
const BUILTIN_HDRI := "res://production/lighting/lilienstein_2k.hdr"
const HDRI_PRESETS := [BUILTIN_HDRI, "res://art/lighting/kloppenheim_06_puresky_2k.hdr",
	"res://art/lighting/moonlit_golf_2k.hdr"]
const CELESTIAL_SKY = preload("res://celestial_sky.gdshader")
const SCREENSHOT_SIZE := Vector2i(3840, 2160)
const ORBIT_SPEED := 0.008
const AUTO_ORBIT_SPEED := 0.38
const ANIMATION_SPEED_MIN := 0.0
const ANIMATION_SPEED_MAX := 2.0
const ANIMATION_SPEED_STEP := 0.01
const ANIMATION_SPEED_DEFAULT := 1.0
const WIREFRAME_MODE := 1
const WIREFRAME_WIDTH_MIN := 0.5
const WIREFRAME_WIDTH_MAX := 8.0
const WIREFRAME_WIDTH_DEFAULT := 1.2
const DEFAULT_FLOOR_COLOR := Color("#282829")
const STUDIO_VIEW := Vector2(0.14, 0.04)
const POINTS_MODE := 5
const QUADS_MODE := 6
const COLOR_MODE := 7
const UV0_MODE := 8
const UV2_MODE := 9
const CYCLE_SKY_MODE := 3
const ATTRIBUTE_SHADER = preload("res://attribute_preview.gdshader")
const WIREFRAME_SHADER = preload("res://wireframe_preview.gdshader")
const QUAD_LINE_SHADER := """
shader_type spatial;
render_mode unshaded, depth_draw_never, shadows_disabled;

void vertex() {
	POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	// Bias toward the camera in Godot 4's reverse-Z clip space.
	POSITION.z += 0.00001 * POSITION.w;
}

void fragment() {
	ALBEDO = vec3(1.0, 0.54, 0.20);
	ALPHA = 0.90;
}
"""
const DRAW_MODES := [
	Viewport.DEBUG_DRAW_DISABLED, Viewport.DEBUG_DRAW_DISABLED, Viewport.DEBUG_DRAW_UNSHADED,
	Viewport.DEBUG_DRAW_NORMAL_BUFFER, Viewport.DEBUG_DRAW_OVERDRAW,
]

var viewport_3d: SubViewport
var camera: Camera3D
var environment: Environment
var sunlight: DirectionalLight3D
var _fill_light: DirectionalLight3D
var _rim_light: DirectionalLight3D
var model: Materials
var clips: Array[Dictionary]
var animation_player: AnimationPlayer
var current_clip: StringName
var geometry := Vector4i.ZERO
var bounds := AABB()
var capture_in_progress := false

var _sky_material: PanoramaSkyMaterial
var _celestial_sky: ShaderMaterial
var _hdri_textures: Dictionary[int, Texture2D]
var _sky_mode := 0
var _show_source := true
var _hdri_angle := 0.0
var _direct_strength := 1.0
var _animation_loop := Animation.LOOP_LINEAR
var _animation_speed := ANIMATION_SPEED_DEFAULT
var _animation_in_place := false
var _model_placement: Node3D
var _model_anchor: Node3D
var _model_gizmo: ModelGizmo
var _model_gizmo_enabled := false
var _motion_node: Node3D
var _motion_bone := -1
var _motion_origin := Vector3.ZERO
var _manual_light := Vector2(-35.0, 42.0)
var _night_mix := 0.0
var _source_strength := 1.0
var _cycle_playing := false
var _cycle_seconds := 45.0
var cycle_hour := 12.0
var _grid: MeshInstance3D
var _floor: MeshInstance3D
var _floor_material: StandardMaterial3D
var _floor_offset := 0.0
var _hdri_on := true
var _background := 0
var _custom_background := Color("#55575c")
var _studio_backdrop: CanvasLayer
var _center := Vector3(0.0, 0.81, 0.0)
var _radius := 1.0
var _distance := 5.1
var _yaw := STUDIO_VIEW.x
var _pitch := STUDIO_VIEW.y
var _orbiting := false
var _panning := false
var _background_on := true
var _auto_orbit := false
var _screen_space_panning := true
var _rotation_hold := 0.0
var _skeletons: Array[Skeleton3D]
var _skeleton_overlay: MeshInstance3D
var _bone_lines: ImmediateMesh
var _bone_material: StandardMaterial3D
var _point_material: StandardMaterial3D
var _point_instances: Dictionary[MeshInstance3D, MeshInstance3D]
var _mesh_layers: Dictionary[MeshInstance3D, int]
var _hidden_parts: Dictionary[MeshInstance3D, bool]
var _wireframe_material: ShaderMaterial
var _wireframe_meshes: Dictionary[ArrayMesh, ArrayMesh]
var _wireframe_instances: Dictionary[MeshInstance3D, MeshInstance3D]
var _wireframe_prepared := false
var _wireframe_width := WIREFRAME_WIDTH_DEFAULT
var _quad_material: ShaderMaterial
var _quad_instances: Dictionary[MeshInstance3D, MeshInstance3D]
var _quad_statistics := Vector2i.ZERO
var _quads_prepared := false
var _display_mode := 0
var _isolated: MeshInstance3D
var _isolated_surface := -1
var _inspection_nodes: Dictionary[MeshInstance3D, Array]
var _attribute_meshes: Dictionary[MeshInstance3D, ArrayMesh]
var _attribute_input := "#"
var _color_layer := "COLOR_0"
var _color_channel := 0
var _attribute_materials: Dictionary[Vector2i, ShaderMaterial]


func _ready() -> void:
	stretch = true
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	viewport_3d = SubViewport.new()
	viewport_3d.own_world_3d = true
	viewport_3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport_3d.msaa_3d = Viewport.MSAA_4X
	viewport_3d.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	viewport_3d.gui_disable_input = true
	add_child(viewport_3d)
	_model_placement = Node3D.new()
	viewport_3d.add_child(_model_placement)
	_model_anchor = Node3D.new()
	_model_placement.add_child(_model_anchor)

	environment = Environment.new()
	environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.sky = Sky.new()
	environment.sky.radiance_size = Sky.RADIANCE_SIZE_128
	_sky_material = PanoramaSkyMaterial.new()
	_celestial_sky = ShaderMaterial.new()
	_celestial_sky.shader = CELESTIAL_SKY
	environment.sky.sky_material = _sky_material
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	viewport_3d.add_child(world_environment)
	_studio_backdrop = _make_studio_backdrop()
	viewport_3d.add_child(_studio_backdrop)
	environment.background_canvas_max_layer = _studio_backdrop.layer
	reset_hdri()
	background(0)

	sunlight = DirectionalLight3D.new()
	sunlight.shadow_enabled = true
	viewport_3d.add_child(sunlight)
	_fill_light = _auxiliary_light(Vector3(-25.0, 48.0, 0.0), 0.30)
	_rim_light = _auxiliary_light(Vector3(-32.0, 155.0, 0.0), 0.15)
	light_direction(-35.0, 42.0)
	light_intensity(_direct_strength)

	camera = Camera3D.new()
	camera.fov = 34.0
	viewport_3d.add_child(camera)
	camera.make_current()
	_update_camera()
	resized.connect(_update_camera)
	get_window().focus_exited.connect(_end_drag)

	_floor = MeshInstance3D.new()
	_floor_material = StandardMaterial3D.new()
	_floor_material.albedo_color = DEFAULT_FLOOR_COLOR
	_floor_material.roughness = 0.96
	_floor_material.metallic_specular = 0.0
	_floor_material.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	_floor.material_override = _floor_material
	_floor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_floor.hide()
	viewport_3d.add_child(_floor)

	_grid = MeshInstance3D.new()
	_grid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_grid.hide()
	viewport_3d.add_child(_grid)
	_make_floor_and_grid()

	_bone_material = StandardMaterial3D.new()
	_bone_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bone_material.no_depth_test = true
	_bone_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_bone_material.albedo_color = Color("#ffd082")
	_bone_lines = ImmediateMesh.new()
	_skeleton_overlay = MeshInstance3D.new()
	_skeleton_overlay.mesh = _bone_lines
	_skeleton_overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_skeleton_overlay.hide()
	viewport_3d.add_child(_skeleton_overlay)

	_point_material = StandardMaterial3D.new()
	_point_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_point_material.albedo_color = Color("#f1bd83")
	_point_material.use_point_size = true
	_point_material.point_size = 4.2

	_wireframe_material = ShaderMaterial.new()
	_wireframe_material.shader = WIREFRAME_SHADER
	_wireframe_material.set_shader_parameter("width_px", _wireframe_width)

	_quad_material = ShaderMaterial.new()
	var line_shader := Shader.new()
	line_shader.code = QUAD_LINE_SHADER
	_quad_material.shader = line_shader

	_model_gizmo = ModelGizmo.new()
	_model_gizmo.translation_requested.connect(_translate_model)
	_model_gizmo.rotation_requested.connect(_rotate_model)
	_model_gizmo.hide()
	add_child(_model_gizmo)
	_model_gizmo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func load_model(path: String, manifest: RefCounted = null) -> String:
	if not path.get_extension().to_lower() in ["glb", "gltf"]:
		return tr("Vyber soubor ve formátu GLB nebo glTF.")
	var pending := Materials.new()
	var error := pending.import_model(path, manifest)
	if not error.is_empty():
		return error
	_install_model(pending)
	return ""


func apply_prepared_model(pending: Materials) -> String:
	var error := pending.finish_model()
	if error.is_empty():
		_install_model(pending)
	return error


func _install_model(pending: Materials) -> void:
	if model:
		_model_anchor.remove_child(model.root)
		model.root.queue_free()
	reset_model_transform()
	_model_anchor.position = Vector3.ZERO
	_motion_node = null
	_point_instances.clear()
	_wireframe_instances.clear()
	_wireframe_meshes.clear()
	_wireframe_prepared = false
	_quad_instances.clear()
	_inspection_nodes.clear()
	_mesh_layers.clear()
	_hidden_parts.clear()
	_attribute_meshes.clear()
	_attribute_input = "#"
	_isolated = null
	_isolated_surface = -1
	_quad_statistics = Vector2i.ZERO
	_quads_prepared = false
	_skeletons.clear()
	_bone_lines.clear_surfaces()
	model = pending
	_model_anchor.add_child(model.root)
	for mesh in model.meshes:
		_mesh_layers[mesh] = mesh.layers
	_inspect_model()
	animation_player = null
	current_clip = &""
	clips.clear()
	_collect_clips(model.root)
	frame()
	_make_floor_and_grid()
	_apply_model_display()
	set_model_gizmo_enabled(_model_gizmo_enabled)
	if _skeleton_overlay.visible:
		_draw_skeletons()


func _inspect_model() -> void:
	bounds = AABB()
	geometry = Vector4i.ZERO
	var has_bounds := false
	for instance: MeshInstance3D in model.meshes:
		geometry.x += 1
		var local := instance.get_aabb()
		var world := instance.global_transform * local
		bounds = bounds.merge(world) if has_bounds else world
		has_bounds = true
		var mesh := instance.mesh as ArrayMesh
		if mesh == null:
			continue
		for surface in range(mesh.get_surface_count()):
			geometry.y += 1
			var vertices := mesh.surface_get_array_len(surface)
			geometry.z += vertices
			if mesh.surface_get_primitive_type(surface) == Mesh.PRIMITIVE_TRIANGLES:
				var indices := mesh.surface_get_array_index_len(surface)
				@warning_ignore("integer_division")
				geometry.w += (indices if indices > 0 else vertices) / 3


func _collect_clips(node: Node) -> void:
	if node is AnimationPlayer:
		for name: StringName in node.get_animation_list():
			if name != &"RESET":
				clips.append({"player": node, "name": name})
	elif node is Light3D:
		node.hide()
	elif node is Skeleton3D:
		_skeletons.append(node)
	for child in node.get_children():
		_collect_clips(child)


func select_clip(index: int, keep_playing := false) -> float:
	if animation_player:
		animation_player.mixer_applied.disconnect(_apply_in_place)
		animation_player.stop()
	_model_anchor.position = Vector3.ZERO
	animation_player = clips[index].player
	current_clip = clips[index].name
	var clip := animation_player.get_animation(current_clip)
	clip.loop_mode = _animation_loop
	animation_player.speed_scale = _animation_speed
	animation_player.play(current_clip)
	animation_player.advance(0)
	if not keep_playing:
		animation_player.pause()
	_find_motion_track(clip)
	if _motion_node:
		_motion_origin = _motion_position()
	animation_player.mixer_applied.connect(_apply_in_place)
	return clip.length


func animation_loop(enabled: bool) -> void:
	_animation_loop = Animation.LOOP_LINEAR if enabled else Animation.LOOP_NONE
	if animation_player:
		animation_player.get_animation(current_clip).loop_mode = _animation_loop


static func normalized_animation_speed(value: Variant) -> float:
	if (not value is float and not value is int) or not is_finite(float(value)):
		return ANIMATION_SPEED_DEFAULT
	return snappedf(clampf(float(value), ANIMATION_SPEED_MIN, ANIMATION_SPEED_MAX), ANIMATION_SPEED_STEP)


func animation_speed(value: Variant) -> float:
	_animation_speed = normalized_animation_speed(value)
	if animation_player:
		animation_player.speed_scale = _animation_speed
	return _animation_speed


func animation_in_place(enabled: bool) -> void:
	_animation_in_place = enabled
	_apply_in_place()


func _find_motion_track(clip: Animation) -> void:
	_motion_node = null
	_motion_bone = -1
	var best_rank := 0
	var root := animation_player.get_node_or_null(animation_player.root_node)
	if not root:
		return
	for track in range(clip.get_track_count()):
		if clip.track_get_type(track) != Animation.TYPE_POSITION_3D or not clip.track_is_enabled(track):
			continue
		var last := clip.track_get_key_count(track) - 1
		if last < 1:
			continue
		var path := clip.track_get_path(track)
		var node := root.get_node_or_null(NodePath(path.get_concatenated_names())) as Node3D
		if not node:
			continue
		var bone := -1
		var rank := 0
		var basis := Basis.IDENTITY
		if path.get_subname_count() == 0 and model.meshes.all(func(mesh: MeshInstance3D):
			return node == mesh or node.is_ancestor_of(mesh)
		):
			rank = 2
			var parent := node.get_parent_node_3d()
			if parent and not node.top_level:
				basis = parent.global_basis
		elif node is Skeleton3D and path.get_subname_count() == 1:
			var name := str(path.get_subname(0))
			bone = node.find_bone(name)
			if bone >= 0:
				var parent: int = node.get_bone_parent(bone)
				var label := name.to_lower().replace("_", "").replace("-", "")
				rank = 3 if parent < 0 or label in ["root", "rootmotion", "motion"] else 0
				if rank == 0 and (label.ends_with("hips") or label.ends_with("pelvis")):
					rank = 1
				basis = node.global_basis
				if parent >= 0:
					basis *= node.get_bone_global_pose(parent).basis
		if rank <= best_rank:
			continue
		var displacement: Vector3 = _model_placement.global_basis.inverse() * basis * (
			clip.track_get_key_value(track, last) - clip.track_get_key_value(track, 0))
		if Vector2(displacement.x, displacement.z).length() > maxf(0.001, bounds.size.length() * 0.008):
			best_rank = rank
			_motion_node = node
			_motion_bone = bone


func _motion_position() -> Vector3:
	var skeleton := _motion_node as Skeleton3D
	if _motion_bone >= 0 and skeleton:
		return _model_placement.to_local(skeleton.to_global(skeleton.get_bone_global_pose(_motion_bone).origin))
	return _model_placement.to_local(_motion_node.global_position)


func _apply_in_place() -> void:
	if _animation_in_place and _motion_node:
		var shift := _motion_position() - _model_anchor.position - _motion_origin
		_model_anchor.position = Vector3(-shift.x, 0.0, -shift.z)
	else:
		_model_anchor.position = Vector3.ZERO


func toggle_play() -> bool:
	if not animation_player:
		return false
	if animation_player.is_playing():
		animation_player.pause()
		return false
	if animation_player.current_animation_position >= animation_player.current_animation_length - 0.0001:
		animation_player.seek(0.0, true)
	animation_player.play(current_clip)
	return true


func seek(time: float) -> void:
	if animation_player:
		animation_player.seek(time, true)


func frame(direction := Vector2(0.63, 0.13)) -> void:
	if not model:
		_center = Vector3(0.0, 0.7, 0.0)
		_yaw = direction.x
		_pitch = direction.y
		_distance = 5.1
		_update_camera()
		return
	_center = _placed_model_center()
	_radius = maxf(bounds.size.length() * 0.5, 0.0001)
	_yaw = direction.x
	_pitch = direction.y
	var half_height := tan(deg_to_rad(camera.fov * 0.5))
	var half_width := half_height * maxf(0.1, size.x / maxf(1.0, size.y))
	var inverse_view := Basis.looking_at(-_orbit_direction()).transposed()
	_distance = _radius * 1.1
	for corner in range(8):
		var local := inverse_view * (_model_placement.to_global(bounds.get_endpoint(corner)) - _center)
		var fit := maxf(absf(local.x) / half_width, absf(local.y) / half_height) * 1.16
		if camera.projection == Camera3D.PROJECTION_PERSPECTIVE:
			fit += local.z
		_distance = maxf(_distance, fit)
	_update_camera()


func _gui_input(event: InputEvent) -> void:
	if not model:
		return
	if _model_gizmo.visible and not (_orbiting or _panning or capture_in_progress):
		if _model_gizmo.handle_input(event) or _model_gizmo.is_dragging():
			accept_event()
			return
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_orbiting = event.pressed
			MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT:
				_panning = event.pressed
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					zoom(event.button_index == MOUSE_BUTTON_WHEEL_UP)
			_:
				return
		accept_event()
	elif event is InputEventMouseMotion:
		if _panning:
			var scale := 2.0 * _distance * tan(deg_to_rad(camera.fov * 0.5)) / maxf(size.y, 1.0)
			var right := camera.basis.x
			var up := camera.basis.y
			if not _screen_space_panning:
				right = Vector3(cos(_yaw), 0.0, -sin(_yaw))
				up = Vector3(-sin(_yaw), 0.0, -cos(_yaw))
			_center += (-right * event.relative.x + up * event.relative.y) * scale
		elif _orbiting:
			orbit_by(event.relative)
			accept_event()
			return
		else:
			return
		_update_camera()
		accept_event()


func _end_drag() -> void:
	_orbiting = false
	_panning = false
	_model_gizmo.cancel_drag()


func set_model_gizmo_enabled(enabled: bool) -> void:
	_model_gizmo_enabled = enabled
	_model_gizmo.visible = enabled and model != null
	if not _model_gizmo.visible:
		_model_gizmo.cancel_drag()


func reset_model_transform() -> void:
	_model_gizmo.cancel_drag()
	_model_placement.transform = Transform3D.IDENTITY


func model_transform_state() -> Dictionary:
	var origin := _model_placement.position
	var rotation := _model_placement.basis.get_rotation_quaternion()
	return {
		"origin": [origin.x, origin.y, origin.z],
		"rotation": [rotation.x, rotation.y, rotation.z, rotation.w],
	}


func restore_model_transform(data: Dictionary) -> void:
	var origin: Variant = data.get("origin")
	var rotation: Variant = data.get("rotation")
	if not origin is Array or origin.size() != 3 or not rotation is Array or rotation.size() != 4:
		return
	for component in origin + rotation:
		if (not component is int and not component is float) or not is_finite(float(component)):
			return
	var position := Vector3(origin[0], origin[1], origin[2])
	var orientation := Quaternion(rotation[0], rotation[1], rotation[2], rotation[3])
	if not is_finite(position.length_squared()) or not is_finite(orientation.length_squared()) \
			or orientation.length_squared() < 0.000001:
		return
	_model_placement.transform = Transform3D(Basis(orientation.normalized()), position)


func _translate_model(delta: Vector3) -> void:
	var position := _model_placement.position + delta
	if is_finite(position.length_squared()):
		_model_placement.position = position


func _rotate_model(axis: Vector3, angle: float) -> void:
	var pivot := _placed_model_center()
	var current := _model_placement.transform
	var rotation := Basis(axis, angle)
	_model_placement.transform = Transform3D((rotation * current.basis).orthonormalized(),
		pivot + rotation * (current.origin - pivot))


func _placed_model_center() -> Vector3:
	return _model_placement.to_global(bounds.get_center())


func zoom(inward: bool) -> void:
	if not model:
		return
	_distance = clampf(_distance * (0.86 if inward else 1.16), _radius * 0.015, _radius * 150.0)
	_update_camera()


func orient_to(direction: Vector3) -> void:
	if direction.is_zero_approx():
		return
	var axis := direction.normalized()
	_yaw = 0.0 if absf(axis.y) >= 0.99999 else atan2(axis.x, axis.z)
	_pitch = clampf(asin(axis.y), -1.555, 1.555)
	_rotation_hold = 1.0
	_update_camera()


func orbit_by(relative: Vector2) -> void:
	_yaw -= relative.x * ORBIT_SPEED
	_pitch = clampf(_pitch + relative.y * ORBIT_SPEED, -1.555, 1.555)
	_rotation_hold = 1.0
	_update_camera()


func auto_rotate_enabled(enabled: bool) -> void:
	_auto_orbit = enabled


func screen_space_panning(enabled: bool) -> void:
	_screen_space_panning = enabled


func _process(delta: float) -> void:
	if _sky_mode == CYCLE_SKY_MODE and _cycle_playing and not capture_in_progress:
		sky_cycle_seek(cycle_hour + delta * 24.0 / _cycle_seconds)
	if not model:
		return
	_rotation_hold = maxf(_rotation_hold - delta, 0.0)
	if _auto_orbit and _rotation_hold == 0.0 and not (_orbiting or _panning or capture_in_progress
			or _model_gizmo.is_dragging()):
		_yaw = wrapf(_yaw + delta * AUTO_ORBIT_SPEED, -PI, PI)
		_update_camera()
	if _model_gizmo.visible and not capture_in_progress:
		_model_gizmo.sync(camera, _placed_model_center())
	if _skeleton_overlay.visible:
		_draw_skeletons()
	if _display_mode == WIREFRAME_MODE:
		_sync_debug_morphs(_wireframe_instances)
	elif _display_mode == POINTS_MODE:
		_sync_debug_morphs(_point_instances)
	elif _display_mode == QUADS_MODE:
		_sync_debug_morphs(_quad_instances)
	for source in _inspection_nodes:
		for preview: MeshInstance3D in _inspection_nodes[source]:
			_copy_morphs(source, preview)


func _update_camera() -> void:
	if not camera:
		return
	camera.position = _center + _orbit_direction() * _distance
	camera.look_at(_center)
	camera.near = maxf(0.00001, minf(_distance * 0.12, _radius * 0.03))
	camera.far = maxf(1.0, _distance + _radius * 54.0)
	camera.size = 2.0 * _distance * tan(deg_to_rad(camera.fov * 0.5))


func orientation_display_basis() -> Basis:
	if not model and is_equal_approx(_yaw, STUDIO_VIEW.x) and is_equal_approx(_pitch, STUDIO_VIEW.y):
		return Basis(Vector3.UP, 0.57) * Basis(Vector3.RIGHT, -0.37)
	return camera.global_basis


func _orbit_direction() -> Vector3:
	return Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch))


func _make_studio_backdrop() -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.layer = -1
	var panel := TextureRect.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shades := Gradient.new()
	shades.offsets = PackedFloat32Array([0.0, 0.56, 1.0])
	shades.colors = PackedColorArray([Color("#363637"), Color("#323233"), Color("#2c2c2d")])
	var texture := GradientTexture2D.new()
	texture.width = 320
	texture.height = 240
	texture.gradient = shades
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.50, 0.62)
	texture.fill_to = Vector2(1.0, 0.0)
	panel.texture = texture
	panel.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	layer.add_child(panel)
	return layer


func background(index: int) -> void:
	_background = index
	if not _background_on:
		return
	_studio_backdrop.visible = index == 0
	var colors := [Color("#2c2c2d"), Color("#111112"), Color("#c9c9c5")]
	if index == 0:
		environment.background_mode = Environment.BG_CANVAS
	elif index == 3:
		environment.background_mode = Environment.BG_SKY
	else:
		environment.background_mode = Environment.BG_COLOR
		environment.background_color = _custom_background if index == 4 else colors[index]


func background_enabled(enabled: bool) -> void:
	_background_on = enabled
	viewport_3d.transparent_bg = not enabled
	if enabled:
		background(_background)
	else:
		_studio_backdrop.hide()
		environment.background_mode = Environment.BG_CLEAR_COLOR


func custom_background(color: Color) -> void:
	_custom_background = color
	if _background == 4:
		background(4)


func orthographic(enabled: bool) -> void:
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL if enabled else Camera3D.PROJECTION_PERSPECTIVE


func camera_state() -> Dictionary:
	return {"target": [_center.x, _center.y, _center.z], "yaw": _yaw, "pitch": _pitch, "distance": _distance}


func restore_camera(data: Dictionary, limit_distance := true) -> void:
	var pivot: Variant = data.get("target", [])
	if not pivot is Array or pivot.size() != 3:
		return
	var numbers: Array = pivot + [data.get("yaw"), data.get("pitch"), data.get("distance")]
	for number in numbers:
		if (not number is float and not number is int) or not is_finite(float(number)):
			return
	_center = Vector3(pivot[0], pivot[1], pivot[2])
	_yaw = wrapf(float(data["yaw"]), -PI, PI)
	_pitch = clampf(float(data["pitch"]), -1.555, 1.555)
	var distance := float(data["distance"])
	if limit_distance or distance <= 0.0:
		distance = clampf(distance, _radius * 0.015, _radius * 150.0)
	_distance = distance
	_update_camera()


func grid_visible(enabled: bool) -> void:
	_grid.visible = enabled


func skeleton_visible(enabled: bool) -> void:
	_skeleton_overlay.visible = enabled
	if enabled:
		_draw_skeletons()


func _draw_skeletons() -> void:
	_bone_lines.clear_surfaces()
	var bones := PackedVector3Array()
	for skeleton in _skeletons:
		var transform := skeleton.global_transform
		for index in range(skeleton.get_bone_count()):
			var parent := skeleton.get_bone_parent(index)
			if parent != -1:
				bones.append(transform * skeleton.get_bone_global_pose(parent).origin)
				bones.append(transform * skeleton.get_bone_global_pose(index).origin)
	if bones.is_empty():
		return
	_bone_lines.surface_begin(Mesh.PRIMITIVE_LINES, _bone_material)
	for point in bones:
		_bone_lines.surface_add_vertex(point)
	_bone_lines.surface_end()


func floor_visible(enabled: bool) -> void:
	_floor.visible = enabled


func set_floor_color(color: Color) -> void:
	_floor_material.albedo_color = color


func set_floor_offset(offset: float) -> void:
	_floor_offset = offset
	var height := bounds.position.y + _floor_offset
	_grid.position.y = height
	_floor.position.y = height - _radius * 0.005


func _make_floor_and_grid() -> void:
	var center := Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)
	var step := pow(10.0, floorf(log(_radius) / log(10.0))) * (0.5 if model else 0.78)
	var cells := clampi(ceili(28.0 * _radius / step), 30, 80)
	var half := step * cells
	_floor_material.distance_fade_max_distance = half * 0.40
	_floor_material.distance_fade_min_distance = half * 0.84
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2.ONE * (2.0 * half)
	_floor.mesh = floor_mesh
	_floor.position = center
	_grid.position = center
	set_floor_offset(_floor_offset)
	var lines := ImmediateMesh.new()
	var line_style := StandardMaterial3D.new()
	line_style.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_style.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	line_style.vertex_color_use_as_albedo = true
	line_style.render_priority = 1
	line_style.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	line_style.distance_fade_max_distance = half * 0.26
	line_style.distance_fade_min_distance = half * 0.65
	lines.surface_begin(Mesh.PRIMITIVE_LINES, line_style)
	for index in range(-cells, cells + 1):
		var offset := index * step
		var grid_color := Color(0.43, 0.42, 0.41, 0.20 if index % 5 == 0 else 0.10)
		_grid_line(lines, Vector3(-half, 0, offset), Vector3(half, 0, offset),
			grid_color)
		_grid_line(lines, Vector3(offset, 0, -half), Vector3(offset, 0, half),
			grid_color)
	lines.surface_end()
	_grid.mesh = lines


func _grid_line(lines: ImmediateMesh, start: Vector3, finish: Vector3, color: Color) -> void:
	lines.surface_set_color(color)
	lines.surface_add_vertex(start)
	lines.surface_set_color(color)
	lines.surface_add_vertex(finish)


func light_direction(azimuth: float, elevation: float) -> void:
	_manual_light = Vector2(azimuth, elevation)
	if _sky_mode == CYCLE_SKY_MODE:
		_update_day_cycle()
	else:
		sunlight.rotation_degrees = Vector3(-elevation, azimuth, 0)
		_update_light_source()


func light_intensity(value: float) -> void:
	_direct_strength = value
	sunlight.light_energy = value * lerpf(1.0, 0.28, _night_mix) * _source_strength


func _auxiliary_light(direction: Vector3, intensity: float) -> DirectionalLight3D:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = direction
	light.light_energy = intensity
	viewport_3d.add_child(light)
	return light


func fill_intensity(value: float) -> void:
	_fill_light.light_energy = value


func rim_intensity(value: float) -> void:
	_rim_light.light_energy = value


func hdri_orientation(degrees: float) -> void:
	_hdri_angle = degrees
	environment.sky_rotation = Vector3(0.0, deg_to_rad(degrees), 0.0) if _sky_mode == 0 else Vector3.ZERO
	_celestial_sky.set_shader_parameter("panorama_rotation", degrees / 360.0)


func hdri_intensity(value: float) -> void:
	_sky_material.energy_multiplier = value
	_celestial_sky.set_shader_parameter("exposure", value)
	environment.ambient_light_energy = 1.0 if _sky_material.panorama else value


func hdri_enabled(enabled: bool) -> void:
	_hdri_on = enabled
	if not enabled:
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	elif _sky_material.panorama or _sky_mode != 0:
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	else:
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR


func light_enabled(enabled: bool) -> void:
	sunlight.visible = enabled
	_fill_light.visible = enabled
	_rim_light.visible = enabled
	_update_light_source()


func sky_mode(index: int) -> void:
	_sky_mode = index
	if index == CYCLE_SKY_MODE:
		environment.sky.radiance_size = Sky.RADIANCE_SIZE_256
		environment.sky.process_mode = Sky.PROCESS_MODE_REALTIME
	else:
		environment.sky.process_mode = Sky.PROCESS_MODE_AUTOMATIC
		environment.sky.radiance_size = Sky.RADIANCE_SIZE_128
	environment.sky.sky_material = _sky_material if index == 0 else _celestial_sky
	hdri_orientation(_hdri_angle)
	hdri_enabled(_hdri_on)
	if index == CYCLE_SKY_MODE:
		_update_day_cycle()
		return
	_night_mix = 1.0 if index == 2 else 0.0
	_source_strength = 1.0
	_celestial_sky.set_shader_parameter("night_mix", _night_mix)
	_celestial_sky.set_shader_parameter("source_is_moon", index == 2)
	_celestial_sky.set_shader_parameter("source_strength", 1.0)
	sunlight.light_color = Color.WHITE if index == 0 else Color("#a9c6ff" if index == 2 else "#ffe8cb")
	light_intensity(_direct_strength)
	light_direction(_manual_light.x, _manual_light.y)


func sky_cycle_play(enabled: bool) -> void:
	_cycle_playing = enabled


func sky_cycle_duration(seconds: float) -> void:
	_cycle_seconds = seconds


func sky_cycle_seek(hour: float) -> void:
	cycle_hour = fposmod(hour, 24.0)
	if _sky_mode == CYCLE_SKY_MODE:
		_update_day_cycle()


func _update_day_cycle() -> void:
	var angle := (cycle_hour - 6.0) * TAU / 24.0
	var altitude := sin(angle)
	var moon := altitude < 0.0
	var source := Vector3(cos(angle), altitude * 0.82, altitude * 0.57).normalized()
	source = source.rotated(Vector3.UP, deg_to_rad(_manual_light.x))
	if moon:
		source = -source
	sunlight.rotation = Vector3(-asin(source.y), atan2(source.x, source.z), 0.0)
	_night_mix = 1.0 - smoothstep(-0.18, 0.12, altitude)
	_source_strength = smoothstep(0.0, 0.16, absf(altitude))
	sunlight.light_color = Color("#ffe8cb").lerp(Color("#a9c6ff"), _night_mix)
	light_intensity(_direct_strength)
	_celestial_sky.set_shader_parameter("night_mix", _night_mix)
	_celestial_sky.set_shader_parameter("source_is_moon", moon)
	_celestial_sky.set_shader_parameter("source_strength", _source_strength)
	_update_light_source()


func source_visible(enabled: bool) -> void:
	_show_source = enabled
	_update_light_source()


func _update_light_source() -> void:
	_celestial_sky.set_shader_parameter("source_direction", sunlight.basis.z.normalized())
	_celestial_sky.set_shader_parameter("show_source", _show_source and sunlight.visible)


func aim_at_light() -> void:
	var target := sunlight.basis.z.normalized()
	var side := target.cross(Vector3.UP)
	if side.is_zero_approx():
		side = Vector3.RIGHT
	side = side.normalized()
	var above := side.cross(target)
	var half_height := tan(deg_to_rad(camera.fov * 0.5))
	var half_width := half_height * maxf(0.1, size.x / maxf(1.0, size.y))
	if model:
		_center = _placed_model_center()
		# Leave enough sky beside the model for the disc at any viewport aspect.
		_distance = maxf(_distance, _radius * (1.0 + 1.0 / (0.58 * minf(half_width, half_height))))
	orient_to(-(target - side * half_width * 0.76 - above * half_height * 0.38))


func reflections_enabled(enabled: bool) -> void:
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY if enabled \
		else Environment.REFLECTION_SOURCE_DISABLED


func reset_hdri() -> bool:
	environment.ambient_light_color = Color("#bfc7d7")
	var found := select_hdri(0)
	if not found:
		_set_panorama(null)
	return found


func select_hdri(index: int) -> bool:
	if index < 0 or index >= HDRI_PRESETS.size():
		return false
	if not _hdri_textures.has(index):
		var path: String = HDRI_PRESETS[index]
		if ResourceLoader.exists(path):
			_hdri_textures[index] = ResourceLoader.load(path) as Texture2D
	var panorama: Texture2D = _hdri_textures.get(index)
	if not panorama:
		return false
	_set_panorama(panorama)
	return true


func preload_hdri(index: int) -> void:
	if _hdri_textures.has(index):
		return
	var path: String = HDRI_PRESETS[index]
	if ResourceLoader.load_threaded_request(path, "Texture2D") != OK:
		return
	var status := ResourceLoader.load_threaded_get_status(path)
	while status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await get_tree().process_frame
		status = ResourceLoader.load_threaded_get_status(path)
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		_hdri_textures[index] = ResourceLoader.load_threaded_get(path) as Texture2D


func _set_panorama(texture: Texture2D) -> void:
	_sky_material.panorama = texture
	_celestial_sky.set_shader_parameter("panorama", texture)
	_celestial_sky.set_shader_parameter("has_panorama", texture != null)
	hdri_intensity(_sky_material.energy_multiplier)
	hdri_enabled(_hdri_on)


func set_hdri(path: String) -> String:
	return apply_hdri(decode_hdri(path))


static func decode_hdri(path: String) -> Variant:
	var image := Image.new()
	var error := image.load(path)
	if error != OK:
		return error
	if image.get_height() * 2 != image.get_width():
		return ERR_INVALID_DATA
	return image


func apply_hdri(decoded: Variant) -> String:
	if decoded is int:
		if decoded == ERR_INVALID_DATA:
			return tr("Použij equirektangulární HDRI s poměrem 2 : 1.")
		return tr("HDRI nelze načíst (%s).") % error_string(decoded)
	if not decoded is Image:
		return tr("Načítání se nepodařilo spustit.")
	_set_panorama(ImageTexture.create_from_image(decoded))
	return ""


func wireframe(enabled: bool) -> void:
	display_mode(WIREFRAME_MODE if enabled else 0)


func set_wireframe_width(value: float) -> void:
	_wireframe_width = clampf(value, WIREFRAME_WIDTH_MIN, WIREFRAME_WIDTH_MAX)
	if _wireframe_material:
		_wireframe_material.set_shader_parameter("width_px", _wireframe_width)


func display_mode(index: int) -> void:
	_display_mode = index
	viewport_3d.debug_draw = DRAW_MODES[index] if index < DRAW_MODES.size() else Viewport.DEBUG_DRAW_DISABLED
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR if index >= COLOR_MODE else Environment.TONE_MAPPER_AGX
	_apply_model_display()


func color_preview(layer: String, channel: int) -> void:
	if layer == _color_layer and channel == _color_channel:
		return
	_color_layer = layer
	_color_channel = channel
	if _display_mode == COLOR_MODE:
		_apply_model_display()


func isolate(instance: MeshInstance3D, surface := -1) -> void:
	if instance == _isolated and surface == _isolated_surface:
		return
	_isolated = instance
	_isolated_surface = surface
	_apply_model_display()


func is_part_visible(instance: MeshInstance3D) -> bool:
	return not _hidden_parts.has(instance)


func set_part_visible(instance: MeshInstance3D, visible_part: bool) -> void:
	if not _mesh_layers.has(instance):
		return
	if visible_part:
		_hidden_parts.erase(instance)
	else:
		_hidden_parts[instance] = true
	_apply_model_display()


func hidden_parts_state() -> Array[String]:
	var paths: Array[String]
	if model:
		for instance: MeshInstance3D in _hidden_parts:
			paths.append(str(model.root.get_path_to(instance)))
	return paths


func restore_hidden_parts(paths: Variant) -> void:
	if not model or not paths is Array:
		return
	_hidden_parts.clear()
	for path: Variant in paths:
		if path is String:
			var instance := model.root.get_node_or_null(NodePath(path)) as MeshInstance3D
			if _mesh_layers.has(instance):
				_hidden_parts[instance] = true
	_apply_model_display()


func model_gizmo_tool(tool: int) -> void:
	_model_gizmo.mode = tool
	_model_gizmo.cancel_drag()
	_model_gizmo.queue_redraw()


func isolation_state() -> Dictionary:
	if not _isolated:
		return {}
	var state := {"node": str(model.root.get_path_to(_isolated)), "surface": _isolated_surface}
	if _isolated_surface >= 0:
		state["material"] = model.surface_material_name(_isolated, _isolated_surface)
	return state


func _apply_model_display() -> void:
	if not model:
		return
	for nodes in _inspection_nodes.values():
		for preview: MeshInstance3D in nodes:
			preview.hide()
			preview.queue_free()
	_inspection_nodes.clear()
	var attributes := _display_mode >= COLOR_MODE
	var input := _color_layer if _display_mode == COLOR_MODE else ""
	if attributes and input != _attribute_input:
		_attribute_meshes = model.inspection_meshes(input)
		_attribute_input = input
	var points := _display_mode == POINTS_MODE
	var quads := _display_mode == QUADS_MODE
	var wires := _display_mode == WIREFRAME_MODE
	if wires:
		_prepare_wireframe()
	if points and _point_instances.is_empty():
		_make_point_instances()
	if quads:
		_prepare_quads()
	for instance in model.meshes:
		var visible_part := not _hidden_parts.has(instance) and (not _isolated or instance == _isolated)
		var surface := _isolated_surface if instance == _isolated else -1
		var original_layers := _mesh_layers[instance]
		instance.layers = original_layers if visible_part and surface == -1 and not attributes else 0
		var wire_view := _wireframe_instances.get(instance) as MeshInstance3D
		var point_view := _point_instances.get(instance) as MeshInstance3D
		var quad_view := _quad_instances.get(instance) as MeshInstance3D
		if wire_view:
			wire_view.visible = wires and visible_part and surface == -1
			wire_view.layers = original_layers
			if wire_view.visible:
				instance.layers = 0
		if point_view:
			point_view.visible = points and visible_part and surface == -1
			point_view.layers = original_layers
			if point_view.visible:
				instance.layers = 0
		if quad_view:
			quad_view.visible = quads and visible_part and surface == -1
			quad_view.layers = original_layers
		if visible_part and (attributes or surface >= 0):
			_make_inspection_view(instance, surface, attributes, points, quads)


func _make_inspection_view(instance: MeshInstance3D, surface: int, attributes: bool, points: bool, quads: bool) -> void:
	if _display_mode == WIREFRAME_MODE:
		var wires := _wireframe_meshes.get(instance.mesh) as ArrayMesh
		if wires and surface >= 0 and surface < wires.get_surface_count() \
				and wires.surface_get_primitive_type(surface) == Mesh.PRIMITIVE_TRIANGLES:
			var part := _copy_surface(wires, surface)
			if part:
				_add_inspection_node(instance, part, _wireframe_material)
				return
	var mesh := _attribute_meshes.get(instance) as ArrayMesh if attributes else instance.mesh as ArrayMesh
	var has_mesh := mesh != null
	if not has_mesh:
		mesh = instance.mesh as ArrayMesh
	if not mesh:
		return
	if surface >= 0:
		mesh = _copy_surface(mesh, surface)
		if not mesh:
			return
	if points:
		_add_inspection_node(instance, _make_point_mesh(mesh), _point_material)
		return
	var preview := _add_inspection_node(instance, mesh, null)
	if attributes:
		for index in range(mesh.get_surface_count()):
			var source_index := surface if surface >= 0 else index
			preview.set_surface_override_material(index, _preview_material(instance, mesh, index, source_index, has_mesh))
	else:
		preview.cast_shadow = instance.cast_shadow
		preview.set_surface_override_material(0, instance.get_active_material(surface))
	if quads:
		var outline: ArrayMesh = TopologyOverlay.build(mesh).mesh
		if outline.get_surface_count() > 0:
			_add_inspection_node(instance, outline, _quad_material)


func _add_inspection_node(instance: MeshInstance3D, mesh: ArrayMesh, material: Material) -> MeshInstance3D:
	var preview := _make_debug_instance(instance, mesh, material)
	preview.layers = _mesh_layers[instance]
	_copy_morphs(instance, preview)
	if not _inspection_nodes.has(instance):
		_inspection_nodes[instance] = []
	_inspection_nodes[instance].append(preview)
	return preview


func _preview_material(instance: MeshInstance3D, mesh: ArrayMesh, surface: int, source_surface: int, imported: bool) -> ShaderMaterial:
	var flags := mesh.surface_get_format(surface)
	var mode := _color_channel
	var present := bool(flags & Mesh.ARRAY_FORMAT_COLOR)
	if _display_mode == COLOR_MODE and mode == 4:
		present = present and model.has_color_alpha(instance, source_surface, _color_layer)
	elif _display_mode == UV0_MODE:
		mode = 5
		present = bool(flags & Mesh.ARRAY_FORMAT_TEX_UV)
	elif _display_mode == UV2_MODE:
		mode = 6
		present = bool(flags & Mesh.ARRAY_FORMAT_TEX_UV2)
	var key := Vector2i(mode, int(present and imported))
	if not _attribute_materials.has(key):
		var material := ShaderMaterial.new()
		material.shader = ATTRIBUTE_SHADER
		material.set_shader_parameter("mode", mode)
		material.set_shader_parameter("has_attribute", bool(key.y))
		_attribute_materials[key] = material
	return _attribute_materials[key]


func _copy_surface(source: ArrayMesh, surface: int) -> ArrayMesh:
	if surface >= source.get_surface_count():
		return null
	var mesh := ArrayMesh.new()
	mesh.blend_shape_mode = source.blend_shape_mode
	for shape in range(source.get_blend_shape_count()):
		mesh.add_blend_shape(source.get_blend_shape_name(shape))
	var flags := source.surface_get_format(surface)
	mesh.add_surface_from_arrays(source.surface_get_primitive_type(surface), source.surface_get_arrays(surface),
		source.surface_get_blend_shape_arrays(surface), {}, flags)
	return mesh


func _prepare_wireframe() -> void:
	if _wireframe_prepared:
		return
	_wireframe_prepared = true
	for instance in model.meshes:
		var source := instance.mesh as ArrayMesh
		if source == null:
			continue
		if not _wireframe_meshes.has(source):
			_wireframe_meshes[source] = WireframeMesh.build(source)
		var mesh: ArrayMesh = _wireframe_meshes[source]
		if not mesh:
			continue
		var preview := _make_debug_instance(instance, mesh, null)
		for surface in range(mesh.get_surface_count()):
			var material := instance.get_active_material(surface)
			if mesh.surface_get_primitive_type(surface) == Mesh.PRIMITIVE_TRIANGLES:
				material = _wireframe_material
			preview.set_surface_override_material(surface, material)
		_copy_morphs(instance, preview)
		_wireframe_instances[instance] = preview


func quad_statistics() -> Vector2i:
	_prepare_quads()
	return _quad_statistics


func _prepare_quads() -> void:
	if not model or _quads_prepared:
		return
	_quads_prepared = true
	var converted: Dictionary[ArrayMesh, Dictionary]
	for instance in model.meshes:
		var source := instance.mesh as ArrayMesh
		if source == null:
			continue
		if not converted.has(source):
			converted[source] = TopologyOverlay.build(source)
		var result := converted[source]
		_quad_statistics += result.statistics
		var overlay_mesh: ArrayMesh = result.mesh
		if overlay_mesh.get_surface_count() > 0:
			var overlay := _make_debug_instance(instance, overlay_mesh, _quad_material)
			overlay.hide()
			_quad_instances[instance] = overlay


func set_point_size(value: float) -> void:
	_point_material.point_size = clampf(value, 1.0, 32.0)


func _make_point_instances() -> void:
	var converted: Dictionary[ArrayMesh, ArrayMesh]
	for instance in model.meshes:
		var source := instance.mesh as ArrayMesh
		if source == null:
			continue
		if not converted.has(source):
			converted[source] = _make_point_mesh(source)
		var point_mesh := converted[source]
		if point_mesh.get_surface_count() == 0:
			continue
		_point_instances[instance] = _make_debug_instance(instance, point_mesh, _point_material)


func _make_debug_instance(instance: MeshInstance3D, mesh: ArrayMesh, material: Material) -> MeshInstance3D:
	var debug_instance := MeshInstance3D.new()
	debug_instance.mesh = mesh
	debug_instance.material_override = material
	debug_instance.layers = instance.layers
	debug_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.add_child(debug_instance)
	var skeleton := instance.get_node_or_null(instance.skeleton) as Skeleton3D
	if skeleton:
		debug_instance.skin = instance.skin
		debug_instance.skeleton = debug_instance.get_path_to(skeleton)
	return debug_instance


func _make_point_mesh(source: ArrayMesh) -> ArrayMesh:
	var points := ArrayMesh.new()
	points.blend_shape_mode = source.blend_shape_mode
	for shape in range(source.get_blend_shape_count()):
		points.add_blend_shape(source.get_blend_shape_name(shape))
	for surface in range(source.get_surface_count()):
		var original := source.surface_get_arrays(surface)
		var vertices: Array = []
		vertices.resize(Mesh.ARRAY_MAX)
		vertices[Mesh.ARRAY_VERTEX] = original[Mesh.ARRAY_VERTEX]
		vertices[Mesh.ARRAY_BONES] = original[Mesh.ARRAY_BONES]
		vertices[Mesh.ARRAY_WEIGHTS] = original[Mesh.ARRAY_WEIGHTS]
		var shapes: Array[Array] = []
		for shape in source.surface_get_blend_shape_arrays(surface):
			var positions: Array = []
			positions.resize(Mesh.ARRAY_MAX)
			positions[Mesh.ARRAY_VERTEX] = shape[Mesh.ARRAY_VERTEX]
			shapes.append(positions)
		var flags := source.surface_get_format(surface) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		points.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, vertices, shapes, {}, flags)
	return points


func _sync_debug_morphs(instances: Dictionary[MeshInstance3D, MeshInstance3D]) -> void:
	for instance in instances:
		_copy_morphs(instance, instances[instance])


func _copy_morphs(instance: MeshInstance3D, preview: MeshInstance3D) -> void:
	for shape in range(mini(instance.get_blend_shape_count(), preview.get_blend_shape_count())):
		preview.set_blend_shape_value(shape, instance.get_blend_shape_value(shape))


func screenshot(path: String) -> Error:
	if capture_in_progress or not model:
		return ERR_BUSY
	if DisplayServer.get_name() == "headless":
		return ERR_UNAVAILABLE
	capture_in_progress = true
	var capture := SubViewport.new()
	capture.size = SCREENSHOT_SIZE
	capture.world_3d = viewport_3d.find_world_3d()
	capture.msaa_3d = viewport_3d.msaa_3d
	capture.screen_space_aa = viewport_3d.screen_space_aa
	capture.debug_draw = viewport_3d.debug_draw
	capture.transparent_bg = viewport_3d.transparent_bg
	capture.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport_3d.add_child(capture)
	if _background_on and _background == 0:
		capture.add_child(_make_studio_backdrop())
	var capture_camera := Camera3D.new()
	capture_camera.projection = camera.projection
	capture_camera.fov = camera.fov
	capture_camera.size = camera.size
	capture_camera.near = camera.near
	capture_camera.far = camera.far
	capture.add_child(capture_camera)
	capture_camera.global_transform = camera.global_transform
	capture_camera.make_current()
	capture.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var image := capture.get_texture().get_image()
	capture.queue_free()
	capture_in_progress = false
	return image.save_png(path) if image and not image.is_empty() else ERR_CANT_CREATE
