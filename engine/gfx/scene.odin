package gfx

import "core:math"

Scene_Push_Constants :: struct {
	view_proj: [16]f32,
	model:     [16]f32,
}

build_scene_push_constants :: proc(elapsed: f64, aspect: f32) -> Scene_Push_Constants {
	spin_angle := f32(elapsed * (math.TAU / 8.0))
	model_correction := mat4_rotation_x(0.5 * math.PI)
	model_spin := mat4_rotation_z(spin_angle)
	model := mat4_mul(model_spin, model_correction)

	eye := vec3(0.0, -2.8, 1.4)
	target := vec3(0.0, 0.0, 0.1)
	up := vec3(0.0, 0.0, 1.0)
	view := mat4_look_at(eye, target, up)
	proj := mat4_perspective_vulkan(45.0 * math.PI / 180.0, aspect, 0.1, 100.0)

	return {
		view_proj = mat4_mul(proj, view),
		model     = model,
	}
}

Vec3 :: struct {
	x, y, z: f32,
}

vec3 :: proc(x, y, z: f32) -> Vec3 {
	return {x, y, z}
}

vec3_sub :: proc(a, b: Vec3) -> Vec3 {
	return {a.x - b.x, a.y - b.y, a.z - b.z}
}

vec3_dot :: proc(a, b: Vec3) -> f32 {
	return a.x * b.x + a.y * b.y + a.z * b.z
}

vec3_cross :: proc(a, b: Vec3) -> Vec3 {
	return {
		a.y * b.z - a.z * b.y,
		a.z * b.x - a.x * b.z,
		a.x * b.y - a.y * b.x,
	}
}

vec3_length :: proc(v: Vec3) -> f32 {
	return math.sqrt(vec3_dot(v, v))
}

vec3_normalize :: proc(v: Vec3) -> Vec3 {
	length := vec3_length(v)
	if length <= 0 {
		return v
	}
	inv := 1.0 / length
	return {v.x * inv, v.y * inv, v.z * inv}
}

mat4_identity :: proc() -> [16]f32 {
	return [16]f32{
		1, 0, 0, 0,
		0, 1, 0, 0,
		0, 0, 1, 0,
		0, 0, 0, 1,
	}
}

mat4_mul :: proc(a, b: [16]f32) -> (out: [16]f32) {
	for col in 0 ..< 4 {
		for row in 0 ..< 4 {
			sum: f32
			for k in 0 ..< 4 {
				sum += a[k*4+row] * b[col*4+k]
			}
			out[col*4+row] = sum
		}
	}
	return out
}

mat4_rotation_x :: proc(angle: f32) -> [16]f32 {
	c := math.cos(angle)
	s := math.sin(angle)
	return [16]f32{
		1, 0, 0, 0,
		0, c, s, 0,
		0, -s, c, 0,
		0, 0, 0, 1,
	}
}

mat4_rotation_z :: proc(angle: f32) -> [16]f32 {
	c := math.cos(angle)
	s := math.sin(angle)
	return [16]f32{
		c, s, 0, 0,
		-s, c, 0, 0,
		0, 0, 1, 0,
		0, 0, 0, 1,
	}
}

mat4_look_at :: proc(eye, center, up: Vec3) -> [16]f32 {
	forward := vec3_normalize(vec3_sub(center, eye))
	side := vec3_normalize(vec3_cross(forward, up))
	true_up := vec3_cross(side, forward)

	return [16]f32{
		side.x, true_up.x, -forward.x, 0,
		side.y, true_up.y, -forward.y, 0,
		side.z, true_up.z, -forward.z, 0,
		-vec3_dot(side, eye), -vec3_dot(true_up, eye), vec3_dot(forward, eye), 1,
	}
}

mat4_perspective_vulkan :: proc(fovy_radians, aspect, near, far: f32) -> [16]f32 {
	f := 1.0 / math.tan(fovy_radians * 0.5)
	range_inv := 1.0 / (near - far)

	return [16]f32{
		f / aspect, 0, 0, 0,
		0, -f, 0, 0,
		0, 0, far * range_inv, -1,
		0, 0, far * near * range_inv, 0,
	}
}
