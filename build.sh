#!/usr/bin/env bash
set -e
mkdir -p bin
mkdir -p shaders
glslc shaders/cel.vert -o shaders/cel.vert.spv
glslc shaders/cel.frag -o shaders/cel.frag.spv
glslc shaders/outline.vert -o shaders/outline.vert.spv
glslc shaders/outline.frag -o shaders/outline.frag.spv
glslc shaders/ui.vert -o shaders/ui.vert.spv
glslc shaders/ui.frag -o shaders/ui.frag.spv
$HOME/Downloads/odin-linux-amd64-nightly+2026-02-04/odin build examples/mesh_viewer -collection:thor=. -out:bin/mesh_viewer -debug
$HOME/Downloads/odin-linux-amd64-nightly+2026-02-04/odin build examples/animation_viewer -collection:thor=. -out:bin/animation_viewer -debug
$HOME/Downloads/odin-linux-amd64-nightly+2026-02-04/odin build examples/headless_smoke -collection:thor=. -out:bin/headless_smoke -debug
echo "Build successful: bin/mesh_viewer, bin/animation_viewer, bin/headless_smoke"
