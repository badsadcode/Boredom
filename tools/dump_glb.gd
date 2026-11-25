extends SceneTree
# usage: godot --headless --path . -s tools/dump_glb.gd -- res://assets/level/facility.glb
func _init():
	var path: String = OS.get_cmdline_user_args()[0]
	var ps: PackedScene = load(path)
	var root := ps.instantiate()
	_dump(root, 0, 3)
	quit()
func _dump(n: Node, depth: int, maxd: int):
	var extra := ""
	if n.has_meta("extras"): extra = " extras=" + str(n.get_meta("extras"))
	var t := ""
	if n is Node3D: t = " pos=" + str((n as Node3D).position)
	if depth <= maxd and (depth < 2 or not (n is MeshInstance3D)):
		print("  ".repeat(depth), n.name, " [", n.get_class(), "]", t, extra)
	for c in n.get_children():
		if depth < maxd: _dump(c, depth + 1, maxd)
