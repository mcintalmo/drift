# Godot Shading Language (GSL) Standards

Guidelines and reference specifications for authoring shaders in Godot 4.7+.

## Shader Structure and Declarations

Every Godot shader must declare its target pipeline on line 1:

```glsl
shader_type canvas_item; // 2D Sprites, Controls, UI, Screen effects
// shader_type spatial;   // 3D Meshes, PBR materials
// shader_type particles; // GPU Particle compute
// shader_type fog;       // Volumetric fog volumes
```

### Render Modes

Render modes configure pipeline blend states, culling, and lighting models:

```glsl
// CanvasItem modes: blend_mix, blend_add, blend_sub, blend_mul, unshaded
render_mode blend_mix, unshaded;

// Spatial modes: blend_mix, cull_back, cull_disabled, diffuse_burley, specular_schlick_ggx, depth_draw_opaque
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
```

## Built-in Pipeline Functions

| Function | Execution Domain | Purpose |
| --- | --- | --- |
| `void vertex()` | Per-vertex | Modifies vertex positions, normals, and passes custom varyings. |
| `void fragment()` | Per-pixel / Per-fragment | Computes base color, surface roughness, normals, and alpha. |
| `void light()` | Per-light source | Customizes dynamic lighting calculations (ambient, diffuse, specular). |
| `void start()` | Particles (Emit) | Initializes particle attributes on spawn. |
| `void process()` | Particles (Tick) | Updates particle physics, velocities, and lifetimes each frame. |

## Standard Built-in Variables Reference

### CanvasItem (2D) Pipeline

- `VERTEX`: Vector2 vertex position in local space.
- `UV`: Vector2 normalized texture coordinates [0.0, 1.0].
- `COLOR`: Vector4 vertex modulation color.
- `TEXTURE`: sampler2D main texture bound to the CanvasItem.
- `SCREEN_UV`: Vector2 normalized screen-space coordinates.
- `SCREEN_TEXTURE`: sampler2D screen texture (requires `hint_screen_texture`).
- `TIME`: Global elapsed time in seconds.

### Spatial (3D) Pipeline

- `VERTEX`: Vector3 vertex position in view-space coordinates.
- `NORMAL`: Vector3 normal vector in view-space.
- `ALBEDO`: Vector3 base surface color.
- `ROUGHNESS`: float surface roughness [0.0 = mirror reflection, 1.0 = diffuse matte].
- `METALLIC`: float metallic factor [0.0 = dielectric insulator, 1.0 = pure metal].
- `SPECULAR`: float specular reflection intensity (default 0.5).
- `EMISSION`: Vector3 self-illuminating emissive light contribution.
- `AO`: float ambient occlusion factor.
- `NORMAL_MAP`: Vector3 tangent-space normal texture map.

## Uniform Declarations and Hints

Use uniform hints to provide clean editor controls and accurate data typing:

```glsl
// Colors
uniform vec4 tint_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// Numeric sliders
uniform float dissolve_amount : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float wave_speed : hint_range(0.0, 20.0, 0.1) = 2.0;

// Texture samplers with filter hints
uniform sampler2D noise_texture : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_map : hint_normal, filter_linear;

// Screen texture sampling (Godot 4 requirement)
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
```

## GLSL Idioms and Best Practices

- Use `mix(a, b, t)` for linear interpolation (do not use `lerp()`).
- Use `fract(x)` for fractional components (do not use custom modulo on floats).
- Use `clamp(x, min_val, max_val)` for range bounding.
- Avoid dynamic conditional branching (`if`/`else`) inside `fragment()` when possible; favor `mix()`, `step()`, and `smoothstep()` for GPU efficiency.
