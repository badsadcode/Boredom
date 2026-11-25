extends Node3D
## Builds the whole slice in code: environment, level, player, HUD, retro post pass.
##
## Command line (after `--`), handy for screenshots and CI:
##   --retro=0.6        start dial
##   --shot=out.png     save a screenshot after --frames and quit
##   --frames=40
##   --tpp              start in third person
##   --god              invulnerable
##   --at=x,y,z,yawdeg,pitchdeg   teleport the player
##   --level=res://assets/level/facility.glb

const DEFAULT_LEVEL: String = "res://assets/level/facility.glb"

var level: FacilityLevel
var player: Player
var hud: Hud
var _shot_path: String = ""
var _frames_left: int = 0
var _won: bool = false
var _fails: int = 0


func _ready() -> void:
	var opts: Dictionary = _parse_args()
	Retro.level = float(opts.get("retro", Retro.level))

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.03, 0.04)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.5, 0.58)
	env.ambient_light_energy = 0.5
	env.fog_sky_affect = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	Retro.bind_environment(env)

	level = FacilityLevel.new()
	add_child(level)
	level.build(str(opts.get("level", DEFAULT_LEVEL)))
	level.exit_reached.connect(_on_exit)

	player = Player.new()
	add_child(player)
	player.global_transform = level.player_start
	player.god = opts.has("god")
	if opts.has("at"):
		var p: PackedFloat64Array = opts["at"]
		player.global_position = Vector3(p[0], p[1], p[2])
		player.rotation.y = deg_to_rad(p[3])
		player._pitch = deg_to_rad(p[4])
		player.head.rotation.x = player._pitch
	if opts.has("tpp"):
		player._set_view(false, true)

	hud = Hud.new()
	add_child(hud)
	hud.setup(player)
	player.died.connect(_on_died)

	var post := CanvasLayer.new()
	post.layer = 10
	add_child(post)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/retro_post.gdshader")
	rect.material = mat
	post.add_child(rect)

	if opts.has("selftest"):
		_selftest.call_deferred()
	if opts.has("shot"):
		_shot_path = str(opts["shot"])
		_frames_left = int(opts.get("frames", 40))


func _parse_args() -> Dictionary:
	var out: Dictionary = {}
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			continue
		var kv: PackedStringArray = a.substr(2).split("=", true, 1)
		var v: String = kv[1] if kv.size() > 1 else ""
		match kv[0]:
			"at": out["at"] = PackedFloat64Array(Array(v.split(",")).map(func(s: String) -> float: return s.to_float()))
			_: out[kv[0]] = v if kv.size() > 1 else true
	return out


func _process(_delta: float) -> void:
	if _shot_path != "":
		_frames_left -= 1
		if _frames_left <= 0:
			var img: Image = get_viewport().get_texture().get_image()
			img.save_png(_shot_path)
			print("saved ", _shot_path, " ", img.get_size())
			get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k and k.pressed and not k.echo and k.keycode == KEY_R and (player.dead or _won):
		get_tree().reload_current_scene()


func _on_died() -> void:
	pass


func _on_exit() -> void:
	if _won:
		return
	_won = true
	hud.banner("SECTOR CLEARED\npress R to go again", Color(0.4, 1.0, 0.5))
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# ------------------------------------------------------------------ headless self-test
# godot --headless --path . -- --selftest
func _selftest() -> void:
	_fails = 0
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		print("FAIL  selftest watchdog expired")
		get_tree().quit(2))
	var check := func(label: String, ok: bool, detail: String = "") -> void:
		print(("PASS  " if ok else "FAIL  "), label, "  ", detail)
		if not ok:
			_fails += 1
	for _i in 60:
		await get_tree().physics_frame
	check.call("player settles on floor", player.is_on_floor(), str(player.global_position))

	var zs: Array[Node] = get_tree().get_nodes_in_group("enemy")
	check.call("enemies spawned", zs.size() > 10, "%d zombies" % zs.size())
	var doors: Array[Node] = level.world_root.find_children("door_*", "MeshInstance3D", true, false)
	check.call("locked doors built", doors.size() >= 2, "%d doors" % doors.size())
	check.call("player start found", level.player_start.origin != Vector3.ZERO, str(level.player_start.origin))

	# navmesh: can a zombie path to the player start?
	var map: RID = level.nav_region.get_navigation_map()
	await get_tree().physics_frame
	var zombie: Zombie = zs[0] as Zombie
	var path: PackedVector3Array = NavigationServer3D.map_get_path(map, zombie.global_position, player.global_position, true)
	var reach: float = path[path.size() - 1].distance_to(player.global_position) if path.size() > 0 else 999.0
	check.call("navmesh baked", NavigationServer3D.map_get_regions(map).size() > 0)
	print("      path points=", path.size(), " ends ", snappedf(reach, 0.1), " m from target (zombie 0 to start)")

	# chase + shoot test: take a zombie, find a spot with a clear line on its own floor
	var best: Zombie = zs[zs.size() / 2] as Zombie
	var space: PhysicsDirectSpaceState3D = best.get_world_3d().direct_space_state
	var spot: Vector3 = Vector3.INF
	for ang in 8:
		var dir: Vector3 = Vector3(cos(ang * PI / 4.0), 0, sin(ang * PI / 4.0))
		for dist in [7.0, 5.5, 4.0]:
			var pos: Vector3 = best.global_position + dir * dist
			var los: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(
				best.global_position + Vector3(0, 1.4, 0), pos + Vector3(0, 1.4, 0), 1))
			var floor_hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(
				pos + Vector3(0, 0.6, 0), pos + Vector3(0, -1.2, 0), 1))
			if los.is_empty() and not floor_hit.is_empty() and absf((floor_hit["position"] as Vector3).y - best.global_position.y) < 0.4:
				spot = floor_hit["position"]
				break
		if spot != Vector3.INF:
			break
	check.call("found open spot near a zombie", spot != Vector3.INF, str(spot))
	if spot == Vector3.INF:
		get_tree().quit(1)
		return
	player.global_position = spot + Vector3(0, 0.05, 0)
	var flat: Vector3 = best.global_position - player.global_position
	player.rotation.y = atan2(-flat.x, -flat.z)
	await get_tree().physics_frame
	await get_tree().physics_frame
	player.head.rotation.x = 0.0
	var aim: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(
		player.cam.global_position, player.cam.global_position - player.cam.global_transform.basis.z * 70.0, 1 | 4, [player.get_rid()]))
	var target: Zombie = aim.get("collider") as Zombie
	check.call("crosshair is on a zombie", target != null, str(aim.get("collider")))
	var start_hp: float = target.health if target != null else 0.0
	player._try_fire()
	await get_tree().physics_frame
	check.call("pistol shot damages the zombie it hits", target != null and target.health < start_hp,
		"%.0f -> %.0f hp" % [start_hp, target.health if target != null else -1.0])
	check.call("ammo used", player.mags[0] == 11, "mag %d" % player.mags[0])

	var hp0: float = player.health
	var t: float = 0.0
	var closest: float = 99.0
	while t < 14.0 and player.health >= hp0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		closest = minf(closest, best.global_position.distance_to(player.global_position))
	check.call("zombie woke up and chased", best.state == Zombie.State.CHASE, "state=%d closest=%.1f m" % [best.state, closest])
	check.call("zombie reached and hurt the player", player.health < hp0, "hp %.0f after %.1fs" % [player.health, t])

	# doors: locked without the key, opens with it
	var door: Node = doors[0]
	var key: String = door.key_color
	door.interact(player)
	check.call("locked door stays shut without key", not door.is_open, "needs %s" % key)
	player.keys.append(key)
	door.interact(player)
	check.call("door opens with key", door.is_open)

	# pickups
	player.health = 50.0
	check.call("health pickup works", player.collect("health", {}) and player.health == 75.0)
	check.call("weapon pickup grants shotgun", player.collect("weapon", {"type": "shotgun"}) and player.owned[1] and player.current == 1)

	# pickups through the real trigger area
	var ammo: Pickup = null
	for n in level.get_node("Entities").get_children():
		if n is Pickup and (n as Pickup).kind == "ammo":
			ammo = n as Pickup
			break
	check.call("an ammo pickup exists", ammo != null)
	if ammo != null:
		var before: int = int(player.reserve["9mm"])
		player.global_position = ammo.global_position + Vector3(0, 0.05, 0)
		for _i in 6:
			await get_tree().physics_frame
		check.call("walking onto ammo collects it", int(player.reserve["9mm"]) > before, "%d -> %d" % [before, int(player.reserve["9mm"])])

	# the exit
	var exit_node: Node3D = level.world_root.find_child("exit_0", true, false) as Node3D
	check.call("exit trigger exists", exit_node != null)
	if exit_node != null:
		player.health = 100.0
		player.global_position = exit_node.global_position - Vector3(0, 0.8, 0)
		for _i in 8:
			await get_tree().physics_frame
		check.call("reaching the exit wins", _won)

	print("---- selftest: ", "ALL PASSED" if _fails == 0 else "%d FAILED" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)
