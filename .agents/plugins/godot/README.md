# Godot Agent Plugin (`godot-agent-plugin`)

An extension package for the Godot Engine 4.7+ implementing the Agent Plugins Specification (v1.0.0).

This plugin provides live runtime engine bridge tools, ClassDB documentation lookup, Blender 3D DCC pipeline automation, GDScript conventions, and game design document authoring skills for AI coding agents.

## Included Components

### 1. Model Context Protocol Servers (`mcp.json`)

- `godot-engine`: Dual-tier live editor bridge and headless CLI server with tools for scene management, node hierarchy mutation, physics inspection, shader compilation, and viewport capture. Source: `https://github.com/mcintalmo/godot-engine-mcp`.
- `godot-docs`: Godot 4.7 engine documentation and ClassDB metadata query server. Source: `https://github.com/mcintalmo/godot-docs-mcp`.
- `blender`: Blender 3D automation and GLTF export pipeline.

### 2. Context Rules (`rules/`)

- `gdscript.md`: Godot 4.7+ static typing standards, annotations, and deprecated syntax rules.
- `scene_architecture.md`: Node composition, ownership rules, and signal decoupling patterns.
- `shaders.md`: Godot Shading Language standards and built-in variable definitions.
- `project_structure.md`: Directory layout, naming conventions, and resource UID references.

### 3. Agent Skills (`skills/`)

- `gdd-authoring`: Structured methodology for authoring technical Game Design Documents covering core loops, mechanics, systems, pacing, and Godot 4 architecture.
- `godot-vision-fix`: Multi-turn viewport layout and UI debugging workflow using screenshot capture.
- `godot-frame-step-sim`: Interactive frame-by-frame physics and collision debugging.
- `godot-dcc-pipeline`: Automated Blender to Godot 4 GLTF/PBR asset import pipeline.
- `godot-gut-testing`: Headless Godot Unit Test (GUT) scaffolding, execution, and failure diagnosis.

### 4. Lifecycle Hooks (`hooks.json`)

- `gdscript-syntax-guard`: Runs `godot --headless --check-only` after file modifications to validate GDScript syntax.

## Installation

### Claude Code

```bash
claude plugin add mcintalmo/godot-agent-plugin
```

### Antigravity IDE / Agent CLI

```bash
agy plugin add mcintalmo/godot-agent-plugin
```

### Manual Installation

Clone or submodule the repository into your project's `.agents/plugins/` directory:

```bash
mkdir -p .agents/plugins
git clone https://github.com/mcintalmo/godot-agent-plugin.git .agents/plugins/godot
```

## Continuous Integration

Run the markdown linter across all documentation:

```bash
npx markdownlint-cli "**/*.md"
```

## License

MIT License. See [LICENSE](LICENSE) for details.
