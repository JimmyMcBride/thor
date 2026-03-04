#version 450
layout(location = 0) out vec4 out_color;

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
    out_color = cel.u_outline_color;
}
