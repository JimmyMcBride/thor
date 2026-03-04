#version 450
layout(location = 0) in vec3 in_world_normal;
layout(location = 0) out vec4 out_color;

void main() {
    vec3 normal = normalize(in_world_normal);
    vec3 light_dir = normalize(vec3(0.15, -0.95, 0.65));
    float diffuse = max(dot(normal, light_dir), 0.0);
    float ambient = 0.38;
    float rim = pow(1.0 - max(normal.z, 0.0), 2.0) * 0.18;

    vec3 base = vec3(0.78, 0.80, 0.86);
    vec3 lit = base * (ambient + diffuse * 0.9) + rim;
    out_color = vec4(lit, 1.0);
}
