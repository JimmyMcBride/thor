package gfx

import "core:fmt"
import "core:c"
import vk "vendor:vulkan"
import "../platform"

VALIDATION_LAYER :: "VK_LAYER_KHRONOS_validation"

instance_layer_available :: proc(name: cstring) -> bool {
	layer_count: u32
	if vk.EnumerateInstanceLayerProperties(&layer_count, nil) != .SUCCESS {
		return false
	}

	layers := make([]vk.LayerProperties, layer_count)
	defer delete(layers)
	if vk.EnumerateInstanceLayerProperties(&layer_count, raw_data(layers)) != .SUCCESS {
		return false
	}

	for &layer in layers {
		if cstring(&layer.layerName[0]) == name {
			return true
		}
	}

	return false
}

instance_extension_available :: proc(name: cstring) -> bool {
	ext_count: u32
	if vk.EnumerateInstanceExtensionProperties(nil, &ext_count, nil) != .SUCCESS {
		return false
	}

	extensions := make([]vk.ExtensionProperties, ext_count)
	defer delete(extensions)
	if vk.EnumerateInstanceExtensionProperties(nil, &ext_count, raw_data(extensions)) != .SUCCESS {
		return false
	}

	for &ext in extensions {
		if cstring(&ext.extensionName[0]) == name {
			return true
		}
	}

	return false
}

create_instance :: proc(win: ^platform.Window) -> (instance: vk.Instance, ok: bool) {
	// Load global Vulkan function pointers
	vk.load_proc_addresses_global(platform.get_vk_get_instance_proc_addr())

	// Get required extensions from SDL
	sdl_extensions, ext_ok := platform.get_vulkan_instance_extensions(win)
	if !ext_ok {
		fmt.eprintln("Failed to get Vulkan instance extensions from SDL")
		return {}, false
	}
	defer delete(sdl_extensions)

	// Build extension list
	extensions := make([dynamic]cstring)
	defer delete(extensions)
	for ext in sdl_extensions {
		append(&extensions, ext)
	}

	// Validation layers for debug builds
	layers := make([dynamic]cstring)
	defer delete(layers)

	when ODIN_DEBUG {
		if instance_layer_available(VALIDATION_LAYER) {
			append(&layers, VALIDATION_LAYER)

			if instance_extension_available(vk.EXT_DEBUG_UTILS_EXTENSION_NAME) {
				append(&extensions, vk.EXT_DEBUG_UTILS_EXTENSION_NAME)
			} else {
				fmt.eprintln("Vulkan debug utils extension unavailable; continuing without it")
			}

			fmt.println("Vulkan validation layers enabled")
		} else {
			fmt.eprintln("Vulkan validation layer not installed; continuing without validation")
		}
	}

	app_info := vk.ApplicationInfo {
		sType              = .APPLICATION_INFO,
		pApplicationName   = "Thor",
		applicationVersion = vk.MAKE_VERSION(0, 1, 0),
		pEngineName        = "Thor",
		engineVersion      = vk.MAKE_VERSION(0, 1, 0),
		apiVersion         = vk.API_VERSION_1_3,
	}

	create_info := vk.InstanceCreateInfo {
		sType                   = .INSTANCE_CREATE_INFO,
		pApplicationInfo        = &app_info,
		enabledExtensionCount   = u32(len(extensions)),
		ppEnabledExtensionNames = raw_data(extensions),
		enabledLayerCount       = u32(len(layers)),
		ppEnabledLayerNames     = raw_data(layers),
	}

	result := vk.CreateInstance(&create_info, nil, &instance)
	if result != .SUCCESS {
		fmt.eprintln("Failed to create Vulkan instance:", result)
		return {}, false
	}

	// Load instance-level function pointers
	vk.load_proc_addresses_instance(instance)

	fmt.println("Vulkan instance created")
	return instance, true
}

Queue_Family_Indices :: struct {
	graphics_family: Maybe(u32),
	present_family:  Maybe(u32),
}

queue_families_complete :: proc(indices: Queue_Family_Indices) -> bool {
	_, g_ok := indices.graphics_family.?
	_, p_ok := indices.present_family.?
	return g_ok && p_ok
}

find_queue_families :: proc(
	device: vk.PhysicalDevice,
	surface: vk.SurfaceKHR,
) -> Queue_Family_Indices {
	indices: Queue_Family_Indices

	family_count: u32
	vk.GetPhysicalDeviceQueueFamilyProperties(device, &family_count, nil)
	families := make([]vk.QueueFamilyProperties, family_count)
	defer delete(families)
	vk.GetPhysicalDeviceQueueFamilyProperties(device, &family_count, raw_data(families))

	for fam, i in families {
		idx := u32(i)

		if .GRAPHICS in fam.queueFlags {
			indices.graphics_family = idx
		}

		present_support: b32
		vk.GetPhysicalDeviceSurfaceSupportKHR(device, idx, surface, &present_support)
		if present_support {
			indices.present_family = idx
		}

		if queue_families_complete(indices) {
			break
		}
	}

	return indices
}

check_device_extension_support :: proc(device: vk.PhysicalDevice) -> bool {
	ext_count: u32
	vk.EnumerateDeviceExtensionProperties(device, nil, &ext_count, nil)
	available := make([]vk.ExtensionProperties, ext_count)
	defer delete(available)
	vk.EnumerateDeviceExtensionProperties(device, nil, &ext_count, raw_data(available))

	required :: "VK_KHR_swapchain"
	for &ext in available {
		name := cstring(&ext.extensionName[0])
		if name == required {
			return true
		}
	}
	return false
}

is_device_suitable :: proc(device: vk.PhysicalDevice, surface: vk.SurfaceKHR) -> bool {
	indices := find_queue_families(device, surface)
	if !queue_families_complete(indices) {
		return false
	}
	if !check_device_extension_support(device) {
		return false
	}

	// Check swapchain support
	format_count: u32
	vk.GetPhysicalDeviceSurfaceFormatsKHR(device, surface, &format_count, nil)
	present_mode_count: u32
	vk.GetPhysicalDeviceSurfacePresentModesKHR(device, surface, &present_mode_count, nil)

	return format_count > 0 && present_mode_count > 0
}

pick_physical_device :: proc(
	instance: vk.Instance,
	surface: vk.SurfaceKHR,
) -> (device: vk.PhysicalDevice, ok: bool) {
	device_count: u32
	vk.EnumeratePhysicalDevices(instance, &device_count, nil)
	if device_count == 0 {
		fmt.eprintln("No Vulkan-capable GPU found")
		return {}, false
	}

	devices := make([]vk.PhysicalDevice, device_count)
	defer delete(devices)
	vk.EnumeratePhysicalDevices(instance, &device_count, raw_data(devices))

	// Prefer discrete GPU
	best_device: vk.PhysicalDevice
	best_score: int = -1

	for dev in devices {
		if !is_device_suitable(dev, surface) {
			continue
		}

		props: vk.PhysicalDeviceProperties
		vk.GetPhysicalDeviceProperties(dev, &props)

		score := 0
		if props.deviceType == .DISCRETE_GPU {
			score = 1000
		} else if props.deviceType == .INTEGRATED_GPU {
			score = 100
		}

		if score > best_score {
			best_score = score
			best_device = dev
		}
	}

	if best_score < 0 {
		fmt.eprintln("No suitable GPU found")
		return {}, false
	}

	props: vk.PhysicalDeviceProperties
	vk.GetPhysicalDeviceProperties(best_device, &props)
	fmt.println("Selected GPU:", cstring(&props.deviceName[0]))

	return best_device, true
}
