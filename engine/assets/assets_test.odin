package assets

import "core:testing"

TEST_MESH_PATH :: "examples/assets/SK_Grruzam_Katana_InWeapon.glb"

@(test)
load_mesh_from_glb_extracts_positions_and_indices :: proc(t: ^testing.T) {
	mesh, ok := load_mesh_from_glb(TEST_MESH_PATH)
	testing.expect_value(t, ok, true)
	if !ok {
		return
	}
	defer destroy_mesh(&mesh)

	testing.expect_value(t, len(mesh.vertices), 7147)
	testing.expect_value(t, len(mesh.indices), 32166)
}
