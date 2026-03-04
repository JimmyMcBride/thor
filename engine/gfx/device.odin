package gfx

import "core:fmt"
import vk "vendor:vulkan"

create_logical_device :: proc(
	physical_device: vk.PhysicalDevice,
	indices: Queue_Family_Indices,
) -> (
	device: vk.Device,
	graphics_queue: vk.Queue,
	present_queue: vk.Queue,
	ok: bool,
) {
	graphics_family := indices.graphics_family.? or_return
	present_family := indices.present_family.? or_return

	// Collect unique queue families
	unique_families: [2]u32
	unique_count: int = 1
	unique_families[0] = graphics_family
	if present_family != graphics_family {
		unique_families[1] = present_family
		unique_count = 2
	}

	queue_priority: f32 = 1.0
	queue_create_infos: [2]vk.DeviceQueueCreateInfo
	for i in 0 ..< unique_count {
		queue_create_infos[i] = vk.DeviceQueueCreateInfo {
			sType            = .DEVICE_QUEUE_CREATE_INFO,
			queueFamilyIndex = unique_families[i],
			queueCount       = 1,
			pQueuePriorities = &queue_priority,
		}
	}

	device_extensions := [?]cstring{vk.KHR_SWAPCHAIN_EXTENSION_NAME}

	device_features: vk.PhysicalDeviceFeatures

	create_info := vk.DeviceCreateInfo {
		sType                   = .DEVICE_CREATE_INFO,
		queueCreateInfoCount    = u32(unique_count),
		pQueueCreateInfos       = &queue_create_infos[0],
		enabledExtensionCount   = u32(len(device_extensions)),
		ppEnabledExtensionNames = &device_extensions[0],
		pEnabledFeatures        = &device_features,
	}

	result := vk.CreateDevice(physical_device, &create_info, nil, &device)
	if result != .SUCCESS {
		fmt.eprintln("Failed to create logical device:", result)
		return {}, {}, {}, false
	}

	// Load device-level function pointers
	vk.load_proc_addresses_device(device)

	vk.GetDeviceQueue(device, graphics_family, 0, &graphics_queue)
	vk.GetDeviceQueue(device, present_family, 0, &present_queue)

	fmt.println("Logical device created")
	return device, graphics_queue, present_queue, true
}
