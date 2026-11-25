extends SceneTree
func _init():
	var root: Node = (load(OS.get_cmdline_user_args()[0]) as PackedScene).instantiate()
	_walk(root, 0)
	var aabb := _aabb(root, Transform3D.IDENTITY)
	print("AABB pos=", aabb.position, " size=", aabb.size)
	quit()
func _walk(n: Node, d: int):
	if n is AnimationPlayer:
		print("  ".repeat(d), "ANIMS: ", (n as AnimationPlayer).get_animation_list())
	if n.get_class() != "MeshInstance3D" or d < 2:
		var pos: String = str((n as Node3D).position) if n is Node3D else ""
		print("  ".repeat(d), n.name, " [", n.get_class(), "] ", pos)
	if d < 4 and not n is Skeleton3D:
		for c in n.get_children(): _walk(c, d + 1)
func _aabb(n: Node, t: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	var tt := t
	if n is Node3D: tt = t * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		out = tt * (n as MeshInstance3D).mesh.get_aabb(); first = false
	for c in n.get_children():
		var a := _aabb(c, tt)
		if a.size != Vector3.ZERO:
			if first: out = a; first = false
			else: out = out.merge(a)
	return out
