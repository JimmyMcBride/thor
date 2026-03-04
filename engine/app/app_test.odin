package app

import "core:testing"

test_startup_system :: proc(engine: ^App) {
	engine.window.width += 1
}

test_fixed_system :: proc(engine: ^App) {
	engine.window.height += 1
}

test_update_system :: proc(engine: ^App) {
	engine.input.mouse_x += 1
}

@(test)
app_tick_runs_registered_systems :: proc(t: ^testing.T) {
	engine: App
	init(&engine)
	defer destroy(&engine)

	add_system(&engine, .Startup, test_startup_system)
	add_system(&engine, .Fixed_Update, test_fixed_system)
	add_system(&engine, .Update, test_update_system)

	tick(&engine, DEFAULT_FIXED_DT * 2.0)

	testing.expect_value(t, engine.window.width, 1)
	testing.expect_value(t, engine.window.height, 2)
	testing.expect_value(t, engine.input.mouse_x, 1)
	testing.expect_value(t, engine.time.frame_count, u64(1))
}

@(test)
app_tick_caps_large_frame_dt :: proc(t: ^testing.T) {
	engine: App
	init(&engine)
	defer destroy(&engine)

	add_system(&engine, .Fixed_Update, test_fixed_system)

	tick(&engine, 10.0)

	expected_fixed_updates := i32(MAX_FRAME_DT / DEFAULT_FIXED_DT)
	testing.expect_value(t, engine.window.height, expected_fixed_updates)
	testing.expect_value(t, engine.time.delta, MAX_FRAME_DT)
}
