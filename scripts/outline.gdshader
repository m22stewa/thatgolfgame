shader_type spatial;

// Define uniforms to control the mask from a script
uniform vec3 mask_center = vec3(0.0, 0.0, 0.0); // World position of the mask center
uniform float mask_radius = 6.0;                 // Radius of the masking sphere
uniform bool use_mask = true;                   // Toggle the mask effect

// Define the texture uniform explicitly for Godot 4.x
uniform sampler2D albedo_texture; 

void fragment() {
    if (use_mask) {
        // Calculate the current pixel's world position using INV_VIEW_MATRIX
        vec3 pixel_world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
        
        // Calculate the distance from the pixel to the mask center
        float dist = distance(pixel_world_pos, mask_center);
        
        // Discard the fragment (pixel) if it's within the mask radius
        if (dist < mask_radius) {
            discard;
        }
    }
    // Standard albedo assignment using albedo_texture
    ALBEDO = texture(albedo_texture, UV).rgb;
}