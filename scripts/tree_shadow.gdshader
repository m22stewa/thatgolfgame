shader_type spatial;
// Faux contact shadow for a placed tree piece: an unshaded, soft radial-alpha
// dark disc laid flat under each tree so it reads as sitting on its tile even
// when the real directional shadow is faint at the board camera angle. Cheap:
// no texture, procedural radial falloff from the quad UV.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix;

uniform vec4 shadow_colour : source_color = vec4(0.04, 0.06, 0.05, 1.0);
uniform float max_alpha : hint_range(0.0, 1.0) = 0.35;
uniform float edge : hint_range(0.0, 1.0) = 0.5;

void fragment() {
	// UV is 0..1 across the quad; distance from centre gives the radial falloff.
	float d = length(UV - vec2(0.5)) * 2.0;
	float a = smoothstep(1.0, edge, d) * max_alpha;
	ALBEDO = shadow_colour.rgb;
	ALPHA = a;
}
