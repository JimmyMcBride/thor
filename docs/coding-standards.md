# Coding Standards

> **Read when:** Writing new code, reviewing style, or adding new modules.

## Naming Conventions

| Kind | Style | Example |
|------|-------|---------|
| Types / Structs | `Upper_Snake_Case` | `Game_State`, `Gfx_Context`, `Queue_Family_Indices` |
| Procedures | `snake_case` | `create_window`, `begin_frame`, `world_spawn` |
| Variables | `snake_case` | `frame_dt`, `image_count`, `best_score` |
| Constants | `UPPER_SNAKE_CASE` | `MAX_FRAMES_IN_FLIGHT`, `FIXED_DT`, `VALIDATION_LAYER` |
| Package names | `lowercase` | `platform`, `gfx`, `game`, `ecs` |
| Enum variants | `UPPER_SNAKE_CASE` (via Vulkan) or `.PascalCase` (Odin built-in) | — |

## File Organization

- One package per directory under `engine/`
- Each module has a clear single responsibility
- Package name matches directory name
- Runnable entry points live under `examples/` with `package main`

### Adding a New Module

1. Create `engine/<module_name>/<module_name>.odin`
2. Declare `package <module_name>`
3. Export a context/state struct if the module has persistent state
4. Provide `create_*/init` and `destroy_*/shutdown` pairs
5. Import from other engine modules as `"../platform"`, `"../gfx"`, etc.

## Error Handling

### `or_return` Pattern (preferred)
Procs that can fail return `(value, ok: bool)`. Callers chain with `or_return`:

```odin
create_thing :: proc() -> (thing: Thing, ok: bool) {
    dependency := create_dependency() or_return
    // ...
    return thing, true
}
```

### Manual Check Pattern (when cleanup needed)
```odin
if vk.CreateSomething(device, &info, nil, &handle) != .SUCCESS {
    fmt.eprintln("Failed to create something")
    return {}, false
}
```

### Always print errors with `fmt.eprintln()` before returning false.

## Resource Management

- Use `defer` for cleanup in reverse order of creation
- Every `create_*` must have a matching `destroy_*`
- `defer delete(...)` for dynamic allocations
- Vulkan destruction order: sync objects → command pool → swapchain → device → surface → instance

## Vulkan Struct Style

Always set `sType` explicitly. Use Odin struct literal syntax:

```odin
info := vk.SomeCreateInfo {
    sType = .SOME_CREATE_INFO,
    flags = {.SOME_FLAG},
    // ...
}
```

## Conditional Compilation

Use `when` for compile-time conditionals:

```odin
when ODIN_DEBUG {
    append(&layers, VALIDATION_LAYER)
    fmt.println("Debug feature enabled")
}
```

## Import Style

```odin
import "core:fmt"
import "core:c"
import vk "vendor:vulkan"       // aliased
import sdl "vendor:sdl2"        // aliased
import "../platform"            // relative engine imports
```

- Vendor packages get short aliases (`vk`, `sdl`)
- Core packages use full names
- Engine packages use relative paths

## Logging

- Use `fmt.println()` for success/info messages
- Use `fmt.eprintln()` for errors
- No logging framework — keep it simple
