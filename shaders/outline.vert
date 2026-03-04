#version 450
layout(location = 0) in vec3 in_position;
layout(location = 1) in vec3 in_normal;

layout(push_constant) uniform PushConstants {
    mat4 u_view_proj;
    mat4 u_model;
} pc;

layout(set = 0, binding = 0) uniform CelScene {
    vec4 u_light_direction;
    vec4 u_light_color;
    vec4 u_base_color;
    vec4 u_shade_color;
    vec4 u_shadow_color;
    vec4 u_highlight_color;
    vec4 u_rim_color;
    vec4 u_cel_params;
    vec4 u_material_params;
    vec4 u_outline_color;
} cel;

void main() {
    vec3 expanded = in_position + normalize(in_normal) * cel.u_material_params.y;
    vec4 world_position = pc.u_model * vec4(expanded, 1.0);
    gl_Position = pc.u_view_proj * world_position;
}
