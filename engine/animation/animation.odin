package animation

import "core:math"
import "../assets"

Player :: struct {
	asset: ^assets.Skinned_Asset,

	local_transforms: [dynamic]assets.Node_Transform,
	world_transforms: [dynamic][16]f32,
	joint_matrices:   [dynamic][16]f32,
	skinned_vertices: [dynamic]assets.Mesh_Vertex,

	active_clip_index: int,
	time:              f32,
	playing:           bool,
	loop:              bool,
}

create_player :: proc(asset: ^assets.Skinned_Asset) -> (player: Player, ok: bool) {
	player.asset = asset
	player.active_clip_index = -1
	player.loop = true

	if resize(&player.local_transforms, len(asset.nodes)) != .None {
		return {}, false
	}
	if resize(&player.world_transforms, len(asset.nodes)) != .None {
		destroy_player(&player)
		return {}, false
	}
	if resize(&player.joint_matrices, len(asset.skin.joint_nodes)) != .None {
		destroy_player(&player)
		return {}, false
	}
	if resize(&player.skinned_vertices, len(asset.vertices)) != .None {
		destroy_player(&player)
		return {}, false
	}

	evaluate_pose(&player)
	return player, true
}

destroy_player :: proc(player: ^Player) {
	delete(player.local_transforms)
	delete(player.world_transforms)
	delete(player.joint_matrices)
	delete(player.skinned_vertices)
	player^ = {}
}

play_clip :: proc(player: ^Player, clip_index: int, restart := true) {
	if player.asset == nil || clip_index < 0 || clip_index >= len(player.asset.clips) {
		return
	}

	player.active_clip_index = clip_index
	if restart {
		player.time = 0
	}
	player.playing = true
	evaluate_pose(player)
}

set_looping :: proc(player: ^Player, loop: bool) {
	player.loop = loop
}

toggle_playing :: proc(player: ^Player) {
	player.playing = !player.playing
}

update :: proc(player: ^Player, dt: f32) {
	if player.asset == nil {
		return
	}

	if player.playing && player.active_clip_index >= 0 && player.active_clip_index < len(player.asset.clips) {
		clip := player.asset.clips[player.active_clip_index]
		player.time += dt
		if clip.duration > 0 {
			if player.loop {
				for player.time >= clip.duration {
					player.time -= clip.duration
				}
			} else if player.time >= clip.duration {
				player.time = clip.duration
				player.playing = false
			}
		}
	}

	evaluate_pose(player)
}

current_clip :: proc(player: ^Player) -> (assets.Animation_Clip, bool) {
	if player.asset == nil || player.active_clip_index < 0 || player.active_clip_index >= len(player.asset.clips) {
		return {}, false
	}
	return player.asset.clips[player.active_clip_index], true
}

evaluate_pose :: proc(player: ^Player) {
	for node, index in player.asset.nodes {
		player.local_transforms[index] = node.transform
	}

	if clip, ok := current_clip(player); ok {
		sample_clip_into_local_transforms(player, clip, player.time)
	}

	for node_index in 0 ..< len(player.asset.nodes) {
		player.world_transforms[node_index] = world_transform_for_node(player, node_index)
	}

	for joint_node, joint_index in player.asset.skin.joint_nodes {
		player.joint_matrices[joint_index] = mat4_mul(
			player.world_transforms[joint_node],
			player.asset.skin.inverse_bind_matrices[joint_index],
		)
	}

	for vertex, vertex_index in player.asset.vertices {
		skinned_position := [3]f32{}
		skinned_normal := [3]f32{}

		for influence in 0 ..< 4 {
			weight := vertex.weights[influence]
			if weight <= 0 {
				continue
			}

			joint_index := int(vertex.joints[influence])
			if joint_index < 0 || joint_index >= len(player.joint_matrices) {
				continue
			}

			joint_matrix := player.joint_matrices[joint_index]
			position := mat4_transform_point(joint_matrix, vertex.position)
			normal := mat4_transform_vector(joint_matrix, vertex.normal)
			for axis in 0 ..< 3 {
				skinned_position[axis] += position[axis] * weight
				skinned_normal[axis] += normal[axis] * weight
			}
		}

		player.skinned_vertices[vertex_index] = assets.Mesh_Vertex{
			position = skinned_position,
			normal   = vec3_normalize(skinned_normal),
		}
	}
}

sample_clip_into_local_transforms :: proc(player: ^Player, clip: assets.Animation_Clip, time: f32) {
	for channel in clip.channels {
		sampler := clip.samplers[channel.sampler_index]
		if len(sampler.keyframe_times) == 0 || sampler.value_stride == 0 {
			continue
		}

		sample_index := 0
		next_index := 0
		alpha: f32

		if len(sampler.keyframe_times) > 1 && time > sampler.keyframe_times[0] {
			for i in 0 ..< len(sampler.keyframe_times)-1 {
				t0 := sampler.keyframe_times[i]
				t1 := sampler.keyframe_times[i+1]
				if time <= t1 {
					sample_index = i
					next_index = i + 1
					delta := t1 - t0
					if delta > 0 {
						alpha = (time - t0) / delta
					}
					break
				}
				sample_index = i + 1
				next_index = i + 1
			}
		}

		target := &player.local_transforms[channel.node_index]
		switch channel.path {
		case .Translation:
			target.translation = sample_vec3(sampler, sample_index, next_index, alpha)
		case .Scale:
			target.scale = sample_vec3(sampler, sample_index, next_index, alpha)
		case .Rotation:
			target.rotation = sample_quat(sampler, sample_index, next_index, alpha)
		}
	}
}

sample_vec3 :: proc(sampler: assets.Animation_Sampler, index0, index1: int, alpha: f32) -> [3]f32 {
	base0 := index0 * sampler.value_stride
	base1 := index1 * sampler.value_stride
	return [3]f32{
		lerp(sampler.output_values[base0+0], sampler.output_values[base1+0], alpha),
		lerp(sampler.output_values[base0+1], sampler.output_values[base1+1], alpha),
		lerp(sampler.output_values[base0+2], sampler.output_values[base1+2], alpha),
	}
}

sample_quat :: proc(sampler: assets.Animation_Sampler, index0, index1: int, alpha: f32) -> [4]f32 {
	base0 := index0 * sampler.value_stride
	base1 := index1 * sampler.value_stride
	return quat_normalize([4]f32{
		lerp(sampler.output_values[base0+0], sampler.output_values[base1+0], alpha),
		lerp(sampler.output_values[base0+1], sampler.output_values[base1+1], alpha),
		lerp(sampler.output_values[base0+2], sampler.output_values[base1+2], alpha),
		lerp(sampler.output_values[base0+3], sampler.output_values[base1+3], alpha),
	})
}

world_transform_for_node :: proc(player: ^Player, node_index: int) -> [16]f32 {
	node := player.asset.nodes[node_index]
	local := mat4_from_transform(player.local_transforms[node_index])
	if node.parent < 0 {
		return local
	}
	return mat4_mul(world_transform_for_node(player, node.parent), local)
}

lerp :: proc(a, b, t: f32) -> f32 {
	return a + (b-a) * t
}

quat_normalize :: proc(q: [4]f32) -> [4]f32 {
	length := math.sqrt(q[0]*q[0] + q[1]*q[1] + q[2]*q[2] + q[3]*q[3])
	if length <= 0 {
		return [4]f32{0, 0, 0, 1}
	}
	inv := 1.0 / length
	return [4]f32{q[0] * inv, q[1] * inv, q[2] * inv, q[3] * inv}
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

mat4_from_transform :: proc(transform: assets.Node_Transform) -> [16]f32 {
	q := quat_normalize(transform.rotation)
	x := q[0]
	y := q[1]
	z := q[2]
	w := q[3]

	xx := x * x
	yy := y * y
	zz := z * z
	xy := x * y
	xz := x * z
	yz := y * z
	wx := w * x
	wy := w * y
	wz := w * z

	sx := transform.scale[0]
	sy := transform.scale[1]
	sz := transform.scale[2]

	return [16]f32{
		(1 - 2*(yy+zz)) * sx, (2 * (xy + wz)) * sx, (2 * (xz - wy)) * sx, 0,
		(2 * (xy - wz)) * sy, (1 - 2*(xx+zz)) * sy, (2 * (yz + wx)) * sy, 0,
		(2 * (xz + wy)) * sz, (2 * (yz - wx)) * sz, (1 - 2*(xx+yy)) * sz, 0,
		transform.translation[0], transform.translation[1], transform.translation[2], 1,
	}
}

mat4_transform_point :: proc(m: [16]f32, v: [3]f32) -> [3]f32 {
	return [3]f32{
		m[0]*v[0] + m[4]*v[1] + m[8]*v[2] + m[12],
		m[1]*v[0] + m[5]*v[1] + m[9]*v[2] + m[13],
		m[2]*v[0] + m[6]*v[1] + m[10]*v[2] + m[14],
	}
}

mat4_transform_vector :: proc(m: [16]f32, v: [3]f32) -> [3]f32 {
	return [3]f32{
		m[0]*v[0] + m[4]*v[1] + m[8]*v[2],
		m[1]*v[0] + m[5]*v[1] + m[9]*v[2],
		m[2]*v[0] + m[6]*v[1] + m[10]*v[2],
	}
}

vec3_normalize :: proc(v: [3]f32) -> [3]f32 {
	length := math.sqrt(v[0]*v[0] + v[1]*v[1] + v[2]*v[2])
	if length <= 0 {
		return [3]f32{0, 0, 1}
	}
	inv := 1.0 / length
	return [3]f32{v[0] * inv, v[1] * inv, v[2] * inv}
}
