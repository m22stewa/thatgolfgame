shader_type spatial;
render_mode blend_mix, cull_back, specular_disabled;

// Procedural woven table felt under the course (the "table" the hole sits on).
// Same family as scripts/ui/felt_tray.gdshader: a basket-weave over/under mask
// plus fine fuzz noise, sampled in world space so the weave stays a constant
// size however far the plane extends. A cooler, brighter green than the course
// grass so the hole reads as a piece on the table.

uniform vec4 felt_dark : source_color = vec4(0.07, 0.24, 0.17, 1.0);
uniform vec4 felt_light : source_color = vec4(0.10, 0.30, 0.21, 1.0);
uniform float weave_per_unit : hint_range(0.5, 20.0) = 5.0;   // weave cells per world unit
uniform float weave_contrast : hint_range(0.0, 1.0) = 0.35;
uniform float fuzz_strength : hint_range(0.0, 0.3) = 0.035;
uniform float mottle_strength : hint_range(0.0, 0.3) = 0.015;  // faint soft blotches, like worn felt

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
	vec2 p = world_pos.xz * weave_per_unit;
	// Fade the fine detail out where a weave cell gets smaller than a pixel or
	// two, so the distance reads as smooth felt instead of shimmering grain
	float detail = clamp(1.5 - fwidth(p.x) * 3.0, 0.0, 1.0);

	// Basket weave: warp/weft ridges, alternating which thread is on top
	float warp = sin(p.x * TAU);
	float weft = sin(p.y * TAU);
	float over = mod(floor(p.x) + floor(p.y), 2.0);
	float mask = mix(weft, warp, over) * 0.5 + 0.5;
	vec3 albedo = mix(felt_dark.rgb, felt_light.rgb, mix(0.5, mask, detail) * weave_contrast);

	// Fibrous fuzz + soft mottling so it doesn't read as a flat colour
	albedo += (value_noise(p * 6.0) - 0.5) * 2.0 * fuzz_strength * detail;
	albedo += (value_noise(world_pos.xz * 0.15) - 0.5) * 2.0 * mottle_strength;

	ALBEDO = clamp(albedo, vec3(0.0), vec3(1.0));
	ROUGHNESS = 1.0;
}
