class_name Hud
extends CanvasLayer
## Plain on-screen text HUD, built in code. Sits above the retro post pass so it stays readable.

var player: Player
var _hp: Label
var _ammo: Label
var _prompt: Label
var _msgs: VBoxContainer
var _retro: Label
var _keys: HBoxContainer
var _flash: ColorRect
var _banner: Label
var _help: Label
var _help_t: float = 14.0


func setup(p: Player) -> void:
	player = p
	layer = 20
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_flash = ColorRect.new()
	_flash.color = Color(0.8, 0.0, 0.0, 0.0)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_flash)

	# crosshair
	for r: Rect2 in [Rect2(-1, -7, 2, 5), Rect2(-1, 2, 2, 5), Rect2(-7, -1, 5, 2), Rect2(2, -1, 5, 2)]:
		var c := ColorRect.new()
		c.color = Color(1, 1, 1, 0.75)
		c.set_anchors_preset(Control.PRESET_CENTER)
		c.position = r.position
		c.size = r.size
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(c)

	_hp = _label(root, Control.PRESET_BOTTOM_LEFT, Vector2(24, -64), 26)
	_ammo = _label(root, Control.PRESET_BOTTOM_RIGHT, Vector2(-300, -76), 26)
	_ammo.size = Vector2(276, 60)
	_ammo.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_prompt = _label(root, Control.PRESET_CENTER, Vector2(-300, 60), 22)
	_prompt.size = Vector2(600, 30)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_retro = _label(root, Control.PRESET_TOP_RIGHT, Vector2(-420, 14), 16)
	_retro.size = Vector2(404, 24)
	_retro.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_help = _label(root, Control.PRESET_TOP_LEFT, Vector2(16, 14), 16)
	_help.text = "WASD move  Shift sprint  Space jump  LMB fire  R reload  Q punch  E use  F flashlight\nV first/third person   1-3 / wheel weapons   [ ] retro dial   F1 modern  F2 mixed  F3 PS1"

	_msgs = VBoxContainer.new()
	_msgs.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_msgs.position = Vector2(-250, 60)
	_msgs.custom_minimum_size = Vector2(500, 0)
	_msgs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_msgs)

	_keys = HBoxContainer.new()
	_keys.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_keys.position = Vector2(24, -96)
	root.add_child(_keys)

	_banner = _label(root, Control.PRESET_CENTER, Vector2(-400, -60), 56)
	_banner.size = Vector2(800, 120)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.visible = false

	p.message.connect(show_message)
	p.damaged.connect(_on_damaged)
	p.died.connect(func() -> void:
		get_tree().create_timer(1.4).timeout.connect(func() -> void:
			banner("YOU DIED\npress R to try again", Color(0.9, 0.1, 0.1))))
	Retro.changed.connect(func(_v: float) -> void: _update_retro())
	_update_retro()


func _label(parent: Control, preset: int, pos: Vector2, size: int) -> Label:
	var l := Label.new()
	l.set_anchors_preset(preset)
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(0.92, 0.95, 0.9))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _update_retro() -> void:
	var l: float = Retro.level
	var tag: String = "MODERN" if l < 0.15 else ("PS1" if l > 0.9 else "MIXED")
	_retro.text = "RETRO %d%%  [%s]" % [roundi(l * 100.0), tag]


func show_message(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 5)
	_msgs.add_child(l)
	var tw: Tween = l.create_tween()
	tw.tween_interval(2.6)
	tw.tween_property(l, "modulate:a", 0.0, 0.8)
	tw.tween_callback(l.queue_free)


func banner(text: String, color: Color) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", color)
	_banner.visible = true


func _on_damaged(amount: float) -> void:
	_flash.color.a = clampf(0.25 + amount * 0.02, 0.25, 0.6)
	var tw: Tween = create_tween()
	tw.tween_property(_flash, "color:a", 0.0, 0.45)


func _process(delta: float) -> void:
	if player == null:
		return
	_hp.text = "HP %d    ARMOR %d" % [ceili(player.health), ceili(player.armor)]
	var w: Dictionary = Player.WEAPONS[player.current]
	var res: int = int(player.reserve[w["ammo"]])
	_ammo.text = "%s\n%d / %d" % [w["name"], player.mags[player.current], res]
	_prompt.text = player.prompt_text
	if _help_t > 0.0:
		_help_t -= delta
		_help.modulate.a = clampf(_help_t / 3.0, 0.0, 1.0)
	elif _help.visible:
		_help.visible = false
	if _keys.get_child_count() != player.keys.size():
		for c in _keys.get_children():
			c.queue_free()
		for k in player.keys:
			var sq := ColorRect.new()
			sq.custom_minimum_size = Vector2(22, 30)
			sq.color = Pickup.KEY_COLORS.get(k, Color.WHITE)
			_keys.add_child(sq)
