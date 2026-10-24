extends RefCounted
# The shadow under the Guard wings (Psalm 91:4, "under his wings"), as in
# the reference animation: while the wings fold the sheep ducks down (the
# crouching frame of Playerwalkanim.png), and as the dome lands its shadow
# sweeps down over them (guard_shadow.gdshader). There's one light source,
# so the shadow is the sprite's own shadow colours (PALETTES): the lit wool
# becomes exactly the grey on the sheep's underside, and so on. It stays,
# whole, while the wings stay (see-through), and lifts when they go. One of
# these per character, fed their wings and sprites; it only follows the
# wings' state, so play-in / linger / fade stay in step.
# (battle_3d.gd copies the shadow onto the 3D billboards.)

const SHADER = preload("res://guard_shadow.gdshader")
const CROUCH_TEXTURE = "res://Playerwalkanim.png"
const CROUCH_FRAME = 2      # the sheep tucked down
const DOME_FRAME = 3        # the first frame of the closed dome (Guardeffect.png)
const CROUCH_FROM = 2       # the wings folding in

# Each sprite sheet's colours in the light -> the same colours in shadow,
# taken from the art itself (the shaded undersides). The phone sheep and
# Baana use the player's sheet (tinted), so its shadow tints with them.
const SHEEP = [
	["ffffff", "bfbfbf"],   # wool -> the grey of its underside
	["eec39a", "d4ad8a"],   # face -> its darker tone (under the chin)
]
const RAMUEL = [
	["ffffe4", "bfbfbf"],   # cream wool -> the grey of his underside
	["ffffe5", "bfbfbf"],
	["8a4836", "5d2c28"],   # horns / staff -> their dark brown
	["8c4c39", "5d2c28"],
	["884b2b", "5d2c28"],
	["505050", "2f2f2f"],   # legs -> their dark grey
	["4f4f4f", "2f2f2f"],
	["e1e1cf", "a9a9ae"],   # face: no darker tone drawn; his wool's own step (ffffe4 -> bfbfbf)
	["e2e2cf", "a9a9ae"],
]
const PALETTES = {
	"res://Playerwalkanim.png": SHEEP,
	"res://Pastor_idle.png": RAMUEL,
	"res://Pastor_walk.png": RAMUEL,
}

var fx: AnimatedSprite2D
var sprites: Array = []
var reach = 0.0       # how far the shadow has come down them (0 none .. > 1 all)
var crouching = false

func _init(wings: AnimatedSprite2D, bodies: Array):
	fx = wings
	sprites = bodies.filter(func(s): return s != null)

func update(delta: float):
	var on = false
	if fx and is_instance_valid(fx) and fx.visible:
		on = not fx.is_playing() or fx.frame >= DOME_FRAME
	# down as the dome lands (~0.12 s), back up when the wings go
	reach = clamp(reach + delta * (9.0 if on else -7.0), 0.0, 1.1)
	crouching = fx != null and is_instance_valid(fx) and fx.visible and fx.is_playing() and fx.frame >= CROUCH_FROM
	for s in sprites:
		if not is_instance_valid(s):
			continue
		if crouching and s is Sprite2D and s.texture and s.texture.resource_path == CROUCH_TEXTURE and s.hframes > CROUCH_FRAME:
			s.frame = CROUCH_FRAME
		if s.material != null and not (s.material is ShaderMaterial and s.material.shader == SHADER):
			continue   # (it has a look of its own)
		if reach <= 0.0:
			if s.material != null:
				s.material = null
			continue
		if s.material == null:
			var m = ShaderMaterial.new()
			m.shader = SHADER
			_set_palette(m, s.texture)
			s.material = m
		var r: Rect2 = s.get_rect()
		s.material.set_shader_parameter("reach", reach)
		s.material.set_shader_parameter("span", Vector2(r.position.y, r.end.y))

static func palette_for(tex: Texture2D) -> Array:
	return PALETTES.get(tex.resource_path if tex else "", SHEEP)

static func _set_palette(m: ShaderMaterial, tex: Texture2D):
	var pal = palette_for(tex)
	var lit = PackedVector3Array(); var shade = PackedVector3Array()
	for pair in pal:
		var a = Color(pair[0]); var b = Color(pair[1])
		lit.append(Vector3(a.r, a.g, a.b)); shade.append(Vector3(b.r, b.g, b.b))
	m.set_shader_parameter("swaps", pal.size())
	m.set_shader_parameter("lit", lit)
	m.set_shader_parameter("shade", shade)

# How much of a sprite is in the shadow now (0..1; for the 3D billboard of it)
static func shade_of(s: CanvasItem) -> float:
	var m = s.material
	if m is ShaderMaterial and m.shader == SHADER:
		return clamp(float(m.get_shader_parameter("reach")), 0.0, 1.0)
	return 0.0
