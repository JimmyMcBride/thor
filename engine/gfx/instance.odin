package gfx

import "core:fmt"
import "core:c"
import "core:os"
import filepath "core:path/filepath"
import "core:strings"
import vk "vendor:vulkan"
import "../platform"

VALIDATION_LAYER :: "VK_LAYER_KHRONOS_validation"
VALIDATION_LAYER_MANIFEST :: "VkLayer_khronos_validation.json"
VALIDATION_LAYER_LIBRARY :: "libVkLayer_khronos_validation.so"

find_named_file_dir :: proc(search_root, file_name: string, allocator := context.allocator) -> (dir: string, ok: bool) {
	if search_root == "" || !os.exists(search_root) {
		return "", false
	}

	search_handle, open_err := os.open(search_root, os.O_RDONLY)
	if open_err != nil {
		return "", false
	}
	defer os.close(search_handle)

	entries, read_err := os.read_dir(search_handle, -1, context.temp_allocator)
	if read_err != nil {
		return "", false
	}
	defer os.file_info_slice_delete(entries, context.temp_allocator)

	for entry in entries {
		if entry.is_dir {
			dir, ok = find_named_file_dir(entry.fullpath, file_name, allocator)
			if ok {
				return dir, true
			}
			continue
		}
		if entry.name != file_name {
			continue
		}

		parent_dir, _ := filepath.split(entry.fullpath)
		dir, alloc_err := strings.clone(parent_dir, allocator)
		if alloc_err != nil {
			return "", false
		}
		return dir, true
	}

	return "", false
}

prepend_library_path :: proc(dir: string) -> bool {
	existing_library_path, library_path_set := os.lookup_env("LD_LIBRARY_PATH", context.allocator)
	defer if library_path_set {
		delete(existing_library_path)
	}

	library_path_value := dir
	owned_library_path_value := false
	if library_path_set && existing_library_path != "" {
		joined_library_path, join_err := strings.concatenate([]string{dir, ":", existing_library_path})
		if join_err != nil {
			fmt.eprintln("Failed to build LD_LIBRARY_PATH value")
			return false
		}
		library_path_value = joined_library_path
		owned_library_path_value = true
	}
	defer if owned_library_path_value {
		delete(library_path_value)
	}

	if err := os.set_env("LD_LIBRARY_PATH", library_path_value); err != nil {
		fmt.eprintln("Failed to set LD_LIBRARY_PATH:", err)
		return false
	}

	return true
}

set_validation_layer_path_from_root :: proc(search_root: string) -> bool {
	manifest_dir, manifest_ok := find_named_file_dir(search_root, VALIDATION_LAYER_MANIFEST)
	if !manifest_ok {
		return false
	}
	defer delete(manifest_dir)

	library_dir, library_ok := find_named_file_dir(search_root, VALIDATION_LAYER_LIBRARY)
	if !library_ok {
		fmt.eprintln("Found Vulkan validation manifest but missing", VALIDATION_LAYER_LIBRARY, "under", search_root)
		return false
	}
	defer delete(library_dir)

	if err := os.set_env("VK_LAYER_PATH", manifest_dir); err != nil {
		fmt.eprintln("Failed to set VK_LAYER_PATH:", err)
		return false
	}
	if !prepend_library_path(library_dir) {
		return false
	}

	fmt.println("Using Vulkan validation layer manifest from:", manifest_dir)
	return true
}

try_configure_validation_layer_path :: proc() {
	existing_layer_path, layer_path_set := os.lookup_env("VK_LAYER_PATH", context.allocator)
	if layer_path_set {
		delete(existing_layer_path)
		return
	}

	if set_validation_layer_path_from_root("/usr/share/vulkan/explicit_layer.d") do return
	if set_validation_layer_path_from_root("/etc/vulkan/explicit_layer.d") do return
	if set_validation_layer_path_from_root("/usr/local/share/vulkan/explicit_layer.d") do return

	home_dir, home_ok := os.lookup_env("HOME", context.allocator)
	defer if home_ok {
		delete(home_dir)
	}
	if !home_ok || home_dir == "" {
		return
	}

	local_layer_dir, local_layer_err := filepath.join([]string{home_dir, ".local", "share", "vulkan", "explicit_layer.d"})
	if local_layer_err == nil {
		defer delete(local_layer_dir)
		if set_validation_layer_path_from_root(local_layer_dir) do return
	}

	local_flatpak_root, local_flatpak_err := filepath.join([]string{home_dir, ".local", "share", "flatpak", "runtime", "org.freedesktop.Platform.GL.default"})
	if local_flatpak_err == nil {
		defer delete(local_flatpak_root)
		if set_validation_layer_path_from_root(local_flatpak_root) do return
	}

	if set_validation_layer_path_from_root("/var/lib/flatpak/runtime/org.freedesktop.Platform.GL.default") do return
}

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

	when ODIN_DEBUG {
		if !instance_layer_available(VALIDATION_LAYER) {
			try_configure_validation_layer_path()
		}
	}

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
