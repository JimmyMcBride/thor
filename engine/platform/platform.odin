package platform

import "core:c"
import "../app"
import sdl "vendor:sdl2"
import vk "vendor:vulkan"

Window_Config :: struct {
	title:  cstring,
	width:  i32,
	height: i32,
}

Window :: struct {
	handle:       ^sdl.Window,
	should_close: bool,
	width:        i32,
	height:       i32,
	resized:      bool,
}

Input :: struct {
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

Platform_Bridge :: struct {
	window: ^Window,
	input:  ^Input,
}

platform_bridge: Platform_Bridge

install :: proc(engine: ^app.App, bridge: Platform_Bridge) {
	platform_bridge = bridge
	app.add_system(engine, .Startup, sync_app_state)
	app.add_system(engine, .Update, sync_app_state)
	app.add_system(engine, .Shutdown, clear_bridge)
}

create_window :: proc(cfg: Window_Config) -> (win: Window, ok: bool) {
	if sdl.Init({.VIDEO}) < 0 {
		return {}, false
	}

	if sdl.Vulkan_LoadLibrary(nil) < 0 {
		sdl.Quit()
		return {}, false
	}

	handle := sdl.CreateWindow(
		cfg.title,
		sdl.WINDOWPOS_CENTERED,
		sdl.WINDOWPOS_CENTERED,
		cfg.width,
		cfg.height,
		{.VULKAN, .RESIZABLE, .SHOWN},
	)
	if handle == nil {
		sdl.Vulkan_UnloadLibrary()
		sdl.Quit()
		return {}, false
	}

	return Window{handle = handle, width = cfg.width, height = cfg.height}, true
}

destroy_window :: proc(win: ^Window) {
	if win.handle != nil {
		sdl.DestroyWindow(win.handle)
	}
	sdl.Vulkan_UnloadLibrary()
	sdl.Quit()
}

start_text_input :: proc() {
	sdl.StartTextInput()
}

stop_text_input :: proc() {
	sdl.StopTextInput()
}

set_window_title :: proc(win: ^Window, title: cstring) {
	if win.handle == nil {
		return
	}

	sdl.SetWindowTitle(win.handle, title)
}

poll_events :: proc(win: ^Window, input: ^Input) {
	// Clear per-frame input state
	input.keys_pressed = {}
	input.keys_released = {}
	input.mouse_dx = 0
	input.mouse_dy = 0
	input.mouse_pressed = {}
	input.mouse_released = {}
	input.mouse_wheel_x = 0
	input.mouse_wheel_y = 0
	input.text_input_count = 0
	input.text_input = {}
	win.resized = false

	event: sdl.Event
	for sdl.PollEvent(&event) {
		#partial switch event.type {
		case .QUIT:
			win.should_close = true

		case .WINDOWEVENT:
			#partial switch event.window.event {
			case .RESIZED, .SIZE_CHANGED:
				win.width = event.window.data1
				win.height = event.window.data2
				win.resized = true
			case .CLOSE:
				win.should_close = true
			}

		case .KEYDOWN:
			sc := int(event.key.keysym.scancode)
			if sc >= 0 && sc < 512 {
				if !input.keys_down[sc] {
					input.keys_pressed[sc] = true
				}
				input.keys_down[sc] = true
			}
			// Escape to close
			if event.key.keysym.scancode == .ESCAPE {
				win.should_close = true
			}

		case .KEYUP:
			sc := int(event.key.keysym.scancode)
			if sc >= 0 && sc < 512 {
				input.keys_down[sc] = false
				input.keys_released[sc] = true
			}

		case .MOUSEMOTION:
			input.mouse_x = event.motion.x
			input.mouse_y = event.motion.y
			input.mouse_dx = event.motion.xrel
			input.mouse_dy = event.motion.yrel

		case .MOUSEBUTTONDOWN:
			btn := int(event.button.button) - 1
			if btn >= 0 && btn < 5 {
				if !input.mouse_buttons[btn] {
					input.mouse_pressed[btn] = true
				}
				input.mouse_buttons[btn] = true
			}

		case .MOUSEBUTTONUP:
			btn := int(event.button.button) - 1
			if btn >= 0 && btn < 5 {
				input.mouse_buttons[btn] = false
				input.mouse_released[btn] = true
			}

		case .MOUSEWHEEL:
			input.mouse_wheel_x += event.wheel.x
			input.mouse_wheel_y += event.wheel.y

		case .TEXTINPUT:
			for ch in event.text.text {
				if ch == 0 || input.text_input_count >= len(input.text_input) {
					break
				}
				input.text_input[input.text_input_count] = ch
				input.text_input_count += 1
			}
		}
	}
}

get_time :: proc() -> f64 {
	return f64(sdl.GetPerformanceCounter()) / f64(sdl.GetPerformanceFrequency())
}

get_vulkan_instance_extensions :: proc(win: ^Window) -> (extensions: []cstring, ok: bool) {
	count: c.uint
	if !sdl.Vulkan_GetInstanceExtensions(win.handle, &count, nil) {
		return nil, false
	}
	if count == 0 {
		return nil, true
	}
	ext_buf := make([]cstring, count)
	if !sdl.Vulkan_GetInstanceExtensions(win.handle, &count, raw_data(ext_buf)) {
		delete(ext_buf)
		return nil, false
	}
	return ext_buf, true
}

create_vulkan_surface :: proc(win: ^Window, instance: vk.Instance) -> (surface: vk.SurfaceKHR, ok: bool) {
	if !sdl.Vulkan_CreateSurface(win.handle, instance, &surface) {
		return {}, false
	}
	return surface, true
}

get_drawable_size :: proc(win: ^Window) -> (w, h: i32) {
	cw, ch: c.int
	sdl.Vulkan_GetDrawableSize(win.handle, &cw, &ch)
	return i32(cw), i32(ch)
}

get_vk_get_instance_proc_addr :: proc() -> rawptr {
	return sdl.Vulkan_GetVkGetInstanceProcAddr()
}

sync_app_state :: proc(engine: ^app.App) {
	if platform_bridge.window == nil || platform_bridge.input == nil {
		return
	}

	input := platform_bridge.input
	app.set_input(engine, app.Input_State{
		keys_down     = input.keys_down,
		keys_pressed  = input.keys_pressed,
		keys_released = input.keys_released,
		mouse_x       = input.mouse_x,
		mouse_y       = input.mouse_y,
		mouse_dx      = input.mouse_dx,
		mouse_dy      = input.mouse_dy,
		mouse_buttons = input.mouse_buttons,
		mouse_pressed = input.mouse_pressed,
		mouse_released = input.mouse_released,
		mouse_wheel_x = input.mouse_wheel_x,
		mouse_wheel_y = input.mouse_wheel_y,
		text_input_count = input.text_input_count,
		text_input = input.text_input,
	})

	window := platform_bridge.window
	app.set_window(engine, app.Window_State{
		width        = window.width,
		height       = window.height,
		resized      = window.resized,
		should_close = window.should_close,
	})
}

clear_bridge :: proc(engine: ^app.App) {
	_ = engine
	platform_bridge = {}
}
