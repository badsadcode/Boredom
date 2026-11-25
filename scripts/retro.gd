extends Node
## The "retro dial". One number (0 = modern, 1 = full PS1) drives the whole look:
##  - the global shader parameter `retro` (vertex snap, affine UVs, banding, post pass)
##  - the Environment (SSAO / glow / volumetric fog fade out, short thick fog fades in)
##  - light shadows (modern soft shadows fade out at high retro)
## Keys:  [ and ]  step the dial   F1 modern   F2 mixed   F3 full PS1

signal changed(value: float)

const SURFACE_SHADER: Shader = preload("res://shaders/retro_surface.gdshader")

var level: float = 0.6:
	set(v):
		level = clampf(v, 0.0, 1.0)
		RenderingServer.global_shader_parameter_set("retro", level)
		_apply_env()
		changed.emit(level)

var _env: Environment
var _mat_cache: Dictionary = {}
var _shader_double: Shader


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	RenderingServer.global_shader_parameter_set("retro", level)


func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	match k.keycode:
		KEY_BRACKETLEFT: level -= 0.1
		KEY_BRACKETRIGHT: level += 0.1
		KEY_F1: level = 0.0
		KEY_F2: level = 0.6
		KEY_F3: level = 1.0


func bind_environment(env: Environment) -> void:
	_env = env
	_apply_env()


func _apply_env() -> void:
	if _env == null:
		return
	var m: float = 1.0 - level   # how "modern" we still are
	# Modern layer: fades out as the dial goes up. (Ignored by renderers lacking the feature.)
	_env.ssao_enabled = m > 0.25
	_env.ssao_intensity = 2.5 * m
	_env.ssil_enabled = m > 0.6
	_env.glow_enabled = m > 0.15
	_env.glow_intensity = 0.9 * m
	_env.glow_bloom = 0.1 * m
	_env.volumetric_fog_enabled = m > 0.4
	_env.volumetric_fog_density = 0.025 * m
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC if m > 0.4 else Environment.TONE_MAPPER_LINEAR
	# PS1 layer: short, thick fog hides the draw distance (and the level's size).
	_env.fog_enabled = true
	_env.fog_light_color = Color(0.03, 0.05, 0.05).lerp(Color(0.05, 0.07, 0.06), level)
	_env.fog_density = lerpf(0.006, 0.05, level)
	_env.ambient_light_energy = lerpf(0.16, 0.3, level)


func shadows_wanted() -> bool:
	return level < 0.65


## Swap every opaque StandardMaterial3D under `root` for the retro-blendable shader.
## Transparent materials (glass, triggers) stay as they are.
## `snap_strength` and `snap_grid` tune the PS1 vertex wobble per call: the static level uses
## a gentle one (large polygons crack at T-junctions if snapped hard), objects use the full one.
func retrofy(root: Node, snap_strength: float = 1.0, snap_grid: Vector2 = Vector2(200, 150), tint: Color = Color.WHITE) -> void:
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var src: Material = mi.get_active_material(s)
			var conv: Material = _convert(src, snap_strength, snap_grid, tint)
			if conv != src:
				mi.set_surface_override_material(s, conv)


func _convert(src: Material, snap_strength: float, snap_grid: Vector2, tint: Color) -> Material:
	var std := src as StandardMaterial3D
	if std == null:
		return src
	if std.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or std.albedo_color.a < 0.99:
		return src
	var key: String = "%d_%.2f_%d_%s" % [std.get_instance_id(), snap_strength, int(snap_grid.x), tint.to_html()]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var sm := ShaderMaterial.new()
	sm.shader = _shader_for(std.cull_mode == BaseMaterial3D.CULL_DISABLED)
	sm.set_shader_parameter("snap_strength", snap_strength)
	sm.set_shader_parameter("snap_grid", snap_grid)
	sm.set_shader_parameter("albedo_color", std.albedo_color * tint)
	sm.set_shader_parameter("use_vcol", std.vertex_color_use_as_albedo)
	if std.albedo_texture != null:
		sm.set_shader_parameter("use_tex", true)
		sm.set_shader_parameter("albedo_tex", std.albedo_texture)
	sm.set_shader_parameter("metallic_val", std.metallic)
	sm.set_shader_parameter("roughness_val", std.roughness)
	if std.emission_enabled:
		sm.set_shader_parameter("emission_color", std.emission)
		sm.set_shader_parameter("emission_energy", std.emission_energy_multiplier)
	_mat_cache[key] = sm
	return sm


func _shader_for(double_sided: bool) -> Shader:
	if not double_sided:
		return SURFACE_SHADER
	if _shader_double == null:
		_shader_double = Shader.new()
		_shader_double.code = SURFACE_SHADER.code.replace("cull_back", "cull_disabled")
	return _shader_double
