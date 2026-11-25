extends MeshInstance3D
## A BadLevel door volume turned into a real door. Attached at runtime by FacilityLevel
## (the node is already a MeshInstance3D in the imported GLB), so call setup() explicitly.
## Locked doors need the matching keycard; secret doors just need a push (E).

var key_color: String = ""
var secret: bool = false
var is_open: bool = false
var _closed_y: float = 0.0
var _body: StaticBody3D


func setup(key: String, is_secret: bool) -> void:
	key_color = key
	secret = is_secret
	_closed_y = position.y
	var aabb: AABB = mesh.get_aabb()
	_body = StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = aabb.size
	cs.shape = box
	cs.position = aabb.get_center()
	_body.add_child(cs)
	_body.add_to_group("interactable")
	add_child(_body)


func prompt(player: Node) -> String:
	if is_open:
		return ""
	if key_color != "" and not player.call("has_key", key_color):
		return "Locked - needs the %s keycard" % key_color
	return "[E] Open" if not secret else "[E] Push"


func interact(player: Node) -> void:
	if is_open:
		return
	if key_color != "" and not player.call("has_key", key_color):
		Sfx.play("locked")
		player.call("say", "Locked. You need the %s keycard." % key_color)
		return
	open()


func open() -> void:
	is_open = true
	Sfx.play("door")
	var h: float = mesh.get_aabb().size.y
	var tw: Tween = create_tween()
	tw.tween_property(self, "position:y", _closed_y - h - 0.05, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func() -> void: _body.collision_layer = 0)
