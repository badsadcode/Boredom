class_name PoseLayer
extends SkeletonModifier3D
## Procedural pose layers on top of BadCharacters' baked clips (Idle, Walk, Run, Jump, Wave, Punch).
## The clips drive legs, balance and one-off actions; this layer adds what the generator doesn't
## ship: a gun-aim pose that follows the camera pitch, a zombie shamble, hit flinches.
##
## Rig facts (docs/RIG.md in BadCharacters): T-pose with identity rest rotations, the character
## looks down +Z, its left side is +X. So "raise an arm forward" is a rotation about Y
## (+90 deg for the right arm, -90 deg for the left), and pitch is a rotation about X.
##
## All weights are 0..1 and are set by gameplay code every frame; 0 leaves the clip untouched.

var aim: float = 0.0          # both arms up, holding a gun
var aim_pitch: float = 0.0    # radians, positive = looking up
var reach: float = 0.0        # zombie arms stretched out in front
var slump: float = 0.0        # head hung, spine hunched (idle zombie)
var flinch: float = 0.0       # hit reaction: rocks the torso back, decays by itself
var head_roll: float = 0.0    # per-zombie creepy head tilt, radians
var phase: float = 0.0        # desync between zombies

## How far the right hand is in front of the hips (metres, model space) after all layers.
## Skeleton3D resets modified poses after each update, so this is captured while they are live.
var hand_forward: float = 0.0
## Head height above the floor in model space: ~1.6 standing, ~0.3 once down (used by tests).
var head_height: float = 1.6

## Death. BadCharacters ships no death clip, so it is built here: the whole body pivots around
## the feet (Root bone) with a gravity-style ease-in, limbs react, and it lands with a small bounce.
##   0 = falls over backwards (shot from the front)      1 = knees give way, then face-plants
var death_kind: int = -1
var death_t: float = -1.0
var death_angle: float = 0.0   # commanded body pitch in radians (tests / debugging)

var _t: float = 0.0
var _idx: Dictionary = {}


func _ready() -> void:
	var sk: Skeleton3D = get_skeleton()
	if sk:
		sk.skeleton_updated.connect(_measure)


func _measure() -> void:
	var sk: Skeleton3D = get_skeleton()
	var h: int = _bone(sk, "RightHand")
	var hips: int = _bone(sk, "Hips")
	if h >= 0 and hips >= 0:
		hand_forward = sk.get_bone_global_pose(h).origin.z - sk.get_bone_global_pose(hips).origin.z
	var head: int = _bone(sk, "Head")
	if head >= 0:
		head_height = sk.get_bone_global_pose(head).origin.y


func _bone(sk: Skeleton3D, bone_name: String) -> int:
	if not _idx.has(bone_name):
		_idx[bone_name] = sk.find_bone(bone_name)
	return _idx[bone_name]


func _blend(sk: Skeleton3D, bone_name: String, target: Quaternion, w: float) -> void:
	if w <= 0.001:
		return
	var i: int = _bone(sk, bone_name)
	if i < 0:
		return
	var cur: Quaternion = sk.get_bone_pose_rotation(i)
	sk.set_bone_pose_rotation(i, cur.slerp(target, clampf(w, 0.0, 1.0)))


func _arms(sk: Skeleton3D, w: float, pitch_down: float, bend: float, wobble: float) -> void:
	# pitch_down > 0 points the arms below the horizon; bend folds the elbows toward the centre line
	var up_r: Quaternion = Quaternion(Vector3.RIGHT, pitch_down) * Quaternion(Vector3.UP, PI * 0.5)
	var up_l: Quaternion = Quaternion(Vector3.RIGHT, pitch_down) * Quaternion(Vector3.UP, -PI * 0.5)
	_blend(sk, "RightUpperArm", up_r, w)
	_blend(sk, "LeftUpperArm", up_l, w)
	_blend(sk, "RightLowerArm", Quaternion(Vector3.UP, bend + wobble), w)
	_blend(sk, "LeftLowerArm", Quaternion(Vector3.UP, -bend - wobble), w)


## Start dying. Callers should also play the RestPose clip so the underlying pose is a clean T-pose.
func die(kind: int) -> void:
	death_kind = kind
	death_t = 0.0
	aim = 0.0
	reach = 0.0
	slump = 0.0
	flinch = 0.0


func _set_pos(sk: Skeleton3D, bone_name: String, v: Vector3) -> void:
	var i: int = _bone(sk, bone_name)
	if i >= 0:
		sk.set_bone_pose_position(i, v)


func _apply_death(sk: Skeleton3D, delta: float) -> void:
	death_t += delta
	var t: float = death_t
	var back: bool = death_kind == 0
	var e: float = 0.0          # 0 upright .. 1 flat on the floor (accelerating, like falling)
	var kneel: float = 0.0      # knees giving way
	var arm_phi: float = 0.0    # 0 = T-pose, positive = arms swing down
	var brace: float = 0.0      # forward fall: arms thrown out in front first
	var head_x: float = 0.0

	if back:
		var f: float = clampf((t - 0.12) / 0.55, 0.0, 1.0)
		e = f * f
		kneel = sin(clampf(t / 0.4, 0.0, 1.0) * PI) * 0.45        # buckle, then straighten
		arm_phi = lerpf(0.4, -0.7, smoothstep(0.0, 0.3, t))        # flail up as the feet go...
		arm_phi = lerpf(arm_phi, 1.25, smoothstep(0.6, 0.95, t))   # ...then flop limp
		head_x = -0.55 * e
		death_angle = -PI * 0.5 * e
	else:
		var f2: float = clampf((t - 0.38) / 0.5, 0.0, 1.0)
		e = f2 * f2
		kneel = smoothstep(0.0, 0.35, t) * (1.0 - 0.7 * smoothstep(0.7, 1.1, t))
		brace = smoothstep(0.3, 0.5, t) * (1.0 - smoothstep(0.78, 1.0, t))
		arm_phi = lerpf(0.4, 1.25, smoothstep(0.7, 1.0, t))
		head_x = 0.5 * kneel * (1.0 - e)
		death_angle = PI * 0.5 * e

	# landing bounce
	var t_land: float = 0.67 if back else 0.88
	if t > t_land:
		var b: float = 0.06 * exp(-(t - t_land) * 9.0) * sin((t - t_land) * 28.0)
		death_angle += b if back else -b

	var root: int = _bone(sk, "Root")
	var hips: int = _bone(sk, "Hips")
	if root >= 0:
		sk.set_bone_pose_rotation(root, Quaternion(Vector3.RIGHT, death_angle))
		sk.set_bone_pose_position(root, Vector3(0.0, 0.22 * e, 0.0))   # the body has thickness
	if hips >= 0:
		var rest_y: float = sk.get_bone_rest(hips).origin.y
		sk.set_bone_pose_position(hips, Vector3(0.0, rest_y - 0.30 * (kneel if not back else 0.0), 0.0))

	var thigh: float = -0.55 * kneel if not back else 0.0
	var shin: float = (1.5 if not back else 1.2) * kneel
	for side: String in ["Left", "Right"]:
		_blend(sk, side + "UpperLeg", Quaternion(Vector3.RIGHT, thigh), 1.0)
		_blend(sk, side + "LowerLeg", Quaternion(Vector3.RIGHT, shin), 1.0)

	var drop_r: Quaternion = Quaternion(Vector3.BACK, arm_phi)
	var drop_l: Quaternion = Quaternion(Vector3.BACK, -arm_phi)
	_blend(sk, "RightUpperArm", drop_r, 1.0)
	_blend(sk, "LeftUpperArm", drop_l, 1.0)
	_blend(sk, "RightLowerArm", Quaternion.IDENTITY, 1.0)
	_blend(sk, "LeftLowerArm", Quaternion.IDENTITY, 1.0)
	if brace > 0.001:
		_arms(sk, brace, 0.15, 0.0, 0.0)
	_blend(sk, "Spine", Quaternion(Vector3.RIGHT, 0.5 * kneel if not back else -0.25 * e), 1.0)
	_blend(sk, "Head", Quaternion(Vector3.RIGHT, head_x) * Quaternion(Vector3.BACK, 0.5 * e), 1.0)


func _process_modification_with_delta(delta: float) -> void:
	var sk: Skeleton3D = get_skeleton()
	if sk == null:
		return
	if death_kind >= 0:
		_apply_death(sk, delta)
		return
	_t += delta
	flinch = maxf(0.0, flinch - delta * 3.5)

	# zombie: arms out in front, drooping a little, swaying out of sync
	if reach > 0.001:
		var sway: float = sin(_t * 2.3 + phase) * 0.12
		_arms(sk, reach, 0.22 + sway * 0.5, 0.05, sway)
		_blend(sk, "Spine", Quaternion(Vector3.RIGHT, 0.22), reach)
		_blend(sk, "Head", Quaternion(Vector3.RIGHT, 0.38) * Quaternion(Vector3.BACK, head_roll), reach)

	# idle zombie: slumped, head hanging, arms left to the Idle clip
	if slump > 0.001:
		_blend(sk, "Spine", Quaternion(Vector3.RIGHT, 0.30), slump)
		_blend(sk, "Neck", Quaternion(Vector3.RIGHT, 0.35), slump)
		_blend(sk, "Head", Quaternion(Vector3.RIGHT, 0.30) * Quaternion(Vector3.BACK, head_roll), slump)

	# player: gun up, both hands in front, arms follow where the camera looks
	if aim > 0.001:
		_arms(sk, aim, -aim_pitch, 0.75, 0.0)
		_blend(sk, "Chest", Quaternion(Vector3.UP, 0.12), aim)   # shoulders open a touch toward the gun

	# any hit: torso and head rock backwards, then settle
	if flinch > 0.001:
		var f: float = flinch
		_blend(sk, "Spine", Quaternion(Vector3.RIGHT, -0.45), f)
		_blend(sk, "Head", Quaternion(Vector3.RIGHT, -0.5), f)
