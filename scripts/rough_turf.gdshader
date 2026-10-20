shader_type spatial;
render_mode diffuse_lambert, specular_disabled, cull_back;

// Matte rough / deep-rough turf: higher-frequency mottled grass-tuft noise,
// NO mowing stripes (rough is unmown). World-space XZ, no texture fetch.

uniform vec4 base_color : source_color = vec4(0.184, 0.314, 0.188, 1.0);
uniform float tuft_scale : hint_range(1.0, 40.0) = 16.0;
uniform float tuft_strength : hint_range(0.0, 0.3) = 0.08;
uniform float roughness : hint_range(0.0, 1.0) = 1.0;

varying vec3 world_pos;

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash2(i);
	float b = hash2(i + vec2(1.0, 0.0));
	float c = hash2(i + vec2(0.0, 1.0));
	float d = hash2(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Two octaves of value noise for a mottled, clumpy tuft break-up.
float fbm(vec2 p) {
	return value_noise(p) * 0.65 + value_noise(p * 2.3 + 11.0) * 0.35;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 wxz = world_pos.xz;

	float tuft = fbm(wxz * tuft_scale) - 0.5;
	vec3 col = base_color.rgb * (1.0 + tuft * 2.0 * tuft_strength);

	float facing = clamp(NORMAL.y, 0.0, 1.0);
	col *= mix(0.76, 1.0, facing);

	ALBEDO = clamp(col, vec3(0.0), vec3(1.0));
	ROUGHNESS = clamp(roughness - tuft * 0.12, 0.0, 1.0);
	METALLIC = 0.0;
	SPECULAR = 0.1;
}
