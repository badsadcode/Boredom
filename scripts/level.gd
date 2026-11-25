class_name FacilityLevel
extends Node3D
## Loads a BadLevel GLB and turns it into a playable level:
##  collision for the geometry, a baked navmesh, and every entity node
##  (lights, enemies, pickups, keys, locked doors, secret door, exit) becomes a real game object.

signal exit_reached

const PICKUP_KINDS: Array[String] = ["health", "ammo", "armor", "megahealth", "key", "weapon"]
const SOLID_SKIP_KINDS: Array[String] = ["door", "secret_door", "exit"]

var player_start: Transform3D = Transform3D.IDENTITY
var world_root: Node3D
var nav_region: NavigationRegion3D
var _lights: Array[OmniLight3D] = []
var _entity_root: Node3D


func build(path: String) -> void:
	var packed: PackedScene = load(path)
	world_root = packed.instantiate()
	nav_region = NavigationRegion3D.new()
	add_child(nav_region)
	nav_region.add_child(world_root)
	_entity_root = Node3D.new()
	_entity_root.name = "Entities"
	add_child(_entity_root)

	_retrofy_world(path.get_basename() + ".json")
	_style_sky()
	_add_collision()
	_spawn_entities()
	_bake_nav()
	Retro.changed.connect(_on_retro_changed)
	_on_retro_changed(Retro.level)


# Facility sectors get their own colour identity (BadLevel tags every room with one).
const SECTOR_TINT: Dictionary = {
	"admin": Color(0.86, 0.80, 0.66),      # warm office beige
	"research": Color(0.62, 0.78, 0.82),   # cold lab teal
	"reactor": Color(0.82, 0.56, 0.40),    # hot rust
	"storage": Color(0.70, 0.66, 0.58),
	"maintenance": Color(0.58, 0.68, 0.52),
}
const NEUTRAL_TINT: Color = Color(0.68, 0.70, 0.68)
const WORLD_SNAP_STRENGTH: float = 0.35
const WORLD_SNAP_GRID: Vector2 = Vector2(520, 390)


func _retrofy_world(json_path: String) -> void:
	var sector_of: Dictionary = {}   # room id -> sector name
	if FileAccess.file_exists(json_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(json_path))
		if parsed is Dictionary:
			for r: Variant in (parsed as Dictionary).get("rooms", []):
				var rd: Dictionary = r as Dictionary
				sector_of[int(rd.get("id", -1))] = str((rd.get("meta", {}) as Dictionary).get("sector", ""))
	# rooms first, each with its sector tint; everything left (corridors, doors...) gets neutral
	for n in world_root.find_children("room_*", "Node3D", true, false):
		var area: String = str(_extras(n).get("area", ""))
		if not area.begins_with("room:") or n is MeshInstance3D:
			continue
		var sector: String = str(sector_of.get(int(area.get_slice(":", 1)), ""))
		var tint: Color = SECTOR_TINT.get(sector, NEUTRAL_TINT)
		Retro.retrofy(n, WORLD_SNAP_STRENGTH, WORLD_SNAP_GRID, tint, true)
	Retro.retrofy(world_root, WORLD_SNAP_STRENGTH, WORLD_SNAP_GRID, NEUTRAL_TINT, true)


func _extras(n: Node) -> Dictionary:
	if n.has_meta("extras"):
		var e: Variant = n.get_meta("extras")
		if e is Dictionary:
			return e
	return {}


func _mat_names(mi: MeshInstance3D) -> Array[String]:
	var out: Array[String] = []
	if mi.mesh:
		for i in mi.mesh.get_surface_count():
			var m: Material = mi.mesh.surface_get_material(i)
			out.append(m.resource_name if m else "")
	return out


# The generator's flat blue "sky" becomes an unshaded night sky: it is Oregon, after dark.
func _style_sky() -> void:
	var sky := StandardMaterial3D.new()
	sky.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sky.albedo_color = Color(0.02, 0.04, 0.07)
	for n in world_root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n
		var names: Array[String] = _mat_names(mi)
		for i in names.size():
			if names[i] == "bl_sky":
				mi.set_surface_override_material(i, sky)


func _add_collision() -> void:
	for n in world_root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n
		var kind: String = str(_extras(mi).get("kind", ""))
		if kind in SOLID_SKIP_KINDS:
			continue
		if "bl_trigger" in _mat_names(mi):
			continue
		mi.create_trimesh_collision()


func _spawn_entities() -> void:
	var level_node: Node = world_root.get_child(0)
	for n in level_node.get_children():
		var node3: Node3D = n as Node3D
		if node3 == null:
			continue
		var ex: Dictionary = _extras(node3)
		var kind: String = str(ex.get("kind", ""))
		match kind:
			"light": _spawn_light(node3.position, float(ex.get("intensity", 250.0)))
			"player_start": _set_start(node3.position, float(ex.get("angle", 0.0)))
			"enemy": _spawn_enemy(node3.position, int(ex.get("tier", 1)))
			"door": _make_door(node3 as MeshInstance3D, str(ex.get("key", "")), false)
			"secret_door": _make_door(node3 as MeshInstance3D, "", true)
			"exit": _make_exit(node3 as MeshInstance3D)
			_:
				if kind in PICKUP_KINDS:
					_spawn_pickup(kind, node3.position, ex)


func _set_start(pos: Vector3, angle_deg: float) -> void:
	# Quake angle: 0 = +X, counter-clockwise seen from above.  Godot forward is -Z.
	player_start = Transform3D(Basis(Vector3.UP, deg_to_rad(angle_deg) - PI * 0.5), pos - Vector3(0, 0.85, 0))


func _spawn_light(pos: Vector3, intensity: float) -> void:
	var l := OmniLight3D.new()
	l.position = pos - Vector3(0, 0.4, 0)
	l.light_color = Color(1.0, 0.93, 0.8)
	l.light_energy = clampf(intensity / 400.0, 0.5, 1.4)
	l.omni_range = 11.0
	l.omni_attenuation = 1.3
	l.distance_fade_enabled = true
	l.distance_fade_begin = 28.0
	l.distance_fade_shadow = 14.0
	l.distance_fade_length = 8.0
	_entity_root.add_child(l)
	_lights.append(l)


func _spawn_enemy(pos: Vector3, tier: int) -> void:
	var z := Zombie.new()
	_entity_root.add_child(z)
	z.setup(tier, randi() % 2)
	z.global_position = pos - Vector3(0, 0.6, 0)
	z.killed.connect(_on_enemy_killed)


func _on_enemy_killed(z: Zombie) -> void:
	if randf() < 0.3:
		var kinds: Array[String] = ["ammo", "ammo", "health"]
		_spawn_pickup(kinds[randi() % kinds.size()], z.global_position + Vector3(0, 0.2, 0), {})


func _spawn_pickup(kind: String, pos: Vector3, ex: Dictionary) -> void:
	var p := Pickup.new()
	_entity_root.add_child(p)
	p.setup(kind, ex)
	p.global_position = pos


func _make_door(mi: MeshInstance3D, key: String, secret: bool) -> void:
	if mi == null:
		return
	mi.set_script(load("res://scripts/door.gd"))
	mi.call("setup", key, secret)


func _make_exit(mi: MeshInstance3D) -> void:
	if mi == null:
		return
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = 2
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = mi.mesh.get_aabb().size
	cs.shape = box
	cs.position = mi.mesh.get_aabb().get_center()
	area.add_child(cs)
	mi.add_child(area)
	area.body_entered.connect(func(b: Node3D) -> void:
		if b.is_in_group("player"):
			exit_reached.emit())


func _bake_nav() -> void:
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.4
	nm.agent_height = 1.8
	nm.agent_max_climb = 0.6
	nm.agent_max_slope = 46.0
	nm.cell_size = 0.2
	nm.cell_height = 0.15
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_MESH_INSTANCES
	var map: RID = nav_region.get_navigation_map()
	NavigationServer3D.map_set_cell_size(map, nm.cell_size)
	NavigationServer3D.map_set_cell_height(map, nm.cell_height)
	nav_region.navigation_mesh = nm
	nav_region.bake_navigation_mesh(false)


func _on_retro_changed(_v: float) -> void:
	var want: bool = Retro.shadows_wanted()
	for l in _lights:
		l.shadow_enabled = want
