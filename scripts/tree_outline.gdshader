shader_type spatial;
// Inverted-hull outline: render only the back faces, pushed out along the
// normal, in a near-black navy. Used as a next_pass on tree_toon so every
// tree gets a subtle dark silhouette that stays legible at the board camera
// angle. Unshaded so the outline colour is constant regardless of lighting.
render_mode cull_front, unshaded, shadows_disabled;

uniform vec4 outline_colour : source_color = vec4(0.078, 0.114, 0.157, 1.0);
// Expansion in local units along the vertex normal. Mesh base scale is small
// (~0.2 node transform) so this is kept modest to read as a thin line.
uniform float outline_width : hint_range(0.0, 0.5) = 0.04;

void vertex() {
	VERTEX += normalize(NORMAL) * outline_width;
}

void fragment() {
	ALBEDO = outline_colour.rgb;
}
