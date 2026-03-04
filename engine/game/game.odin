package game

import "../app"
import "../gfx"

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

	extent := ctx.swapchain.extent
	aspect := f32(extent.width) / f32(max(extent.height, 1))
	push_constants := gfx.build_scene_push_constants(engine.time.elapsed, aspect)
	if len(ctx.scene_mesh.primitives) > 0 {
		gfx.draw_gpu_scene_mesh(ctx, &ctx.scene_mesh, push_constants)
		return
	}
	gfx.draw_gpu_mesh(ctx, &ctx.mesh, push_constants)
}
