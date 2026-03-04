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

destroy_gpu_mesh :: proc(device: vk.Device, mesh: ^Gpu_Mesh) {
	vk.DestroyBuffer(device, mesh.index_buffer, nil)
	vk.FreeMemory(device, mesh.index_memory, nil)
	vk.DestroyBuffer(device, mesh.vertex_buffer, nil)
	vk.FreeMemory(device, mesh.vertex_memory, nil)
	assets.destroy_mesh(&mesh.mesh)
	mesh^ = {}
}

create_buffer_with_data :: proc(ctx: ^Gfx_Context, data: []$T, usage: vk.BufferUsageFlags) -> (buffer: vk.Buffer, memory: vk.DeviceMemory, ok: bool) {
	if len(data) == 0 {
		fmt.eprintln("Buffer upload requires data")
		return {}, {}, false
	}

	buffer_size := vk.DeviceSize(len(data) * size_of(T))
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

	mapped: rawptr
	if vk.MapMemory(ctx.device, memory, 0, buffer_size, {}, &mapped) != .SUCCESS {
		fmt.eprintln("Failed to map GPU buffer memory")
		vk.FreeMemory(ctx.device, memory, nil)
		vk.DestroyBuffer(ctx.device, buffer, nil)
		return {}, {}, false
	}

	intrinsics.mem_copy(mapped, raw_data(data), len(data) * size_of(T))
	vk.UnmapMemory(ctx.device, memory)

	return buffer, memory, true
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
