#version 450
layout(location = 0) in vec3 in_world_normal;
layout(location = 1) in vec3 in_view_dir;
layout(location = 0) out vec4 out_color;

layout(set = 0, binding = 0) uniform CelScene {
    vec4 u_light_direction;
    vec4 u_light_color;
    vec4 u_base_color;
    vec4 u_shade_color;
    vec4 u_shadow_color;
    vec4 u_highlight_color;
    vec4 u_rim_color;
    vec4 u_cel_params;      // diffuse bands, spec bands, spec threshold, rim threshold
    vec4 u_material_params; // rim strength, outline width, unused, unused
    vec4 u_outline_color;
} cel;

float quantize_bands(float value, float bands) {
    if (bands <= 1.0) {
        return step(0.5, value);
    }
    float steps = max(bands - 1.0, 1.0);
    return floor(value * bands) / steps;
}

void main() {
    vec3 normal = normalize(in_world_normal);
    vec3 light_dir = normalize(-cel.u_light_direction.xyz);
    vec3 view_dir = normalize(in_view_dir);
    vec3 half_dir = normalize(light_dir + view_dir);

    float ndotl = max(dot(normal, light_dir), 0.0);
    float diffuse_band = quantize_bands(ndotl, cel.u_cel_params.x);

    float specular_term = max(dot(normal, half_dir), 0.0);
    float specular_band = step(cel.u_cel_params.z, specular_term);

    float rim_term = 1.0 - max(dot(normal, view_dir), 0.0);
    float rim = step(cel.u_cel_params.w, rim_term) * cel.u_material_params.x;

    vec3 shade_mix = mix(cel.u_shadow_color.rgb, cel.u_shade_color.rgb, diffuse_band);
    vec3 lit = cel.u_base_color.rgb * shade_mix;
    lit += cel.u_highlight_color.rgb * specular_band * 0.35;
    lit += cel.u_rim_color.rgb * rim;
    lit *= cel.u_light_color.rgb;

    out_color = vec4(lit, cel.u_base_color.a);
}
