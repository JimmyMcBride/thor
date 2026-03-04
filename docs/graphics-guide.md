# Graphics Guide (Vulkan)

> **Read when:** Working on Vulkan rendering, shaders, pipelines, swapchain, or fixing graphics errors.

## File Map

| File | Responsibility |
|------|---------------|
| `gfx.odin` | `Gfx_Context` struct, `create_context`, `destroy_context`, `recreate_swapchain` |
| `cel.odin` | Cel-scene uniform data, descriptor set layout/pool/set creation |
| `mesh.odin` | GPU mesh/scene-mesh buffers, memory allocation, vertex/index upload |
| `pipeline.odin` | Shared mesh pipeline creation, cel pass, outline pass |
| `instance.odin` | Vulkan instance, validation layers, `Queue_Family_Indices`, physical device selection |
| `device.odin` | Logical device creation, queue retrieval |
| `swapchain.odin` | `Swapchain` struct, format/present mode/extent selection, image view creation |
| `frame.odin` | `begin_frame` / `end_frame`, command recording, image transitions, sync |

## Gfx_Context (Central State)

```odin
Gfx_Context :: struct {
    // Vulkan core
    instance, physical_device, device, surface
    graphics_queue, present_queue, queue_indices

    // Swapchain
    swapchain: Swapchain  // handle, images, image_views, format, extent

    // Per-frame (indexed by current_frame, 0..MAX_FRAMES_IN_FLIGHT-1)
    command_pool, command_buffers[2]
    image_available_semaphores[2], render_finished_semaphores[2], in_flight_fences[2]

    // State
    current_frame: u32        // alternates 0/1
    image_index: u32          // acquired swapchain image
    framebuffer_resized: bool // set by main loop on window resize
    window: ^platform.Window  // back-reference
}
```

## Initialization Sequence

```
1. vk.load_proc_addresses_global()     — via SDL's GetInstanceProcAddr
2. vk.CreateInstance()                  — app info (v0.1.0), Vulkan 1.3, SDL extensions
   when ODIN_DEBUG and supported: + debug utils ext + validation layer
3. vk.load_proc_addresses_instance()
4. SDL Vulkan_CreateSurface()
5. pick_physical_device()               — enumerate, score (discrete=1000, integrated=100)
6. find_queue_families()                — graphics + present support
7. create_logical_device()              — unique queue families, VK_KHR_swapchain extension
   vk.load_proc_addresses_device()
8. create_swapchain()                   — B8G8R8A8_SRGB preferred, MAILBOX→FIFO
9. Create cel descriptor set layout/pool + per-frame uniform buffers
10. Create cel pass, outline pass, and UI pipelines
11. Load `.glb` scene mesh + upload vertex/index buffers
12. CreateCommandPool()                 — RESET_COMMAND_BUFFER flag
13. AllocateCommandBuffers()            — 2 primary buffers
14. Create semaphores + fences          — fences start SIGNALED
```

## Frame Rendering Flow

### begin_frame(ctx) → bool

```
1. WaitForFences(current_frame)
2. AcquireNextImageKHR → image_index
   - ERROR_OUT_OF_DATE → recreate_swapchain(), return false
3. ResetFences(current_frame)
4. ResetCommandBuffer + BeginCommandBuffer (ONE_TIME_SUBMIT)
5. CmdBeginRenderPass (clear to dark blue-gray: 0.01, 0.01, 0.02)
6. Set dynamic viewport + scissor
7. return true
```

### end_frame(ctx)

```
1. CmdEndRenderPass + EndCommandBuffer
2. QueueSubmit: wait on image_available, signal render_finished, fence
3. QueuePresentKHR
   - OUT_OF_DATE / SUBOPTIMAL / framebuffer_resized → recreate_swapchain()
4. current_frame = (current_frame + 1) % 2
```

## Swapchain Details

- **Format preference**: `B8G8R8A8_SRGB` + `SRGB_NONLINEAR` (falls back to first available)
- **Present mode**: `MAILBOX` preferred (low-latency), `FIFO` fallback (always supported)
- **Image count**: `minImageCount + 1`, clamped to `maxImageCount`
- **Image usage**: `COLOR_ATTACHMENT | TRANSFER_DST` (supports both render pass and clear)
- **Sharing mode**: `EXCLUSIVE` if graphics==present family, `CONCURRENT` otherwise
- **Recreation**: passes old swapchain handle, destroys old after new is created

## Current Mesh Slice

The current renderer draws imported `.glb` static meshes as primitive/material batches with two stylized passes:

1. **CPU scene-mesh extraction** — primitive-local `POSITION` + `NORMAL` plus imported material base colors
2. **CPU normalization** — each primitive is normalized into the current viewer-friendly framing
3. **GPU upload** — host-visible Vulkan vertex/index buffers per primitive
4. **Outline pass** — inverted-hull draw with front-face culling
5. **Cel pass** — quantized diffuse/spec/rim lighting using per-frame cel scene data, with per-primitive material color overrides

Key considerations:
- Framebuffers must be recreated alongside swapchain
- Cel descriptor sets and pipeline layouts are independent of swapchain (can be created once)
- Use dynamic viewport/scissor to avoid pipeline recreation on resize

## Common Vulkan Errors

| Error | Likely Cause |
|-------|-------------|
| `ERROR_OUT_OF_DATE_KHR` | Window resized, swapchain stale — handled automatically |
| `SUBOPTIMAL_KHR` | Swapchain usable but not ideal — triggers recreation |
| `ERROR_DEVICE_LOST` | GPU crash or driver issue — fatal |
| Validation: "not set sType" | Missing `sType` field in a Vulkan struct |
| Validation: "layout transition" | Wrong image layout in barrier |

## Vulkan Function Pointer Loading

Odin's Vulkan bindings require explicit loading at three levels:
1. `vk.load_proc_addresses_global()` — before instance creation
2. `vk.load_proc_addresses_instance(instance)` — after instance creation
3. `vk.load_proc_addresses_device(device)` — after device creation

Missing any of these causes null function pointer crashes.
