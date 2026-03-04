package gfx

import "core:fmt"
import vk "vendor:vulkan"
import "../app"
import "../assets"
import "../platform"

MAX_FRAMES_IN_FLIGHT :: 2

Context_Config :: struct {
	mesh_path: string,
}

Gfx_Context :: struct {
	// Vulkan core
	instance:        vk.Instance,
	physical_device: vk.PhysicalDevice,
	device:          vk.Device,
	surface:         vk.SurfaceKHR,
	graphics_queue:  vk.Queue,
	present_queue:   vk.Queue,
	queue_indices:   Queue_Family_Indices,

	// Swapchain
	swapchain: Swapchain,

	// Command pools and buffers (per frame in flight)
	command_pool:    vk.CommandPool,
	command_buffers: [MAX_FRAMES_IN_FLIGHT]vk.CommandBuffer,

	// Sync objects (per frame in flight)
	image_available_semaphores: [MAX_FRAMES_IN_FLIGHT]vk.Semaphore,
	render_finished_semaphores: [MAX_FRAMES_IN_FLIGHT]vk.Semaphore,
	in_flight_fences:           [MAX_FRAMES_IN_FLIGHT]vk.Fence,

	// Pipeline
	render_pass:            vk.RenderPass,
	descriptor_set_layout:  vk.DescriptorSetLayout,
	descriptor_pool:        vk.DescriptorPool,
	descriptor_sets:        [MAX_FRAMES_IN_FLIGHT]vk.DescriptorSet,
	cel_uniform_buffers:    [MAX_FRAMES_IN_FLIGHT]vk.Buffer,
	cel_uniform_memories:   [MAX_FRAMES_IN_FLIGHT]vk.DeviceMemory,
	pipeline_layout:        vk.PipelineLayout,
	pipeline:               vk.Pipeline,
	outline_pipeline_layout: vk.PipelineLayout,
	outline_pipeline:        vk.Pipeline,
	cel_scene:             Cel_Scene_Data,
	scene_mesh:            Gpu_Scene_Mesh,
	mesh:                  Gpu_Mesh,
	ui_pipeline_layout: vk.PipelineLayout,
	ui_pipeline:        vk.Pipeline,
	ui_vertex_buffers:  [MAX_FRAMES_IN_FLIGHT]vk.Buffer,
	ui_vertex_memories: [MAX_FRAMES_IN_FLIGHT]vk.DeviceMemory,

	// Frame state
	current_frame: u32,
	image_index:   u32,
	framebuffer_resized: bool,

	// Backref
	window: ^platform.Window,
}

Render_Bridge :: struct {
	ctx: ^Gfx_Context,
}

render_bridge: Render_Bridge

install :: proc(engine: ^app.App, bridge: Render_Bridge) {
	render_bridge = bridge
	app.add_system(engine, .Shutdown, clear_bridge)
}

current_context :: proc() -> ^Gfx_Context {
	return render_bridge.ctx
}

render_app :: proc(engine: ^app.App) {
	ctx := render_bridge.ctx
	if ctx == nil {
		return
	}

	if engine.window.resized {
		ctx.framebuffer_resized = true
	}

	if begin_frame(ctx) {
		app.render(engine)
		end_frame(ctx)
	}
}

create_context :: proc(win: ^platform.Window, config: Context_Config) -> (ctx: Gfx_Context, ok: bool) {
	ctx.window = win

	// Create Vulkan instance
	ctx.instance = create_instance(win) or_return

	// Create surface
	ctx.surface = platform.create_vulkan_surface(win, ctx.instance) or_return

	// Pick physical device
	ctx.physical_device = pick_physical_device(ctx.instance, ctx.surface) or_return

	// Find queue families
	ctx.queue_indices = find_queue_families(ctx.physical_device, ctx.surface)
	if !queue_families_complete(ctx.queue_indices) {
		fmt.eprintln("Incomplete queue families")
		return {}, false
	}

	// Create logical device
	ctx.device, ctx.graphics_queue, ctx.present_queue = create_logical_device(
		ctx.physical_device,
		ctx.queue_indices,
	) or_return

	// Create swapchain
	ctx.swapchain = create_swapchain(
		ctx.device,
		ctx.physical_device,
		ctx.surface,
		ctx.queue_indices,
		win,
	) or_return

	// Create render pass, framebuffers, and pipeline
	ctx.render_pass = create_render_pass(ctx.device, ctx.swapchain.format, ctx.swapchain.depth_format) or_return
	create_framebuffers(ctx.device, ctx.render_pass, &ctx.swapchain) or_return
	ctx.descriptor_set_layout = create_cel_descriptor_set_layout(ctx.device) or_return
	ctx.descriptor_pool, ctx.descriptor_sets = create_cel_descriptor_pool_and_sets(ctx.device, ctx.descriptor_set_layout) or_return
	for frame_index in 0 ..< MAX_FRAMES_IN_FLIGHT {
		ctx.cel_uniform_buffers[frame_index], ctx.cel_uniform_memories[frame_index], ok = create_buffer(
			&ctx,
			vk.DeviceSize(size_of(Cel_Scene_Data)),
			{.UNIFORM_BUFFER},
		)
		if !ok {
			return {}, false
		}
	}
	write_cel_descriptor_sets(ctx.device, ctx.descriptor_sets[:], ctx.cel_uniform_buffers[:])
	ctx.cel_scene = default_cel_scene_data()
	ctx.pipeline_layout, ctx.pipeline = create_cel_pipeline(ctx.device, ctx.render_pass, ctx.descriptor_set_layout) or_return
	ctx.outline_pipeline_layout, ctx.outline_pipeline = create_outline_pipeline(ctx.device, ctx.render_pass, ctx.descriptor_set_layout) or_return
	ctx.ui_pipeline_layout, ctx.ui_pipeline = create_ui_pipeline(ctx.device, ctx.render_pass) or_return

	for frame_index in 0 ..< MAX_FRAMES_IN_FLIGHT {
		ctx.ui_vertex_buffers[frame_index], ctx.ui_vertex_memories[frame_index], ok = create_buffer(
			&ctx,
			UI_VERTEX_BUFFER_SIZE,
			{.VERTEX_BUFFER},
		)
		if !ok {
			return {}, false
		}
	}

	if len(config.mesh_path) > 0 {
		scene_mesh := assets.load_scene_mesh_from_glb(config.mesh_path) or_return
		ctx.scene_mesh = create_gpu_scene_mesh(&ctx, scene_mesh) or_return
	}

	// Create command pool
	graphics_family := ctx.queue_indices.graphics_family.? or_return
	pool_info := vk.CommandPoolCreateInfo {
		sType            = .COMMAND_POOL_CREATE_INFO,
		flags            = {.RESET_COMMAND_BUFFER},
		queueFamilyIndex = graphics_family,
	}
	if vk.CreateCommandPool(ctx.device, &pool_info, nil, &ctx.command_pool) != .SUCCESS {
		fmt.eprintln("Failed to create command pool")
		return {}, false
	}

	// Allocate command buffers
	alloc_info := vk.CommandBufferAllocateInfo {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool        = ctx.command_pool,
		level              = .PRIMARY,
		commandBufferCount = MAX_FRAMES_IN_FLIGHT,
	}
	if vk.AllocateCommandBuffers(ctx.device, &alloc_info, &ctx.command_buffers[0]) != .SUCCESS {
		fmt.eprintln("Failed to allocate command buffers")
		return {}, false
	}

	// Create sync objects
	sem_info := vk.SemaphoreCreateInfo {
		sType = .SEMAPHORE_CREATE_INFO,
	}
	fence_info := vk.FenceCreateInfo {
		sType = .FENCE_CREATE_INFO,
		flags = {.SIGNALED},
	}

	for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
		if vk.CreateSemaphore(ctx.device, &sem_info, nil, &ctx.image_available_semaphores[i]) != .SUCCESS ||
		   vk.CreateSemaphore(ctx.device, &sem_info, nil, &ctx.render_finished_semaphores[i]) != .SUCCESS ||
		   vk.CreateFence(ctx.device, &fence_info, nil, &ctx.in_flight_fences[i]) != .SUCCESS {
			fmt.eprintln("Failed to create sync objects")
			return {}, false
		}
	}

	fmt.println("Graphics context created")
	return ctx, true
}

destroy_context :: proc(ctx: ^Gfx_Context) {
	vk.DeviceWaitIdle(ctx.device)

	// Destroy pipeline
	if len(ctx.scene_mesh.primitives) > 0 {
		destroy_gpu_scene_mesh(ctx.device, &ctx.scene_mesh)
	}
	if ctx.mesh.index_count > 0 {
		destroy_gpu_mesh(ctx.device, &ctx.mesh)
	}
	for frame_index in 0 ..< MAX_FRAMES_IN_FLIGHT {
		vk.DestroyBuffer(ctx.device, ctx.ui_vertex_buffers[frame_index], nil)
		vk.FreeMemory(ctx.device, ctx.ui_vertex_memories[frame_index], nil)
		vk.DestroyBuffer(ctx.device, ctx.cel_uniform_buffers[frame_index], nil)
		vk.FreeMemory(ctx.device, ctx.cel_uniform_memories[frame_index], nil)
	}
	vk.DestroyPipeline(ctx.device, ctx.ui_pipeline, nil)
	vk.DestroyPipelineLayout(ctx.device, ctx.ui_pipeline_layout, nil)
	vk.DestroyPipeline(ctx.device, ctx.outline_pipeline, nil)
	vk.DestroyPipelineLayout(ctx.device, ctx.outline_pipeline_layout, nil)
	vk.DestroyPipeline(ctx.device, ctx.pipeline, nil)
	vk.DestroyPipelineLayout(ctx.device, ctx.pipeline_layout, nil)
	vk.DestroyDescriptorPool(ctx.device, ctx.descriptor_pool, nil)
	vk.DestroyDescriptorSetLayout(ctx.device, ctx.descriptor_set_layout, nil)
	destroy_framebuffers(ctx.device, &ctx.swapchain)
	vk.DestroyRenderPass(ctx.device, ctx.render_pass, nil)

	// Destroy sync objects
	for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
		vk.DestroySemaphore(ctx.device, ctx.image_available_semaphores[i], nil)
		vk.DestroySemaphore(ctx.device, ctx.render_finished_semaphores[i], nil)
		vk.DestroyFence(ctx.device, ctx.in_flight_fences[i], nil)
	}

	// Destroy command pool (frees command buffers too)
	vk.DestroyCommandPool(ctx.device, ctx.command_pool, nil)

	// Destroy swapchain
	destroy_swapchain(ctx.device, &ctx.swapchain)

	// Destroy device
	vk.DestroyDevice(ctx.device, nil)

	// Destroy surface
	vk.DestroySurfaceKHR(ctx.instance, ctx.surface, nil)

	// Destroy instance
	vk.DestroyInstance(ctx.instance, nil)

	fmt.println("Graphics context destroyed")
}

recreate_swapchain :: proc(ctx: ^Gfx_Context) {
	// Wait until window is non-zero size
	w, h := platform.get_drawable_size(ctx.window)
	if w == 0 || h == 0 {
		return
	}

	vk.DeviceWaitIdle(ctx.device)

	old_swapchain := ctx.swapchain.handle

	// Destroy framebuffers and old image views but keep the swapchain handle for oldSwapchain
	destroy_framebuffers(ctx.device, &ctx.swapchain)
	for view in ctx.swapchain.image_views {
		vk.DestroyImageView(ctx.device, view, nil)
	}
	delete(ctx.swapchain.image_views)
	delete(ctx.swapchain.images)

	new_sc, ok := create_swapchain(
		ctx.device,
		ctx.physical_device,
		ctx.surface,
		ctx.queue_indices,
		ctx.window,
		old_swapchain,
	)

	// Destroy old swapchain handle
	vk.DestroySwapchainKHR(ctx.device, old_swapchain, nil)

	if !ok {
		fmt.eprintln("Failed to recreate swapchain")
		return
	}

	ctx.swapchain = new_sc
	ctx.framebuffer_resized = false
	create_framebuffers(ctx.device, ctx.render_pass, &ctx.swapchain)
}

clear_bridge :: proc(engine: ^app.App) {
	_ = engine
	render_bridge = {}
}
