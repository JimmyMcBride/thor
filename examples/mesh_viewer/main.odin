package main

import "core:fmt"
import "thor:engine/app"
import "thor:engine/platform"
import "thor:engine/gfx"
import "thor:engine/game"

main :: proc() {
	win, win_ok := platform.create_window({
		title  = "Thor",
		width  = 1280,
		height = 720,
	})
	if !win_ok {
		fmt.eprintln("Failed to create window")
		return
	}
	defer platform.destroy_window(&win)

	ctx, gfx_ok := gfx.create_context(&win, {
		mesh_path = "examples/assets/SK_Grruzam_Katana_InWeapon.glb",
	})
	if !gfx_ok {
		fmt.eprintln("Failed to create graphics context")
		return
	}
	defer gfx.destroy_context(&ctx)

	engine_app: app.App
	app.init(&engine_app)
	defer app.destroy(&engine_app)

	input: platform.Input
	platform.install(&engine_app, {
		window = &win,
		input  = &input,
	})
	gfx.install(&engine_app, {
		ctx = &ctx,
	})
	game.register_game_systems(&engine_app)
	app.run_startup(&engine_app)

	last_time := platform.get_time()

	for !engine_app.exit.should_exit {
		current_time := platform.get_time()
		frame_dt := current_time - last_time
		last_time = current_time

		platform.poll_events(&win, &input)
		app.tick(&engine_app, frame_dt)
		gfx.render_app(&engine_app)
	}

	fmt.println("Engine shutdown complete")
}
