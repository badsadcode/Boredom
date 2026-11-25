class_name Pickup
extends Area3D
## Floating brick-style pickup: health, ammo, armor, keycards, weapons.

const GUN_PATHS: Dictionary = {
	"shotgun": "res://assets/guns/BadGun_shotgun_scrap_5.glb",
	"smg": "res://assets/guns/BadGun_smg_modern_2.glb",
}
const KEY_COLORS: Dictionary = {
	"red": Color(0.9, 0.15, 0.12),
	"blue": Color(0.2, 0.4, 0.95),
	"yellow": Color(0.95, 0.8, 0.15),
	"green": Color(0.2, 0.85, 0.3),
}

var kind: String = "health"
var props: Dictionary = {}
var _visual: Node3D
var _t: float = randf() * 6.0


func setup(k: String, p: Dictionary) -> void:
	kind = k
	props = p


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2   # player
	monitoring = true
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.9
	cs.shape = sph
	cs.position.y = 0.5
	add_child(cs)

	_visual = Node3D.new()
	_visual.position.y = 0.6
	add_child(_visual)
	var tint: Color = _build_visual()
	var lamp := OmniLight3D.new()
	lamp.light_color = tint
	lamp.light_energy = 0.7
	lamp.omni_range = 3.5
	lamp.position.y = 0.7
	add_child(lamp)
	Retro.retrofy(self)
	body_entered.connect(_on_body)


func _build_visual() -> Color:
	var c: Color = Color.WHITE
	match kind:
		"health":
			c = Color(0.9, 0.2, 0.2)
			_box(Vector3(0.4, 0.28, 0.28), c)
			_box(Vector3(0.12, 0.3, 0.3), Color.WHITE)
		"megahealth":
			c = Color(0.2, 0.9, 0.95)
			_box(Vector3(0.45, 0.45, 0.45), c, 2.0)
		"armor":
			c = Color(0.25, 0.45, 0.95)
			_box(Vector3(0.42, 0.34, 0.2), c)
		"ammo":
			c = Color(0.95, 0.8, 0.2)
			_box(Vector3(0.36, 0.22, 0.24), c)
			_box(Vector3(0.1, 0.24, 0.26), Color(0.3, 0.25, 0.1))
		"key":
			c = KEY_COLORS.get(str(props.get("color", "red")), Color.RED)
			_box(Vector3(0.3, 0.46, 0.06), c, 1.5)
			_box(Vector3(0.12, 0.12, 0.08), Color.WHITE)
		"weapon":
			c = Color(1.0, 0.9, 0.6)
			var wid: String = str(props.get("type", "smg"))
			var path: String = GUN_PATHS.get(wid, GUN_PATHS["smg"])
			var gun: Node3D = (load(path) as PackedScene).instantiate()
			gun.rotation.y = PI
			gun.scale = Vector3.ONE * 1.6
			_visual.add_child(gun)
		_:
			_box(Vector3(0.3, 0.3, 0.3), c)
	return c


func _box(size: Vector3, color: Color, glow: float = 0.0) -> void:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if glow > 0.0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = glow
	m.material_override = mat
	_visual.add_child(m)


func _process(delta: float) -> void:
	_t += delta
	_visual.rotation.y += delta * 1.8
	_visual.position.y = 0.6 + sin(_t * 2.2) * 0.07


func _on_body(body: Node3D) -> void:
	if body.has_method("collect") and body.call("collect", kind, props):
		Sfx.play("pickup")
		queue_free()
