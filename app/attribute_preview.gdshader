shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

// 0: RGB, 1–4: R/G/B/A, 5: first UV set, 6: second UV set.
uniform int mode = 0;
uniform bool has_attribute = true;

void fragment() {
	if (!has_attribute) {
		float stripe = step(0.5, fract((FRAGCOORD.x + FRAGCOORD.y) / 12.0));
		ALBEDO = mix(vec3(0.10, 0.02, 0.07), vec3(0.45, 0.13, 0.27), stripe);
	} else if (mode == 0) {
		ALBEDO = COLOR.rgb;
	} else if (mode <= 4) {
		ALBEDO = vec3(COLOR[mode - 1]);
	} else {
		vec2 coords = mode == 5 ? UV : UV2;
		vec2 cell = coords * 10.0;
		vec2 tile = floor(cell);
		float checker = mod(tile.x + tile.y, 2.0);
		vec2 edge = min(fract(cell), 1.0 - fract(cell));
		vec2 aa = max(fwidth(cell), vec2(0.001));
		vec2 grid = smoothstep(vec2(0.0), aa * 1.25, edge);
		vec3 tint = mix(vec3(0.11, 0.32, 0.53), vec3(0.70, 0.39, 0.13), fract(coords.x));
		ALBEDO = mix(vec3(0.035), tint * mix(0.40, 1.0, checker), grid.x * grid.y);
	}
}
