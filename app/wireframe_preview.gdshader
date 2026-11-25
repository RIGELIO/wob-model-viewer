shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_always, shadows_disabled;

uniform float width_px : hint_range(0.5, 8.0) = 1.2;
varying vec4 barycentric_and_clip_w;

void vertex() {
	POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	int corner = VERTEX_ID % 3;
	vec3 barycentric = vec3(float(corner == 0), float(corner == 1), float(corner == 2));
	// Undo perspective interpolation so gradients measure the distance in pixels.
	barycentric_and_clip_w = vec4(barycentric, 1.0) * POSITION.w;
}

void fragment() {
	vec3 barycentric = barycentric_and_clip_w.xyz / barycentric_and_clip_w.w;
	vec3 dx = dFdx(barycentric);
	vec3 dy = dFdy(barycentric);
	vec3 distances = barycentric / max(sqrt(dx * dx + dy * dy), vec3(0.000001));
	float distance_to_edge = min(distances.x, min(distances.y, distances.z));
	float coverage = clamp(width_px * 0.5 + 0.5 - distance_to_edge, 0.0, 1.0);
	if (coverage <= 0.0) {
		discard;
	}
	ALBEDO = vec3(1.0, 0.63, 0.30);
	ALPHA = coverage;
}
