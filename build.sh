#!/usr/bin/env bash
set -e
mkdir -p bin
mkdir -p shaders
glslc shaders/mesh_viewer.vert -o shaders/mesh_viewer.vert.spv
glslc shaders/mesh_viewer.frag -o shaders/mesh_viewer.frag.spv
$HOME/Downloads/odin-linux-amd64-nightly+2026-02-04/odin build examples/mesh_viewer -collection:thor=. -out:bin/mesh_viewer -debug
$HOME/Downloads/odin-linux-amd64-nightly+2026-02-04/odin build examples/headless_smoke -collection:thor=. -out:bin/headless_smoke -debug
echo "Build successful: bin/mesh_viewer, bin/headless_smoke"
