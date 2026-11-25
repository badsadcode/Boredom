extends Node3D
## Death-animation filmstrip: two zombies on a flat floor, side-on camera, killed from opposite
## sides (one topples backwards, one collapses forward). Fixed timestep, so it is repeatable.
##
##   xvfb-run -a godot --rendering-method gl_compatibility --rendering-driver opengl3 \
##       --fixed-fps 30 --path . res://tools/death_stage.tscn -- docs/death.png
const KILL_FRAME: int = 6
const SAMPLES: Array[float] = [0.0, 0.2, 0.4, 0.6, 0.8, 1.0, 1.3, 2.0]   # seconds after the kill

var _frame: int = 0
var _zs: Array[Zombie] = []
var _shots: Array[Image] = []


func _ready() -> void:
	Retro.level = 0.4
	var scene: Node3D = self
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.1, 0.12, 0.13)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.62, 0.65)
	var we := WorldEnvironment.new()
	we.environment = env
	scene.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	scene.add_child(sun)

	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30, 0.2, 30)
	cs.shape = box
	floor_body.add_child(cs)
	floor_body.position.y = -0.1
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = box.size
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.45, 0.42)
	mi.material_override = mat
	floor_body.add_child(mi)
	scene.add_child(floor_body)

	for zpos: float in [1.4, -1.4]:
		var z := Zombie.new()
		scene.add_child(z)
		z.setup(2, 0)
		z.global_position = Vector3(0, 0.05, zpos)
		_zs.append(z)

	var cam := Camera3D.new()
	cam.fov = 38
	scene.add_child(cam)
	cam.position = Vector3(7.5, 1.2, 0)
	cam.look_at(Vector3(0, 0.75, 0))
	cam.make_current()


func _process(_delta: float) -> void:
	_frame += 1
	if _frame == KILL_FRAME:
		# zombie 0 is shot from the front (topples back), zombie 1 from behind (collapses forward)
		for i in _zs.size():
			var z: Zombie = _zs[i]
			var side: float = -3.0 if i == 0 else 3.0
			z.take_damage(9999.0, z.global_position + z.global_transform.basis.z * side)
	for s in SAMPLES:
		if _frame == KILL_FRAME + int(round(s * 30.0)) + 1:
			_shots.append(get_viewport().get_texture().get_image())
	if _shots.size() == SAMPLES.size():
		var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "death.png"
		var w: int = 480
		var h: int = 270
		var sheet := Image.create(w * 4, h * 2, false, Image.FORMAT_RGB8)
		for i in _shots.size():
			var im: Image = _shots[i].duplicate()
			im.convert(Image.FORMAT_RGB8)
			im.resize(w, h)
			sheet.blit_rect(im, Rect2i(0, 0, w, h), Vector2i((i % 4) * w, (i / 4) * h))
		sheet.save_png(out)
		print("saved ", out, "  heads at end: ", _zs[0]._pose.head_height, " / ", _zs[1]._pose.head_height)
		get_tree().quit()
