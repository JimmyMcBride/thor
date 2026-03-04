package assets

import "core:encoding/endian"
import json "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:os"

GLB_MAGIC :: 0x46546C67
GLB_VERSION :: 2
GLB_CHUNK_JSON :: 0x4E4F534A
GLB_CHUNK_BIN :: 0x004E4942

GLTF_COMPONENT_TYPE_UNSIGNED_BYTE :: 5121
GLTF_COMPONENT_TYPE_UNSIGNED_SHORT :: 5123
GLTF_COMPONENT_TYPE_UNSIGNED_INT :: 5125
GLTF_COMPONENT_TYPE_FLOAT :: 5126
GLTF_MODE_TRIANGLES :: 4

Mesh_Vertex :: struct {
	position: [3]f32,
	normal:   [3]f32,
}

Mesh :: struct {
	vertices: []Mesh_Vertex,
	indices:  []u32,
}

Material :: struct {
	name:       string,
	base_color: [4]f32,
}

Mesh_Primitive :: struct {
	vertices:       []Mesh_Vertex,
	indices:        []u32,
	material_index: int,
}

Scene_Mesh :: struct {
	primitives:    [dynamic]Mesh_Primitive,
	materials:     [dynamic]Material,
	name_storage:  [dynamic][]u8,
}

Animation_Clip_Info :: struct {
	name:          string,
	duration:      f32,
	sampler_count: int,
	channel_count: int,
}

Animation_Catalog :: struct {
	clips:        [dynamic]Animation_Clip_Info,
	name_storage: [dynamic][]u8,
}

destroy_mesh :: proc(mesh: ^Mesh) {
	delete(mesh.vertices)
	delete(mesh.indices)
	mesh^ = {}
}

destroy_scene_mesh :: proc(scene_mesh: ^Scene_Mesh) {
	for &primitive in scene_mesh.primitives {
		delete(primitive.vertices)
		delete(primitive.indices)
	}
	delete(scene_mesh.primitives)
	delete(scene_mesh.materials)
	for storage in scene_mesh.name_storage {
		delete(storage)
	}
	delete(scene_mesh.name_storage)
	scene_mesh^ = {}
}

destroy_animation_catalog :: proc(catalog: ^Animation_Catalog) {
	for storage in catalog.name_storage {
		delete(storage)
	}
	delete(catalog.name_storage)
	delete(catalog.clips)
	catalog^ = {}
}

Gltf_Buffer_View :: struct {
	buffer:      int,
	byte_offset: u32 `json:"byteOffset"`,
	byte_length: u32 `json:"byteLength"`,
	byte_stride: u32 `json:"byteStride"`,
}

Gltf_Accessor :: struct {
	buffer_view:    int    `json:"bufferView"`,
	byte_offset:    u32    `json:"byteOffset"`,
	component_type: u32    `json:"componentType"`,
	count:          u32,
	normalized:     bool,
	type:           string,
}

Gltf_Primitive_Attributes :: struct {
	position: int `json:"POSITION"`,
	normal:   int `json:"NORMAL"`,
	joints_0: int `json:"JOINTS_0"`,
	weights_0: int `json:"WEIGHTS_0"`,
}

Gltf_Mesh_Primitive :: struct {
	attributes: Gltf_Primitive_Attributes,
	indices:    int,
	material:   int,
	mode:       int,
}

Gltf_Mesh :: struct {
	name:       string,
	primitives: []Gltf_Mesh_Primitive,
}

Gltf_Node :: struct {
	name:        string,
	children:    []int,
	mesh:        int,
	skin:        int,
	translation: [3]f32,
	rotation:    [4]f32,
	scale:       [3]f32,
	transform_matrix: [16]f32 `json:"matrix"`,
}

Gltf_Skin :: struct {
	name:                  string,
	inverse_bind_matrices: int `json:"inverseBindMatrices"`,
	skeleton:              int,
	joints:                []int,
}

Gltf_Animation_Sampler :: struct {
	input:         int,
	output:        int,
	interpolation: string,
}

Gltf_Animation_Channel_Target :: struct {
	node: int,
	path: string,
}

Gltf_Animation_Channel :: struct {
	sampler: int,
	target:  Gltf_Animation_Channel_Target,
}

Gltf_Animation :: struct {
	name:     string,
	samplers: []Gltf_Animation_Sampler,
	channels: []Gltf_Animation_Channel,
}

Gltf_Pbr_Metallic_Roughness :: struct {
	base_color_factor: [4]f32 `json:"baseColorFactor"`,
}

Gltf_Material :: struct {
	name:                    string,
	pbr_metallic_roughness:  Gltf_Pbr_Metallic_Roughness `json:"pbrMetallicRoughness"`,
}

Gltf_Document :: struct {
	accessors:    []Gltf_Accessor,
	nodes:        []Gltf_Node,
	skins:        []Gltf_Skin,
	buffer_views: []Gltf_Buffer_View `json:"bufferViews"`,
	animations:   []Gltf_Animation,
	materials:    []Gltf_Material,
	meshes:       []Gltf_Mesh,
}

glb_chunk :: struct {
	kind: u32,
	data: []byte,
}

load_mesh_from_glb :: proc(path: string) -> (mesh: Mesh, ok: bool) {
	file_data, read_ok := os.read_entire_file(path)
	if !read_ok {
		fmt.eprintln("Failed to read mesh asset:", path)
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

	primitive := doc.meshes[0].primitives[0]
	mode := primitive.mode
	if mode == 0 {
		mode = GLTF_MODE_TRIANGLES
	}
	if mode != GLTF_MODE_TRIANGLES {
		fmt.eprintln("Only triangle-list glTF primitives are supported")
		return {}, false
	}
	if primitive.attributes.position < 0 || primitive.attributes.normal < 0 || primitive.indices < 0 {
		fmt.eprintln("glTF primitive is missing POSITION, NORMAL, or indices")
		return {}, false
	}

	positions, pos_ok := decode_positions(doc, primitive.attributes.position, bin_chunk)
	if !pos_ok {
		return {}, false
	}
	defer delete(positions)

	normals, normal_ok := decode_normals(doc, primitive.attributes.normal, bin_chunk)
	if !normal_ok {
		return {}, false
	}
	defer delete(normals)
	if len(normals) != len(positions) {
		fmt.eprintln("glTF NORMAL accessor count does not match POSITION accessor count")
		return {}, false
	}

	mesh.indices, ok = decode_indices(doc, primitive.indices, bin_chunk)
	if !ok {
		return {}, false
	}

	mesh.vertices = make([]Mesh_Vertex, len(positions))
	for i in 0 ..< len(mesh.vertices) {
		mesh.vertices[i].position = positions[i].position
		mesh.vertices[i].normal = normals[i]
	}
	normalize_mesh(&mesh)

	fmt.println("Loaded mesh asset:", path, "vertices=", len(mesh.vertices), "indices=", len(mesh.indices))
	return mesh, true
}

load_scene_mesh_from_glb :: proc(path: string) -> (scene_mesh: Scene_Mesh, ok: bool) {
	file_data, read_ok := os.read_entire_file(path)
	if !read_ok {
		fmt.eprintln("Failed to read scene mesh asset:", path)
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

	scene_mesh.materials = make([dynamic]Material, max(len(doc.materials), 1))
	if len(doc.materials) == 0 {
		scene_mesh.materials[0] = {
			name       = "Default",
			base_color = {0.82, 0.84, 0.90, 1.0},
		}
	} else {
		for source, index in doc.materials {
			material_name := source.name
			if len(material_name) == 0 {
				material_name = fmt.aprintf("Material_%d", index)
			}
			name_storage := clone_string_bytes(material_name)
			append(&scene_mesh.name_storage, name_storage)
			base_color := source.pbr_metallic_roughness.base_color_factor
			if base_color == {} {
				base_color = [4]f32{0.82, 0.84, 0.90, 1.0}
			}
			scene_mesh.materials[index] = {
				name       = string(name_storage),
				base_color = base_color,
			}
		}
	}

	for primitive in doc.meshes[0].primitives {
		mesh_primitive, primitive_ok := decode_mesh_primitive(doc, primitive, bin_chunk)
		if !primitive_ok {
			destroy_scene_mesh(&scene_mesh)
			return {}, false
		}
		if mesh_primitive.material_index < 0 || mesh_primitive.material_index >= len(scene_mesh.materials) {
			mesh_primitive.material_index = 0
		}
		append(&scene_mesh.primitives, mesh_primitive)
	}

	fmt.println("Loaded scene mesh asset:", path, "primitives=", len(scene_mesh.primitives), "materials=", len(scene_mesh.materials))
	return scene_mesh, true
}

load_animation_catalog_from_glb :: proc(path: string) -> (catalog: Animation_Catalog, ok: bool) {
	file_data, read_ok := os.read_entire_file(path)
	if !read_ok {
		fmt.eprintln("Failed to read animation asset:", path)
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

	if len(doc.animations) == 0 {
		fmt.eprintln("glTF file has no animations:", path)
		return {}, false
	}

	for animation, index in doc.animations {
		duration, duration_ok := animation_duration(doc, animation, bin_chunk)
		if !duration_ok {
			return {}, false
		}

		clip_name := animation.name
		if len(clip_name) == 0 {
			clip_name = fmt.aprintf("Animation_%d", index)
		}
		name_storage := clone_string_bytes(clip_name)
		append(&catalog.name_storage, name_storage)
		append(&catalog.clips, Animation_Clip_Info{
			name          = string(name_storage),
			duration      = duration,
			sampler_count = len(animation.samplers),
			channel_count = len(animation.channels),
		})
	}

	fmt.println("Loaded animation catalog:", path, "clips=", len(catalog.clips))
	return catalog, true
}

parse_glb :: proc(file_data: []byte) -> (json_chunk: []byte, bin_chunk: []byte, ok: bool) {
	if len(file_data) < 12 {
		fmt.eprintln("GLB file too small")
		return nil, nil, false
	}

	magic := endian.unchecked_get_u32le(file_data[0:])
	version := endian.unchecked_get_u32le(file_data[4:])
	length := endian.unchecked_get_u32le(file_data[8:])
	if magic != GLB_MAGIC || version != GLB_VERSION {
		fmt.eprintln("Unsupported GLB header")
		return nil, nil, false
	}
	if int(length) > len(file_data) {
		fmt.eprintln("GLB length exceeds file size")
		return nil, nil, false
	}

	offset := 12
	for offset + 8 <= int(length) {
		chunk_length := int(endian.unchecked_get_u32le(file_data[offset:]))
		chunk_type := endian.unchecked_get_u32le(file_data[offset+4:])
		offset += 8

		if offset + chunk_length > int(length) {
			fmt.eprintln("GLB chunk exceeds file size")
			return nil, nil, false
		}

		chunk_data := file_data[offset : offset+chunk_length]
		offset += chunk_length

		switch chunk_type {
		case GLB_CHUNK_JSON:
			json_chunk = chunk_data
		case GLB_CHUNK_BIN:
			bin_chunk = chunk_data
		}
	}

	if len(json_chunk) == 0 || len(bin_chunk) == 0 {
		fmt.eprintln("GLB is missing JSON or BIN chunks")
		return nil, nil, false
	}

	return json_chunk, bin_chunk, true
}

decode_positions :: proc(doc: Gltf_Document, accessor_index: int, bin_chunk: []byte) -> (vertices: []Mesh_Vertex, ok: bool) {
	accessor, view, data, stride, access_ok := accessor_bytes(doc, accessor_index, bin_chunk)
	if !access_ok {
		return nil, false
	}
	if accessor.component_type != GLTF_COMPONENT_TYPE_FLOAT || accessor.type != "VEC3" {
		fmt.eprintln("Only float VEC3 POSITION accessors are supported")
		return nil, false
	}
	if stride < 12 {
		fmt.eprintln("POSITION accessor stride is invalid")
		return nil, false
	}

	vertices = make([]Mesh_Vertex, accessor.count)
	base_offset := int(accessor.byte_offset)
	for i in 0 ..< len(vertices) {
		offset := base_offset + i * stride
		if offset + 12 > len(data) {
			fmt.eprintln("POSITION accessor overruns buffer view")
			delete(vertices)
			return nil, false
		}

		vertices[i].position[0] = transmute(f32)endian.unchecked_get_u32le(data[offset+0:])
		vertices[i].position[1] = transmute(f32)endian.unchecked_get_u32le(data[offset+4:])
		vertices[i].position[2] = transmute(f32)endian.unchecked_get_u32le(data[offset+8:])
	}

	_ = view
	return vertices, true
}

decode_normals :: proc(doc: Gltf_Document, accessor_index: int, bin_chunk: []byte) -> (normals: [][3]f32, ok: bool) {
	accessor, _, data, stride, access_ok := accessor_bytes(doc, accessor_index, bin_chunk)
	if !access_ok {
		return nil, false
	}
	if accessor.component_type != GLTF_COMPONENT_TYPE_FLOAT || accessor.type != "VEC3" {
		fmt.eprintln("Only float VEC3 NORMAL accessors are supported")
		return nil, false
	}
	if stride < 12 {
		fmt.eprintln("NORMAL accessor stride is invalid")
		return nil, false
	}

	normals = make([][3]f32, accessor.count)
	base_offset := int(accessor.byte_offset)
	for i in 0 ..< len(normals) {
		offset := base_offset + i * stride
		if offset + 12 > len(data) {
			fmt.eprintln("NORMAL accessor overruns buffer view")
			delete(normals)
			return nil, false
		}

		normals[i][0] = transmute(f32)endian.unchecked_get_u32le(data[offset+0:])
		normals[i][1] = transmute(f32)endian.unchecked_get_u32le(data[offset+4:])
		normals[i][2] = transmute(f32)endian.unchecked_get_u32le(data[offset+8:])
	}

	return normals, true
}

decode_indices :: proc(doc: Gltf_Document, accessor_index: int, bin_chunk: []byte) -> (indices: []u32, ok: bool) {
	accessor, _, data, stride, access_ok := accessor_bytes(doc, accessor_index, bin_chunk)
	if !access_ok {
		return nil, false
	}
	if accessor.type != "SCALAR" {
		fmt.eprintln("Only scalar index accessors are supported")
		return nil, false
	}

	elem_size := accessor_component_size(accessor.component_type)
	if elem_size == 0 || stride < elem_size {
		fmt.eprintln("Index accessor stride is invalid")
		return nil, false
	}

	indices = make([]u32, accessor.count)
	base_offset := int(accessor.byte_offset)
	for i in 0 ..< len(indices) {
		offset := base_offset + i * stride
		if offset + elem_size > len(data) {
			fmt.eprintln("Index accessor overruns buffer view")
			delete(indices)
			return nil, false
		}

		switch accessor.component_type {
		case GLTF_COMPONENT_TYPE_UNSIGNED_BYTE:
			indices[i] = u32(data[offset])
		case GLTF_COMPONENT_TYPE_UNSIGNED_SHORT:
			indices[i] = u32(endian.unchecked_get_u16le(data[offset:]))
		case GLTF_COMPONENT_TYPE_UNSIGNED_INT:
			indices[i] = endian.unchecked_get_u32le(data[offset:])
		case:
			fmt.eprintln("Unsupported glTF index component type:", accessor.component_type)
			delete(indices)
			return nil, false
		}
	}

	return indices, true
}

accessor_bytes :: proc(doc: Gltf_Document, accessor_index: int, bin_chunk: []byte) -> (accessor: Gltf_Accessor, view: Gltf_Buffer_View, data: []byte, stride: int, ok: bool) {
	if accessor_index < 0 || accessor_index >= len(doc.accessors) {
		fmt.eprintln("Accessor index out of range:", accessor_index)
		return {}, {}, nil, 0, false
	}

	accessor = doc.accessors[accessor_index]
	if accessor.buffer_view < 0 || accessor.buffer_view >= len(doc.buffer_views) {
		fmt.eprintln("Accessor bufferView index out of range:", accessor.buffer_view)
		return {}, {}, nil, 0, false
	}

	view = doc.buffer_views[accessor.buffer_view]
	if view.buffer != 0 {
		fmt.eprintln("Only GLB buffer 0 is supported")
		return {}, {}, nil, 0, false
	}

	view_offset := int(view.byte_offset)
	view_end := view_offset + int(view.byte_length)
	if view_offset < 0 || view_end > len(bin_chunk) {
		fmt.eprintln("Buffer view exceeds BIN chunk")
		return {}, {}, nil, 0, false
	}

	data = bin_chunk[view_offset:view_end]
	stride = int(view.byte_stride)
	if stride == 0 {
		stride = accessor_packed_size(accessor)
	}
	if stride == 0 {
		fmt.eprintln("Unsupported accessor layout")
		return {}, {}, nil, 0, false
	}

	return accessor, view, data, stride, true
}

accessor_component_size :: proc(component_type: u32) -> int {
	switch component_type {
	case GLTF_COMPONENT_TYPE_UNSIGNED_BYTE:
		return 1
	case GLTF_COMPONENT_TYPE_UNSIGNED_SHORT:
		return 2
	case GLTF_COMPONENT_TYPE_UNSIGNED_INT, GLTF_COMPONENT_TYPE_FLOAT:
		return 4
	case:
		return 0
	}
}

accessor_component_count :: proc(kind: string) -> int {
	switch kind {
	case "SCALAR":
		return 1
	case "VEC2":
		return 2
	case "VEC3":
		return 3
	case "VEC4":
		return 4
	case "MAT4":
		return 16
	case:
		return 0
	}
}

accessor_packed_size :: proc(accessor: Gltf_Accessor) -> int {
	return accessor_component_size(accessor.component_type) * accessor_component_count(accessor.type)
}

decode_mesh_primitive :: proc(doc: Gltf_Document, primitive: Gltf_Mesh_Primitive, bin_chunk: []byte) -> (mesh_primitive: Mesh_Primitive, ok: bool) {
	mode := primitive.mode
	if mode == 0 {
		mode = GLTF_MODE_TRIANGLES
	}
	if mode != GLTF_MODE_TRIANGLES {
		fmt.eprintln("Only triangle-list glTF primitives are supported")
		return {}, false
	}
	if primitive.attributes.position < 0 || primitive.attributes.normal < 0 || primitive.indices < 0 {
		fmt.eprintln("glTF primitive is missing POSITION, NORMAL, or indices")
		return {}, false
	}

	positions, pos_ok := decode_positions(doc, primitive.attributes.position, bin_chunk)
	if !pos_ok {
		return {}, false
	}
	defer delete(positions)

	normals, normal_ok := decode_normals(doc, primitive.attributes.normal, bin_chunk)
	if !normal_ok {
		return {}, false
	}
	defer delete(normals)
	if len(normals) != len(positions) {
		fmt.eprintln("glTF NORMAL accessor count does not match POSITION accessor count")
		return {}, false
	}

	mesh_primitive.indices, ok = decode_indices(doc, primitive.indices, bin_chunk)
	if !ok {
		return {}, false
	}

	mesh_primitive.vertices = make([]Mesh_Vertex, len(positions))
	for i in 0 ..< len(mesh_primitive.vertices) {
		mesh_primitive.vertices[i].position = positions[i].position
		mesh_primitive.vertices[i].normal = normals[i]
	}
	normalize_mesh_primitive(&mesh_primitive)
	mesh_primitive.material_index = primitive.material
	return mesh_primitive, true
}

animation_duration :: proc(doc: Gltf_Document, animation: Gltf_Animation, bin_chunk: []byte) -> (duration: f32, ok: bool) {
	for sampler in animation.samplers {
		sampler_duration, duration_ok := decode_max_time(doc, sampler.input, bin_chunk)
		if !duration_ok {
			return 0, false
		}
		duration = math.max(duration, sampler_duration)
	}

	return duration, true
}

decode_max_time :: proc(doc: Gltf_Document, accessor_index: int, bin_chunk: []byte) -> (max_time: f32, ok: bool) {
	accessor, _, data, stride, access_ok := accessor_bytes(doc, accessor_index, bin_chunk)
	if !access_ok {
		return 0, false
	}
	if accessor.component_type != GLTF_COMPONENT_TYPE_FLOAT || accessor.type != "SCALAR" {
		fmt.eprintln("Only float SCALAR animation inputs are supported")
		return 0, false
	}
	if stride < 4 {
		fmt.eprintln("Animation input accessor stride is invalid")
		return 0, false
	}

	base_offset := int(accessor.byte_offset)
	for i in 0 ..< int(accessor.count) {
		offset := base_offset + i * stride
		if offset + 4 > len(data) {
			fmt.eprintln("Animation input accessor overruns buffer view")
			return 0, false
		}

		value := transmute(f32)endian.unchecked_get_u32le(data[offset:])
		max_time = math.max(max_time, value)
	}

	return max_time, true
}

clone_string_bytes :: proc(src: string) -> []u8 {
	buf := make([]u8, len(src))
	copy(buf, src[:])
	return buf
}

normalize_mesh :: proc(mesh: ^Mesh) {
	if len(mesh.vertices) == 0 {
		return
	}

	min_pos := mesh.vertices[0].position
	max_pos := mesh.vertices[0].position

	for vertex in mesh.vertices[1:] {
		for axis in 0 ..< 3 {
			min_pos[axis] = math.min(min_pos[axis], vertex.position[axis])
			max_pos[axis] = math.max(max_pos[axis], vertex.position[axis])
		}
	}

	center := [3]f32{
		(min_pos[0] + max_pos[0]) * 0.5,
		(min_pos[1] + max_pos[1]) * 0.5,
		(min_pos[2] + max_pos[2]) * 0.5,
	}
	extent_x := max_pos[0] - min_pos[0]
	extent_y := max_pos[1] - min_pos[1]
	extent_z := max_pos[2] - min_pos[2]
	max_extent := math.max(extent_x, math.max(extent_y, extent_z))
	if max_extent <= 0 {
		max_extent = 1
	}

	scale := f32(1.6) / max_extent
	for i in 0 ..< len(mesh.vertices) {
		for axis in 0 ..< 3 {
			mesh.vertices[i].position[axis] = (mesh.vertices[i].position[axis] - center[axis]) * scale
		}
	}
}

normalize_mesh_primitive :: proc(primitive: ^Mesh_Primitive) {
	mesh := Mesh{
		vertices = primitive.vertices,
		indices  = primitive.indices,
	}
	normalize_mesh(&mesh)
	primitive.vertices = mesh.vertices
	primitive.indices = mesh.indices
}
