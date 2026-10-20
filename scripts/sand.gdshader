shader_type spatial;
render_mode diffuse_lambert, specular_disabled, cull_back;

// Matte bunker sand with a fine world-space ripple. No texture fetch.

uniform vec4 base_color : source_color = vec4(0.824, 0.741, 0.518, 1.0);
uniform vec2 ripple_dir = vec2(0.7, 0.7);
uniform float ripple_freq : hint_range(0.0, 60.0) = 22.0;
uniform float ripple_strength : hint_range(0.0, 0.2) = 0.05;
uniform float grain_strength : hint_range(0.0, 0.3) = 0.05;
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

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 wxz = world_pos.xz;

	// Sand grain speckle.
	float grain = value_noise(wxz * 14.0) - 0.5;

	// Fine sinusoidal ripple along ripple_dir, broken up a touch by noise.
	vec2 dir = normalize(ripple_dir + vec2(0.0001, 0.0));
	float wobble = (value_noise(wxz * 3.0) - 0.5) * 2.0;
	float ripple = sin(dot(wxz, dir) * ripple_freq + wobble);

	float light = ripple * ripple_strength + grain * 2.0 * grain_strength;
	vec3 col = base_color.rgb * (1.0 + light);

	float facing = clamp(NORMAL.y, 0.0, 1.0);
	col *= mix(0.80, 1.0, facing);

	ALBEDO = clamp(col, vec3(0.0), vec3(1.0));
	ROUGHNESS = clamp(roughness - ripple * 0.08, 0.0, 1.0);
	METALLIC = 0.0;
	SPECULAR = 0.1;
}
