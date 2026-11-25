class_name StepHelper
extends RefCounted
## BadLevel stairs have 0.5 m risers, which a plain capsule can't climb.
## Call before move_and_slide(): if horizontal motion is blocked by something low enough,
## lift the body onto it (floor snap then settles it).


static func try_step(body: CharacterBody3D, motion: Vector3, height: float) -> void:
	motion.y = 0.0
	if motion.length_squared() < 0.000001 or not body.is_on_floor():
		return
	var t: Transform3D = body.global_transform
	if not body.test_move(t, motion):
		return
	var up: Vector3 = Vector3.UP * height
	if body.test_move(t, up):
		return
	if body.test_move(t.translated(up), motion):
		return
	body.global_position += up
