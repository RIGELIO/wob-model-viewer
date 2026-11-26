shader_type canvas_item;
render_mode unshaded;

uniform bool compact = false;
uniform vec2 source_size = vec2(1586.0, 992.0);

// Pixel coordinates in art/startup.png. Keep the portrait and lettering fixed.
const vec2 ORBIT_CENTER = vec2(787.0, 362.0);
const float LABEL_TOP = 706.0;

void fragment() {
	vec2 dimensions = source_size;
	vec2 pixel = compact ? ORBIT_CENTER + (UV - 0.5) * 722.0 : UV * dimensions;
	vec2 offset = pixel - ORBIT_CENTER;
	float radius = length(offset);
	float angle = TAU * fract(TIME / 4.4);
	float c = cos(angle);
	float s = sin(angle);
	vec2 moving_pixel = ORBIT_CENTER + vec2(c * offset.x + s * offset.y, -s * offset.x + c * offset.y);
	float band = smoothstep(304.0, 312.0, radius) * (1.0 - smoothstep(348.0, 355.0, radius));
	float below_orbit = smoothstep(LABEL_TOP - 7.0, LABEL_TOP, pixel.y);
	// Exclude the original lettering when it lies in a rotated sample.
	float original_lettering = smoothstep(LABEL_TOP - 7.0, LABEL_TOP, moving_pixel.y);
	vec3 base = texture(TEXTURE, pixel / dimensions).rgb;
	vec3 moving = texture(TEXTURE, moving_pixel / dimensions).rgb;
	vec3 quiet_background = texture(TEXTURE, vec2(0.26, 0.32)).rgb;
	moving = mix(moving, quiet_background, original_lettering);
	vec3 artwork = mix(base, moving, band * (1.0 - below_orbit));
	if (compact) {
		// Keep the leading bead legible when the full artwork is scaled down.
		vec2 bead = vec2(c, s) * 327.0;
		float glow = 1.0 - smoothstep(4.5, 19.0, length(offset - bead));
		float core = 1.0 - smoothstep(5.0, 12.0, length(offset - bead));
		artwork = mix(artwork, vec3(0.67, 0.37, 0.12), glow * 0.6);
		artwork = mix(artwork, vec3(1.0, 0.83, 0.5), core);
		float edge_fade = 1.0 - smoothstep(345.0, 360.0, radius);
		COLOR = vec4(artwork, edge_fade);
	} else {
		COLOR = vec4(artwork, 1.0);
	}
}
