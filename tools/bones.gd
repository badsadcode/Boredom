extends SceneTree
func _init():
	var root: Node = (load("res://assets/chars/blocky_zombie_9_kit-mesh.glb") as PackedScene).instantiate()
	var sk: Skeleton3D = root.find_child("Skeleton3D", true, false) as Skeleton3D
	for i in sk.get_bone_count():
		var r: Quaternion = sk.get_bone_rest(i).basis.get_rotation_quaternion()
		print(i, " ", sk.get_bone_name(i), " parent=", sk.get_bone_parent(i), " rest_pos=", sk.get_bone_rest(i).origin, " rest_rot=", r if not r.is_equal_approx(Quaternion.IDENTITY) else "id")
	print("modifier API: ", ClassDB.class_get_method_list("SkeletonModifier3D").map(func(m): return m.name))
	var ap: AnimationPlayer = root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	print("callback_mode=", ap.callback_mode_process)
	for a in ap.get_animation_list(): print("anim ", a, " len=", ap.get_animation(a).length, " loop=", ap.get_animation(a).loop_mode)
	quit()
