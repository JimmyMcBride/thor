package gfx

import "core:fmt"
import "core:os"
import "../assets"
import vk "vendor:vulkan"

@(private)
create_shader_module :: proc(device: vk.Device, code: []byte) -> (module: vk.ShaderModule, ok: bool) {
	create_info := vk.ShaderModuleCreateInfo{
		sType    = .SHADER_MODULE_CREATE_INFO,
		codeSize = len(code),
		pCode    = cast(^u32)raw_data(code),
	}
	if vk.CreateShaderModule(device, &create_info, nil, &module) != .SUCCESS {
		fmt.eprintln("Failed to create shader module")
		return {}, false
	}
	return module, true
}

create_render_pass :: proc(device: vk.Device, color_format, depth_format: vk.Format) -> (render_pass: vk.RenderPass, ok: bool) {
	color_attachment := vk.AttachmentDescription{
		format         = color_format,
		samples         = {._1},
		loadOp          = .CLEAR,
		storeOp         = .STORE,
		stencilLoadOp   = .DONT_CARE,
		stencilStoreOp  = .DONT_CARE,
		initialLayout   = .UNDEFINED,
		finalLayout     = .PRESENT_SRC_KHR,
	}

	color_attachment_ref := vk.AttachmentReference{
		attachment = 0,
		layout     = .COLOR_ATTACHMENT_OPTIMAL,
	}
	depth_attachment := vk.AttachmentDescription{
		format         = depth_format,
		samples         = {._1},
		loadOp          = .CLEAR,
		storeOp         = .DONT_CARE,
		stencilLoadOp   = .DONT_CARE,
		stencilStoreOp  = .DONT_CARE,
		initialLayout   = .UNDEFINED,
		finalLayout     = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
	}
	depth_attachment_ref := vk.AttachmentReference{
		attachment = 1,
		layout     = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
	}

	subpass := vk.SubpassDescription{
		pipelineBindPoint       = .GRAPHICS,
		colorAttachmentCount    = 1,
		pColorAttachments       = &color_attachment_ref,
		pDepthStencilAttachment = &depth_attachment_ref,
	}

	dependency := vk.SubpassDependency{
		srcSubpass    = vk.SUBPASS_EXTERNAL,
		dstSubpass    = 0,
		srcStageMask  = {.COLOR_ATTACHMENT_OUTPUT},
		srcAccessMask = {},
		dstStageMask  = {.COLOR_ATTACHMENT_OUTPUT},
		dstAccessMask = {.COLOR_ATTACHMENT_WRITE},
	}

	attachments := [2]vk.AttachmentDescription{
		color_attachment,
		depth_attachment,
	}
	render_pass_info := vk.RenderPassCreateInfo{
		sType           = .RENDER_PASS_CREATE_INFO,
		attachmentCount = 2,
		pAttachments    = &attachments[0],
		subpassCount    = 1,
		pSubpasses      = &subpass,
		dependencyCount = 1,
		pDependencies   = &dependency,
	}

	if vk.CreateRenderPass(device, &render_pass_info, nil, &render_pass) != .SUCCESS {
		fmt.eprintln("Failed to create render pass")
		return {}, false
	}
	return render_pass, true
}

create_framebuffers :: proc(device: vk.Device, render_pass: vk.RenderPass, sc: ^Swapchain) -> bool {
	sc.framebuffers = make([]vk.Framebuffer, len(sc.image_views))
	for i in 0 ..< len(sc.image_views) {
		attachments := [2]vk.ImageView{
			sc.image_views[i],
			sc.depth_view,
		}
		fb_info := vk.FramebufferCreateInfo{
			sType           = .FRAMEBUFFER_CREATE_INFO,
			renderPass      = render_pass,
			attachmentCount = 2,
			pAttachments    = &attachments[0],
			width           = sc.extent.width,
			height          = sc.extent.height,
			layers          = 1,
		}
		if vk.CreateFramebuffer(device, &fb_info, nil, &sc.framebuffers[i]) != .SUCCESS {
			fmt.eprintln("Failed to create framebuffer", i)
			for j in 0 ..< i {
				vk.DestroyFramebuffer(device, sc.framebuffers[j], nil)
			}
			delete(sc.framebuffers)
			sc.framebuffers = nil
			return false
		}
	}
	return true
}

destroy_framebuffers :: proc(device: vk.Device, sc: ^Swapchain) {
	for fb in sc.framebuffers {
		vk.DestroyFramebuffer(device, fb, nil)
	}
	delete(sc.framebuffers)
	sc.framebuffers = nil
}

create_pipeline :: proc(device: vk.Device, render_pass: vk.RenderPass) -> (layout: vk.PipelineLayout, pipeline: vk.Pipeline, ok: bool) {
	vert_code, vert_ok := os.read_entire_file("shaders/mesh_viewer.vert.spv")
	if !vert_ok {
		fmt.eprintln("Failed to read shaders/mesh_viewer.vert.spv")
		return {}, {}, false
	}
	defer delete(vert_code)

	frag_code, frag_ok := os.read_entire_file("shaders/mesh_viewer.frag.spv")
	if !frag_ok {
		fmt.eprintln("Failed to read shaders/mesh_viewer.frag.spv")
		return {}, {}, false
	}
	defer delete(frag_code)

	vert_module := create_shader_module(device, vert_code) or_return
	defer vk.DestroyShaderModule(device, vert_module, nil)

	frag_module := create_shader_module(device, frag_code) or_return
	defer vk.DestroyShaderModule(device, frag_module, nil)

	shader_stages := [2]vk.PipelineShaderStageCreateInfo{
		{
			sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage  = {.VERTEX},
			module = vert_module,
			pName  = "main",
		},
		{
			sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage  = {.FRAGMENT},
			module = frag_module,
			pName  = "main",
		},
	}

	vertex_binding := vk.VertexInputBindingDescription{
		binding   = 0,
		stride    = u32(size_of(assets.Mesh_Vertex)),
		inputRate = .VERTEX,
	}
	vertex_attribute := vk.VertexInputAttributeDescription{
		location = 0,
		binding  = 0,
		format   = .R32G32B32_SFLOAT,
		offset   = u32(offset_of(assets.Mesh_Vertex, position)),
	}
	vertex_normal_attribute := vk.VertexInputAttributeDescription{
		location = 1,
		binding  = 0,
		format   = .R32G32B32_SFLOAT,
		offset   = u32(offset_of(assets.Mesh_Vertex, normal)),
	}
	vertex_attributes := [2]vk.VertexInputAttributeDescription{
		vertex_attribute,
		vertex_normal_attribute,
	}

	vertex_input_state := vk.PipelineVertexInputStateCreateInfo{
		sType                           = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
		vertexBindingDescriptionCount   = 1,
		pVertexBindingDescriptions      = &vertex_binding,
		vertexAttributeDescriptionCount = 2,
		pVertexAttributeDescriptions    = &vertex_attributes[0],
	}

	input_assembly := vk.PipelineInputAssemblyStateCreateInfo{
		sType                  = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
		topology               = .TRIANGLE_LIST,
		primitiveRestartEnable = false,
	}

	dynamic_states := [2]vk.DynamicState{.VIEWPORT, .SCISSOR}
	dynamic_state := vk.PipelineDynamicStateCreateInfo{
		sType             = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
		dynamicStateCount = 2,
		pDynamicStates    = &dynamic_states[0],
	}

	viewport_state := vk.PipelineViewportStateCreateInfo{
		sType         = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
		viewportCount = 1,
		scissorCount  = 1,
	}

	rasterizer := vk.PipelineRasterizationStateCreateInfo{
		sType                   = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
		depthClampEnable        = false,
		rasterizerDiscardEnable = false,
		polygonMode             = .FILL,
		lineWidth               = 1.0,
		cullMode                = {.BACK},
		frontFace               = .COUNTER_CLOCKWISE,
		depthBiasEnable         = false,
	}

	multisample := vk.PipelineMultisampleStateCreateInfo{
		sType                = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
		rasterizationSamples = {._1},
		sampleShadingEnable  = false,
	}
	depth_stencil := vk.PipelineDepthStencilStateCreateInfo{
		sType            = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
		depthTestEnable  = true,
		depthWriteEnable = true,
		depthCompareOp   = .LESS,
		depthBoundsTestEnable = false,
		stencilTestEnable = false,
	}

	color_blend_attachment := vk.PipelineColorBlendAttachmentState{
		colorWriteMask = {.R, .G, .B, .A},
		blendEnable    = false,
	}

	color_blend := vk.PipelineColorBlendStateCreateInfo{
		sType           = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
		logicOpEnable   = false,
		attachmentCount = 1,
		pAttachments    = &color_blend_attachment,
	}

	push_constant_range := vk.PushConstantRange{
		stageFlags = {.VERTEX},
		offset     = 0,
		size       = u32(size_of(Scene_Push_Constants)),
	}
	layout_info := vk.PipelineLayoutCreateInfo{
		sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
		pushConstantRangeCount = 1,
		pPushConstantRanges    = &push_constant_range,
	}
	if vk.CreatePipelineLayout(device, &layout_info, nil, &layout) != .SUCCESS {
		fmt.eprintln("Failed to create pipeline layout")
		return {}, {}, false
	}

	pipeline_info := vk.GraphicsPipelineCreateInfo{
		sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
		stageCount          = 2,
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
		fmt.eprintln("Failed to create graphics pipeline")
		vk.DestroyPipelineLayout(device, layout, nil)
		return {}, {}, false
	}

	return layout, pipeline, true
}
