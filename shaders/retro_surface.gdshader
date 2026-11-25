// Retro-blendable surface shader.
//
// One global dial, `retro` (0..1), fades the PS1 look in and out:
//   0.0  modern: smooth PBR, perspective-correct filtered textures
//   1.0  PS1:    snapped vertices, affine texture warp, nearest texels, banded colour
// The lighting itself stays Godot's PBR, so "mixed" looks like a modern game that
// was run through a 1997 console. Works in Forward+ and Compatibility.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

global uniform float retro;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform bool use_tex = false;
uniform bool use_normal = false;
uniform float normal_strength = 1.0;
uniform bool use_vcol = false;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float metallic_val : hint_range(0.0, 1.0) = 0.0;
uniform float roughness_val : hint_range(0.0, 1.0) = 1.0;
uniform vec3 emission_color : source_color = vec3(0.0);
uniform float emission_energy = 1.0;

// "Virtual" screen the vertices snap to. Lower = wobblier.
uniform vec2 snap_grid = vec2(240.0, 180.0);
uniform float snap_strength : hint_range(0.0, 1.0) = 1.0;
uniform float color_steps = 24.0;

varying vec2 uv_persp;
varying vec2 uv_over_w;
varying float clip_w;

void vertex() {
	uv_persp = UV;
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	clip_w = max(clip.w, 0.0001);
	uv_over_w = UV * clip_w;

	// Vertex snapping: round the projected vertex to a coarse pixel grid.
	// POSITION must be written on every path, or unwritten paths collapse to zero.
	vec4 pos = clip;
	float snap_amt = smoothstep(0.15, 0.65, retro) * snap_strength;
	if (clip.w > 0.05 && snap_amt > 0.0) {
		vec2 ndc = clip.xy / clip.w;
		vec2 g = snap_grid * 0.5;
		vec2 snapped = floor(ndc * g + 0.5) / g;
		ndc = mix(ndc, snapped, snap_amt);
		pos = vec4(ndc * clip.w, clip.z, clip.w);
	}
	POSITION = pos;
}

void fragment() {
	// Affine texture mapping: undo perspective correction on the UVs.
	float affine_amt = smoothstep(0.35, 1.0, retro) * 0.8;
	vec2 uv_affine = uv_over_w / clip_w;
	vec2 uv = mix(uv_persp, uv_affine, affine_amt);

	vec4 col = albedo_color;
	if (use_vcol) {
		col *= COLOR;
	}
	if (use_tex) {
		// PS1 end: nearest texels from one mip down (chunkier, like a 64 px/m console texture).
		int lod_i = int(round(smoothstep(0.6, 0.95, retro)));
		vec2 tsz = vec2(textureSize(albedo_tex, lod_i));
		vec2 uv_near = (floor(uv * tsz) + 0.5) / tsz;
		float near_amt = smoothstep(0.3, 0.8, retro);
		vec4 smooth_s = texture(albedo_tex, uv);
		vec4 near_s = textureLod(albedo_tex, uv_near, float(lod_i));
		col *= mix(smooth_s, near_s, near_amt);
	}
	if (use_normal) {
		// Modern layer: surface relief fades out as the dial goes up.
		NORMAL_MAP = texture(normal_tex, uv).rgb;
		NORMAL_MAP_DEPTH = normal_strength * (1.0 - smoothstep(0.3, 0.9, retro));
	}

	// Banded colour depth.
	float q_amt = smoothstep(0.4, 1.0, retro);
	vec3 banded = floor(col.rgb * color_steps + 0.5) / color_steps;

	ALBEDO = mix(col.rgb, banded, q_amt);
	METALLIC = metallic_val * (1.0 - retro * 0.8);
	ROUGHNESS = mix(roughness_val, 1.0, retro * 0.7);
	EMISSION = emission_color * emission_energy;
}
