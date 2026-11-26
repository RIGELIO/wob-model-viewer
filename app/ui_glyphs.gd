extends RefCounted

const PATHS := {
	"chevron_down": '<path d="M4 8l8 8 8-8"/>',
	"chevron_right": '<path d="M8 4l8 8-8 8"/>',
	"dot": '<circle cx="12" cy="12" r="10.3" fill="currentColor"/>',
	"scene": '<path d="M10 2h4v4h-4zM2 18h4v4H2zM10 18h4v4h-4zM18 18h4v4h-4zM12 6v12M4 18v-6h16v6"/>',
	"cube": '<path d="M12 2l9 5v10l-9 5-9-5V7zM3 7l9 5 9-5M12 12v10"/>',
	"mesh": '<path d="M12 3l9 17H3zM7 14h10M12 3v11"/>',
	"layers": '<path d="M12 3l9 5-9 5-9-5zM3 12l9 5 9-5M3 16l9 5 9-5"/>',
	"bone": '<path d="M9 14l5-5c-1-3 2-5 4-3 2 2 0 5-2 5l-5 5c0 2-3 4-5 2-2-2 0-5 3-4z"/>',
	"clip": '<path d="M3 3h18v18H3zM7 3v18m10-18v18M3 8h4m10 0h4M3 16h4m10 0h4M7 12h10"/>',
	"sun": '<circle cx="12" cy="12" r="4.1"/><path d="M12 1v4m0 14v4M1 12h4m14 0h4M4.2 4.2 7 7m10 10 2.8 2.8M4.2 19.8 7 17M17 7l2.8-2.8"/>',
	"select": '<path fill="#110e0b" opacity=".48" stroke="none" d="M5.4 2.8v17.4l4.9-4.65 3.55 6.25 3.1-1.82-3.55-6.2 6.8-.48z"/><path fill="currentColor" stroke="none" d="M4.5 2.15v17.4l4.9-4.65 3.55 6.25 3.1-1.82-3.55-6.2 6.8-.48z"/>',
	"move": '<path d="M12 2v20M2 12h20M8 6l4-4 4 4M8 18l4 4 4-4M6 8l-4 4 4 4m12-8 4 4-4 4"/>',
	"rotate": '<path d="M12 3a9 9 0 11-6 2.5M12 1v6l5-4"/>',
	"frame": '<path d="M3 9V3h6m6 0h6v6m0 6v6h-6m-6 0H3v-6m0 6 5-5m13-13-5 5"/>',
	"grid": '<path d="M3 3h18v18H3zM9 3v18m6-18v18M3 9h18m-18 6h18"/>',
	"fullscreen": '<path d="M3 9V3h6m6 0h6v6m0 6v6h-6m-6 0H3v-6"/>',
	"play": '<path fill="currentColor" d="M7 3l14 9-14 9z"/>',
	"pause": '<path fill="currentColor" d="M7 4h3v16H7zm7 0h3v16h-3z"/>',
	"previous": '<path d="M5 4v16"/><path fill="currentColor" d="M20 4v16L8 12z"/>',
	"next": '<path d="M19 4v16"/><path fill="currentColor" d="M4 4v16l12-8z"/>',
	"loop": '<path d="M4 11V8a4 4 0 014-4h12M17 1l3 3-3 3M20 13v3a4 4 0 01-4 4H4m3 3-3-3 3-3"/>',
	"folder": '<path d="M3 5h7l2 3h9v12H3zM3 11h18"/>',
	"dropper": '<path d="M8 15l8-8m-3-1 4 4m-7 4 1 3-5 2-1-1 2-5zM16 7l2-3a2 2 0 013 3l-3 2"/>',
}

static var cache: Dictionary[String, Texture2D]


static func texture(name: String, color: Color, size: int = 20) -> Texture2D:
	var key := "%s-%s-%d" % [name, color.to_html(), size]
	if cache.has(key):
		return cache[key]
	var hex := color.to_html(false)
	var markup := str(PATHS.get(name, "")).replace("currentColor", "#" + hex)
	var source := '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 24 24"><g stroke="#%s" stroke-width="1.55" stroke-linecap="round" stroke-linejoin="round" fill="none">%s</g></svg>' % [size, size, hex, markup]
	var pixels := Image.new()
	if pixels.load_svg_from_string(source) != OK:
		return null
	var result := ImageTexture.create_from_image(pixels)
	cache[key] = result
	return result


static func tool_surface() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#39322b")
	style.border_color = Color("#8b714d")
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.shadow_color = Color(0.06, 0.05, 0.04, 0.65)
	style.shadow_size = 2
	style.shadow_offset = Vector2(0, 1)
	style.set_content_margin_all(7.0)
	return style


static func active_tab() -> StyleBoxTexture:
	var image := Image.create_empty(158, 48, false, Image.FORMAT_RGBA8)
	for y in image.get_height():
		for x in image.get_width():
			var amount := clampf(0.8 - absf(x - 45.0) / 145.0 + y / 160.0, 0.0, 1.0)
			var color := Color("#272420").lerp(Color("#332c28"), amount)
			if y == 0 or x == 0 or x == 157:
				color = Color("#433b35")
			elif y == 1 or x == 1:
				color = color.lightened(0.05)
			if y >= 46:
				color = Color("#d4ac70") if y == 46 else Color("#b38d59")
			image.set_pixel(x, y, color)
	var style := StyleBoxTexture.new()
	style.texture = ImageTexture.create_from_image(image)
	style.texture_margin_bottom = 2.0
	style.set_content_margin_all(10.0)
	return style


static func play_surface(brightness: float = 0.0) -> StyleBoxTexture:
	var image := Image.create_empty(58, 58, false, Image.FORMAT_RGBA8)
	for y in 58:
		for x in 58:
			var distance := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(29, 29))
			var color := Color("#e6c184").lerp(Color("#cfa466"), y / 57.0).lightened(brightness)
			if distance > 27.8:
				color = color.lightened(0.2)
			color.a = clampf(29.0 - distance, 0.0, 1.0)
			image.set_pixel(x, y, color)
	var style := StyleBoxTexture.new()
	style.texture = ImageTexture.create_from_image(image)
	return style


static func playhead() -> Texture2D:
	var image := Image.create_empty(10, 36, false, Image.FORMAT_RGBA8)
	for y in 36:
		var width := 1 if y >= 31 else 8
		var color := Color("#f8dd93").lerp(Color("#d7ae72"), y / 35.0)
		for x in width:
			image.set_pixel(floori((10 - width) * 0.5) + x, y, color)
	return ImageTexture.create_from_image(image)
