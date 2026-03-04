package gfx

import "core:fmt"
import "../assets"
import vk "vendor:vulkan"

Cel_Scene_Data :: struct {
	light_direction: [4]f32,
	light_color:     [4]f32,
	base_color:      [4]f32,
	shade_color:     [4]f32,
	shadow_color:    [4]f32,
	highlight_color: [4]f32,
	rim_color:       [4]f32,
	cel_params:      [4]f32,
	material_params: [4]f32,
	outline_color:   [4]f32,
}

default_cel_scene_data :: proc() -> Cel_Scene_Data {
	return {
		light_direction = {0.15, -0.95, 0.65, 0.0},
		light_color     = {1.0, 0.98, 0.92, 1.0},
		base_color      = {0.82, 0.84, 0.90, 1.0},
		shade_color     = {0.68, 0.72, 0.82, 1.0},
		shadow_color    = {0.38, 0.43, 0.56, 1.0},
		highlight_color = {0.98, 0.99, 1.0, 1.0},
		rim_color       = {0.55, 0.66, 0.94, 1.0},
		cel_params      = {3.0, 1.0, 0.72, 0.52},
		material_params = {0.20, 0.012, 0.0, 0.0}, // rim strength, outline width
		outline_color   = {0.04, 0.04, 0.05, 1.0},
	}
}

set_cel_scene :: proc(ctx: ^Gfx_Context, scene: Cel_Scene_Data) {
	ctx.cel_scene = scene
}

cel_scene_for_material :: proc(base: Cel_Scene_Data, material: assets.Material) -> Cel_Scene_Data {
	scene := base
	scene.base_color = material.base_color
	scene.shade_color = [4]f32{
		material.base_color[0] * 0.82,
		material.base_color[1] * 0.82,
		material.base_color[2] * 0.82,
		material.base_color[3],
	}
	scene.shadow_color = [4]f32{
		material.base_color[0] * 0.46,
		material.base_color[1] * 0.46,
		material.base_color[2] * 0.52,
		material.base_color[3],
	}
	return scene
}

create_cel_descriptor_set_layout :: proc(device: vk.Device) -> (layout: vk.DescriptorSetLayout, ok: bool) {
	binding := vk.DescriptorSetLayoutBinding{
		binding         = 0,
		descriptorType  = .UNIFORM_BUFFER,
		descriptorCount = 1,
		stageFlags      = {.VERTEX, .FRAGMENT},
	}
	info := vk.DescriptorSetLayoutCreateInfo{
		sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		bindingCount = 1,
		pBindings    = &binding,
	}
	if vk.CreateDescriptorSetLayout(device, &info, nil, &layout) != .SUCCESS {
		fmt.eprintln("Failed to create cel descriptor set layout")
		return {}, false
	}
	return layout, true
}

create_cel_descriptor_pool_and_sets :: proc(device: vk.Device, layout: vk.DescriptorSetLayout) -> (pool: vk.DescriptorPool, sets: [MAX_FRAMES_IN_FLIGHT]vk.DescriptorSet, ok: bool) {
	pool_size := vk.DescriptorPoolSize{
		type            = .UNIFORM_BUFFER,
		descriptorCount = MAX_FRAMES_IN_FLIGHT,
	}
	pool_info := vk.DescriptorPoolCreateInfo{
		sType         = .DESCRIPTOR_POOL_CREATE_INFO,
		maxSets       = MAX_FRAMES_IN_FLIGHT,
		poolSizeCount = 1,
		pPoolSizes    = &pool_size,
	}
	if vk.CreateDescriptorPool(device, &pool_info, nil, &pool) != .SUCCESS {
		fmt.eprintln("Failed to create cel descriptor pool")
		return {}, sets, false
	}

	layouts := [MAX_FRAMES_IN_FLIGHT]vk.DescriptorSetLayout{layout, layout}
	alloc_info := vk.DescriptorSetAllocateInfo{
		sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
		descriptorPool     = pool,
		descriptorSetCount = MAX_FRAMES_IN_FLIGHT,
		pSetLayouts        = &layouts[0],
	}
	if vk.AllocateDescriptorSets(device, &alloc_info, &sets[0]) != .SUCCESS {
		fmt.eprintln("Failed to allocate cel descriptor sets")
		vk.DestroyDescriptorPool(device, pool, nil)
		return {}, sets, false
	}

	return pool, sets, true
}

write_cel_descriptor_sets :: proc(device: vk.Device, descriptor_sets: []vk.DescriptorSet, uniform_buffers: []vk.Buffer) {
	for i in 0 ..< min(len(descriptor_sets), len(uniform_buffers)) {
		buffer_info := vk.DescriptorBufferInfo{
			buffer = uniform_buffers[i],
			offset = 0,
			range  = vk.DeviceSize(size_of(Cel_Scene_Data)),
		}
		write := vk.WriteDescriptorSet{
			sType           = .WRITE_DESCRIPTOR_SET,
			dstSet          = descriptor_sets[i],
			dstBinding      = 0,
			descriptorCount = 1,
			descriptorType  = .UNIFORM_BUFFER,
			pBufferInfo     = &buffer_info,
		}
		vk.UpdateDescriptorSets(device, 1, &write, 0, nil)
	}
}

update_cel_scene_buffer :: proc(ctx: ^Gfx_Context) -> bool {
	return write_buffer_data(ctx.device, ctx.cel_uniform_memories[ctx.current_frame], []Cel_Scene_Data{ctx.cel_scene})
}
