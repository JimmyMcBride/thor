package gfx

import "core:fmt"
import vk "vendor:vulkan"
import "../platform"

Swapchain :: struct {
	handle:       vk.SwapchainKHR,
	images:       []vk.Image,
	image_views:  []vk.ImageView,
	framebuffers: []vk.Framebuffer,
	depth_image:  vk.Image,
	depth_memory: vk.DeviceMemory,
	depth_view:   vk.ImageView,
	depth_format: vk.Format,
	format:       vk.Format,
	extent:       vk.Extent2D,
}

choose_depth_format :: proc(physical_device: vk.PhysicalDevice) -> (format: vk.Format, ok: bool) {
	candidates := [?]vk.Format{
		.D32_SFLOAT,
		.D32_SFLOAT_S8_UINT,
		.D24_UNORM_S8_UINT,
	}

	for candidate in candidates {
		properties: vk.FormatProperties
		vk.GetPhysicalDeviceFormatProperties(physical_device, candidate, &properties)
		if .DEPTH_STENCIL_ATTACHMENT in properties.optimalTilingFeatures {
			return candidate, true
		}
	}

	return {}, false
}

create_depth_resources :: proc(device: vk.Device, physical_device: vk.PhysicalDevice, sc: ^Swapchain) -> bool {
	depth_format, ok := choose_depth_format(physical_device)
	if !ok {
		fmt.eprintln("Failed to find supported depth format")
		return false
	}

	image_info := vk.ImageCreateInfo{
		sType         = .IMAGE_CREATE_INFO,
		imageType     = .D2,
		format        = depth_format,
		extent        = {width = sc.extent.width, height = sc.extent.height, depth = 1},
		mipLevels     = 1,
		arrayLayers   = 1,
		samples       = {._1},
		tiling        = .OPTIMAL,
		usage         = {.DEPTH_STENCIL_ATTACHMENT},
		sharingMode   = .EXCLUSIVE,
		initialLayout = .UNDEFINED,
	}
	if vk.CreateImage(device, &image_info, nil, &sc.depth_image) != .SUCCESS {
		fmt.eprintln("Failed to create depth image")
		return false
	}

	requirements: vk.MemoryRequirements
	vk.GetImageMemoryRequirements(device, sc.depth_image, &requirements)

	memory_type_index, type_ok := find_memory_type(
		physical_device,
		requirements.memoryTypeBits,
		{.DEVICE_LOCAL},
	)
	if !type_ok {
		fmt.eprintln("Failed to find depth memory type")
		vk.DestroyImage(device, sc.depth_image, nil)
		sc.depth_image = {}
		return false
	}

	alloc_info := vk.MemoryAllocateInfo{
		sType           = .MEMORY_ALLOCATE_INFO,
		allocationSize  = requirements.size,
		memoryTypeIndex = memory_type_index,
	}
	if vk.AllocateMemory(device, &alloc_info, nil, &sc.depth_memory) != .SUCCESS {
		fmt.eprintln("Failed to allocate depth image memory")
		vk.DestroyImage(device, sc.depth_image, nil)
		sc.depth_image = {}
		return false
	}

	if vk.BindImageMemory(device, sc.depth_image, sc.depth_memory, 0) != .SUCCESS {
		fmt.eprintln("Failed to bind depth image memory")
		vk.FreeMemory(device, sc.depth_memory, nil)
		vk.DestroyImage(device, sc.depth_image, nil)
		sc.depth_memory = {}
		sc.depth_image = {}
		return false
	}

	view_info := vk.ImageViewCreateInfo{
		sType    = .IMAGE_VIEW_CREATE_INFO,
		image    = sc.depth_image,
		viewType = .D2,
		format   = depth_format,
		subresourceRange = {
			aspectMask     = {.DEPTH},
			baseMipLevel   = 0,
			levelCount     = 1,
			baseArrayLayer = 0,
			layerCount     = 1,
		},
	}
	if vk.CreateImageView(device, &view_info, nil, &sc.depth_view) != .SUCCESS {
		fmt.eprintln("Failed to create depth image view")
		vk.FreeMemory(device, sc.depth_memory, nil)
		vk.DestroyImage(device, sc.depth_image, nil)
		sc.depth_memory = {}
		sc.depth_image = {}
		return false
	}

	sc.depth_format = depth_format
	return true
}

destroy_depth_resources :: proc(device: vk.Device, sc: ^Swapchain) {
	vk.DestroyImageView(device, sc.depth_view, nil)
	vk.DestroyImage(device, sc.depth_image, nil)
	vk.FreeMemory(device, sc.depth_memory, nil)
	sc.depth_view = {}
	sc.depth_image = {}
	sc.depth_memory = {}
	sc.depth_format = {}
}

choose_surface_format :: proc(
	physical_device: vk.PhysicalDevice,
	surface: vk.SurfaceKHR,
) -> vk.SurfaceFormatKHR {
	format_count: u32
	vk.GetPhysicalDeviceSurfaceFormatsKHR(physical_device, surface, &format_count, nil)
	formats := make([]vk.SurfaceFormatKHR, format_count)
	defer delete(formats)
	vk.GetPhysicalDeviceSurfaceFormatsKHR(physical_device, surface, &format_count, raw_data(formats))

	for f in formats {
		if f.format == .B8G8R8A8_SRGB && f.colorSpace == .SRGB_NONLINEAR {
			return f
		}
	}

	return formats[0]
}

choose_present_mode :: proc(
	physical_device: vk.PhysicalDevice,
	surface: vk.SurfaceKHR,
) -> vk.PresentModeKHR {
	mode_count: u32
	vk.GetPhysicalDeviceSurfacePresentModesKHR(physical_device, surface, &mode_count, nil)
	modes := make([]vk.PresentModeKHR, mode_count)
	defer delete(modes)
	vk.GetPhysicalDeviceSurfacePresentModesKHR(physical_device, surface, &mode_count, raw_data(modes))

	for m in modes {
		if m == .MAILBOX {
			return m
		}
	}

	return .FIFO
}

choose_extent :: proc(
	capabilities: vk.SurfaceCapabilitiesKHR,
	win: ^platform.Window,
) -> vk.Extent2D {
	if capabilities.currentExtent.width != max(u32) {
		return capabilities.currentExtent
	}

	w, h := platform.get_drawable_size(win)
	return vk.Extent2D {
		width  = clamp(u32(w), capabilities.minImageExtent.width, capabilities.maxImageExtent.width),
		height = clamp(u32(h), capabilities.minImageExtent.height, capabilities.maxImageExtent.height),
	}
}

create_swapchain :: proc(
	device: vk.Device,
	physical_device: vk.PhysicalDevice,
	surface: vk.SurfaceKHR,
	indices: Queue_Family_Indices,
	win: ^platform.Window,
	old_swapchain: vk.SwapchainKHR = {},
) -> (sc: Swapchain, ok: bool) {
	capabilities: vk.SurfaceCapabilitiesKHR
	vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(physical_device, surface, &capabilities)

	surface_format := choose_surface_format(physical_device, surface)
	present_mode := choose_present_mode(physical_device, surface)
	extent := choose_extent(capabilities, win)

	image_count := capabilities.minImageCount + 1
	if capabilities.maxImageCount > 0 && image_count > capabilities.maxImageCount {
		image_count = capabilities.maxImageCount
	}

	graphics_family := indices.graphics_family.? or_return
	present_family := indices.present_family.? or_return

	queue_family_indices := [2]u32{graphics_family, present_family}
	sharing_mode: vk.SharingMode
	queue_family_index_count: u32
	p_queue_family_indices: [^]u32

	if graphics_family != present_family {
		sharing_mode = .CONCURRENT
		queue_family_index_count = 2
		p_queue_family_indices = &queue_family_indices[0]
	} else {
		sharing_mode = .EXCLUSIVE
	}

	create_info := vk.SwapchainCreateInfoKHR {
		sType                 = .SWAPCHAIN_CREATE_INFO_KHR,
		surface               = surface,
		minImageCount         = image_count,
		imageFormat           = surface_format.format,
		imageColorSpace       = surface_format.colorSpace,
		imageExtent           = extent,
		imageArrayLayers      = 1,
		imageUsage            = {.COLOR_ATTACHMENT, .TRANSFER_DST},
		imageSharingMode      = sharing_mode,
		queueFamilyIndexCount = queue_family_index_count,
		pQueueFamilyIndices   = p_queue_family_indices,
		preTransform          = capabilities.currentTransform,
		compositeAlpha        = {.OPAQUE},
		presentMode           = present_mode,
		clipped               = true,
		oldSwapchain          = old_swapchain,
	}

	result := vk.CreateSwapchainKHR(device, &create_info, nil, &sc.handle)
	if result != .SUCCESS {
		fmt.eprintln("Failed to create swapchain:", result)
		return {}, false
	}

	sc.format = surface_format.format
	sc.extent = extent

	// Get swapchain images
	img_count: u32
	vk.GetSwapchainImagesKHR(device, sc.handle, &img_count, nil)
	sc.images = make([]vk.Image, img_count)
	vk.GetSwapchainImagesKHR(device, sc.handle, &img_count, raw_data(sc.images))

	// Create image views
	sc.image_views = make([]vk.ImageView, img_count)
	for i in 0 ..< img_count {
		view_info := vk.ImageViewCreateInfo {
			sType    = .IMAGE_VIEW_CREATE_INFO,
			image    = sc.images[i],
			viewType = .D2,
			format   = sc.format,
			components = {
				r = .IDENTITY,
				g = .IDENTITY,
				b = .IDENTITY,
				a = .IDENTITY,
			},
			subresourceRange = {
				aspectMask     = {.COLOR},
				baseMipLevel   = 0,
				levelCount     = 1,
				baseArrayLayer = 0,
				layerCount     = 1,
			},
		}
		result = vk.CreateImageView(device, &view_info, nil, &sc.image_views[i])
		if result != .SUCCESS {
			fmt.eprintln("Failed to create image view:", result)
			// Clean up already created views
			for j in 0 ..< i {
				vk.DestroyImageView(device, sc.image_views[j], nil)
			}
			delete(sc.image_views)
			delete(sc.images)
			vk.DestroySwapchainKHR(device, sc.handle, nil)
			return {}, false
		}
	}

	if !create_depth_resources(device, physical_device, &sc) {
		for view in sc.image_views {
			vk.DestroyImageView(device, view, nil)
		}
		delete(sc.image_views)
		delete(sc.images)
		vk.DestroySwapchainKHR(device, sc.handle, nil)
		return {}, false
	}

	fmt.println("Swapchain created:", extent.width, "x", extent.height)
	return sc, true
}

destroy_swapchain :: proc(device: vk.Device, sc: ^Swapchain) {
	destroy_depth_resources(device, sc)
	for view in sc.image_views {
		vk.DestroyImageView(device, view, nil)
	}
	delete(sc.image_views)
	delete(sc.images)
	vk.DestroySwapchainKHR(device, sc.handle, nil)
	sc^ = {}
}
