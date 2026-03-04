#version 450
layout(location = 0) in vec2 in_position;
layout(location = 1) in vec4 in_color;

layout(location = 0) out vec4 out_color;

layout(push_constant) uniform UiPushConstants {
    vec2 u_screen_size;
} pc;

void main() {
    vec2 clip = vec2(
        (in_position.x / pc.u_screen_size.x) * 2.0 - 1.0,
        (in_position.y / pc.u_screen_size.y) * 2.0 - 1.0
    );
    gl_Position = vec4(clip, 0.0, 1.0);
    out_color = in_color;
}
