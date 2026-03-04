package gfx

import "base:intrinsics"
import "core:fmt"
import "../assets"
import vk "vendor:vulkan"

Gpu_Mesh :: struct {
	mesh:          assets.Mesh,
	vertex_buffer: vk.Buffer,
	vertex_memory: vk.DeviceMemory,
	index_buffer:  vk.Buffer,
	index_memory:  vk.DeviceMemory,
	index_count:   u32,
}

Gpu_Scene_Primitive :: struct {
	primitive:      assets.Mesh_Primitive,
	vertex_buffer:  vk.Buffer,
	vertex_memory:  vk.DeviceMemory,
	index_buffer:   vk.Buffer,
	index_memory:   vk.DeviceMemory,
	index_count:    u32,
	material_index: int,
}

Gpu_Scene_Mesh :: struct {
	primitives:   [dynamic]Gpu_Scene_Primitive,
	materials:    [dynamic]assets.Material,
	name_storage: [dynamic][]u8,
}

Dynamic_Gpu_Mesh :: struct {
	mesh:            assets.Mesh,
	vertex_buffers:  [MAX_FRAMES_IN_FLIGHT]vk.Buffer,
	vertex_memories: [MAX_FRAMES_IN_FLIGHT]vk.DeviceMemory,
	index_buffer:    vk.Buffer,
	index_memory:    vk.DeviceMemory,
	index_count:     u32,
}

create_gpu_mesh :: proc(ctx: ^Gfx_Context, mesh: assets.Mesh) -> (gpu_mesh: Gpu_Mesh, ok: bool) {
	if len(mesh.vertices) == 0 || len(mesh.indices) == 0 {
		fmt.eprintln("Cannot upload an empty mesh")
		return {}, false
	}

	gpu_mesh.mesh = mesh
	gpu_mesh.vertex_buffer, gpu_mesh.vertex_memory, ok = create_buffer_with_data(
		ctx,
		mesh.vertices,
		{.VERTEX_BUFFER},
	)
	if !ok {
		assets.destroy_mesh(&gpu_mesh.mesh)
		return {}, false
	}

	gpu_mesh.index_buffer, gpu_mesh.index_memory, ok = create_buffer_with_data(
		ctx,
		mesh.indices,
		{.INDEX_BUFFER},
	)
	if !ok {
		vk.DestroyBuffer(ctx.device, gpu_mesh.vertex_buffer, nil)
		vk.FreeMemory(ctx.device, gpu_mesh.vertex_memory, nil)
		assets.destroy_mesh(&gpu_mesh.mesh)
		return {}, false
	}
	gpu_mesh.index_count = u32(len(mesh.indices))

	return gpu_mesh, true
}

create_gpu_scene_mesh :: proc(ctx: ^Gfx_Context, scene_mesh: assets.Scene_Mesh) -> (gpu_scene_mesh: Gpu_Scene_Mesh, ok: bool) {
	for storage in scene_mesh.name_storage {
		append(&gpu_scene_mesh.name_storage, storage)
	}
	for source_material in scene_mesh.materials {
		append(&gpu_scene_mesh.materials, source_material)
	}

	for source_primitive in scene_mesh.primitives {
		gpu_primitive := Gpu_Scene_Primitive{
			primitive      = source_primitive,
			material_index = source_primitive.material_index,
		}
		gpu_primitive.vertex_buffer, gpu_primitive.vertex_memory, ok = create_buffer_with_data(
			ctx,
			source_primitive.vertices,
			{.VERTEX_BUFFER},
		)
		if !ok {
			destroy_gpu_scene_mesh(ctx.device, &gpu_scene_mesh)
			return {}, false
		}

		gpu_primitive.index_buffer, gpu_primitive.index_memory, ok = create_buffer_with_data(
			ctx,
			source_primitive.indices,
			{.INDEX_BUFFER},
		)
		if !ok {
			destroy_gpu_scene_mesh(ctx.device, &gpu_scene_mesh)
			return {}, false
		}
		gpu_primitive.index_count = u32(len(source_primitive.indices))
		append(&gpu_scene_mesh.primitives, gpu_primitive)
	}

	return gpu_scene_mesh, true
}

draw_gpu_mesh :: proc(ctx: ^Gfx_Context, mesh: ^Gpu_Mesh, push_constants: Scene_Push_Constants) {
	if !update_cel_scene_buffer(ctx) {
		return
	}

	cmd := ctx.command_buffers[ctx.current_frame]
	push := push_constants
	vertex_buffers := [1]vk.Buffer{mesh.vertex_buffer}
	offsets := [1]vk.DeviceSize{0}
	descriptor_set := ctx.descriptor_sets[ctx.current_frame]

	vk.CmdBindPipeline(cmd, .GRAPHICS, ctx.outline_pipeline)
	vk.CmdBindDescriptorSets(cmd, .GRAPHICS, ctx.outline_pipeline_layout, 0, 1, &descriptor_set, 0, nil)
	vk.CmdPushConstants(
		cmd,
		ctx.outline_pipeline_layout,
		{.VERTEX},
		0,
		u32(size_of(Scene_Push_Constants)),
		&push,
	)
	vk.CmdBindVertexBuffers(cmd, 0, 1, &vertex_buffers[0], &offsets[0])
	vk.CmdBindIndexBuffer(cmd, mesh.index_buffer, 0, .UINT32)
	vk.CmdDrawIndexed(cmd, mesh.index_count, 1, 0, 0, 0)

	vk.CmdBindPipeline(cmd, .GRAPHICS, ctx.pipeline)
	vk.CmdBindDescriptorSets(cmd, .GRAPHICS, ctx.pipeline_layout, 0, 1, &descriptor_set, 0, nil)
	vk.CmdPushConstants(
		cmd,
		ctx.pipeline_layout,
		{.VERTEX},
		0,
		u32(size_of(Scene_Push_Constants)),
		&push,
	)
	vk.CmdDrawIndexed(cmd, mesh.index_count, 1, 0, 0, 0)
}

draw_gpu_scene_mesh :: proc(ctx: ^Gfx_Context, scene_mesh: ^Gpu_Scene_Mesh, push_constants: Scene_Push_Constants) {
	for &primitive in scene_mesh.primitives {
		ctx.cel_scene = cel_scene_for_material(ctx.cel_scene, scene_mesh.materials[clamp(primitive.material_index, 0, len(scene_mesh.materials)-1)])
		if !update_cel_scene_buffer(ctx) {
			return
		}

		cmd := ctx.command_buffers[ctx.current_frame]
		push := push_constants
		vertex_buffers := [1]vk.Buffer{primitive.vertex_buffer}
		offsets := [1]vk.DeviceSize{0}
		descriptor_set := ctx.descriptor_sets[ctx.current_frame]

		vk.CmdBindPipeline(cmd, .GRAPHICS, ctx.outline_pipeline)
		vk.CmdBindDescriptorSets(cmd, .GRAPHICS, ctx.outline_pipeline_layout, 0, 1, &descriptor_set, 0, nil)
		vk.CmdPushConstants(cmd, ctx.outline_pipeline_layout, {.VERTEX}, 0, u32(size_of(Scene_Push_Constants)), &push)
		vk.CmdBindVertexBuffers(cmd, 0, 1, &vertex_buffers[0], &offsets[0])
		vk.CmdBindIndexBuffer(cmd, primitive.index_buffer, 0, .UINT32)
		vk.CmdDrawIndexed(cmd, primitive.index_count, 1, 0, 0, 0)

		vk.CmdBindPipeline(cmd, .GRAPHICS, ctx.pipeline)
		vk.CmdBindDescriptorSets(cmd, .GRAPHICS, ctx.pipeline_layout, 0, 1, &descriptor_set, 0, nil)
		vk.CmdPushConstants(cmd, ctx.pipeline_layout, {.VERTEX}, 0, u32(size_of(Scene_Push_Constants)), &push)
		vk.CmdDrawIndexed(cmd, primitive.index_count, 1, 0, 0, 0)
	}
}

destroy_gpu_mesh :: proc(device: vk.Device, mesh: ^Gpu_Mesh) {
	vk.DestroyBuffer(device, mesh.index_buffer, nil)
	vk.FreeMemory(device, mesh.index_memory, nil)
	vk.DestroyBuffer(device, mesh.vertex_buffer, nil)
	vk.FreeMemory(device, mesh.vertex_memory, nil)
	assets.destroy_mesh(&mesh.mesh)
	mesh^ = {}
}

destroy_gpu_scene_mesh :: proc(device: vk.Device, scene_mesh: ^Gpu_Scene_Mesh) {
	for &primitive in scene_mesh.primitives {
		vk.DestroyBuffer(device, primitive.index_buffer, nil)
		vk.FreeMemory(device, primitive.index_memory, nil)
		vk.DestroyBuffer(device, primitive.vertex_buffer, nil)
		vk.FreeMemory(device, primitive.vertex_memory, nil)
		delete(primitive.primitive.vertices)
		delete(primitive.primitive.indices)
	}
	delete(scene_mesh.primitives)
	delete(scene_mesh.materials)
	for storage in scene_mesh.name_storage {
		delete(storage)
	}
	delete(scene_mesh.name_storage)
	scene_mesh^ = {}
}

create_dynamic_gpu_mesh :: proc(ctx: ^Gfx_Context, mesh: assets.Mesh) -> (gpu_mesh: Dynamic_Gpu_Mesh, ok: bool) {
	if len(mesh.vertices) == 0 || len(mesh.indices) == 0 {
		fmt.eprintln("Cannot upload an empty dynamic mesh")
		return {}, false
	}

	gpu_mesh.mesh = mesh
	for frame_index in 0 ..< MAX_FRAMES_IN_FLIGHT {
		gpu_mesh.vertex_buffers[frame_index], gpu_mesh.vertex_memories[frame_index], ok = create_buffer_with_data(
			ctx,
			mesh.vertices,
			{.VERTEX_BUFFER},
		)
		if !ok {
			destroy_dynamic_gpu_mesh(ctx.device, &gpu_mesh)
			return {}, false
		}
	}

	gpu_mesh.index_buffer, gpu_mesh.index_memory, ok = create_buffer_with_data(
		ctx,
		mesh.indices,
		{.INDEX_BUFFER},
	)
	if !ok {
		destroy_dynamic_gpu_mesh(ctx.device, &gpu_mesh)
		return {}, false
	}
	gpu_mesh.index_count = u32(len(mesh.indices))
	return gpu_mesh, true
}

update_dynamic_gpu_mesh :: proc(ctx: ^Gfx_Context, mesh: ^Dynamic_Gpu_Mesh, vertices: []assets.Mesh_Vertex) -> bool {
	if len(vertices) != len(mesh.mesh.vertices) {
		fmt.eprintln("Dynamic mesh vertex count mismatch")
		return false
	}
	return write_buffer_data(ctx.device, mesh.vertex_memories[ctx.current_frame], vertices)
}

draw_dynamic_gpu_mesh :: proc(ctx: ^Gfx_Context, mesh: ^Dynamic_Gpu_Mesh, push_constants: Scene_Push_Constants) {
	if !update_cel_scene_buffer(ctx) {
		return
	}

	cmd := ctx.command_buffers[ctx.current_frame]
	vertex_buffers := [1]vk.Buffer{mesh.vertex_buffers[ctx.current_frame]}
	offsets := [1]vk.DeviceSize{0}
	push := push_constants
	descriptor_set := ctx.descriptor_sets[ctx.current_frame]

	vk.CmdBindPipeline(cmd, .GRAPHICS, ctx.outline_pipeline)
	vk.CmdBindDescriptorSets(cmd, .GRAPHICS, ctx.outline_pipeline_layout, 0, 1, &descriptor_set, 0, nil)
	vk.CmdPushConstants(
		cmd,
		ctx.outline_pipeline_layout,
		{.VERTEX},
		0,
		u32(size_of(Scene_Push_Constants)),
		&push,
	)
	vk.CmdBindVertexBuffers(cmd, 0, 1, &vertex_buffers[0], &offsets[0])
	vk.CmdBindIndexBuffer(cmd, mesh.index_buffer, 0, .UINT32)
	vk.CmdDrawIndexed(cmd, mesh.index_count, 1, 0, 0, 0)

	vk.CmdBindPipeline(cmd, .GRAPHICS, ctx.pipeline)
	vk.CmdBindDescriptorSets(cmd, .GRAPHICS, ctx.pipeline_layout, 0, 1, &descriptor_set, 0, nil)
	vk.CmdPushConstants(
		cmd,
		ctx.pipeline_layout,
		{.VERTEX},
		0,
		u32(size_of(Scene_Push_Constants)),
		&push,
	)
	vk.CmdDrawIndexed(cmd, mesh.index_count, 1, 0, 0, 0)
}

destroy_dynamic_gpu_mesh :: proc(device: vk.Device, mesh: ^Dynamic_Gpu_Mesh) {
	vk.DestroyBuffer(device, mesh.index_buffer, nil)
	vk.FreeMemory(device, mesh.index_memory, nil)
	for frame_index in 0 ..< MAX_FRAMES_IN_FLIGHT {
		vk.DestroyBuffer(device, mesh.vertex_buffers[frame_index], nil)
		vk.FreeMemory(device, mesh.vertex_memories[frame_index], nil)
	}
	assets.destroy_mesh(&mesh.mesh)
	mesh^ = {}
}

create_buffer_with_data :: proc(ctx: ^Gfx_Context, data: []$T, usage: vk.BufferUsageFlags) -> (buffer: vk.Buffer, memory: vk.DeviceMemory, ok: bool) {
	if len(data) == 0 {
		fmt.eprintln("Buffer upload requires data")
		return {}, {}, false
	}

	buffer_size := vk.DeviceSize(len(data) * size_of(T))
	buffer, memory, ok = create_buffer(ctx, buffer_size, usage)
	if !ok {
		return {}, {}, false
	}
	if !write_buffer_data(ctx.device, memory, data) {
		vk.FreeMemory(ctx.device, memory, nil)
		vk.DestroyBuffer(ctx.device, buffer, nil)
		return {}, {}, false
	}
	return buffer, memory, true
}

create_buffer :: proc(ctx: ^Gfx_Context, buffer_size: vk.DeviceSize, usage: vk.BufferUsageFlags) -> (buffer: vk.Buffer, memory: vk.DeviceMemory, ok: bool) {
	buffer_info := vk.BufferCreateInfo{
		sType = .BUFFER_CREATE_INFO,
		size  = buffer_size,
		usage = usage,
	}
	if vk.CreateBuffer(ctx.device, &buffer_info, nil, &buffer) != .SUCCESS {
		fmt.eprintln("Failed to create GPU buffer")
		return {}, {}, false
	}

	requirements: vk.MemoryRequirements
	vk.GetBufferMemoryRequirements(ctx.device, buffer, &requirements)

	memory_type_index, type_ok := find_memory_type(
		ctx.physical_device,
		requirements.memoryTypeBits,
		{.HOST_VISIBLE, .HOST_COHERENT},
	)
	if !type_ok {
		fmt.eprintln("Failed to find compatible Vulkan memory type")
		vk.DestroyBuffer(ctx.device, buffer, nil)
		return {}, {}, false
	}

	alloc_info := vk.MemoryAllocateInfo{
		sType           = .MEMORY_ALLOCATE_INFO,
		allocationSize  = requirements.size,
		memoryTypeIndex = memory_type_index,
	}
	if vk.AllocateMemory(ctx.device, &alloc_info, nil, &memory) != .SUCCESS {
		fmt.eprintln("Failed to allocate GPU buffer memory")
		vk.DestroyBuffer(ctx.device, buffer, nil)
		return {}, {}, false
	}

	if vk.BindBufferMemory(ctx.device, buffer, memory, 0) != .SUCCESS {
		fmt.eprintln("Failed to bind GPU buffer memory")
		vk.FreeMemory(ctx.device, memory, nil)
		vk.DestroyBuffer(ctx.device, buffer, nil)
		return {}, {}, false
	}

	return buffer, memory, true
}

write_buffer_data :: proc(device: vk.Device, memory: vk.DeviceMemory, data: []$T) -> bool {
	if len(data) == 0 {
		return true
	}

	buffer_size := vk.DeviceSize(len(data) * size_of(T))
	mapped: rawptr
	if vk.MapMemory(device, memory, 0, buffer_size, {}, &mapped) != .SUCCESS {
		fmt.eprintln("Failed to map GPU buffer memory")
		return false
	}

	intrinsics.mem_copy(mapped, raw_data(data), len(data) * size_of(T))
	vk.UnmapMemory(device, memory)
	return true
}

find_memory_type :: proc(physical_device: vk.PhysicalDevice, type_bits: u32, required: vk.MemoryPropertyFlags) -> (index: u32, ok: bool) {
	properties: vk.PhysicalDeviceMemoryProperties
	vk.GetPhysicalDeviceMemoryProperties(physical_device, &properties)

	for i in 0 ..< int(properties.memoryTypeCount) {
		supported := (type_bits & (1 << u32(i))) != 0
		has_flags := (properties.memoryTypes[i].propertyFlags & required) == required
		if supported && has_flags {
			return u32(i), true
		}
	}

	return 0, false
}
