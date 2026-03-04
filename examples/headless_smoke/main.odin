package main

import "core:fmt"
import "thor:engine/app"

Counter :: struct {
	fixed_updates: u32,
	updates:       u32,
	startups:      u32,
}

counter: Counter

startup_system :: proc(engine: ^app.App) {
	_ = engine
	counter.startups += 1
}

fixed_update_system :: proc(engine: ^app.App) {
	_ = engine
	counter.fixed_updates += 1
}

update_system :: proc(engine: ^app.App) {
	_ = engine
	counter.updates += 1
}

main :: proc() {
	engine_app: app.App
	app.init(&engine_app)
	defer app.destroy(&engine_app)

	counter = {}
	app.add_system(&engine_app, .Startup, startup_system)
	app.add_system(&engine_app, .Fixed_Update, fixed_update_system)
	app.add_system(&engine_app, .Update, update_system)
	app.run_startup(&engine_app)

	for _ in 0 ..< 120 {
		app.tick(&engine_app, app.DEFAULT_FIXED_DT)
	}

	fmt.printf(
		"headless smoke ok: startup=%d fixed=%d update=%d frames=%d\n",
		counter.startups,
		counter.fixed_updates,
		counter.updates,
		engine_app.time.frame_count,
	)
}
