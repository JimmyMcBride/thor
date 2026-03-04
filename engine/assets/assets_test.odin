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

@(test)
load_scene_mesh_from_glb_extracts_primitives_and_materials :: proc(t: ^testing.T) {
	scene_mesh, ok := load_scene_mesh_from_glb(TEST_MESH_PATH)
	testing.expect_value(t, ok, true)
	if !ok {
		return
	}
	defer destroy_scene_mesh(&scene_mesh)

	testing.expect_value(t, len(scene_mesh.primitives), 2)
	testing.expect_value(t, len(scene_mesh.materials), 2)
	testing.expect_value(t, len(scene_mesh.primitives[0].vertices) > 0, true)
}

@(test)
load_animation_catalog_from_glb_extracts_clip_names_and_durations :: proc(t: ^testing.T) {
	catalog, ok := load_animation_catalog_from_glb(TEST_MESH_PATH)
	testing.expect_value(t, ok, true)
	if !ok {
		return
	}
	defer destroy_animation_catalog(&catalog)

	testing.expect_value(t, len(catalog.clips), 510)
	testing.expect_value(t, catalog.clips[0].name, "Katana_Blade_Crouch_ver_A_Idle_Turn_0")
	testing.expect_value(t, catalog.clips[0].duration > 0, true)
}

@(test)
load_skinned_asset_from_glb_extracts_skin_and_animation_data :: proc(t: ^testing.T) {
	asset, ok := load_skinned_asset_from_glb(TEST_MESH_PATH)
	testing.expect_value(t, ok, true)
	if !ok {
		return
	}
	defer destroy_skinned_asset(&asset)

	testing.expect_value(t, len(asset.vertices) > 0, true)
	testing.expect_value(t, len(asset.indices) > 0, true)
	testing.expect_value(t, len(asset.skin.joint_nodes), 72)
	testing.expect_value(t, len(asset.clips), 510)
	testing.expect_value(t, asset.clips[0].name, "Katana_Blade_Crouch_ver_A_Idle_Turn_0")
}
