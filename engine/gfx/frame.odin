package gfx

import vk "vendor:vulkan"

// begin_frame acquires the next swapchain image and begins recording commands.
// Returns false if the frame should be skipped (e.g., swapchain out of date).
begin_frame :: proc(ctx: ^Gfx_Context) -> bool {
	// Wait for this frame's fence
	vk.WaitForFences(ctx.device, 1, &ctx.in_flight_fences[ctx.current_frame], true, max(u64))

	// Acquire next image
	result := vk.AcquireNextImageKHR(
		ctx.device,
		ctx.swapchain.handle,
		max(u64),
		ctx.image_available_semaphores[ctx.current_frame],
		{},
		&ctx.image_index,
	)

	if result == .ERROR_OUT_OF_DATE_KHR {
		recreate_swapchain(ctx)
		return false
	}

	// Reset fence only after we know we'll submit work
	vk.ResetFences(ctx.device, 1, &ctx.in_flight_fences[ctx.current_frame])

	// Reset and begin command buffer
	cmd := ctx.command_buffers[ctx.current_frame]
	vk.ResetCommandBuffer(cmd, {})

	begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {.ONE_TIME_SUBMIT},
	}
	vk.BeginCommandBuffer(cmd, &begin_info)

	// Begin render pass (clear via loadOp=CLEAR)
	clear_values := [2]vk.ClearValue{
		{color = {float32 = {0.01, 0.01, 0.02, 1.0}}},
		{depthStencil = {depth = 1.0, stencil = 0}},
	}
	rp_begin := vk.RenderPassBeginInfo{
		sType           = .RENDER_PASS_BEGIN_INFO,
		renderPass      = ctx.render_pass,
		framebuffer     = ctx.swapchain.framebuffers[ctx.image_index],
		renderArea      = {extent = ctx.swapchain.extent},
		clearValueCount = 2,
		pClearValues    = &clear_values[0],
	}
	vk.CmdBeginRenderPass(cmd, &rp_begin, .INLINE)

	// Set dynamic viewport and scissor for this frame
	extent := ctx.swapchain.extent
	viewport := vk.Viewport{width = f32(extent.width), height = f32(extent.height), maxDepth = 1.0}
	vk.CmdSetViewport(cmd, 0, 1, &viewport)
	scissor := vk.Rect2D{extent = ctx.swapchain.extent}
	vk.CmdSetScissor(cmd, 0, 1, &scissor)

	return true
}

// end_frame submits the command buffer and presents the image.
end_frame :: proc(ctx: ^Gfx_Context) {
	cmd := ctx.command_buffers[ctx.current_frame]
	vk.CmdEndRenderPass(cmd)
	vk.EndCommandBuffer(cmd)

	wait_stage := vk.PipelineStageFlags{.COLOR_ATTACHMENT_OUTPUT}
	submit_info := vk.SubmitInfo {
		sType                = .SUBMIT_INFO,
		waitSemaphoreCount   = 1,
		pWaitSemaphores      = &ctx.image_available_semaphores[ctx.current_frame],
		pWaitDstStageMask    = &wait_stage,
		commandBufferCount   = 1,
		pCommandBuffers      = &cmd,
		signalSemaphoreCount = 1,
		pSignalSemaphores    = &ctx.render_finished_semaphores[ctx.current_frame],
	}

	vk.QueueSubmit(ctx.graphics_queue, 1, &submit_info, ctx.in_flight_fences[ctx.current_frame])

	present_info := vk.PresentInfoKHR {
		sType              = .PRESENT_INFO_KHR,
		waitSemaphoreCount = 1,
		pWaitSemaphores    = &ctx.render_finished_semaphores[ctx.current_frame],
		swapchainCount     = 1,
		pSwapchains        = &ctx.swapchain.handle,
		pImageIndices       = &ctx.image_index,
	}

	result := vk.QueuePresentKHR(ctx.present_queue, &present_info)

	if result == .ERROR_OUT_OF_DATE_KHR || result == .SUBOPTIMAL_KHR || ctx.framebuffer_resized {
		recreate_swapchain(ctx)
	}

	ctx.current_frame = (ctx.current_frame + 1) % MAX_FRAMES_IN_FLIGHT
}
