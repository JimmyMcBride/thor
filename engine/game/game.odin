package game

import "../app"
import "../gfx"
import vk "vendor:vulkan"

register_game_systems :: proc(engine: ^app.App) {
	app.add_system(engine, .Startup, startup_system)
	app.add_system(engine, .Fixed_Update, fixed_update_system)
	app.add_system(engine, .Update, update_system)
	app.add_system(engine, .Render, render_system)
}

startup_system :: proc(engine: ^app.App) {
	_ = engine
}

fixed_update_system :: proc(engine: ^app.App) {
	// Physics and gameplay logic at fixed rate
	_ = engine
}

update_system :: proc(engine: ^app.App) {
	// Per-frame logic
	_ = engine
}

render_system :: proc(engine: ^app.App) {
	_ = engine

	ctx := gfx.current_context()
	if ctx == nil {
		return
	}

	cmd := ctx.command_buffers[ctx.current_frame]
	vertex_buffers := [1]vk.Buffer{ctx.mesh.vertex_buffer}
	offsets := [1]vk.DeviceSize{0}
	extent := ctx.swapchain.extent
	aspect := f32(extent.width) / f32(max(extent.height, 1))
	push_constants := gfx.build_scene_push_constants(engine.time.elapsed, aspect)

	vk.CmdBindPipeline(cmd, .GRAPHICS, ctx.pipeline)
	vk.CmdPushConstants(
		cmd,
		ctx.pipeline_layout,
		{.VERTEX},
		0,
		u32(size_of(gfx.Scene_Push_Constants)),
		&push_constants,
	)
	vk.CmdBindVertexBuffers(cmd, 0, 1, &vertex_buffers[0], &offsets[0])
	vk.CmdBindIndexBuffer(cmd, ctx.mesh.index_buffer, 0, .UINT32)
	vk.CmdDrawIndexed(cmd, ctx.mesh.index_count, 1, 0, 0, 0)
}
