shader_type sky;

uniform sampler2D panorama : source_color, filter_linear, repeat_enable;
uniform bool has_panorama;
uniform bool night;
uniform bool show_source;
uniform float panorama_rotation;
uniform float exposure = 1.0;
uniform vec3 source_direction = vec3(0.0, 1.0, 0.0);

float crater(vec2 position, vec2 center, float radius) {
	return 1.0 - smoothstep(radius * 0.7, radius, length(position - center));
}

void sky() {
	float elevation = max(EYEDIR.y, 0.0);
	vec3 horizon = night ? vec3(0.027, 0.047, 0.090) : vec3(0.49, 0.65, 0.81);
	vec3 zenith = night ? vec3(0.004, 0.010, 0.032) : vec3(0.085, 0.27, 0.62);
	vec3 air = mix(horizon, zenith, pow(elevation, 0.6));
	vec2 uv = vec2(fract(SKY_COORDS.x + panorama_rotation), clamp(SKY_COORDS.y, 0.0, 1.0));
	vec3 photo = has_panorama ? texture(panorama, uv).rgb : air;
	photo = night ? min(photo, vec3(0.45)) * vec3(0.28, 0.40, 0.65) : min(photo, vec3(3.0));
	float sky_weight = has_panorama ? smoothstep(-0.10, 0.6, EYEDIR.y) * (night ? 0.78 : 0.42) : 1.0;
	COLOR = mix(photo, air, sky_weight) * exposure;
	if (night && AT_CUBEMAP_PASS) {
		COLOR += vec3(0.018, 0.026, 0.046) * exposure;
	}

	if (night && !AT_CUBEMAP_PASS) {
		vec2 cells = SKY_COORDS * vec2(840.0, 420.0);
		float seed = fract(sin(dot(floor(cells), vec2(13.1, 89.3))) * 43758.55);
		float star = step(0.998, seed) * (1.0 - smoothstep(0.05, 0.24, length(fract(cells) - 0.5)));
		COLOR += star * smoothstep(0.06, 0.55, elevation) * vec3(0.24, 0.31, 0.45);
	}

	if (show_source && !AT_CUBEMAP_PASS) {
		float facing = dot(EYEDIR, source_direction);
		float radius = night ? 0.023 : 0.020;
		float disk = smoothstep(cos(radius * 1.04), cos(radius * 0.96), facing);
		float halo = exp(-max(0.0, 1.0 - facing) * (night ? 780.0 : 260.0));
		vec3 disc_color = night ? vec3(1.45, 1.57, 1.78) : vec3(8.0, 5.4, 2.4);
		if (night && disk > 0.0) {
			vec3 reference = abs(source_direction.y) > 0.97 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 1.0, 0.0);
			vec3 right = normalize(cross(reference, source_direction));
			vec3 up = cross(source_direction, right);
			vec2 surface = vec2(dot(EYEDIR, right), dot(EYEDIR, up)) / radius;
			float marks = crater(surface, vec2(-0.28, 0.16), 0.31)
				+ crater(surface, vec2(0.30, -0.23), 0.24) * 0.7
				+ crater(surface, vec2(0.08, 0.38), 0.17) * 0.8;
			disc_color *= 0.94 - min(marks, 1.0) * 0.42;
		}
		vec3 glow = night ? vec3(0.045, 0.071, 0.14) : vec3(0.41, 0.30, 0.15);
		COLOR = mix(COLOR + glow * halo, disc_color, disk);
	}
}
