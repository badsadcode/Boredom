class_name Zombie
extends CharacterBody3D
## A shambling brick person. Hears you (running is loud, shooting is louder), sees you,
## follows the baked navmesh, and heads straight for you once there is a clear line.

signal killed(z: Zombie)

enum State { IDLE, CHASE, DEAD }

const MODELS: Array[String] = [
	"res://assets/chars/blocky_zombie_9_kit-mesh.glb",
	"res://assets/chars/stocky_zombie_10_pip-skinner.glb",
]
const GRAVITY: float = 16.0
const STEP_HEIGHT: float = 0.6

var tier: int = 1
var health: float = 60.0
var speed: float = 2.2
var damage: float = 10.0
var state: State = State.IDLE
var _model: Node3D
var _anim: AnimationPlayer
var _nav: NavigationAgent3D
var _player: Player
var _attack_cd: float = 0.0
var _repath: float = 0.0
var _groan: float = randf_range(2.0, 6.0)
var _model_index: int = 0
var _pose: PoseLayer
var _punch_t: float = 0.0
var _knock: Vector3 = Vector3.ZERO
var _stagger: float = 0.0
var _last_hit_from: Vector3 = Vector3.ZERO


func setup(t: int, model_index: int) -> void:
	tier = clampi(t, 1, 4)
	_model_index = model_index
	health = 30.0 + tier * 15.0     # tier 1..4 = 45..90 hp
	speed = 1.6 + tier * 0.35       # a brisk walk; only tier 3+ breaks into a run
	damage = 5.0 + tier * 3.0       # 8..17 per hit


func _ready() -> void:
	add_to_group("enemy")
	collision_layer = 4
	collision_mask = 1
	floor_snap_length = 0.65
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.36
	cap.height = 1.7
	cs.shape = cap
	cs.position.y = 0.85
	add_child(cs)

	_model = (load(MODELS[_model_index % MODELS.size()]) as PackedScene).instantiate()
	_model.rotation.y = PI
	add_child(_model)
	Retro.retrofy(_model)
	_anim = _model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _anim:
		for a in ["Idle", "Walk", "Run"]:
			if _anim.has_animation(a):
				_anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
		_anim.play("Idle")
	var skel: Skeleton3D = _model.find_child("Skeleton3D", true, false) as Skeleton3D
	if skel:
		_pose = PoseLayer.new()
		_pose.phase = randf() * TAU
		_pose.head_roll = randf_range(-0.28, 0.28)
		skel.add_child(_pose)

	_nav = NavigationAgent3D.new()
	_nav.path_desired_distance = 0.6
	_nav.target_desired_distance = 1.0
	_nav.radius = 0.4
	_nav.height = 1.8
	add_child(_nav)


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Player
	_attack_cd = maxf(0.0, _attack_cd - delta)
	_punch_t = maxf(0.0, _punch_t - delta)
	_stagger = maxf(0.0, _stagger - delta)
	_knock = _knock.move_toward(Vector3.ZERO, 14.0 * delta)
	if _pose:
		var chasing: bool = state == State.CHASE and _punch_t <= 0.0
		_pose.reach = move_toward(_pose.reach, 1.0 if chasing else 0.0, delta * 4.0)
		_pose.slump = move_toward(_pose.slump, 1.0 if state == State.IDLE else 0.0, delta * 3.0)
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0

	if _player == null or _player.dead:
		_play("Idle")
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return

	var to_p: Vector3 = _player.global_position - global_position
	var flat: Vector3 = Vector3(to_p.x, 0.0, to_p.z)
	var dist: float = flat.length()

	if state == State.IDLE:
		_play("Idle")
		velocity.x = 0.0
		velocity.z = 0.0
		var heard: bool = dist < _player.noise_radius() and dist < 30.0
		if heard or (dist < 15.0 and _line_of_sight()):
			state = State.CHASE
			Sfx.play3d("groan", global_position, 0.85 + randf() * 0.2)
		move_and_slide()
		return

	# CHASE
	_groan -= delta
	if _groan <= 0.0:
		_groan = randf_range(4.0, 9.0)
		Sfx.play3d("groan", global_position, 0.8 + randf() * 0.3)

	if dist < 1.5 and absf(to_p.y) < 1.6:
		velocity.x = 0.0
		velocity.z = 0.0
		_face(flat, delta)
		if _attack_cd <= 0.0:
			_attack_cd = 1.6
			_punch_t = 0.9
			_play("Punch")
			get_tree().create_timer(0.5).timeout.connect(_land_hit)
		move_and_slide()
		return

	var dir: Vector3 = Vector3.ZERO
	var direct: bool = dist < 14.0 and _line_of_sight()
	if direct:
		dir = flat.normalized()
	else:
		_repath -= delta
		if _repath <= 0.0:
			_repath = 0.35
			_nav.target_position = _player.global_position
		var next: Vector3 = _nav.get_next_path_position()
		var nd: Vector3 = next - global_position
		nd.y = 0.0
		dir = nd.normalized() if nd.length() > 0.05 else flat.normalized()
	var slow: float = 0.25 if _stagger > 0.0 else 1.0
	velocity.x = dir.x * speed * slow + _knock.x
	velocity.z = dir.z * speed * slow + _knock.z
	_face(dir, delta)
	_play("Run" if speed > 2.5 else "Walk")
	StepHelper.try_step(self, Vector3(velocity.x, 0.0, velocity.z) * delta, STEP_HEIGHT)
	move_and_slide()


func _land_hit() -> void:
	if state == State.DEAD or _player == null or _player.dead:
		return
	var d: Vector3 = _player.global_position - global_position
	if Vector2(d.x, d.z).length() < 1.9 and absf(d.y) < 1.6:
		_player.take_damage(damage, global_position)


func _face(dir: Vector3, delta: float) -> void:
	if dir.length() < 0.01:
		return
	var target: float = atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, target, clampf(delta * 7.0, 0.0, 1.0))


func _play(anim: String) -> void:
	if _anim and _anim.has_animation(anim) and _anim.current_animation != anim:
		_anim.play(anim, 0.2)


func _line_of_sight() -> bool:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var from: Vector3 = global_position + Vector3(0, 1.5, 0)
	var to: Vector3 = _player.global_position + Vector3(0, 1.4, 0)
	var q := PhysicsRayQueryParameters3D.create(from, to, 1, [get_rid()])
	return space.intersect_ray(q).is_empty()


func take_damage(amount: float, _from: Vector3 = Vector3.ZERO) -> void:
	if state == State.DEAD:
		return
	health -= amount
	_last_hit_from = _from
	Sfx.play3d("hit", global_position)
	if _pose:
		_pose.flinch = 1.0
	_stagger = 0.3
	if state == State.IDLE:
		state = State.CHASE
	if health <= 0.0:
		_die()


func knock_back(impulse: Vector3) -> void:
	_knock = impulse
	_stagger = 0.4


func _die() -> void:
	state = State.DEAD
	collision_layer = 0
	killed.emit(self)
	Sfx.play3d("groan", global_position, 0.6)
	# shot from the front: topples backwards; from behind (or unknown): collapses forward
	var fwd: Vector3 = -global_transform.basis.z
	var to_attacker: Vector3 = _last_hit_from - global_position
	to_attacker.y = 0.0
	var from_front: bool = to_attacker.length() < 0.01 or fwd.dot(to_attacker.normalized()) > 0.0
	if _anim:
		_anim.play("RestPose", 0.1)
	if _pose:
		_pose.die(0 if from_front else 1)
	var land: float = 0.7 if from_front else 0.92
	get_tree().create_timer(land).timeout.connect(func() -> void:
		Sfx.play3d("hit", global_position, 0.45))
