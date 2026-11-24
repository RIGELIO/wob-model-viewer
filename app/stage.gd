extends SubViewportContainer

const Materials = preload("res://materials.gd")
const TopologyOverlay = preload("res://topology_overlay.gd")
const BUILTIN_HDRI := "res://production/lighting/lilienstein_2k.hdr"
const SCREENSHOT_SIZE := Vector2i(3840, 2160)
const ORBIT_SPEED := 0.008
const AUTO_ORBIT_SPEED := 0.38
const POINTS_MODE := 5
const QUADS_MODE := 6
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
	Viewport.DEBUG_DRAW_DISABLED, Viewport.DEBUG_DRAW_WIREFRAME, Viewport.DEBUG_DRAW_UNSHADED,
	Viewport.DEBUG_DRAW_NORMAL_BUFFER, Viewport.DEBUG_DRAW_OVERDRAW,
]

var viewport_3d: SubViewport
var camera: Camera3D
var environment: Environment
var sunlight: DirectionalLight3D
var model: Materials
var clips: Array[Dictionary]
var animation_player: AnimationPlayer
var current_clip: StringName
var geometry := Vector4i.ZERO
var bounds := AABB()
var capture_in_progress := false

var _sky_material: PanoramaSkyMaterial
var _studio_hdri: Texture2D
var _grid: MeshInstance3D
var _floor: MeshInstance3D
var _hdri_on := true
var _background := 0
var _custom_background := Color("#55575c")
var _center := Vector3.ZERO
var _radius := 1.0
var _distance := 3.0
var _yaw := 0.26
var _pitch := 0.04
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
var _quad_material: ShaderMaterial
var _quad_instances: Dictionary[MeshInstance3D, MeshInstance3D]
var _quad_statistics := Vector2i.ZERO
var _quads_prepared := false
var _display_mode := 0


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

	environment = Environment.new()
	environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.sky = Sky.new()
	environment.sky.radiance_size = Sky.RADIANCE_SIZE_128
	_sky_material = PanoramaSkyMaterial.new()
	environment.sky.sky_material = _sky_material
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	viewport_3d.add_child(world_environment)
	if ResourceLoader.exists(BUILTIN_HDRI):
		_studio_hdri = ResourceLoader.load(BUILTIN_HDRI) as Texture2D
	reset_hdri()
	background(0)

	sunlight = DirectionalLight3D.new()
	sunlight.shadow_enabled = true
	viewport_3d.add_child(sunlight)
	light_direction(-35.0, 42.0)
	sunlight.light_energy = 1.25

	camera = Camera3D.new()
	camera.fov = 34.0
	viewport_3d.add_child(camera)
	camera.make_current()
	_update_camera()
	resized.connect(_update_camera)
	get_window().focus_exited.connect(_end_drag)

	_floor = MeshInstance3D.new()
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("#383937")
	floor_material.roughness = 0.9
	_floor.material_override = floor_material
	_floor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_floor.hide()
	viewport_3d.add_child(_floor)

	_grid = MeshInstance3D.new()
	_grid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_grid.hide()
	viewport_3d.add_child(_grid)

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

	_quad_material = ShaderMaterial.new()
	var line_shader := Shader.new()
	line_shader.code = QUAD_LINE_SHADER
	_quad_material.shader = line_shader


func load_model(path: String, manifest: RefCounted = null) -> String:
	if not path.get_extension().to_lower() in ["glb", "gltf"]:
		return tr("Vyber soubor ve formátu GLB nebo glTF.")
	var pending := Materials.new()
	var error := pending.import_model(path, manifest)
	if not error.is_empty():
		return error
	if model:
		_show_point_view(false)
		viewport_3d.remove_child(model.root)
		model.root.queue_free()
	_point_instances.clear()
	_quad_instances.clear()
	_quad_statistics = Vector2i.ZERO
	_quads_prepared = false
	_skeletons.clear()
	_bone_lines.clear_surfaces()
	model = pending
	viewport_3d.add_child(model.root)
	_inspect_model()
	animation_player = null
	current_clip = &""
	clips.clear()
	_collect_clips(model.root)
	frame()
	_make_floor_and_grid()
	_show_point_view(_display_mode == POINTS_MODE)
	_show_quad_view(_display_mode == QUADS_MODE)
	if _skeleton_overlay.visible:
		_draw_skeletons()
	return ""


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


func select_clip(index: int) -> float:
	if animation_player:
		animation_player.stop()
	animation_player = clips[index].player
	current_clip = clips[index].name
	animation_player.play(current_clip)
	animation_player.advance(0)
	animation_player.pause()
	return animation_player.get_animation(current_clip).length


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


func frame(direction := Vector2(0.26, 0.04)) -> void:
	_center = bounds.get_center()
	_radius = maxf(bounds.size.length() * 0.5, 0.0001)
	_yaw = direction.x
	_pitch = direction.y
	var half_height := tan(deg_to_rad(camera.fov * 0.5))
	var half_width := half_height * maxf(0.1, size.x / maxf(1.0, size.y))
	var inverse_view := Basis.looking_at(-_orbit_direction()).transposed()
	_distance = _radius * 1.1
	for corner in range(8):
		var local := inverse_view * (bounds.get_endpoint(corner) - _center)
		var fit := maxf(absf(local.x) / half_width, absf(local.y) / half_height) * 1.16
		if camera.projection == Camera3D.PROJECTION_PERSPECTIVE:
			fit += local.z
		_distance = maxf(_distance, fit)
	_update_camera()


func _gui_input(event: InputEvent) -> void:
	if not model:
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
			_yaw -= event.relative.x * ORBIT_SPEED
			_pitch = clampf(_pitch + event.relative.y * ORBIT_SPEED, -1.555, 1.555)
		else:
			return
		_update_camera()
		accept_event()


func _end_drag() -> void:
	_orbiting = false
	_panning = false


func zoom(inward: bool) -> void:
	if not model:
		return
	_distance = clampf(_distance * (0.86 if inward else 1.16), _radius * 0.015, _radius * 150.0)
	_update_camera()


func orient_to(direction: Vector3) -> void:
	if not model:
		return
	if absf(direction.y) == 1.0:
		_yaw = 0.0
		_pitch = signf(direction.y) * 1.555
	else:
		_yaw = atan2(direction.x, direction.z)
		_pitch = 0.0
	_rotation_hold = 1.0
	_update_camera()


func auto_rotate_enabled(enabled: bool) -> void:
	_auto_orbit = enabled


func screen_space_panning(enabled: bool) -> void:
	_screen_space_panning = enabled


func _process(delta: float) -> void:
	if not model:
		return
	_rotation_hold = maxf(_rotation_hold - delta, 0.0)
	if _auto_orbit and _rotation_hold == 0.0 and not (_orbiting or _panning or capture_in_progress):
		_yaw = wrapf(_yaw + delta * AUTO_ORBIT_SPEED, -PI, PI)
		_update_camera()
	if _skeleton_overlay.visible:
		_draw_skeletons()
	if _display_mode == POINTS_MODE:
		_sync_debug_morphs(_point_instances)
	elif _display_mode == QUADS_MODE:
		_sync_debug_morphs(_quad_instances)


func _update_camera() -> void:
	if not camera:
		return
	camera.position = _center + _orbit_direction() * _distance
	camera.look_at(_center)
	camera.near = maxf(0.00001, minf(_distance * 0.12, _radius * 0.03))
	camera.far = maxf(1.0, _distance + _radius * 12.0)
	camera.size = 2.0 * _distance * tan(deg_to_rad(camera.fov * 0.5))


func _orbit_direction() -> Vector3:
	return Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch))


func background(index: int) -> void:
	_background = index
	if not _background_on:
		return
	var colors := [Color("#212226"), Color("#101113"), Color("#c9c9c5")]
	if index == 3:
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
		environment.background_mode = Environment.BG_CLEAR_COLOR


func custom_background(color: Color) -> void:
	_custom_background = color
	if _background == 4:
		background(4)


func orthographic(enabled: bool) -> void:
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL if enabled else Camera3D.PROJECTION_PERSPECTIVE


func camera_state() -> Dictionary:
	return {"target": [_center.x, _center.y, _center.z], "yaw": _yaw, "pitch": _pitch, "distance": _distance}


func restore_camera(data: Dictionary) -> void:
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
	_distance = clampf(float(data["distance"]), _radius * 0.015, _radius * 150.0)
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


func _make_floor_and_grid() -> void:
	var center := Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)
	var step := pow(10.0, floorf(log(_radius) / log(10.0))) * 0.2
	var half := maxf(4.0 * _radius, 12.0 * step)
	var cells := clampi(ceili(half / step), 12, 80)
	half = step * cells
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2.ONE * (2.0 * half)
	_floor.mesh = floor_mesh
	_floor.position = center - Vector3.UP * _radius * 0.005
	_grid.position = center
	var lines := ImmediateMesh.new()
	var line_style := StandardMaterial3D.new()
	line_style.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_style.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	line_style.vertex_color_use_as_albedo = true
	lines.surface_begin(Mesh.PRIMITIVE_LINES, line_style)
	for index in range(-cells, cells + 1):
		var offset := index * step
		var grid_color := Color(0.65, 0.60, 0.52, 0.48 if index % 5 == 0 else 0.20)
		_grid_line(lines, Vector3(-half, 0, offset), Vector3(half, 0, offset),
			Color("#ba7462") if index == 0 else grid_color)
		_grid_line(lines, Vector3(offset, 0, -half), Vector3(offset, 0, half),
			Color("#6e93bc") if index == 0 else grid_color)
	lines.surface_end()
	_grid.mesh = lines


func _grid_line(lines: ImmediateMesh, start: Vector3, finish: Vector3, color: Color) -> void:
	lines.surface_set_color(color)
	lines.surface_add_vertex(start)
	lines.surface_set_color(color)
	lines.surface_add_vertex(finish)


func light_direction(azimuth: float, elevation: float) -> void:
	sunlight.rotation_degrees = Vector3(-elevation, azimuth, 0)


func hdri_orientation(degrees: float) -> void:
	environment.sky_rotation = Vector3(0.0, deg_to_rad(degrees), 0.0)


func hdri_intensity(value: float) -> void:
	_sky_material.energy_multiplier = value
	environment.ambient_light_energy = 1.0 if _sky_material.panorama else value


func hdri_enabled(enabled: bool) -> void:
	_hdri_on = enabled
	if not enabled:
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	elif _sky_material.panorama:
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	else:
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR


func light_enabled(enabled: bool) -> void:
	sunlight.visible = enabled


func reflections_enabled(enabled: bool) -> void:
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY if enabled \
		else Environment.REFLECTION_SOURCE_DISABLED


func reset_hdri() -> bool:
	_sky_material.panorama = _studio_hdri
	hdri_intensity(_sky_material.energy_multiplier)
	environment.ambient_light_color = Color("#bfc7d7")
	hdri_enabled(_hdri_on)
	return _studio_hdri != null


func set_hdri(path: String) -> String:
	var image := Image.new()
	var error := image.load(path)
	if error != OK:
		return tr("HDRI nelze načíst (%s).") % error_string(error)
	if image.get_height() * 2 != image.get_width():
		return tr("Použij equirektangulární HDRI s poměrem 2 : 1.")
	_sky_material.panorama = ImageTexture.create_from_image(image)
	hdri_intensity(_sky_material.energy_multiplier)
	hdri_enabled(_hdri_on)
	return ""


func wireframe(enabled: bool) -> void:
	display_mode(1 if enabled else 0)


func display_mode(index: int) -> void:
	_display_mode = index
	viewport_3d.debug_draw = DRAW_MODES[index] if index < DRAW_MODES.size() else Viewport.DEBUG_DRAW_DISABLED
	_show_point_view(index == POINTS_MODE)
	_show_quad_view(index == QUADS_MODE)


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


func _show_quad_view(enabled: bool) -> void:
	if enabled:
		_prepare_quads()
	for instance in _quad_instances:
		var overlay := _quad_instances[instance]
		if enabled:
			overlay.layers = instance.layers
		overlay.visible = enabled
	if enabled:
		_sync_debug_morphs(_quad_instances)


func set_point_size(value: float) -> void:
	_point_material.point_size = clampf(value, 1.0, 32.0)


func _show_point_view(enabled: bool) -> void:
	if not model:
		return
	if not enabled:
		for instance in _mesh_layers:
			instance.layers = _mesh_layers[instance]
			_point_instances[instance].hide()
		_mesh_layers.clear()
		return
	if _point_instances.is_empty():
		_make_point_instances()
	for instance in _point_instances:
		if not _mesh_layers.has(instance):
			_mesh_layers[instance] = instance.layers
		var points := _point_instances[instance]
		points.layers = _mesh_layers[instance]
		points.show()
		instance.layers = 0
	_sync_debug_morphs(_point_instances)


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
		var overlay := instances[instance]
		for shape in range(instance.get_blend_shape_count()):
			overlay.set_blend_shape_value(shape, instance.get_blend_shape_value(shape))


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
