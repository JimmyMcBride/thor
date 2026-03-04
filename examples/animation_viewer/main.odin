package main

import "core:fmt"
import "core:math"
import "thor:engine/animation"
import "thor:engine/app"
import "thor:engine/assets"
import "thor:engine/gfx"
import "thor:engine/platform"

ASSET_PATH :: "examples/assets/SK_Grruzam_Katana_InWeapon.glb"
SCANCODE_BACKSPACE :: 42
SCANCODE_RETURN :: 40
MIDDLE_MOUSE_BUTTON :: 1
RIGHT_MOUSE_BUTTON :: 2

PANEL_X :: 24.0
PANEL_Y :: 24.0
PANEL_W :: 470.0
PANEL_H :: 448.0
SEARCH_H :: 34.0
BUTTON_W :: 92.0
BUTTON_H :: 28.0
LIST_X :: PANEL_X + 16.0
LIST_Y :: PANEL_Y + 116.0
LIST_W :: PANEL_W - 32.0
ROW_H :: 24.0
VISIBLE_ROWS :: 11
CAMERA_SMOOTH_SPEED :: 10.0

Animation_Viewer_State :: struct {
	asset: assets.Skinned_Asset,
	player: animation.Player,
	gpu_mesh: gfx.Dynamic_Gpu_Mesh,
	ui: gfx.Ui_Draw_List,

	filtered_clip_indices: [dynamic]int,
	search_query:          [dynamic]u8,
	selected_clip_index:   int,
	scroll_row:            int,
	camera_mode_label:     string,
	camera_azimuth:        f32,
	camera_elevation:      f32,
	camera_distance:       f32,
	camera_target:         gfx.Vec3,
	camera_goal_azimuth:   f32,
	camera_goal_elevation: f32,
	camera_goal_distance:  f32,
	camera_goal_target:    gfx.Vec3,
}

viewer: Animation_Viewer_State

main :: proc() {
	asset, asset_ok := assets.load_skinned_asset_from_glb(ASSET_PATH)
	if !asset_ok {
		fmt.eprintln("Failed to load skinned asset")
		return
	}
	viewer.asset = asset
	defer assets.destroy_skinned_asset(&viewer.asset)

	player, player_ok := animation.create_player(&viewer.asset)
	if !player_ok {
		fmt.eprintln("Failed to create animation player")
		return
	}
	viewer.player = player
	defer animation.destroy_player(&viewer.player)
	reset_camera()

	refresh_filtered_clips()

	win, win_ok := platform.create_window({
		title  = "Thor Animation Viewer",
		width  = 1280,
		height = 720,
	})
	if !win_ok {
		fmt.eprintln("Failed to create window")
		return
	}
	defer platform.destroy_window(&win)
	platform.start_text_input()
	defer platform.stop_text_input()

	ctx, gfx_ok := gfx.create_context(&win, {})
	if !gfx_ok {
		fmt.eprintln("Failed to create graphics context")
		return
	}
	defer gfx.destroy_context(&ctx)

	bind_pose_mesh := assets.build_bind_pose_mesh(&viewer.asset)
	dynamic_mesh, mesh_ok := gfx.create_dynamic_gpu_mesh(&ctx, bind_pose_mesh)
	if !mesh_ok {
		fmt.eprintln("Failed to create dynamic GPU mesh")
		return
	}
	viewer.gpu_mesh = dynamic_mesh
	defer gfx.destroy_dynamic_gpu_mesh(ctx.device, &viewer.gpu_mesh)
	defer gfx.destroy_ui_draw_list(&viewer.ui)
	defer delete(viewer.filtered_clip_indices)
	defer delete(viewer.search_query)

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
	app.add_system(&engine_app, .Update, update_system)
	app.add_system(&engine_app, .Render, render_system)
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

update_system :: proc(engine: ^app.App) {
	apply_text_input(engine.input)

	if engine.input.keys_pressed[SCANCODE_BACKSPACE] && len(viewer.search_query) > 0 {
		ordered_remove(&viewer.search_query, len(viewer.search_query)-1)
		refresh_filtered_clips()
	}
	if engine.input.keys_pressed[SCANCODE_RETURN] {
		play_selected_clip()
	}

	update_mouse_ui(engine.input)
	update_camera_smoothing(f32(engine.time.delta))
	animation.update(&viewer.player, f32(engine.time.delta))
	_ = gfx.update_dynamic_gpu_mesh(gfx.current_context(), &viewer.gpu_mesh, viewer.player.skinned_vertices[:])
}

render_system :: proc(engine: ^app.App) {
	ctx := gfx.current_context()
	if ctx == nil {
		return
	}

	push_constants := build_camera_push_constants(ctx)
	gfx.draw_dynamic_gpu_mesh(ctx, &viewer.gpu_mesh, push_constants)

	build_ui(engine)
	gfx.draw_ui(ctx, &viewer.ui)
}

build_ui :: proc(engine: ^app.App) {
	gfx.ui_reset(&viewer.ui)

	panel_color := [4]u8{18, 22, 32, 224}
	border_color := [4]u8{82, 98, 128, 255}
	search_bg := [4]u8{30, 35, 46, 255}
	row_bg := [4]u8{24, 28, 38, 220}
	row_selected := [4]u8{64, 102, 162, 255}
	button_bg := [4]u8{52, 62, 82, 255}
	button_on := [4]u8{74, 122, 90, 255}
	text_color := [4]u8{230, 234, 242, 255}
	subtle_color := [4]u8{160, 170, 188, 255}

	gfx.ui_add_rect(&viewer.ui, PANEL_X, PANEL_Y, PANEL_W, PANEL_H, panel_color)
	gfx.ui_add_rect(&viewer.ui, PANEL_X, PANEL_Y, PANEL_W, 2, border_color)
	gfx.ui_add_text(&viewer.ui, PANEL_X+16, PANEL_Y+12, "Animation Viewer", text_color, 1.4)

	gfx.ui_add_text(&viewer.ui, PANEL_X+16, PANEL_Y+44, "Search", subtle_color, 1.0)
	gfx.ui_add_rect(&viewer.ui, PANEL_X+16, PANEL_Y+58, LIST_W, SEARCH_H, search_bg)
	gfx.ui_add_text(&viewer.ui, PANEL_X+26, PANEL_Y+67, string(viewer.search_query[:]), text_color, 1.0)
	if len(viewer.search_query) == 0 {
		gfx.ui_add_text(&viewer.ui, PANEL_X+26, PANEL_Y+67, "type to filter clips", subtle_color, 1.0)
	}

	play_color := button_bg
	if viewer.player.playing {
		play_color = button_on
	}
	gfx.ui_add_rect(&viewer.ui, PANEL_X+16, PANEL_Y+98, BUTTON_W, BUTTON_H, play_color)
	gfx.ui_add_text(&viewer.ui, PANEL_X+43, PANEL_Y+106, "Play", text_color, 1.0)

	loop_color := button_on if viewer.player.loop else button_bg
	gfx.ui_add_rect(&viewer.ui, PANEL_X+120, PANEL_Y+98, BUTTON_W, BUTTON_H, loop_color)
	gfx.ui_add_text(&viewer.ui, PANEL_X+145, PANEL_Y+106, "Loop", text_color, 1.0)

	gfx.ui_add_rect(&viewer.ui, PANEL_X+224, PANEL_Y+98, BUTTON_W+18, BUTTON_H, button_bg)
	gfx.ui_add_text(&viewer.ui, PANEL_X+242, PANEL_Y+106, "Reset Cam", text_color, 1.0)

	active_name := "Bind Pose"
	if clip, ok := animation.current_clip(&viewer.player); ok {
		active_name = clip.name
	}
	gfx.ui_add_text(&viewer.ui, PANEL_X+350, PANEL_Y+104, fmt.tprintf("Active: %s", active_name), text_color, 1.0)

	for row in 0 ..< VISIBLE_ROWS {
		filtered_index := viewer.scroll_row + row
		if filtered_index >= len(viewer.filtered_clip_indices) {
			break
		}

		clip_index := viewer.filtered_clip_indices[filtered_index]
		clip := viewer.asset.clips[clip_index]
		row_y := LIST_Y + f32(row) * ROW_H
		color := row_bg
		if clip_index == viewer.selected_clip_index {
			color = row_selected
		}
		gfx.ui_add_rect(&viewer.ui, LIST_X, row_y, LIST_W, ROW_H-2, color)
		gfx.ui_add_text(&viewer.ui, LIST_X+8, row_y+6, clip.name, text_color, 1.0)
	}

	gfx.ui_add_text(&viewer.ui, PANEL_X+16, PANEL_Y+390, fmt.tprintf("Showing %d of %d clips", len(viewer.filtered_clip_indices), len(viewer.asset.clips)), subtle_color, 1.0)
	gfx.ui_add_text(&viewer.ui, PANEL_X+16, PANEL_Y+412, fmt.tprintf("Time %.2fs  Camera %s", viewer.player.time, viewer.camera_mode_label), subtle_color, 1.0)
	gfx.ui_add_text(&viewer.ui, PANEL_X+16, PANEL_Y+432, "Wheel zooms. Right-drag orbits. Middle-drag pans. Reset Cam restores view.", subtle_color, 0.9)

	gizmo_x: f32 = PANEL_X + PANEL_W + f32(24)
	gizmo_y: f32 = PANEL_Y
	gfx.ui_add_rect(&viewer.ui, gizmo_x, gizmo_y, f32(240), f32(114), [4]u8{16, 20, 28, 212})
	gfx.ui_add_rect(&viewer.ui, gizmo_x, gizmo_y, f32(240), f32(2), border_color)
	gfx.ui_add_text(&viewer.ui, gizmo_x+f32(14), gizmo_y+f32(12), "Camera", text_color, 1.2)
	gfx.ui_add_text(&viewer.ui, gizmo_x+f32(14), gizmo_y+f32(38), fmt.tprintf("Mode: %s", viewer.camera_mode_label), subtle_color, 1.0)
	gfx.ui_add_text(&viewer.ui, gizmo_x+f32(14), gizmo_y+f32(58), fmt.tprintf("Dist: %.2f", viewer.camera_distance), subtle_color, 1.0)
	gfx.ui_add_text(&viewer.ui, gizmo_x+f32(14), gizmo_y+f32(78), fmt.tprintf("Target: %.2f %.2f %.2f", viewer.camera_target.x, viewer.camera_target.y, viewer.camera_target.z), subtle_color, 1.0)
	gfx.ui_add_text(&viewer.ui, gizmo_x+f32(14), gizmo_y+f32(98), fmt.tprintf("Az/El: %.2f %.2f", viewer.camera_azimuth, viewer.camera_elevation), subtle_color, 1.0)
}

apply_text_input :: proc(input: app.Input_State) {
	if input.text_input_count <= 0 {
		return
	}

	for i in 0 ..< input.text_input_count {
		ch := input.text_input[i]
		if ch < 32 || ch > 126 {
			continue
		}
		append(&viewer.search_query, ch)
	}
	refresh_filtered_clips()
}

update_mouse_ui :: proc(input: app.Input_State) {
	viewer.camera_mode_label = "Idle"
	mouse_x := f32(input.mouse_x)
	mouse_y := f32(input.mouse_y)
	over_list := point_in_rect(mouse_x, mouse_y, LIST_X, LIST_Y, LIST_W, ROW_H*f32(VISIBLE_ROWS))
	over_panel := point_in_rect(mouse_x, mouse_y, PANEL_X, PANEL_Y, PANEL_W, PANEL_H)

	if input.mouse_wheel_y != 0 {
		if over_list {
			viewer.scroll_row = clamp_scroll(viewer.scroll_row - int(input.mouse_wheel_y))
		} else {
			viewer.camera_goal_distance -= f32(input.mouse_wheel_y) * 0.35
			viewer.camera_goal_distance = clamp(viewer.camera_goal_distance, 2.2, 9.0)
			viewer.camera_mode_label = "Zoom"
		}
	}

	if input.mouse_buttons[RIGHT_MOUSE_BUTTON] {
		viewer.camera_goal_azimuth -= f32(input.mouse_dx) * 0.012
		viewer.camera_goal_elevation += f32(input.mouse_dy) * 0.009
		viewer.camera_goal_elevation = clamp(viewer.camera_goal_elevation, -0.25 * math.PI, 0.48 * math.PI)
		viewer.camera_mode_label = "Orbit"
	}
	if input.mouse_buttons[MIDDLE_MOUSE_BUTTON] {
		pan_camera(f32(input.mouse_dx), f32(input.mouse_dy))
		viewer.camera_mode_label = "Pan"
	}

	if !input.mouse_pressed[0] {
		return
	}

	if !over_panel {
		return
	}

	if point_in_rect(mouse_x, mouse_y, PANEL_X+16, PANEL_Y+98, BUTTON_W, BUTTON_H) {
		play_selected_clip()
		return
	}
	if point_in_rect(mouse_x, mouse_y, PANEL_X+120, PANEL_Y+98, BUTTON_W, BUTTON_H) {
		animation.set_looping(&viewer.player, !viewer.player.loop)
		return
	}
	if point_in_rect(mouse_x, mouse_y, PANEL_X+224, PANEL_Y+98, BUTTON_W+18, BUTTON_H) {
		reset_camera()
		viewer.camera_mode_label = "Reset"
		return
	}

	for row in 0 ..< VISIBLE_ROWS {
		filtered_index := viewer.scroll_row + row
		if filtered_index >= len(viewer.filtered_clip_indices) {
			break
		}

		row_y := LIST_Y + f32(row) * ROW_H
		if point_in_rect(mouse_x, mouse_y, LIST_X, row_y, LIST_W, ROW_H-2) {
			viewer.selected_clip_index = viewer.filtered_clip_indices[filtered_index]
			return
		}
	}
}

play_selected_clip :: proc() {
	if viewer.selected_clip_index < 0 || viewer.selected_clip_index >= len(viewer.asset.clips) {
		return
	}
	animation.play_clip(&viewer.player, viewer.selected_clip_index, true)
}

refresh_filtered_clips :: proc() {
	clear_dynamic_array(&viewer.filtered_clip_indices)
	for clip, clip_index in viewer.asset.clips {
		if query_matches(clip.name, viewer.search_query[:]) {
			append(&viewer.filtered_clip_indices, clip_index)
		}
	}

	if len(viewer.filtered_clip_indices) == 0 {
		viewer.selected_clip_index = -1
		viewer.scroll_row = 0
		return
	}

	found_selection := false
	for clip_index in viewer.filtered_clip_indices {
		if clip_index == viewer.selected_clip_index {
			found_selection = true
			break
		}
	}
	if !found_selection {
		viewer.selected_clip_index = viewer.filtered_clip_indices[0]
	}

	selected_row := 0
	for clip_index, filtered_row in viewer.filtered_clip_indices {
		if clip_index == viewer.selected_clip_index {
			selected_row = filtered_row
			break
		}
	}
	if selected_row < viewer.scroll_row {
		viewer.scroll_row = selected_row
	}
	if selected_row >= viewer.scroll_row + VISIBLE_ROWS {
		viewer.scroll_row = selected_row - VISIBLE_ROWS + 1
	}
	viewer.scroll_row = clamp_scroll(viewer.scroll_row)
}

clamp_scroll :: proc(scroll: int) -> int {
	max_scroll := max(0, len(viewer.filtered_clip_indices)-VISIBLE_ROWS)
	if scroll < 0 {
		return 0
	}
	if scroll > max_scroll {
		return max_scroll
	}
	return scroll
}

query_matches :: proc(name: string, query: []u8) -> bool {
	if len(query) == 0 {
		return true
	}
	if len(query) > len(name) {
		return false
	}

	for start in 0 ..< len(name)-len(query)+1 {
		match := true
		for offset in 0 ..< len(query) {
			if ascii_lower(name[start+offset]) != ascii_lower(query[offset]) {
				match = false
				break
			}
		}
		if match {
			return true
		}
	}

	return false
}

ascii_lower :: proc(ch: u8) -> u8 {
	if ch >= 'A' && ch <= 'Z' {
		return ch + 32
	}
	return ch
}

point_in_rect :: proc(x, y, rect_x, rect_y, rect_w, rect_h: f32) -> bool {
	return x >= rect_x && x <= rect_x + rect_w && y >= rect_y && y <= rect_y + rect_h
}

build_camera_push_constants :: proc(ctx: ^gfx.Gfx_Context) -> gfx.Scene_Push_Constants {
	distance_xy := viewer.camera_distance * math.cos(viewer.camera_elevation)
	eye := gfx.vec3(
		viewer.camera_target.x + math.cos(viewer.camera_azimuth) * distance_xy,
		viewer.camera_target.y + math.sin(viewer.camera_azimuth) * distance_xy,
		viewer.camera_target.z + 0.9 + math.sin(viewer.camera_elevation) * viewer.camera_distance,
	)
	aspect := f32(ctx.swapchain.extent.width) / f32(max(ctx.swapchain.extent.height, 1))
	return gfx.build_scene_push_constants_with_camera(
		eye,
		viewer.camera_target,
		gfx.vec3(0.0, 0.0, 1.0),
		aspect,
		0.0,
	)
}

reset_camera :: proc() {
	viewer.camera_goal_azimuth = 0.0
	viewer.camera_goal_elevation = 0.38
	viewer.camera_goal_distance = 4.25
	viewer.camera_goal_target = gfx.vec3(0.0, 0.0, -0.55)
	viewer.camera_azimuth = viewer.camera_goal_azimuth
	viewer.camera_elevation = viewer.camera_goal_elevation
	viewer.camera_distance = viewer.camera_goal_distance
	viewer.camera_target = viewer.camera_goal_target
	viewer.camera_mode_label = "Reset"
}

pan_camera :: proc(mouse_dx, mouse_dy: f32) {
	target := viewer.camera_goal_target
	distance_xy := viewer.camera_goal_distance * math.cos(viewer.camera_goal_elevation)
	eye := gfx.vec3(
		target.x + math.cos(viewer.camera_goal_azimuth) * distance_xy,
		target.y + math.sin(viewer.camera_goal_azimuth) * distance_xy,
		target.z + 0.9 + math.sin(viewer.camera_goal_elevation) * viewer.camera_goal_distance,
	)
	forward := gfx.vec3_normalize(gfx.vec3_sub(target, eye))
	right := gfx.vec3_normalize(gfx.vec3_cross(forward, gfx.vec3(0.0, 0.0, 1.0)))
	up := gfx.vec3_normalize(gfx.vec3_cross(right, forward))
	pan_scale := 0.0028 * viewer.camera_goal_distance

	viewer.camera_goal_target = gfx.vec3(
		viewer.camera_goal_target.x - right.x * mouse_dx * pan_scale + up.x * mouse_dy * pan_scale,
		viewer.camera_goal_target.y - right.y * mouse_dx * pan_scale + up.y * mouse_dy * pan_scale,
		viewer.camera_goal_target.z - right.z * mouse_dx * pan_scale + up.z * mouse_dy * pan_scale,
	)
}

update_camera_smoothing :: proc(dt: f32) {
	alpha := 1.0 - math.exp(-CAMERA_SMOOTH_SPEED * dt)
	viewer.camera_azimuth = lerp_f32(viewer.camera_azimuth, viewer.camera_goal_azimuth, alpha)
	viewer.camera_elevation = lerp_f32(viewer.camera_elevation, viewer.camera_goal_elevation, alpha)
	viewer.camera_distance = lerp_f32(viewer.camera_distance, viewer.camera_goal_distance, alpha)
	viewer.camera_target = lerp_vec3(viewer.camera_target, viewer.camera_goal_target, alpha)
}

lerp_f32 :: proc(a, b, t: f32) -> f32 {
	return a + (b-a) * t
}

lerp_vec3 :: proc(a, b: gfx.Vec3, t: f32) -> gfx.Vec3 {
	return gfx.vec3(
		lerp_f32(a.x, b.x, t),
		lerp_f32(a.y, b.y, t),
		lerp_f32(a.z, b.z, t),
	)
}
