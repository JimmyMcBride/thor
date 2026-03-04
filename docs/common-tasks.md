# Common Tasks

> **Read when:** Adding entities, components, new engine systems, or new modules.

## Build and Run

```bash
bash build.sh             # Builds examples to bin/mesh_viewer, bin/animation_viewer, and bin/headless_smoke
./bin/mesh_viewer         # Run the static mesh desktop example
./bin/animation_viewer    # Run the skeletal animation viewer example
bash test.sh              # Run engine/app + engine/assets tests and the headless smoke example
```

The build script uses the Odin nightly compiler at:
`$HOME/Downloads/odin-linux-amd64-nightly+2026-02-04/odin`

## Adding a New Component to ECS

The ECS is minimal — you'll need to extend it. Here's the pattern:

### 1. Define the component in `engine/ecs/ecs.odin`

```odin
Position :: struct {
    x, y, z: f32,
}

Velocity :: struct {
    x, y, z: f32,
}
```

### 2. Add component storage to World

```odin
World :: struct {
    next_entity: u64,
    // Add component maps:
    positions:  map[Entity]Position,
    velocities: map[Entity]Velocity,
}
```

### 3. Update world_create and world_destroy

```odin
world_create :: proc() -> World {
    return World{next_entity = 1}
    // maps are zero-initialized in Odin, no extra init needed
}

world_destroy :: proc(world: ^World) {
    delete(world.positions)
    delete(world.velocities)
    world^ = {}
}
```

### 4. Add component accessors

```odin
add_position :: proc(world: ^World, entity: Entity, pos: Position) {
    world.positions[entity] = pos
}

get_position :: proc(world: ^World, entity: Entity) -> (Position, bool) {
    return world.positions[entity]  // map lookup returns (value, ok)
}
```

## Adding a New System (Game Logic)

Systems register through `engine/app` and can live in `engine/game/game.odin` or a new file in `engine/game/`.

### Example: Movement System

```odin
// In engine/game/game.odin or engine/game/movement.odin (same package)
movement_system :: proc(engine: ^app.App) {
    for entity, &vel in engine.world.velocities {
        if pos, ok := &engine.world.positions[entity]; ok {
            pos.x += vel.x * f32(engine.time.fixed_delta)
            pos.y += vel.y * f32(engine.time.fixed_delta)
            pos.z += vel.z * f32(engine.time.fixed_delta)
        }
    }
}
```

Then register it with the app at the appropriate stage:

```odin
register_game_systems :: proc(engine: ^app.App) {
    app.add_system(engine, .Fixed_Update, movement_system)
}
```

- Physics/gameplay systems → `fixed_update` (deterministic 60 Hz)
- Input-responsive/visual systems → `update` (variable timestep)
- Draw submission → `app.Stage.Render`, typically invoked by a render adapter such as `gfx.render_app()`

## Adding a New Engine Module

1. **Create directory and file**: `engine/<name>/<name>.odin`
2. **Declare package**: `package <name>`
3. **Follow the init/shutdown pattern**:

```odin
package audio

Audio_Context :: struct {
    // state
}

create_context :: proc() -> (ctx: Audio_Context, ok: bool) {
    // initialize
    return ctx, true
}

destroy_context :: proc(ctx: ^Audio_Context) {
    // cleanup
}
```

4. **Wire into an example app**:

```odin
import "engine/audio"

// In examples/<app>/main.odin:
audio_ctx, audio_ok := audio.create_context()
if !audio_ok { return }
defer audio.destroy_context(&audio_ctx)
```

5. **If it needs per-frame updates**, register systems through `engine/app` in the appropriate phase. `engine/platform.install()` and `engine/gfx.install()` are the current adapter examples.

## Adding Input Handling

Access input state via the `app.Input_State` resource copied in from the platform layer:

```odin
update_system :: proc(engine: ^app.App) {
    // Check if W key is held
    if engine.input.keys_down[int(sdl.Scancode.W)] {
        // move forward
    }

    // Check if Space was just pressed this frame
    if engine.input.keys_pressed[int(sdl.Scancode.SPACE)] {
        // jump
    }

    // Mouse delta for camera
    dx := engine.input.mouse_dx
    dy := engine.input.mouse_dy
}
```

Note: You'll need `import sdl "vendor:sdl2"` in the game package to access scancodes.

## Spawning Entities

```odin
spawn_player_system :: proc(engine: ^app.App) {
    // Spawn a player entity
    player := ecs.world_spawn(&engine.world)
    ecs.add_position(&engine.world, player, {0, 0, 0})
    ecs.add_velocity(&engine.world, player, {1, 0, 0})
}
```

## Modifying the Game Loop

The desktop example loop in `examples/mesh_viewer/main.odin` now delegates simulation flow to `engine/app` and routes backend work through adapters:

- **Don't modify** the timestep/accumulator logic in `engine/app/app.odin` unless changing engine tick behavior
- **To change tick rate**: modify `DEFAULT_FIXED_DT :: 1.0 / 60.0`
- **To add a new phase** (e.g., late update): extend `app.Stage` and register systems there
- **Rendering** should happen through the render adapter calling `app.render()`, not directly from `main`

## Updating Documentation

When you make changes that affect module interfaces or architecture:
1. Update the relevant guide in `ClaudeInstructions/`
2. If you add a new module, update the project structure in `CLAUDE.md`
3. If you add new types/procs to the public API, update the Key Types section in `CLAUDE.md`
