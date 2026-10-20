shader_type canvas_item;

// Procedural woven dark-green felt with a stitched brass rail for the bottom
// tray. No texture fetch - a basket-weave over/under mask plus fine fuzz noise,
// framed by a dashed brass border. Reuses the hash2/value_noise helpers from
// scripts/turf.gdshader so the felt grain reads as part of the same family.

uniform vec4 felt_dark : source_color = vec4(0.133, 0.227, 0.149, 1.0);   // #223a26
uniform vec4 felt_light : source_color = vec4(0.176, 0.290, 0.188, 1.0);  // #2d4a30
uniform vec4 brass : source_color = vec4(0.722, 0.573, 0.247, 1.0);       // #b8923f
uniform float weave_scale : hint_range(20.0, 400.0) = 160.0;
uniform float weave_contrast : hint_range(0.0, 1.0) = 0.35;
uniform float fuzz_strength : hint_range(0.0, 0.3) = 0.08;
uniform float rail_thickness : hint_range(0.0, 0.1) = 0.018;
uniform float rail_inset : hint_range(0.0, 0.1) = 0.010;
uniform float stitch_freq : hint_range(0.0, 400.0) = 120.0;
uniform float tray_aspect : hint_range(0.1, 10.0) = 7.0;

// Cheap value noise (hash-based) in 2D - same family as turf.gdshader.
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

void fragment() {
	// --- Basket weave over/under ----------------------------------------
	// Two orthogonal sine ridges give the warp (vertical) and weft
	// (horizontal) threads. Alternating which thread sits "on top" per cell
	// (checkerboard via the summed cell indices) reads as a woven basket.
	float warp = sin(UV.x * TAU * weave_scale);
	float weft = sin(UV.y * TAU * weave_scale);
	float cell_x = floor(UV.x * weave_scale);
	float cell_y = floor(UV.y * weave_scale);
	float over = mod(cell_x + cell_y, 2.0); // 0 or 1 - alternating cells
	float thread = mix(weft, warp, over);   // pick the thread that is on top
	float mask = thread * 0.5 + 0.5;        // 0..1 ridge profile

	vec3 albedo = mix(felt_dark.rgb, felt_light.rgb, mask * weave_contrast);

	// Fine fuzz breaks up the regular weave so it reads as fibrous felt.
	float fuzz = (value_noise(UV * weave_scale * 6.0) - 0.5) * 2.0 * fuzz_strength;
	albedo += fuzz;

	// --- Stitched brass rail --------------------------------------------
	// Distance from the nearest edge in UV space (0 at the border).
	float edge_x = min(UV.x, 1.0 - UV.x);
	float edge_y = min(UV.y, 1.0 - UV.y);
	float edge = min(edge_x, edge_y);

	if (edge >= rail_inset && edge <= rail_inset + rail_thickness) {
		// On the top/bottom bands the perimeter runs along X (scaled by the
		// tray aspect so dashes stay roughly square); on the left/right bands
		// it runs along Y. Corners fall through as solid brass.
		float perimeter_coord = (edge_y < edge_x) ? UV.x * tray_aspect : UV.y;
		float dash = step(0.5, fract(perimeter_coord * stitch_freq));
		// Keep the four corners solid brass (no arc-length continuity).
		bool corner = (edge_x <= rail_inset + rail_thickness) && (edge_y <= rail_inset + rail_thickness);
		float bright = corner ? 1.0 : mix(0.55, 1.0, dash);
		albedo = brass.rgb * bright;
	}

	COLOR = vec4(clamp(albedo, vec3(0.0), vec3(1.0)), 1.0);
}
