package ecs

Entity :: distinct u64

World :: struct {
	next_entity: u64,
}

world_create :: proc() -> World {
	return World{next_entity = 1}
}

world_spawn :: proc(world: ^World) -> Entity {
	id := world.next_entity
	world.next_entity += 1
	return Entity(id)
}

world_destroy :: proc(world: ^World) {
	world^ = {}
}
