class_name Player
extends CharacterBody3D
## The regular guy. First- or third-person (V), weapons 1-3, flashlight (F), interact (E).
## Layers: world = 1, player = 2, enemies = 4.

signal damaged(amount: float)
signal died
signal message(text: String)

const CHAR_PATH: String = "res://assets/chars/blocky_worker_7_wren-quadsworth.glb"
const WALK_SPEED: float = 4.0
const SPRINT_SPEED: float = 6.8
const GRAVITY: float = 16.0
const JUMP_SPEED: float = 5.0
const STEP_HEIGHT: float = 0.6
const EYE_HEIGHT: float = 1.55
const TPP_DISTANCE: float = 2.7

const WEAPONS: Array[Dictionary] = [
	{"id": "pistol", "name": "Nail Pistol", "glb": "res://assets/guns/BadGun_pistol_scrap_3.glb",
		"mag": 12, "ammo": "9mm", "damage": 24.0, "pellets": 1, "spread": 0.5, "rate": 0.26,
		"auto": false, "reload": 1.1, "sfx": "shot_pistol", "kick": 0.05, "vm": Vector3(0.2, -0.2, -0.45)},
	{"id": "shotgun", "name": "Pipe Shotgun", "glb": "res://assets/guns/BadGun_shotgun_scrap_5.glb",
		"mag": 2, "ammo": "shell", "damage": 10.0, "pellets": 9, "spread": 4.5, "rate": 0.8,
		"auto": false, "reload": 1.6, "sfx": "shot_shotgun", "kick": 0.12, "vm": Vector3(0.22, -0.24, -0.5)},
	{"id": "smg", "name": "Stamped SMG", "glb": "res://assets/guns/BadGun_smg_modern_2.glb",
		"mag": 30, "ammo": "9mm", "damage": 11.0, "pellets": 1, "spread": 1.8, "rate": 0.085,
		"auto": true, "reload": 1.9, "sfx": "shot_smg", "kick": 0.03, "vm": Vector3(0.2, -0.22, -0.5)},
]

var health: float = 100.0
var armor: float = 0.0
var dead: bool = false
var god: bool = false          # --god: take no damage (screenshots, exploring)
var fpp: bool = true
var keys: Array[String] = []
var owned: Array[bool] = [true, false, false]
var mags: Array[int] = [12, 0, 0]
var reserve: Dictionary = {"9mm": 36, "shell": 0}
var current: int = 0
var prompt_text: String = ""

var head: Node3D
var arm: SpringArm3D
var cam: Camera3D
var flashlight: SpotLight3D
var model: Node3D
var _model_anim: AnimationPlayer
var _vm_root: Node3D          # first-person gun, child of the camera
var _vm_gun: Node3D
var _vm_anim: AnimationPlayer
var _tp_gun: Node3D           # third-person gun, in the hand socket
var _tp_anim: AnimationPlayer
var _hand: Node3D
var _flash: OmniLight3D
var _cooldown: float = 0.0
var _reload_left: float = 0.0
var _kick: float = 0.0
var _noise_timer: float = 0.0
var _pitch: float = 0.0
var _stepped_frame: bool = false
const SENS: float = 0.0022


func _ready() -> void:
	add_to_group("player")
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.65
	floor_max_angle = deg_to_rad(47.0)
	_setup_input()
	_build()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_equip(0)
	_set_view(true, true)


func _build() -> void:
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.34
	cap.height = 1.75
	cs.shape = cap
	cs.position.y = 0.875
	add_child(cs)

	model = (load(CHAR_PATH) as PackedScene).instantiate()
	model.rotation.y = PI
	add_child(model)
	Retro.retrofy(model)
	_model_anim = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _model_anim:
		for a in ["Idle", "Walk", "Run"]:
			if _model_anim.has_animation(a):
				_model_anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	_hand = model.find_child("Socket_RightHand", true, false) as Node3D

	head = Node3D.new()
	head.position.y = EYE_HEIGHT
	add_child(head)
	arm = SpringArm3D.new()
	arm.collision_mask = 1
	arm.margin = 0.25
	arm.spring_length = 0.0
	head.add_child(arm)
	cam = Camera3D.new()
	cam.near = 0.04
	cam.far = 120.0
	cam.fov = 78.0
	arm.add_child(cam)
	cam.make_current()

	flashlight = SpotLight3D.new()
	flashlight.spot_range = 22.0
	flashlight.spot_angle = 32.0
	flashlight.spot_attenuation = 0.8
	flashlight.light_energy = 2.0
	flashlight.light_color = Color(1.0, 0.95, 0.82)
	flashlight.shadow_enabled = true
	flashlight.position = Vector3(0.12, -0.08, 0.0)
	head.add_child(flashlight)

	_vm_root = Node3D.new()
	cam.add_child(_vm_root)
	_flash = OmniLight3D.new()
	_flash.light_color = Color(1.0, 0.75, 0.4)
	_flash.omni_range = 7.0
	_flash.light_energy = 0.0
	head.add_child(_flash)


func _setup_input() -> void:
	var map: Dictionary = {
		"move_forward": KEY_W, "move_back": KEY_S, "move_left": KEY_A, "move_right": KEY_D,
		"jump": KEY_SPACE, "sprint": KEY_SHIFT, "interact": KEY_E, "reload": KEY_R,
		"flashlight": KEY_F, "toggle_view": KEY_V,
		"weapon_1": KEY_1, "weapon_2": KEY_2, "weapon_3": KEY_3,
	}
	for action: String in map:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var ev := InputEventKey.new()
			ev.physical_keycode = map[action]
			InputMap.action_add_event(action, ev)
	if not InputMap.has_action("fire"):
		InputMap.add_action("fire")
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("fire", mb)


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if dead:
		return
	var mm := event as InputEventMouseMotion
	if mm and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-mm.relative.x * SENS)
		_pitch = clampf(_pitch - mm.relative.y * SENS, deg_to_rad(-85.0), deg_to_rad(85.0))
		head.rotation.x = _pitch
		return
	var mb := event as InputEventMouseButton
	if mb and mb.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cycle(-1)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cycle(1)
		return
	if event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if event.is_action_pressed("toggle_view"):
		_set_view(not fpp, false)
	elif event.is_action_pressed("flashlight"):
		flashlight.visible = not flashlight.visible
		Sfx.play("click")
	elif event.is_action_pressed("reload"):
		_start_reload()
	elif event.is_action_pressed("interact"):
		_interact()
	elif event.is_action_pressed("weapon_1"):
		_equip(0)
	elif event.is_action_pressed("weapon_2"):
		_equip(1)
	elif event.is_action_pressed("weapon_3"):
		_equip(2)


func _cycle(dir: int) -> void:
	var n: int = WEAPONS.size()
	var i: int = current
	for _k in n:
		i = (i + dir + n) % n
		if owned[i]:
			_equip(i)
			return


# ---------------------------------------------------------------- view

func _set_view(first_person: bool, instant: bool) -> void:
	fpp = first_person
	model.visible = not fpp
	_vm_root.visible = fpp
	if _tp_gun:
		_tp_gun.visible = not fpp
	var target_len: float = 0.0 if fpp else TPP_DISTANCE
	var target_x: float = 0.0 if fpp else 0.5
	if instant:
		arm.spring_length = target_len
		arm.position.x = target_x
	else:
		var tw: Tween = create_tween().set_parallel(true)
		tw.tween_property(arm, "spring_length", target_len, 0.25)
		tw.tween_property(arm, "position:x", target_x, 0.25)


# ---------------------------------------------------------------- weapons

func _equip(i: int) -> void:
	if i < 0 or i >= WEAPONS.size() or not owned[i]:
		return
	current = i
	_reload_left = 0.0
	var w: Dictionary = WEAPONS[i]
	if _vm_gun:
		_vm_gun.queue_free()
	if _tp_gun:
		_tp_gun.queue_free()
	var scene: PackedScene = load(w["glb"])
	_vm_gun = scene.instantiate()
	_vm_gun.rotation.y = PI
	_vm_root.add_child(_vm_gun)
	_vm_root.position = w["vm"]
	_vm_anim = _vm_gun.find_child("AnimationPlayer", true, false) as AnimationPlayer
	Retro.retrofy(_vm_gun)
	_tp_gun = scene.instantiate()
	if _hand:
		_hand.add_child(_tp_gun)
	else:
		model.add_child(_tp_gun)
	_tp_anim = _tp_gun.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_tp_gun.visible = not fpp
	Retro.retrofy(_tp_gun)
	if mags[i] == 0 and int(reserve[w["ammo"]]) > 0:
		_start_reload()


func _muzzle_light() -> void:
	_flash.light_energy = 3.0
	_flash.position = Vector3(0, -0.05, -0.8)
	var tw: Tween = create_tween()
	tw.tween_property(_flash, "light_energy", 0.0, 0.07)


func _try_fire() -> void:
	if _reload_left > 0.0 or _cooldown > 0.0:
		return
	var w: Dictionary = WEAPONS[current]
	if mags[current] <= 0:
		Sfx.play("click")
		_cooldown = 0.25
		_start_reload()
		return
	mags[current] -= 1
	_cooldown = float(w["rate"])
	_kick = float(w["kick"])
	_noise_timer = 1.2
	Sfx.play(String(w["sfx"]))
	_muzzle_light()
	for a: AnimationPlayer in [_vm_anim, _tp_anim]:
		if a and a.has_animation("Fire"):
			a.play("Fire")
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var origin: Vector3 = cam.global_position
	var forward: Vector3 = -cam.global_transform.basis.z
	for _p in int(w["pellets"]):
		var spread: float = deg_to_rad(float(w["spread"]))
		var d: Vector3 = (forward + cam.global_transform.basis.x * randf_range(-spread, spread)
			+ cam.global_transform.basis.y * randf_range(-spread, spread)).normalized()
		var q := PhysicsRayQueryParameters3D.create(origin, origin + d * 70.0, 1 | 4, [get_rid()])
		var hit: Dictionary = space.intersect_ray(q)
		if hit.is_empty():
			continue
		var col: Object = hit["collider"]
		var pos: Vector3 = hit["position"]
		if col is Node and (col as Node).has_method("take_damage"):
			(col as Node).call("take_damage", float(w["damage"]), global_position)
			_impact(pos, Color(0.8, 0.05, 0.05))
		else:
			_impact(pos, Color(1.0, 0.85, 0.4))


func _impact(pos: Vector3, color: Color) -> void:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3.ONE * 0.09
	m.mesh = b
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.material_override = mat
	get_tree().current_scene.add_child(m)
	m.global_position = pos
	var tw: Tween = m.create_tween()
	tw.tween_property(m, "scale", Vector3.ZERO, 0.3)
	tw.tween_callback(m.queue_free)


func _start_reload() -> void:
	var w: Dictionary = WEAPONS[current]
	var need: int = int(w["mag"]) - mags[current]
	if _reload_left > 0.0 or need <= 0 or int(reserve[w["ammo"]]) <= 0:
		return
	_reload_left = float(w["reload"])
	Sfx.play("reload")
	for a: AnimationPlayer in [_vm_anim, _tp_anim]:
		if a and a.has_animation("Reload"):
			a.play("Reload")


func _finish_reload() -> void:
	var w: Dictionary = WEAPONS[current]
	var need: int = int(w["mag"]) - mags[current]
	var take: int = mini(need, int(reserve[w["ammo"]]))
	mags[current] += take
	reserve[w["ammo"]] = int(reserve[w["ammo"]]) - take
	Sfx.play("reload", 1.3)


# ---------------------------------------------------------------- interaction / pickups

func _interact() -> void:
	var c: Node = _look_target()
	if c and c.get_parent().has_method("interact"):
		c.get_parent().call("interact", self)


func _look_target() -> Node:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var from: Vector3 = head.global_position
	var to: Vector3 = from - head.global_transform.basis.z * 2.6
	var q := PhysicsRayQueryParameters3D.create(from, to, 1, [get_rid()])
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		return null
	var col: Node = hit["collider"] as Node
	if col and col.is_in_group("interactable"):
		return col
	return null


func has_key(color: String) -> bool:
	return color in keys


func say(text: String) -> void:
	message.emit(text)


func collect(kind: String, props: Dictionary) -> bool:
	match kind:
		"health":
			if health >= 100.0:
				return false
			health = minf(100.0, health + 25.0)
			say("+25 health")
		"megahealth":
			health = minf(200.0, health + 100.0)
			say("Megahealth!")
		"armor":
			if armor >= 100.0:
				return false
			armor = minf(100.0, armor + 30.0)
			say("+30 armor")
		"ammo":
			reserve["9mm"] = int(reserve["9mm"]) + 18
			if owned[1]:
				reserve["shell"] = int(reserve["shell"]) + 4
			say("Ammo")
		"key":
			var c: String = str(props.get("color", "red"))
			keys.append(c)
			say("Picked up the %s keycard" % c)
		"weapon":
			var idx: int = 1 if str(props.get("type", "")) == "shotgun" else 2
			if not owned[idx]:
				owned[idx] = true
				mags[idx] = int(WEAPONS[idx]["mag"])
				reserve[WEAPONS[idx]["ammo"]] = int(reserve[WEAPONS[idx]["ammo"]]) + int(WEAPONS[idx]["mag"]) * 2
				say("Found the %s (press %d)" % [WEAPONS[idx]["name"], idx + 1])
				_equip(idx)
			else:
				reserve[WEAPONS[idx]["ammo"]] = int(reserve[WEAPONS[idx]["ammo"]]) + 8
		_:
			return false
	return true


func take_damage(amount: float, _from: Vector3 = Vector3.ZERO) -> void:
	if dead or god:
		return
	if armor > 0.0:
		var soak: float = minf(armor, amount * 0.5)
		armor -= soak
		amount -= soak
	health -= amount
	Sfx.play("hurt")
	damaged.emit(amount)
	if health <= 0.0:
		health = 0.0
		dead = true
		died.emit()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## How far a zombie can "hear" us right now.
func noise_radius() -> float:
	var r: float = 3.0
	var flat: float = Vector2(velocity.x, velocity.z).length()
	if flat > WALK_SPEED + 0.5:
		r = 13.0
	elif flat > 0.5:
		r = 7.0
	if _noise_timer > 0.0:
		r = maxf(r, 26.0)
	return r


# ---------------------------------------------------------------- frame update

func _process(delta: float) -> void:
	if dead:
		return
	if _kick > 0.0:
		_kick = maxf(0.0, _kick - delta * 0.6)
	var w: Dictionary = WEAPONS[current]
	_vm_root.position = (w["vm"] as Vector3) + Vector3(0, 0.015, _kick * 2.5)
	_vm_root.rotation.x = _kick * 2.0
	_noise_timer = maxf(0.0, _noise_timer - delta)
	var t: Node = _look_target()
	prompt_text = ""
	if t and t.get_parent().has_method("prompt"):
		prompt_text = str(t.get_parent().call("prompt", self))


func _physics_process(delta: float) -> void:
	if dead:
		return
	_cooldown = maxf(0.0, _cooldown - delta)
	if _reload_left > 0.0:
		_reload_left -= delta
		if _reload_left <= 0.0:
			_finish_reload()
	var w: Dictionary = WEAPONS[current]
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var want_fire: bool = Input.is_action_pressed("fire") if bool(w["auto"]) else Input.is_action_just_pressed("fire")
		if want_fire:
			_try_fire()

	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var speed: float = SPRINT_SPEED if Input.is_action_pressed("sprint") else WALK_SPEED
	var wish: Vector3 = (global_transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)) * speed
	var accel: float = 38.0 if is_on_floor() else 8.0
	velocity.x = move_toward(velocity.x, wish.x, accel * delta)
	velocity.z = move_toward(velocity.z, wish.z, accel * delta)
	if is_on_floor():
		if Input.is_action_just_pressed("jump"):
			velocity.y = JUMP_SPEED
	else:
		velocity.y -= GRAVITY * delta
	StepHelper.try_step(self, Vector3(velocity.x, 0.0, velocity.z) * delta, STEP_HEIGHT)
	move_and_slide()
	_animate(input_dir, speed)


func _animate(input_dir: Vector2, speed: float) -> void:
	if _model_anim == null:
		return
	var want: String = "Idle"
	if not is_on_floor():
		want = "Jump" if _model_anim.has_animation("Jump") else "Idle"
	elif input_dir.length() > 0.1:
		want = "Run" if speed > WALK_SPEED + 0.5 else "Walk"
	if _model_anim.current_animation != want:
		_model_anim.play(want, 0.15)
