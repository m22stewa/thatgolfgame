// NOTE: Shader automatically converted from Godot Engine 4.4.stable's StandardMaterial3D.

shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx, world_vertex_coords;

uniform vec4 albedo : source_color;
uniform sampler2D texture_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform ivec2 albedo_texture_size;
uniform float point_size : hint_range(0.1, 128.0, 0.1);

uniform float roughness : hint_range(0.0, 1.0);
uniform sampler2D texture_metallic : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 metallic_texture_channel;
uniform sampler2D texture_roughness : hint_roughness_r, filter_linear_mipmap, repeat_enable;

uniform float specular : hint_range(0.0, 1.0, 0.01);
uniform float metallic : hint_range(0.0, 1.0, 0.01);

uniform vec3 uv1_scale;
uniform vec3 uv1_offset;
uniform vec3 uv2_scale;
uniform vec3 uv2_offset;

uniform vec4 wind_strengths = vec4(10.0, 0.0, 0.0, 0.0);
uniform vec4 wind_speeds = vec4(6.0);
uniform mat4 wind_directions = mat4(vec4(1.0, 0.0, 0.0, 0.0), vec4(0.0, 1.0, 0.0, 0.0), vec4(-1.0, 0.0, 0.0, 0.0) , vec4(0.0, -1.0, 0.0, 0.0));
uniform vec4 wind_mask_scales = vec4(200.0);
uniform mat4 wind_albedos = mat4(vec4(1.0),vec4(1.0),vec4(1.0),vec4(1.0));
uniform vec4 wind_albedo_scales = vec4(0.01);

uniform sampler2D wind_mask : source_color, filter_linear_mipmap, repeat_enable; // Grayscale texture to control sway

uniform float height_start = 0.0; // Height at which wind starts affecting the object
uniform float height_end = 25.0;

uniform vec3 force_point;
uniform float force_strength : hint_range(-20.0, 20.0) = 5.0;
uniform float force_area : hint_range(0.0, 50.0) = 16.0;

varying float wind_samples[4];

float sample_wind(vec3 tree_vertex, float _wind_speed, vec2 _wind_direction, float _wind_mask_scale, sampler2D _wind_mask) {
	vec2 _sample_position = (tree_vertex.xz - (TIME * _wind_speed * normalize(_wind_direction))) / _wind_mask_scale;
	return texture(_wind_mask, _sample_position).r;
}

vec3 get_total_wind_offset(vec3 tree_vertex, float wind_local_force, float _wind_strength, vec2 _wind_direction)
{
	float height_factor = smoothstep(height_start, height_start + height_end, tree_vertex.y);
	float total_offset = sin(wind_local_force) * _wind_strength * height_factor;
	vec2 horizontal_wind =  normalize(_wind_direction) * total_offset;
	return vec3(horizontal_wind.x, 0, horizontal_wind.y);
}

vec3 get_force_point_offset(vec3 tree_vertex)
{
	float height_factor = smoothstep(height_start, height_start + height_end, tree_vertex.y);
	float force_distance = distance(tree_vertex.xz, force_point.xz);
	float distance_factor = 1.0 - smoothstep(0, force_area, force_distance);
	vec2 diff_vector = tree_vertex.xz - force_point.xz;
	diff_vector = normalize(diff_vector);
	vec2 final_offset = diff_vector * force_strength * distance_factor * height_factor;
	return vec3(final_offset.x, 0, final_offset.y);
}

void vertex() {
	float _wind_strengths[4] = float[4](wind_strengths.x, wind_strengths.y, wind_strengths.z, wind_strengths.w);
	float _wind_speeds[4] = float[4](wind_speeds.x, wind_speeds.y, wind_speeds.z, wind_speeds.w);
	float _wind_mask_scales[4] = float[4](wind_mask_scales.x, wind_mask_scales.y, wind_mask_scales.z, wind_mask_scales.w);
	vec3 total_offset = vec3(0.0);
	for (int i = 0; i < _wind_strengths.length(); i++) {
		if (_wind_strengths[i] == 0.0) {
			continue;
		}
		wind_samples[i] = sample_wind(VERTEX, _wind_speeds[i], wind_directions[i].xy, _wind_mask_scales[i], wind_mask);
		total_offset += get_total_wind_offset(VERTEX, wind_samples[i], _wind_strengths[i], wind_directions[i].xy);
	}
	VERTEX += total_offset;
	VERTEX += get_force_point_offset(VERTEX);
	UV = UV * uv1_scale.xy + uv1_offset.xy;
}

void fragment() {
	vec2 base_uv = UV;

	vec4 albedo_tex = texture(texture_albedo, base_uv);
	float _wind_strengths[4] = float[4](wind_strengths.x, wind_strengths.y, wind_strengths.z, wind_strengths.w);
	float _wind_albedo_scales[4] = float[4](wind_albedo_scales.x, wind_albedo_scales.y, wind_albedo_scales.z, wind_albedo_scales.w);
	vec3 added_albedo = vec3(0.0);
	for (int i = 0; i < wind_samples.length(); i++) {
		added_albedo += wind_samples[i] * wind_albedos[i].rgb * _wind_albedo_scales[i] * _wind_strengths[i];
	}
	ALBEDO = (albedo.rgb * albedo_tex.rgb) + added_albedo;

	float metallic_tex = dot(texture(texture_metallic, base_uv), metallic_texture_channel);
	METALLIC = metallic_tex * metallic;
	SPECULAR = specular;

	vec4 roughness_texture_channel = vec4(1.0, 0.0, 0.0, 0.0);
	float roughness_tex = dot(texture(texture_roughness, base_uv), roughness_texture_channel);
	ROUGHNESS = roughness_tex * roughness;
}
