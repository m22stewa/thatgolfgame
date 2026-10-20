shader_type spatial;
render_mode diffuse_lambert, specular_disabled, cull_back;

// Crafted "game-piece" foliage: flat soft-cel shading in 2-3 bands over the
// mesh's gradient-palette albedo. No emission. The trunk (brown palette band)
// is left alone; the green foliage is tinted toward foliage_colour so per-tree
// colour variation reads clearly. Pairs with tree_outline.gdshader as a
// next_pass for the dark inverted-hull silhouette.
//
// The imported tree meshes have no vertex colour; they map each vertex's UV
// into a vertical-band palette atlas (texture_gradient.png) that holds both the
// foliage greens and the trunk browns. So we sample that texture by UV exactly
// like the original StandardMaterial3D did, then recolour only the green bands.

uniform sampler2D albedo_texture : source_color;
// Per-tree foliage tint. _apply_random_tree_colors() duplicates the material
// and varies this so each tree reads as its own piece.
uniform vec4 foliage_colour : source_color = vec4(0.18, 0.40, 0.12, 1.0);
// How strongly the baked green is pulled toward foliage_colour (0 = keep baked).
uniform float foliage_tint : hint_range(0.0, 1.0) = 0.7;
// Cel banding controls.
uniform float band_count : hint_range(1.0, 4.0) = 3.0;
uniform float shade_floor : hint_range(0.0, 1.0) = 0.55;
uniform float roughness : hint_range(0.0, 1.0) = 1.0;

varying vec3 inst_tint;

void vertex() {
	// Per-instance foliage tint comes from the MultiMesh custom data (rgb). The
	// alpha flags whether to use it; when 0 (non-MultiMesh) we fall back to the
	// foliage_colour uniform so the material still works outside a MultiMesh.
	inst_tint = mix(foliage_colour.rgb, INSTANCE_CUSTOM.rgb, step(0.5, INSTANCE_CUSTOM.a));
}

void fragment() {
	// Palette-atlas albedo drives the base colour (trunk brown + foliage green).
	vec3 baked = texture(albedo_texture, UV).rgb;

	// Foliage mask: how "green-dominant" the baked colour is. Trunk browns have
	// red >= green, so this stays near zero on the trunk and the tint is a no-op
	// there, keeping the trunk its natural colour.
	float greenness = clamp(baked.g - max(baked.r, baked.b), 0.0, 1.0);
	float mask = smoothstep(0.02, 0.18, greenness);

	// Re-tint the foliage toward the (per-instance or uniform) colour while
	// keeping the baked luminance so the stacked-cone / broadleaf forms read.
	float luma = dot(baked, vec3(0.299, 0.587, 0.114));
	vec3 tinted = inst_tint * (0.5 + luma);
	vec3 foliage = mix(baked, clamp(tinted, vec3(0.0), vec3(1.0)), foliage_tint);
	ALBEDO = mix(baked, foliage, mask);

	ROUGHNESS = roughness;
	METALLIC = 0.0;
	SPECULAR = 0.05;
}

void light() {
	// Quantise the lambert term into a few flat bands for a soft-cel read.
	float ndl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	float bands = max(band_count, 1.0);
	float stepped = floor(ndl * bands) / bands;
	// Lift the darkest band off pure black so shaded sides still read colour.
	float lit = mix(shade_floor, 1.0, stepped);
	DIFFUSE_LIGHT += ALBEDO * ATTENUATION * LIGHT_COLOR * lit;
}
