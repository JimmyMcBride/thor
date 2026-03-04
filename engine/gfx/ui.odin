package gfx

import "core:os"
import easy_font "vendor:stb/easy_font"
import vk "vendor:vulkan"

UI_MAX_VERTICES :: 65536
UI_VERTEX_BUFFER_SIZE :: vk.DeviceSize(UI_MAX_VERTICES * size_of(Ui_Vertex))

Ui_Vertex :: struct {
	position: [2]f32,
	color:    [4]u8,
}

Ui_Push_Constants :: struct {
	screen_size: [2]f32,
}

Ui_Draw_List :: struct {
	vertices: [dynamic]Ui_Vertex,
}

destroy_ui_draw_list :: proc(draw_list: ^Ui_Draw_List) {
	delete(draw_list.vertices)
	draw_list^ = {}
}

ui_reset :: proc(draw_list: ^Ui_Draw_List) {
	clear_dynamic_array(&draw_list.vertices)
}

ui_add_rect :: proc(draw_list: ^Ui_Draw_List, x, y, w, h: f32, color: [4]u8) {
	append(&draw_list.vertices,
		Ui_Vertex{{x, y}, color},
		Ui_Vertex{{x + w, y}, color},
		Ui_Vertex{{x + w, y + h}, color},
		Ui_Vertex{{x, y}, color},
		Ui_Vertex{{x + w, y + h}, color},
		Ui_Vertex{{x, y + h}, color},
	)
}

ui_add_text :: proc(draw_list: ^Ui_Draw_List, x, y: f32, text: string, color: [4]u8, scale := f32(1.0)) {
	if len(text) == 0 {
		return
	}

	max_quads := max(1, len(text) * 32)
	quads := make([]easy_font.Quad, max_quads)
	defer delete(quads)

	quad_count := easy_font.print(x, y, text, color, quads, scale)
	for quad in quads[:quad_count] {
		append(&draw_list.vertices,
			Ui_Vertex{{quad.tl.v[0], quad.tl.v[1]}, quad.tl.c},
			Ui_Vertex{{quad.tr.v[0], quad.tr.v[1]}, quad.tr.c},
			Ui_Vertex{{quad.br.v[0], quad.br.v[1]}, quad.br.c},
			Ui_Vertex{{quad.tl.v[0], quad.tl.v[1]}, quad.tl.c},
			Ui_Vertex{{quad.br.v[0], quad.br.v[1]}, quad.br.c},
			Ui_Vertex{{quad.bl.v[0], quad.bl.v[1]}, quad.bl.c},
		)
	}
}

draw_ui :: proc(ctx: ^Gfx_Context, draw_list: ^Ui_Draw_List) {
	if len(draw_list.vertices) == 0 {
		return
	}

	vertex_count := min(len(draw_list.vertices), UI_MAX_VERTICES)
	if !write_buffer_data(ctx.device, ctx.ui_vertex_memories[ctx.current_frame], draw_list.vertices[:vertex_count]) {
		return
	}

	cmd := ctx.command_buffers[ctx.current_frame]
	vertex_buffer := ctx.ui_vertex_buffers[ctx.current_frame]
	offset: vk.DeviceSize
	push_constants := Ui_Push_Constants{
		screen_size = {f32(ctx.swapchain.extent.width), f32(ctx.swapchain.extent.height)},
	}

	vk.CmdBindPipeline(cmd, .GRAPHICS, ctx.ui_pipeline)
	vk.CmdPushConstants(
		cmd,
		ctx.ui_pipeline_layout,
		{.VERTEX},
		0,
		u32(size_of(Ui_Push_Constants)),
		&push_constants,
	)
	vk.CmdBindVertexBuffers(cmd, 0, 1, &vertex_buffer, &offset)
	vk.CmdDraw(cmd, u32(vertex_count), 1, 0, 0)
}

create_ui_pipeline :: proc(device: vk.Device, render_pass: vk.RenderPass) -> (layout: vk.PipelineLayout, pipeline: vk.Pipeline, ok: bool) {
	vert_code, vert_ok := os.read_entire_file("shaders/ui.vert.spv")
	if !vert_ok {
		return {}, {}, false
	}
	defer delete(vert_code)

	frag_code, frag_ok := os.read_entire_file("shaders/ui.frag.spv")
	if !frag_ok {
		return {}, {}, false
	}
	defer delete(frag_code)

	vert_module := create_shader_module(device, vert_code) or_return
	defer vk.DestroyShaderModule(device, vert_module, nil)

	frag_module := create_shader_module(device, frag_code) or_return
	defer vk.DestroyShaderModule(device, frag_module, nil)

	shader_stages := [2]vk.PipelineShaderStageCreateInfo{
		{ sType = .PIPELINE_SHADER_STAGE_CREATE_INFO, stage = {.VERTEX}, module = vert_module, pName = "main" },
		{ sType = .PIPELINE_SHADER_STAGE_CREATE_INFO, stage = {.FRAGMENT}, module = frag_module, pName = "main" },
	}

	vertex_binding := vk.VertexInputBindingDescription{
		binding   = 0,
		stride    = u32(size_of(Ui_Vertex)),
		inputRate = .VERTEX,
	}
	vertex_attributes := [2]vk.VertexInputAttributeDescription{
		{ location = 0, binding = 0, format = .R32G32_SFLOAT, offset = u32(offset_of(Ui_Vertex, position)) },
		{ location = 1, binding = 0, format = .R8G8B8A8_UNORM, offset = u32(offset_of(Ui_Vertex, color)) },
	}

	vertex_input_state := vk.PipelineVertexInputStateCreateInfo{
		sType                           = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
		vertexBindingDescriptionCount   = 1,
		pVertexBindingDescriptions      = &vertex_binding,
		vertexAttributeDescriptionCount = len(vertex_attributes),
		pVertexAttributeDescriptions    = &vertex_attributes[0],
	}

	input_assembly := vk.PipelineInputAssemblyStateCreateInfo{
		sType    = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
		topology = .TRIANGLE_LIST,
	}

	dynamic_states := [2]vk.DynamicState{.VIEWPORT, .SCISSOR}
	dynamic_state := vk.PipelineDynamicStateCreateInfo{
		sType             = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
		dynamicStateCount = len(dynamic_states),
		pDynamicStates    = &dynamic_states[0],
	}

	viewport_state := vk.PipelineViewportStateCreateInfo{
		sType         = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
		viewportCount = 1,
		scissorCount  = 1,
	}

	rasterizer := vk.PipelineRasterizationStateCreateInfo{
		sType                   = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
		polygonMode             = .FILL,
		lineWidth               = 1.0,
		cullMode                = {},
		frontFace               = .COUNTER_CLOCKWISE,
		rasterizerDiscardEnable = false,
	}

	multisample := vk.PipelineMultisampleStateCreateInfo{
		sType                = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
		rasterizationSamples = {._1},
	}

	color_blend_attachment := vk.PipelineColorBlendAttachmentState{
		colorWriteMask = {.R, .G, .B, .A},
		blendEnable    = true,
		srcColorBlendFactor = .SRC_ALPHA,
		dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA,
		colorBlendOp        = .ADD,
		srcAlphaBlendFactor = .ONE,
		dstAlphaBlendFactor = .ONE_MINUS_SRC_ALPHA,
		alphaBlendOp        = .ADD,
	}

	color_blend := vk.PipelineColorBlendStateCreateInfo{
		sType           = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
		attachmentCount = 1,
		pAttachments    = &color_blend_attachment,
	}

	depth_stencil := vk.PipelineDepthStencilStateCreateInfo{
		sType            = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
		depthTestEnable  = false,
		depthWriteEnable = false,
		stencilTestEnable = false,
	}

	push_constant_range := vk.PushConstantRange{
		stageFlags = {.VERTEX},
		offset     = 0,
		size       = u32(size_of(Ui_Push_Constants)),
	}
	layout_info := vk.PipelineLayoutCreateInfo{
		sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
		pushConstantRangeCount = 1,
		pPushConstantRanges    = &push_constant_range,
	}
	if vk.CreatePipelineLayout(device, &layout_info, nil, &layout) != .SUCCESS {
		return {}, {}, false
	}

	pipeline_info := vk.GraphicsPipelineCreateInfo{
		sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
		stageCount          = len(shader_stages),
		pStages             = &shader_stages[0],
		pVertexInputState   = &vertex_input_state,
		pInputAssemblyState = &input_assembly,
		pViewportState      = &viewport_state,
		pRasterizationState = &rasterizer,
		pMultisampleState   = &multisample,
		pDepthStencilState  = &depth_stencil,
		pColorBlendState    = &color_blend,
		pDynamicState       = &dynamic_state,
		layout              = layout,
		renderPass          = render_pass,
		subpass             = 0,
	}

	if vk.CreateGraphicsPipelines(device, {}, 1, &pipeline_info, nil, &pipeline) != .SUCCESS {
		vk.DestroyPipelineLayout(device, layout, nil)
		return {}, {}, false
	}

	return layout, pipeline, true
}
