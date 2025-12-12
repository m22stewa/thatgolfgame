shader_type canvas_item;

uniform float tl_radius : hint_range(0.0, 100.0) = 0.0;
uniform float tr_radius : hint_range(0.0, 100.0) = 0.0;
uniform float bl_radius : hint_range(0.0, 100.0) = 0.0;
uniform float br_radius : hint_range(0.0, 100.0) = 0.0;
uniform vec2 texture_size;

void fragment() {
    vec2 uv = FRAGCOORD.xy;
	
	vec2 limit_tl = vec2(tl_radius, tl_radius);
	vec2 limit_tr = vec2(texture_size.x - tr_radius, tr_radius);
	vec2 limit_bl = vec2(bl_radius, texture_size.y - bl_radius);
	vec2 limit_br = vec2(texture_size.x - br_radius, texture_size.y - br_radius);
	
	float dist_tl = distance(uv, limit_tl);
	float dist_tr = distance(uv, limit_tr);
	float dist_bl = distance(uv, limit_bl);
	float dist_br = distance(uv, limit_br);
	
	if ( uv.x < tl_radius && uv.y < tl_radius && dist_tl > tl_radius || 
		uv.x > limit_tr.x && uv.y < tr_radius && dist_tr > tr_radius || 
		uv.x < bl_radius && uv.y > limit_bl.y && dist_bl > bl_radius || 
		uv.x > limit_br.x && uv.y > limit_br.y && dist_br > br_radius ) {
		discard;
	} else {
        COLOR = texture(TEXTURE, UV);
	}
}