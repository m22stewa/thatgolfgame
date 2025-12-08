shader_type spatial;
render_mode cull_disabled;  // Shows both front and back faces

uniform float wave_size      : hint_range(0.0, 5.0) = 1.0;
uniform float face_distortion : hint_range(0.0, 2.0) = 0.5;
uniform vec2  time_scale     = vec2(0.3, 0.0);
uniform vec2  uv_offset_scale = vec2(-0.2, -0.1);

uniform vec3  peak_color     : source_color = vec3(0.0, 1.0, 0.0);
uniform vec3  valley_color   : source_color = vec3(0.0, 0.0, 1.0);
uniform float color_mix      : hint_range(0.0, 1.0) = 0.5;

// Noise texture for wave displacement
uniform sampler2D uv_offset_texture : source_color; 

// New albedo texture uniform
uniform sampler2D albedo_texture : source_color;
uniform float texture_mix : hint_range(0.0, 1.0) = 0.7;  // Blend strength vs procedural color

void vertex() {
    // Sample Noise (unchanged)
    vec2 base_uv_offset = UV * uv_offset_scale;
    base_uv_offset += TIME * time_scale;
    float noise = texture(uv_offset_texture, base_uv_offset).r;
    
    // Calculate offset (unchanged)
    float texture_based_offset = noise * 2.0 - 1.0;
    texture_based_offset *= wave_size;
    texture_based_offset *= UV.x;
    
    VERTEX.y += texture_based_offset;
    VERTEX.z += texture_based_offset * face_distortion;
    VERTEX.x += texture_based_offset * -face_distortion;
}

void fragment() {
    vec2 base_uv_offset = UV * uv_offset_scale;
    base_uv_offset += TIME * time_scale;
    float noise = texture(uv_offset_texture, base_uv_offset).r;
    
    // Sample albedo texture
    vec3 tex_color = texture(albedo_texture, UV).rgb;
    
    // Procedural color based on height
    vec3 color = mix(valley_color, peak_color, noise);
    
    // Blend texture with procedural colors
    vec3 final_color = mix(tex_color, color, texture_mix);
    ALBEDO = mix(vec3(1.0), final_color, color_mix);
}
