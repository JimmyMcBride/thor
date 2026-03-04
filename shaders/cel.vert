#version 450
layout(location = 0) in vec3 in_position;
layout(location = 1) in vec3 in_normal;

layout(location = 0) out vec3 out_world_normal;
layout(location = 1) out vec3 out_view_dir;

layout(push_constant) uniform PushConstants {
    mat4 u_view_proj;
    mat4 u_model;
} pc;

void main() {
    vec4 world_position = pc.u_model * vec4(in_position, 1.0);
    out_world_normal = normalize(mat3(pc.u_model) * in_normal);
    out_view_dir = normalize(-world_position.xyz);
    gl_Position = pc.u_view_proj * world_position;
}
