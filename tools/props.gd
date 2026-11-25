extends SceneTree
func _init():
	for p in ClassDB.class_get_property_list("NavigationMesh"):
		if p.name.contains("geometry") or p.name.contains("source") or p.name.contains("collision"): print(p.name, " type=", p.type, " hint=", p.hint_string)
	for c in ClassDB.class_get_integer_constant_list("NavigationMesh"): print(c, "=", ClassDB.class_get_integer_constant("NavigationMesh", c))
	quit()
