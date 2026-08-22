# Drift

An original video game project created with the **Godot Engine 4.7+** and architected using the **Godot Agent Plugin** and Game Design Document (GDD) authoring workflow.

## Project Structure

```text
res://
├── assets/                  # Raw binary assets (models, textures, audio, shaders)
├── scenes/                  # Packed scenes (.tscn)
│   ├── characters/
│   ├── levels/
│   ├── ui/
│   └── vfx/
├── scripts/                 # GDScript source files (.gd)
│   ├── autoloads/
│   ├── components/
│   ├── resources/
│   └── state_machine/
├── resources/               # Saved resource instances (.tres)
├── test/                    # GUT unit and integration test suites
└── docs/                    # Game Design Documents (GDD) and specifications
```

## Agent Customizations

This project has the **Godot Agent Plugin** installed under `.agents/plugins/godot/`:

- **MCP Servers**: Live Godot Engine runtime bridge, ClassDB documentation lookup, and Blender DCC pipeline.
- **Rules**: Strict GDScript 4.7+ typing, scene architecture patterns, shader standards, and project structure rules.
- **Skills**:
  - `gdd-authoring`: 7-Phase Game Design Document creator.
  - `godot-vision-fix`: Viewport UI and layout visual debugging loop.
  - `godot-frame-step-sim`: Interactive frame-by-frame physics simulation debugging.
  - `godot-dcc-pipeline`: Blender to Godot asset pipeline.
  - `godot-gut-testing`: Headless GUT unit test generation and diagnosis.

## Getting Started

1. Open this project in **Godot Engine 4.7+**.
2. Activate the `gdd-authoring` skill in your AI assistant chat to begin drafting the Game Design Document for Drift.
