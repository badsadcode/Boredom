class_name WorldTextures
extends RefCounted
## Texture set for BadLevel's blockout materials (see tools/gen_textures.py).
## 1 UV unit in the GLB = 2 m, so each texture is a 2 m tile.
## Textures are re-created at load with mipmaps: the PS1 look samples one mip down.

const DIR: String = "res://assets/textures/"
const MAP: Dictionary = {
	"bl_floor": "floor", "bl_wall": "wall", "bl_ceiling": "ceiling",
	"bl_door": "door_red", "bl_door_blue": "door_blue", "bl_secret": "secret",
	"bl_lift": "lift", "bl_ladder": "ladder",
}
static var _cache: Dictionary = {}


static func has(material_name: String) -> bool:
	return MAP.has(material_name)


static func albedo(material_name: String) -> Texture2D:
	return _load(DIR + str(MAP[material_name]) + ".png")


static func normal(material_name: String) -> Texture2D:
	return _load(DIR + str(MAP[material_name]) + "_n.png")


static func _load(path: String) -> Texture2D:
	if _cache.has(path):
		return _cache[path]
	var src: Texture2D = load(path)
	if src == null:
		return null
	var img: Image = src.get_image()
	if img.is_compressed():
		img.decompress()
	img.generate_mipmaps()
	var t: ImageTexture = ImageTexture.create_from_image(img)
	_cache[path] = t
	return t
