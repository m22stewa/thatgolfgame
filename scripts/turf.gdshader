shader_type spatial;
render_mode diffuse_lambert, specular_disabled, cull_back;

// Matte felt turf with procedural grain and world-space mowing stripes.
// No texture fetch - cheap procedural noise only. World-space XZ is used for
// both grain and stripes so bands stay continuous across all MultiMesh
// instances (all tiles of a surface share one mesh/material).

uniform vec4 base_color : source_color = vec4(0.235, 0.443, 0.251, 1.0);
uniform vec2 stripe_dir = vec2(0.0, 1.0);
uniform float stripe_freq : hint_range(0.0, 20.0) = 3.0;
uniform float stripe_strength : hint_range(0.0, 0.3) = 0.05;
uniform float grain_strength : hint_range(0.0, 0.3) = 0.04;
uniform float roughness : hint_range(0.0, 1.0) = 1.0;

varying vec3 world_pos;

// Cheap value noise (hash-based) in 2D.
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

	// Fine felt grain: small value-noise modulating lightness a few percent.
	float grain = value_noise(wxz * 8.0) - 0.5;
	float grain_mix = grain * 2.0 * grain_strength;

	// Mowing stripes projected onto the play direction, softened bands.
	vec2 dir = normalize(stripe_dir + vec2(0.0001, 0.0));
	float band = sin(dot(wxz, dir) * stripe_freq);
	float stripe_mix = band * stripe_strength;

	vec3 col = base_color.rgb * (1.0 + grain_mix + stripe_mix);

	// Beveled read: darken fragments on steep (near-vertical) faces so the
	// hex sides fall into shadow and the top reads as a crafted piece.
	float facing = clamp(NORMAL.y, 0.0, 1.0);
	col *= mix(0.78, 1.0, facing);

	ALBEDO = clamp(col, vec3(0.0), vec3(1.0));
	ROUGHNESS = clamp(roughness + grain * 0.1, 0.0, 1.0);
	METALLIC = 0.0;
	SPECULAR = 0.1;
}
