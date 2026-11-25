extends SceneTree
func _init():
	var root: Node = (load(OS.get_cmdline_user_args()[0]) as PackedScene).instantiate()
	var pat := OS.get_cmdline_user_args()[1]
	_walk(root, pat)
	quit()
func _walk(n: Node, pat: String):
	if n.name.to_lower().contains(pat) or (n is MeshInstance3D and _mats(n).contains(pat)):
		var e: String = str(n.get_meta("extras")) if n.has_meta("extras") else ""
		var p: String = str(n.get_parent().name) if n.get_parent() else ""
		print(p, "/", n.name, " [", n.get_class(), "] ", (n as Node3D).position if n is Node3D else "", " ", _mats(n) if n is MeshInstance3D else "", " ", e.substr(0, 160))
	for c in n.get_children(): _walk(c, pat)
func _mats(m: MeshInstance3D) -> String:
	var s := ""
	if m.mesh:
		for i in m.mesh.get_surface_count():
			var mat := m.mesh.surface_get_material(i)
			s += (mat.resource_name if mat else "none") + ","
	return s
