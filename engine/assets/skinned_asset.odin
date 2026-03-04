package assets

import "core:encoding/endian"
import json "core:encoding/json"
import "core:fmt"
import "core:os"

Animation_Path :: enum {
	Translation,
	Rotation,
	Scale,
}

Animation_Sampler :: struct {
	keyframe_times: [dynamic]f32,
	output_values:  [dynamic]f32,
	value_stride:   int,
}

Animation_Channel :: struct {
	sampler_index: int,
	node_index:    int,
	path:          Animation_Path,
}

Animation_Clip :: struct {
	name:     string,
	duration: f32,
	samplers: [dynamic]Animation_Sampler,
	channels: [dynamic]Animation_Channel,
}

Node_Transform :: struct {
	translation: [3]f32,
	rotation:    [4]f32,
	scale:       [3]f32,
}

Skin_Node :: struct {
	name:      string,
	parent:    int,
	children:  [dynamic]int,
	transform: Node_Transform,
}

Skin_Data :: struct {
	name:                  string,
	root_node:             int,
	joint_nodes:           [dynamic]int,
	inverse_bind_matrices: [dynamic][16]f32,
}

Skinned_Vertex :: struct {
	position: [3]f32,
	normal:   [3]f32,
	joints:   [4]u16,
	weights:  [4]f32,
}

Skinned_Asset :: struct {
	vertices:     [dynamic]Skinned_Vertex,
	indices:      [dynamic]u32,
	nodes:        [dynamic]Skin_Node,
	skin:         Skin_Data,
	clips:        [dynamic]Animation_Clip,
	name_storage: [dynamic][]u8,
}

destroy_skinned_asset :: proc(asset: ^Skinned_Asset) {
	for &clip in asset.clips {
		for &sampler in clip.samplers {
			delete(sampler.keyframe_times)
			delete(sampler.output_values)
		}
		delete(clip.samplers)
		delete(clip.channels)
	}
	delete(asset.clips)

	for &node in asset.nodes {
		delete(node.children)
	}
	delete(asset.nodes)

	delete(asset.vertices)
	delete(asset.indices)
	delete(asset.skin.joint_nodes)
	delete(asset.skin.inverse_bind_matrices)

	for storage in asset.name_storage {
		delete(storage)
	}
	delete(asset.name_storage)

	asset^ = {}
}

load_skinned_asset_from_glb :: proc(path: string) -> (asset: Skinned_Asset, ok: bool) {
	file_data, read_ok := os.read_entire_file(path)
	if !read_ok {
		fmt.eprintln("Failed to read skinned asset:", path)
		return {}, false
	}
	defer delete(file_data)

	json_chunk, bin_chunk, chunk_ok := parse_glb(file_data)
	if !chunk_ok {
		return {}, false
	}

	doc: Gltf_Document
	if err := json.unmarshal(json_chunk, &doc, allocator=context.temp_allocator); err != nil {
		fmt.eprintln("Failed to parse glTF JSON:", err)
		return {}, false
	}

	if len(doc.meshes) == 0 || len(doc.meshes[0].primitives) == 0 {
		fmt.eprintln("glTF file has no mesh primitives:", path)
		return {}, false
	}
	if len(doc.skins) == 0 {
		fmt.eprintln("glTF file has no skin:", path)
		return {}, false
	}
	if len(doc.animations) == 0 {
		fmt.eprintln("glTF file has no animations:", path)
		return {}, false
	}

	if !decode_skinned_mesh(&asset, doc, bin_chunk) {
		destroy_skinned_asset(&asset)
		return {}, false
	}
	if !decode_skin_nodes(&asset, doc, bin_chunk) {
		destroy_skinned_asset(&asset)
		return {}, false
	}
	if !decode_animation_clips(&asset, doc, bin_chunk) {
		destroy_skinned_asset(&asset)
		return {}, false
	}

	fmt.println("Loaded skinned asset:", path, "vertices=", len(asset.vertices), "indices=", len(asset.indices), "clips=", len(asset.clips))
	return asset, true
}

build_bind_pose_mesh :: proc(asset: ^Skinned_Asset) -> Mesh {
	mesh := Mesh{
		vertices = make([]Mesh_Vertex, len(asset.vertices)),
		indices  = make([]u32, len(asset.indices)),
	}
	copy(mesh.indices, asset.indices[:])
	for vertex, index in asset.vertices {
		mesh.vertices[index] = Mesh_Vertex{
			position = vertex.position,
			normal   = vertex.normal,
		}
	}
	return mesh
}

decode_skinned_mesh :: proc(asset: ^Skinned_Asset, doc: Gltf_Document, bin_chunk: []byte) -> bool {
	for primitive in doc.meshes[0].primitives {
		mode := primitive.mode
		if mode == 0 {
			mode = GLTF_MODE_TRIANGLES
		}
		if mode != GLTF_MODE_TRIANGLES {
			fmt.eprintln("Only triangle-list glTF primitives are supported")
			return false
		}
		if primitive.attributes.position < 0 || primitive.attributes.normal < 0 || primitive.indices < 0 {
			fmt.eprintln("glTF primitive is missing POSITION, NORMAL, or indices")
			return false
		}
		if primitive.attributes.joints_0 < 0 || primitive.attributes.weights_0 < 0 {
			fmt.eprintln("glTF primitive is missing JOINTS_0 or WEIGHTS_0")
			return false
		}

		positions, positions_ok := decode_vec3_f32_accessor(doc, primitive.attributes.position, bin_chunk)
		if !positions_ok {
			return false
		}
		defer delete(positions)

		normals, normals_ok := decode_vec3_f32_accessor(doc, primitive.attributes.normal, bin_chunk)
		if !normals_ok {
			return false
		}
		defer delete(normals)

		joints, joints_ok := decode_joints_accessor(doc, primitive.attributes.joints_0, bin_chunk)
		if !joints_ok {
			return false
		}
		defer delete(joints)

		weights, weights_ok := decode_weights_accessor(doc, primitive.attributes.weights_0, bin_chunk)
		if !weights_ok {
			return false
		}
		defer delete(weights)

		if len(positions) != len(normals) || len(positions) != len(joints) || len(positions) != len(weights) {
			fmt.eprintln("Skinned primitive accessors have mismatched counts")
			return false
		}

		vertex_base := u32(len(asset.vertices))
		for i in 0 ..< len(positions) {
			append(&asset.vertices, Skinned_Vertex{
				position = positions[i],
				normal   = normals[i],
				joints   = joints[i],
				weights  = weights[i],
			})
		}

		indices, indices_ok := decode_indices(doc, primitive.indices, bin_chunk)
		if !indices_ok {
			return false
		}
		defer delete(indices)
		for index in indices {
			append(&asset.indices, index + vertex_base)
		}
	}

	return true
}

decode_skin_nodes :: proc(asset: ^Skinned_Asset, doc: Gltf_Document, bin_chunk: []byte) -> bool {
	if len(doc.nodes) == 0 {
		fmt.eprintln("glTF file has no nodes")
		return false
	}

	if resize(&asset.nodes, len(doc.nodes)) != .None {
		fmt.eprintln("Failed to allocate node storage")
		return false
	}
	for source, node_index in doc.nodes {
		asset.nodes[node_index].parent = -1
		asset.nodes[node_index].name = clone_owned_string(asset, source.name)
		asset.nodes[node_index].transform = node_transform_from_gltf(source)

		for child in source.children {
			append(&asset.nodes[node_index].children, child)
		}
	}

	for node, node_index in asset.nodes {
		for child in node.children {
			asset.nodes[child].parent = node_index
		}
	}

	skin := doc.skins[0]
	asset.skin.name = clone_owned_string(asset, skin.name)
	asset.skin.root_node = skin.skeleton
	for joint in skin.joints {
		append(&asset.skin.joint_nodes, joint)
	}

	inverse_binds, ok := decode_mat4_accessor(doc, skin.inverse_bind_matrices, bin_chunk)
	if !ok {
		return false
	}
	defer delete(inverse_binds)
	for inverse_bind_matrix in inverse_binds {
		append(&asset.skin.inverse_bind_matrices, inverse_bind_matrix)
	}

	return true
}

decode_animation_clips :: proc(asset: ^Skinned_Asset, doc: Gltf_Document, bin_chunk: []byte) -> bool {
	for animation, animation_index in doc.animations {
		clip := Animation_Clip{
			name = clone_owned_string(asset, animation.name),
		}
		if len(clip.name) == 0 {
			clip.name = clone_owned_string(asset, fmt.aprintf("Animation_%d", animation_index))
		}

		for sampler in animation.samplers {
			times, times_ok := decode_scalar_f32_accessor(doc, sampler.input, bin_chunk)
			if !times_ok {
				return false
			}

			append(&clip.samplers, Animation_Sampler{
				keyframe_times = times,
				value_stride   = 0,
			})
		}

		for channel in animation.channels {
			path, path_ok := animation_path_from_string(channel.target.path)
			if !path_ok {
				return false
			}
			if channel.sampler < 0 || channel.sampler >= len(clip.samplers) {
				fmt.eprintln("Animation channel sampler index out of range")
				return false
			}

			output, stride, output_ok := decode_animation_output_accessor(doc, animation.samplers[channel.sampler].output, bin_chunk, path)
			if !output_ok {
				return false
			}

			if len(clip.samplers[channel.sampler].output_values) == 0 {
				clip.samplers[channel.sampler].output_values = output
				clip.samplers[channel.sampler].value_stride = stride
			} else {
				delete(output)
			}

			append(&clip.channels, Animation_Channel{
				sampler_index = channel.sampler,
				node_index    = channel.target.node,
				path          = path,
			})
		}

		duration, duration_ok := animation_duration(doc, animation, bin_chunk)
		if !duration_ok {
			return false
		}
		clip.duration = duration
		append(&asset.clips, clip)
	}

	return true
}

decode_vec3_f32_accessor :: proc(doc: Gltf_Document, accessor_index: int, bin_chunk: []byte) -> (values: [][3]f32, ok: bool) {
	accessor, _, data, stride, access_ok := accessor_bytes(doc, accessor_index, bin_chunk)
	if !access_ok {
		return nil, false
	}
	if accessor.component_type != GLTF_COMPONENT_TYPE_FLOAT || accessor.type != "VEC3" {
		fmt.eprintln("Only float VEC3 accessors are supported")
		return nil, false
	}
	if stride < 12 {
		fmt.eprintln("VEC3 accessor stride is invalid")
		return nil, false
	}

	values = make([][3]f32, accessor.count)
	base_offset := int(accessor.byte_offset)
	for i in 0 ..< len(values) {
		offset := base_offset + i * stride
		if offset + 12 > len(data) {
			fmt.eprintln("VEC3 accessor overruns buffer view")
			delete(values)
			return nil, false
		}

		values[i][0] = transmute(f32)endian.unchecked_get_u32le(data[offset+0:])
		values[i][1] = transmute(f32)endian.unchecked_get_u32le(data[offset+4:])
		values[i][2] = transmute(f32)endian.unchecked_get_u32le(data[offset+8:])
	}

	return values, true
}

decode_joints_accessor :: proc(doc: Gltf_Document, accessor_index: int, bin_chunk: []byte) -> (values: [][4]u16, ok: bool) {
	accessor, _, data, stride, access_ok := accessor_bytes(doc, accessor_index, bin_chunk)
	if !access_ok {
		return nil, false
	}
	if accessor.component_type != GLTF_COMPONENT_TYPE_UNSIGNED_SHORT || accessor.type != "VEC4" {
		fmt.eprintln("Only unsigned short VEC4 JOINTS_0 accessors are supported")
		return nil, false
	}
	if stride < 8 {
		fmt.eprintln("JOINTS_0 accessor stride is invalid")
		return nil, false
	}

	values = make([][4]u16, accessor.count)
	base_offset := int(accessor.byte_offset)
	for i in 0 ..< len(values) {
		offset := base_offset + i * stride
		if offset + 8 > len(data) {
			fmt.eprintln("JOINTS_0 accessor overruns buffer view")
			delete(values)
			return nil, false
		}
		for component in 0 ..< 4 {
			values[i][component] = endian.unchecked_get_u16le(data[offset+component*2:])
		}
	}

	return values, true
}

decode_weights_accessor :: proc(doc: Gltf_Document, accessor_index: int, bin_chunk: []byte) -> (values: [][4]f32, ok: bool) {
	accessor, _, data, stride, access_ok := accessor_bytes(doc, accessor_index, bin_chunk)
	if !access_ok {
		return nil, false
	}
	if accessor.type != "VEC4" {
		fmt.eprintln("Only VEC4 WEIGHTS_0 accessors are supported")
		return nil, false
	}

	component_size := accessor_component_size(accessor.component_type)
	if component_size == 0 || stride < component_size * 4 {
		fmt.eprintln("WEIGHTS_0 accessor stride is invalid")
		return nil, false
	}

	values = make([][4]f32, accessor.count)
	base_offset := int(accessor.byte_offset)
	for i in 0 ..< len(values) {
		offset := base_offset + i * stride
		if offset + component_size * 4 > len(data) {
			fmt.eprintln("WEIGHTS_0 accessor overruns buffer view")
			delete(values)
			return nil, false
		}

		weight_sum: f32
		for component in 0 ..< 4 {
			component_offset := offset + component * component_size
			value: f32
			switch accessor.component_type {
			case GLTF_COMPONENT_TYPE_UNSIGNED_SHORT:
				raw := endian.unchecked_get_u16le(data[component_offset:])
				value = f32(raw) / 65535.0 if accessor.normalized else f32(raw)
			case GLTF_COMPONENT_TYPE_FLOAT:
				value = transmute(f32)endian.unchecked_get_u32le(data[component_offset:])
			case:
				fmt.eprintln("Unsupported WEIGHTS_0 component type:", accessor.component_type)
				delete(values)
				return nil, false
			}
			values[i][component] = value
			weight_sum += value
		}

		if weight_sum > 0 {
			inv := 1.0 / weight_sum
			for component in 0 ..< 4 {
				values[i][component] *= inv
			}
		}
	}

	return values, true
}

decode_scalar_f32_accessor :: proc(doc: Gltf_Document, accessor_index: int, bin_chunk: []byte) -> (values: [dynamic]f32, ok: bool) {
	accessor, _, data, stride, access_ok := accessor_bytes(doc, accessor_index, bin_chunk)
	if !access_ok {
		return nil, false
	}
	if accessor.component_type != GLTF_COMPONENT_TYPE_FLOAT || accessor.type != "SCALAR" {
		fmt.eprintln("Only float SCALAR accessors are supported")
		return nil, false
	}
	if stride < 4 {
		fmt.eprintln("SCALAR accessor stride is invalid")
		return nil, false
	}

	if resize(&values, int(accessor.count)) != .None {
		fmt.eprintln("Failed to allocate SCALAR accessor values")
		return nil, false
	}
	base_offset := int(accessor.byte_offset)
	for i in 0 ..< len(values) {
		offset := base_offset + i * stride
		if offset + 4 > len(data) {
			fmt.eprintln("SCALAR accessor overruns buffer view")
			delete(values)
			return nil, false
		}
		values[i] = transmute(f32)endian.unchecked_get_u32le(data[offset:])
	}

	return values, true
}

decode_mat4_accessor :: proc(doc: Gltf_Document, accessor_index: int, bin_chunk: []byte) -> (values: [][16]f32, ok: bool) {
	accessor, _, data, stride, access_ok := accessor_bytes(doc, accessor_index, bin_chunk)
	if !access_ok {
		return nil, false
	}
	if accessor.component_type != GLTF_COMPONENT_TYPE_FLOAT || accessor.type != "MAT4" {
		fmt.eprintln("Only float MAT4 accessors are supported")
		return nil, false
	}
	if stride < 64 {
		fmt.eprintln("MAT4 accessor stride is invalid")
		return nil, false
	}

	values = make([][16]f32, accessor.count)
	base_offset := int(accessor.byte_offset)
	for i in 0 ..< len(values) {
		offset := base_offset + i * stride
		if offset + 64 > len(data) {
			fmt.eprintln("MAT4 accessor overruns buffer view")
			delete(values)
			return nil, false
		}

		for component in 0 ..< 16 {
			values[i][component] = transmute(f32)endian.unchecked_get_u32le(data[offset+component*4:])
		}
	}

	return values, true
}

decode_animation_output_accessor :: proc(doc: Gltf_Document, accessor_index: int, bin_chunk: []byte, path: Animation_Path) -> (values: [dynamic]f32, stride: int, ok: bool) {
	expected_type := "VEC3"
	stride = 3
	if path == .Rotation {
		expected_type = "VEC4"
		stride = 4
	}

	accessor, _, data, accessor_stride, access_ok := accessor_bytes(doc, accessor_index, bin_chunk)
	if !access_ok {
		return nil, 0, false
	}
	if accessor.component_type != GLTF_COMPONENT_TYPE_FLOAT || accessor.type != expected_type {
		fmt.eprintln("Animation output accessor has unsupported type:", accessor.type)
		return nil, 0, false
	}
	if accessor_stride < stride * 4 {
		fmt.eprintln("Animation output accessor stride is invalid")
		return nil, 0, false
	}

	if resize(&values, int(accessor.count) * stride) != .None {
		fmt.eprintln("Failed to allocate animation output values")
		return nil, 0, false
	}
	base_offset := int(accessor.byte_offset)
	for i in 0 ..< int(accessor.count) {
		offset := base_offset + i * accessor_stride
		for component in 0 ..< stride {
			values[i*stride+component] = transmute(f32)endian.unchecked_get_u32le(data[offset+component*4:])
		}
	}

	return values, stride, true
}

animation_path_from_string :: proc(path: string) -> (Animation_Path, bool) {
	switch path {
	case "translation":
		return .Translation, true
	case "rotation":
		return .Rotation, true
	case "scale":
		return .Scale, true
	case:
		fmt.eprintln("Unsupported animation target path:", path)
		return .Translation, false
	}
}

node_transform_from_gltf :: proc(node: Gltf_Node) -> Node_Transform {
	transform := Node_Transform{
		translation = node.translation,
		rotation    = node.rotation,
		scale       = node.scale,
	}

	if transform.rotation == {} {
		transform.rotation = {0, 0, 0, 1}
	}
	if transform.scale == {} {
		transform.scale = {1, 1, 1}
	}
	return transform
}

clone_owned_string :: proc(asset: ^Skinned_Asset, src: string) -> string {
	if len(src) == 0 {
		return ""
	}
	storage := clone_string_bytes(src)
	append(&asset.name_storage, storage)
	return string(storage)
}
