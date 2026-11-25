extends SceneTree
func _init():
	var root: Node = (load("res://assets/level/facility.glb") as PackedScene).instantiate()
	var seen: Dictionary = {}
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n
		for s in mi.mesh.get_surface_count():
			var m: Material = mi.mesh.surface_get_material(s)
			var nm: String = m.resource_name if m else "none"
			if seen.has(nm): continue
			seen[nm] = true
			var arr: Array = mi.mesh.surface_get_arrays(s)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
			var nr: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			print("== ", nm, " verts=", v.size(), " has_uv=", uv.size() > 0, " has_tangent=", arr[Mesh.ARRAY_TANGENT] != null)
			for i in mini(6, v.size()):
				print("   p=", v[i], " n=", nr[i] if nr.size() > i else "-", " uv=", uv[i] if uv.size() > i else "-")
	quit()
