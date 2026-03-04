package app

import "../ecs"

MAX_FRAME_DT :: 0.25
DEFAULT_FIXED_DT :: 1.0 / 60.0

Stage :: enum {
	Startup,
	Fixed_Update,
	Update,
	Render,
	Shutdown,
}

System :: distinct proc(engine: ^App)

Time :: struct {
	delta:       f64,
	fixed_delta: f64,
	accumulator: f64,
	elapsed:     f64,
	frame_count: u64,
}

App_Exit :: struct {
	should_exit: bool,
}

Input_State :: struct {
	keys_down:     [512]bool,
	keys_pressed:  [512]bool,
	keys_released: [512]bool,
	mouse_x:       i32,
	mouse_y:       i32,
	mouse_dx:      i32,
	mouse_dy:      i32,
	mouse_buttons: [5]bool,
	mouse_pressed: [5]bool,
	mouse_released: [5]bool,
	mouse_wheel_x: i32,
	mouse_wheel_y: i32,
	text_input_count: int,
	text_input:    [32]u8,
}

Window_State :: struct {
	width:        i32,
	height:       i32,
	resized:      bool,
	should_close: bool,
}

App :: struct {
	world:  ecs.World,
	time:   Time,
	exit:   App_Exit,
	input:  Input_State,
	window: Window_State,

	startup_systems:      [dynamic]System,
	fixed_update_systems: [dynamic]System,
	update_systems:       [dynamic]System,
	render_systems:       [dynamic]System,
	shutdown_systems:     [dynamic]System,

	startup_complete: bool,
}

init :: proc(engine: ^App) {
	engine.world = ecs.world_create()
	engine.time.fixed_delta = DEFAULT_FIXED_DT
}

destroy :: proc(engine: ^App) {
	run_shutdown(engine)
	delete(engine.startup_systems)
	delete(engine.fixed_update_systems)
	delete(engine.update_systems)
	delete(engine.render_systems)
	delete(engine.shutdown_systems)
	ecs.world_destroy(&engine.world)
	engine^ = {}
}

add_system :: proc(engine: ^App, stage: Stage, system: System) {
	#partial switch stage {
	case .Startup:
		append(&engine.startup_systems, system)
	case .Fixed_Update:
		append(&engine.fixed_update_systems, system)
	case .Update:
		append(&engine.update_systems, system)
	case .Render:
		append(&engine.render_systems, system)
	case .Shutdown:
		append(&engine.shutdown_systems, system)
	}
}

run_startup :: proc(engine: ^App) {
	if engine.startup_complete {
		return
	}

	for system in engine.startup_systems {
		system(engine)
	}

	engine.startup_complete = true
}

tick :: proc(engine: ^App, frame_dt: f64) {
	run_startup(engine)

	capped_dt := frame_dt
	if capped_dt > MAX_FRAME_DT {
		capped_dt = MAX_FRAME_DT
	}

	engine.time.delta = capped_dt
	engine.time.elapsed += capped_dt
	engine.time.accumulator += capped_dt

	for engine.time.accumulator >= engine.time.fixed_delta {
		for system in engine.fixed_update_systems {
			system(engine)
		}
		engine.time.accumulator -= engine.time.fixed_delta
	}

	for system in engine.update_systems {
		system(engine)
	}

	engine.time.frame_count += 1
}

render :: proc(engine: ^App) {
	run_startup(engine)

	for system in engine.render_systems {
		system(engine)
	}
}

request_exit :: proc(engine: ^App) {
	engine.exit.should_exit = true
}

set_input :: proc(engine: ^App, input: Input_State) {
	engine.input = input
}

set_window :: proc(engine: ^App, window: Window_State) {
	engine.window = window

	if window.should_close {
		request_exit(engine)
	}
}

run_shutdown :: proc(engine: ^App) {
	if !engine.startup_complete {
		return
	}

	for i := len(engine.shutdown_systems) - 1; i >= 0; i -= 1 {
		engine.shutdown_systems[i](engine)
	}

	engine.startup_complete = false
}
