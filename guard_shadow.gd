extends RefCounted
# The shadow under the Guard wings (Psalm 91:4, "under his wings"), as in
# the reference animation: while the wings fold the sheep ducks down (the
# crouching frame of Playerwalkanim.png), and as the dome lands its shadow
# sweeps down over them (guard_shadow.gdshader). It stays while the wings
# stay, as see-through as they are (half dark while they linger), and goes
# with them. One of these per character, fed their wings and sprites; it
# only follows the wings' state, so play-in / linger / fade stay in step.
# (battle_3d.gd copies the shadow onto the 3D billboards.)

const SHADER = preload("res://guard_shadow.gdshader")
const CROUCH_TEXTURE = "res://Playerwalkanim.png"
const CROUCH_FRAME = 2      # the sheep tucked down
const DOME_FRAME = 3        # the first frame of the closed dome (Guardeffect.png)
const CROUCH_FROM = 2       # the wings folding in

var fx: AnimatedSprite2D
var sprites: Array = []
var amount = 0.0      # how dark now (0..1)
var reach = 2.0       # the sweep (0 top .. 1 bottom, > 1 done)
var crouching = false

func _init(wings: AnimatedSprite2D, bodies: Array):
	fx = wings
	sprites = bodies.filter(func(s): return s != null)

func update(delta: float):
	var target = 0.0
	if fx and is_instance_valid(fx) and fx.visible:
		if not fx.is_playing() or fx.frame >= DOME_FRAME:
			target = fx.modulate.a      # 1 while it plays, 0.5 lingering
	if target > 0.0 and amount <= 0.001:
		reach = -0.1                 # the dome just landed: sweep down
	amount = move_toward(amount, target, delta * (12.0 if target > amount else 4.0))
	reach = min(reach + delta * 9.0, 2.0)
	crouching = fx != null and is_instance_valid(fx) and fx.visible and fx.is_playing() and fx.frame >= CROUCH_FROM
	for s in sprites:
		if not is_instance_valid(s):
			continue
		if crouching and s is Sprite2D and s.texture and s.texture.resource_path == CROUCH_TEXTURE and s.hframes > CROUCH_FRAME:
			s.frame = CROUCH_FRAME
		if s.material != null and not (s.material is ShaderMaterial and s.material.shader == SHADER):
			continue   # (it has a look of its own)
		if amount <= 0.001:
			if s.material != null:
				s.material = null
			continue
		if s.material == null:
			var m = ShaderMaterial.new()
			m.shader = SHADER
			s.material = m
		var r: Rect2 = s.get_rect()
		s.material.set_shader_parameter("shadow", amount)
		s.material.set_shader_parameter("reach", reach)
		s.material.set_shader_parameter("span", Vector2(r.position.y, r.end.y))

# The shadow of a sprite now (for the 3D billboard of it), 0..1
static func shade_of(s: CanvasItem) -> float:
	var m = s.material
	if m is ShaderMaterial and m.shader == SHADER:
		return float(m.get_shader_parameter("shadow")) * clamp(float(m.get_shader_parameter("reach")) + 0.1, 0.0, 1.0)
	return 0.0
