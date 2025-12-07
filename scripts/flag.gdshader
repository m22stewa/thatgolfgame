shader_type spatial;
render_mode cull_disabled;  // Shows both front and back faces

uniform float wave_size      : hint_range(0.0, 5.0) = 1.0;
uniform float face_distortion : hint_range(0.0, 2.0) = 0.5;
uniform vec2  time_scale     = vec2(0.3, 0.0);
uniform vec2  uv_offset_scale = vec2(-0.2, -0.1);

uniform vec3  peak_color     : source_color = vec3(0.0, 1.0, 0.0);
uniform vec3  valley_color   : source_color = vec3(0.0, 0.0, 1.0);
uniform float color_mix      : hint_range(0.0, 1.0) = 0.5;

uniform sampler2D uv_offset_texture : source_color; 

void vertex() {
    // Sample Noise
    vec2 base_uv_offset = UV * uv_offset_scale;
    base_uv_offset += TIME * time_scale;
    float noise = texture(uv_offset_texture, base_uv_offset).r;
    
    // Calculate offset
    float texture_based_offset = noise * 2.0 - 1.0; // Convert from 0.0-1.0 to -1.0-1.0
    texture_based_offset *= wave_size; // Apply amplitude
    texture_based_offset *= UV.x; // Apply dampening
    
    VERTEX.y += texture_based_offset;
    VERTEX.z += texture_based_offset * face_distortion; // Distort the face to give impression of conserving shape
    VERTEX.x += texture_based_offset * -face_distortion;
}

void fragment() {
    vec2 base_uv_offset = UV * uv_offset_scale;
    base_uv_offset += TIME * time_scale;
    float noise = texture(uv_offset_texture, base_uv_offset).r;
    
    // Colorize based on height (noise value)
    vec3 color = mix(valley_color, peak_color, noise);
    ALBEDO = mix(vec3(1.0), color, color_mix); // Blend with white or use full color
}
