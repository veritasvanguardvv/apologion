extends Node3D
# 3D BOSS BATTLE PRESENTATION (Grandia style) - the SinDeath fight only
# ---------------------------------------------------------------------
# Only a PRESENTATION layer: the battle itself (turns, verses, damage, the
# counter, items, phone players...) is still the normal 2D battle. While it's
# on, this node:
#   - hides the 2D level art (Decor, tiles, background...) and the 2D drawing
#     of the combatants (their sprites, HP bars, labels: a canvas cull bit, so
#     their 'visible' and the game logic don't change)
#   - shows each 2D sprite of the combatants (you, the party, phone players,
#     Mammon, SinDeath, the Golden Calf, the guard dome...) as a Sprite3D
#     billboard in a dark 3D arena built from the Greed art. Every frame the
#     Sprite3D copies the 2D sprite (texture / animation frame, flip, offset,
#     colour, visibility), so every animation keeps working as it is.
#   - places the 2D sprites' world position in 3D with one simple map
#     (to_3d): x -> X, height above the floor -> Y, plus a depth lane per
#     combatant (the party in front, SinDeath looming behind). SinDeath
#     sliding over the calf (the counter) moves it in 3D too.
#   - shows the combatants' HP bars / labels as copies on an overlay layer,
#     at the projected spot (so they stay readable).
#   - screen_point() / world_point() / screen_scale() let the 2D UI (speech
#     bubbles, target markers, damage popups) find where a 2D point shows on
#     the screen through the 3D camera.
#   - drives the 3D camera: SinDeath manifesting, your turn (the party),
#     enemy turns, swings to who gets hit, the counter slide, the 2 Cor 1:20
#     idol-zero moment, victory, and a slow drift / orbit while idle.
# Built only from Compatibility-renderer features (the project's renderer on
# desktop, iOS and web): unshaded billboards, a few lights, depth fog, fake
# light beams (additive cones), CPU dust. No volumetric fog, no shadows.
# Turned on/off by Settings > "3D boss battles" (GameSettings.boss_battles_3d).
# Used by Greed/scripts/sindeath_scene.gd: begin() before SinDeath manifests,
# finish() after "Victory!" (the victory talk and the ram are 2D again).

const K = 0.01                 # 3D units per 2D pixel
const CULL_BIT = 1 << 19       # canvas visibility layer for the hidden 2D drawing
const PREVIEW_TEX = "res://Greed/preview-old-dark-castle-interior-tileset.png"
const GLASS_TEX = "res://Greed/stainedglass.png"
const TREASURE_TEX = "res://Greed/treasure_icons_16x16.png"
const GOLD = Color(1.0, 0.86, 0.45)
const PARTY_TINT = Color(1.0, 0.97, 0.9)
const ENEMY_TINT = Color(0.8, 0.84, 1.0)

static var current = null      # the running presentation (or null)

var scene                      # sindeath_scene.gd
var level: Node
var player
var live = false
var center_x = 0.0             # 2D x of the arena centre
var ground_y = 0.0             # 2D y of the floor
var sd_home_x = 0.0
var camera: Camera3D
var overlay: CanvasLayer
var fade_layer: CanvasLayer
var fade: ColorRect
var flash: ColorRect
var proxies = {}               # 2D sprite -> Sprite3D
var proxy_owner = {}           # 2D sprite -> combatant (lane)
var mirrors = {}               # 2D Control -> its copy on the overlay
var mirror_owner = {}
var culled = {}                # CanvasItem -> its old visibility_layer
var hidden = []                # level nodes hidden while 3D is on
var extras = {}                # loose 2D sprites (death ghosts...) -> lane z
var last_hp = {}
var popups = {}                # PopupText label -> [node, 2D point, time, age]
var old_cull_mask = 0
var scan_in = 0.0
var lite = false               # phones / web: fewer particles

# camera
var shot = "manifest"
var shot_node = null
var shot_time = 0.0
var shot_left = -1.0           # > 0: a short shot, then back to base_shot
var base_shot = "manifest"
var base_node = null
var cam_pos = Vector3.ZERO
var cam_look = Vector3.ZERO
var cam_fov = 55.0
var cam_vel = Vector3.ZERO      # (the camera's eased moves)
var look_vel = Vector3.ZERO
var fov_vel = 0.0
var cam_max_speed = 0.0        # fastest camera move, units/s (tests)
var cam_max_accel = 0.0        # most sudden change of speed, units/s² (tests)
var cam_last_v = Vector3.ZERO
const CAM_MAX_SPEED = 7.0
const IDOL_LANE = -0.1
const SD_HOME_LANE = -1.3
const PEDESTAL_DEPTH = 0.5     # the calf's pedestal: IDOL_LANE -/+ 0.25
const SD_FRONT_LANE = 0.18     # just in front of the calf and its pedestal
var shake_left = 0.0
var shake_power = 0.0
var counter_seen = ""
var idle_for = 0.0
var party_light: SpotLight3D
var enemy_light: SpotLight3D
var burst_light: OmniLight3D
var party_beam: MeshInstance3D
var enemy_beam: MeshInstance3D
var dust: CPUParticles3D


# (the TurnManager autoload, looked up when used: this script is preloaded by
# UI scripts that may compile before the autoloads exist)
func _tm() -> Node:
	return get_node("/root/TurnManager")


# ---------------- Static helpers (the 2D UI uses these) ----------------

static func is_on() -> bool:
	return current != null and is_instance_valid(current) and current.live

# Where the 2D world point p (of node, e.g. a combatant) is on the screen
static func screen_point(node, p: Vector2) -> Vector2:
	return current._screen(node, p)

# The 2D WORLD point that shows at that screen spot (for things drawn in the
# level, like the damage popups)
static func world_point(node, p: Vector2) -> Vector2:
	var vp = current.get_viewport()
	return vp.get_canvas_transform().affine_inverse() * current._screen(node, p)

# A popup centred on screen point s, moved so all of it stays on the screen
# and below the turn banner at the top (2D and 3D both use this).
static func keep_on_screen(vp: Viewport, label: Control, s: Vector2, rise := 0.0) -> Vector2:
	var size = vp.get_visible_rect().size
	var k = vp.get_canvas_transform().get_scale().x
	var half = label.size.x * k / 2.0
	s.x = clamp(s.x, half + 8.0, max(half + 8.0, size.x - half - 8.0))
	# the turn banner spans the top; the boss HP panel the top-right corner
	var top = 132.0 if s.x + half > size.x - 290.0 else 62.0
	s.y = max(s.y, top + 15.0 * k + rise)
	return s

# How many screen pixels one 2D pixel is at that spot (perspective)
static func screen_scale(node, p: Vector2) -> float:
	var a = current._screen(node, p)
	var b = current._screen(node, p + Vector2(0, -100))
	return clamp(a.distance_to(b) / 100.0, 0.2, 4.0)


# ---------------- Start / end ----------------

func begin(the_scene, the_player):
	scene = the_scene
	player = the_player
	level = scene.owner if scene.owner else get_tree().current_scene
	lite = OS.has_feature("mobile") or OS.has_feature("web")
	process_priority = -100   # move the camera before the bubbles / markers place themselves
	_build_fade()
	fade.color.a = 0.0
	var t = create_tween()
	t.tween_property(fade, "color:a", 1.0, 0.35)
	await t.finished
	var idol = scene.idol
	center_x = (_feet(player).x + idol.global_position.x) / 2.0
	ground_y = scene.sindeath.global_position.y
	sd_home_x = scene.sindeath.position.x
	_build_arena()
	camera = Camera3D.new()
	camera.near = 0.05
	camera.far = 80.0
	add_child(camera)
	camera.make_current()
	overlay = CanvasLayer.new()
	overlay.layer = 2   # above the level, under the target markers (3) and bubbles (4)
	add_child(overlay)
	var root = get_tree().root
	old_cull_mask = root.canvas_cull_mask
	root.canvas_cull_mask = old_cull_mask & ~CULL_BIT
	_hide_level()
	current = self
	live = true
	_scan()
	_sync()
	set_shot("manifest")
	_snap_camera()
	_tm().turn_started.connect(_on_turn_started)
	_tm().battle_ended.connect(_on_battle_ended)
	t = create_tween()
	t.tween_property(fade, "color:a", 0.0, 0.5)
	await t.finished


func finish():
	if not live:
		return
	var t = create_tween()
	t.tween_property(fade, "color:a", 1.0, 0.45)
	await t.finished
	_restore()
	t = create_tween()
	t.tween_property(fade, "color:a", 0.0, 0.45)
	await t.finished
	queue_free()


func _restore():
	if not live:
		return
	live = false
	if current == self:
		current = null
	if _tm().turn_started.is_connected(_on_turn_started):
		_tm().turn_started.disconnect(_on_turn_started)
	if _tm().battle_ended.is_connected(_on_battle_ended):
		_tm().battle_ended.disconnect(_on_battle_ended)
	if is_inside_tree():
		get_tree().root.canvas_cull_mask = old_cull_mask
	for item in culled:
		if is_instance_valid(item):
			item.visibility_layer = culled[item]
	culled.clear()
	for h in hidden:
		if is_instance_valid(h[0]):
			h[0].visible = h[1]
	hidden.clear()
	for c in mirrors.values():
		if is_instance_valid(c):
			c.queue_free()
	mirrors.clear()
	if is_instance_valid(camera):
		camera.clear_current(false)
	for n in get_children():
		if n != fade_layer:
			n.queue_free()


func _exit_tree():
	_restore()   # (e.g. the level reloads after you lose)


# A rising popup (popup_text.gd) kept over its spot while the camera moves
func track_popup(label: Control, node, p: Vector2, time: float):
	popups[label] = [node, p, max(time, 0.1), 0.0]
	_place_popup(label, 0.0)

func _place_popup(label: Control, delta: float):
	var d = popups[label]
	d[3] += delta
	var xf = get_viewport().get_canvas_transform()
	var at = _screen(d[0], d[1]) if is_instance_valid(d[0]) else xf * d[1]
	at.y -= 40.0 * clamp(d[3] / d[2], 0.0, 1.0)
	label.global_position = xf.affine_inverse() * keep_on_screen(get_viewport(), label, at) - Vector2(label.size.x / 2.0, 15)


# ---------------- The 2D side: hide it, follow it ----------------

func _hide_level():
	for c in level.get_children():
		if c == scene or c.is_in_group("player") or c.is_in_group("party"):
			continue
		if c is CanvasLayer and c.layer < 0:
			hidden.append([c, c.visible]); c.visible = false
		elif c is CanvasItem and c.visible:
			hidden.append([c, c.visible]); c.visible = false
	for c in scene.get_children():
		if c in [scene.mammon, scene.sindeath, scene.idol]:
			continue
		if c is CanvasItem and c.visible:
			hidden.append([c, c.visible]); c.visible = false
	level.child_entered_tree.connect(_on_loose_child)
	scene.child_entered_tree.connect(_on_loose_child)

# A sprite dropped in the level during the fight (an enemy's death ghost...)
func _on_loose_child(node):
	if live and (node is Sprite2D or node is AnimatedSprite2D):
		extras[node] = true

func _combatants() -> Array:
	var list = []
	if is_instance_valid(player):
		list.append(player)
	for m in get_tree().get_nodes_in_group("party"):
		if is_instance_valid(m) and not m in list:
			list.append(m)
	for e in [scene.mammon, scene.sindeath, scene.idol]:
		if is_instance_valid(e):
			list.append(e)
	return list

func _is_party(node) -> bool:
	return node == player or (is_instance_valid(node) and node.is_in_group("party"))

# Depth lane (3D z) of a combatant: the party in front, SinDeath behind
func lane(node) -> float:
	if not is_instance_valid(node):
		return 0.0
	if node == player:
		return 1.0
	if node.is_in_group("party"):
		var i = get_tree().get_nodes_in_group("party").find(node)
		return 0.4 - 0.4 * max(i, 0)   # staggered back from you
	if node == scene.idol:
		return IDOL_LANE
	if node == scene.sindeath:
		# Sliding over the calf (the counter) it comes forward to cover it, as
		# in 2D (drawn over it). It is in front before their sprites overlap,
		# and once the calf is cracked it stays in front of it (sliding back
		# and for the rest of the fight), so the calf never shows through it.
		# Only just in front: little parallax, so the calf shows through the
		# gaps in its coils from any camera angle, as in 2D.
		if is_instance_valid(scene.idol) and scene.idol.get("is_cracked"):
			return SD_FRONT_LANE
		var span = scene.idol.position.x - sd_home_x
		var k = 0.0 if abs(span) < 1.0 else clamp((node.position.x - sd_home_x) / span, 0.0, 1.0)
		return lerp(SD_HOME_LANE, SD_FRONT_LANE, smoothstep(0.0, 0.3, k))
	if node == scene.mammon:
		return -1.3
	return 0.0

# The combatant a node belongs to (for its lane)
func _owner_of(node):
	var n = node
	while n != null and is_instance_valid(n):
		if n == player or n == scene.mammon or n == scene.sindeath or n == scene.idol or (n is Node and n.is_in_group("party")):
			return n
		n = n.get_parent()
	return null

func _lane_for(node, p: Vector2) -> float:
	var o = _owner_of(node)
	if o != null:
		return lane(o)
	# a loose thing: the lane of the nearest combatant
	var best = 0.0
	var dist = INF
	for c in _combatants():
		var d = abs(c.global_position.x - p.x)
		if d < dist:
			dist = d
			best = lane(c)
	return best

func to_3d(p: Vector2, z: float) -> Vector3:
	return Vector3((p.x - center_x) * K, (ground_y - p.y) * K, z)

func _screen(node, p: Vector2) -> Vector2:
	if not is_instance_valid(camera):
		return p
	var v = to_3d(p, _lane_for(node, p))
	if camera.is_position_behind(v):
		return Vector2(-1000, -1000)
	return camera.unproject_position(v)

func _feet(node) -> Vector2:
	var shape = node.get_node_or_null("CollisionShape2D")
	if shape and shape.shape is RectangleShape2D:
		return shape.global_position + Vector2(0, shape.shape.size.y * shape.global_scale.y / 2.0)
	return node.global_position

func pos_3d(node, up := 0.0) -> Vector3:
	if not is_instance_valid(node):
		return Vector3.ZERO
	var f = _feet(node)
	return to_3d(f, lane(node)) + Vector3(0, up, 0)

func _cull(item: CanvasItem):
	if not culled.has(item):
		culled[item] = item.visibility_layer
		item.visibility_layer = CULL_BIT

# Finds the 2D drawing of every combatant: sprites get a 3D copy, HP bars and
# labels an overlay copy, and the 2D drawing is culled.
func _scan():
	for c in _combatants():
		_scan_node(c, c)
	for e in extras.keys():
		if is_instance_valid(e) and not proxies.has(e):
			_add_proxy(e, null)

func _scan_node(n: Node, owner_node):
	for c in n.get_children():
		if c is CanvasLayer:
			continue   # screen UI (bubbles, status row...) stays as it is
		if c is Control:
			if not mirrors.has(c):
				_add_mirror(c, owner_node)
			continue
		if c is Sprite2D or c is AnimatedSprite2D:
			if not proxies.has(c):
				_add_proxy(c, owner_node)
		elif c is CanvasItem and not (c is Light2D):
			_cull(c)
		_scan_node(c, owner_node)

func _add_proxy(src: CanvasItem, owner_node):
	var s = Sprite3D.new()
	s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.shaded = false
	s.double_sided = true
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED   # drawn in lane order (see _sync_sprite)
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.centered = false
	add_child(s)
	proxies[src] = s
	proxy_owner[src] = owner_node
	_cull(src)

func _add_mirror(src: Control, owner_node):
	var m = src.duplicate(0)
	m.visible = false
	overlay.add_child(m)
	mirrors[src] = m
	mirror_owner[src] = owner_node
	_cull_tree(src)

func _cull_tree(item: CanvasItem):
	_cull(item)
	for c in item.get_children():
		if c is CanvasItem:
			_cull_tree(c)

func _color_of(item: CanvasItem) -> Color:
	var c = item.self_modulate
	var n: Node = item
	while n is CanvasItem:
		c *= n.modulate
		n = n.get_parent()
	return c

func _sync():
	for src in proxies.keys():
		var s: Sprite3D = proxies[src]
		if not is_instance_valid(src):
			proxies.erase(src)
			proxy_owner.erase(src)
			extras.erase(src)
			_fade_out(s)
			continue
		_sync_sprite(src, s)
	for src in mirrors.keys():
		var m = mirrors[src]
		if not is_instance_valid(src):
			mirrors.erase(src)
			if is_instance_valid(m):
				m.queue_free()
			continue
		_sync_mirror(src, m)

func _sync_sprite(src: CanvasItem, s: Sprite3D):
	s.visible = src.is_visible_in_tree()
	if not s.visible:
		return
	var rect: Rect2
	if src is Sprite2D:
		s.texture = src.texture
		s.hframes = src.hframes
		s.vframes = src.vframes
		s.frame = src.frame
		s.region_enabled = src.region_enabled
		s.region_rect = src.region_rect
		rect = src.get_rect()
	else:
		var frames: SpriteFrames = src.sprite_frames
		var tex: Texture2D = null
		if frames and frames.has_animation(src.animation) and src.frame < frames.get_frame_count(src.animation):
			tex = frames.get_frame_texture(src.animation, src.frame)
		s.texture = tex
		s.hframes = 1
		s.vframes = 1
		s.frame = 0
		s.region_enabled = false
		var size = tex.get_size() if tex else Vector2.ZERO
		var o = src.offset
		if src.centered:
			o -= (size / 2.0).floor()
		rect = Rect2(o, size)
	var xf: Transform2D = src.get_global_transform()
	var flip_h = src.flip_h
	var flip_v = src.flip_v
	if xf.x.x < 0.0:
		rect.position.x = -(rect.position.x + rect.size.x)
		flip_h = not flip_h
	if xf.y.y < 0.0:
		rect.position.y = -(rect.position.y + rect.size.y)
		flip_v = not flip_v
	s.flip_h = flip_h
	s.flip_v = flip_v
	s.offset = Vector2(rect.position.x, -(rect.position.y + rect.size.y))
	s.pixel_size = K * max(abs(xf.x.x), 0.001)
	var owner_node = proxy_owner.get(src)
	var z = lane(owner_node) if owner_node != null else _lane_for(src, xf.origin)
	z += 0.03 * src.z_index + 0.002 * src.get_index()
	s.position = to_3d(xf.origin, z)
	var col = _color_of(src)
	var tint = PARTY_TINT if _is_party(owner_node) else ENEMY_TINT
	s.modulate = Color(col.r * tint.r, col.g * tint.g, col.b * tint.b, col.a)
	# The sprites overlap each other in lane order, like the 2D draw order,
	# whatever the camera angle. (Depth can't do it: a billboard is as deep as
	# its origin, so from the side wide SinDeath, centred far left of the
	# calf, would sink behind it.) They are blended, don't write depth, and
	# are sorted by render_priority = lane; the arena still hides them.
	var prio = clampi(roundi(z * 100.0), -120, 120)
	if s.render_priority != prio:
		s.render_priority = prio

func _sync_mirror(src: Control, m: Control):
	m.visible = src.is_visible_in_tree() and src.size.x > 0
	if not m.visible:
		return
	if src is Range:
		m.min_value = src.min_value
		m.max_value = src.max_value
		m.value = src.value
	if src is Label:
		m.text = src.text
	m.modulate = _color_of(src)
	m.size = src.size
	var owner_node = mirror_owner.get(src)
	var mid = src.get_global_transform() * (src.size / 2.0)
	var at = _screen(owner_node if owner_node != null else src, mid)
	m.position = (at - src.size / 2.0).round()

func _fade_out(s: Sprite3D):
	if not is_instance_valid(s):
		return
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	var t = s.create_tween().set_parallel(true)
	t.tween_property(s, "modulate", Color(2.0, 1.6, 1.6, 0.0), 1.1)
	t.tween_property(s, "pixel_size", s.pixel_size * 1.25, 1.1).set_ease(Tween.EASE_OUT)
	t.chain().tween_callback(s.queue_free)


# ---------------- The arena ----------------

func _region_texture(path: String, r: Rect2i) -> Texture2D:
	var tex = load(path)
	if tex == null:
		return null
	var img: Image = tex.get_image()
	if img == null:
		return tex
	if img.is_compressed():
		img.decompress()
	var part = img.get_region(r)
	part.generate_mipmaps()
	return ImageTexture.create_from_image(part)

func _mat(tex: Texture2D, color := Color.WHITE, unshaded := false, uv := Vector2.ONE) -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.albedo_texture = tex
	m.albedo_color = color
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.texture_repeat = true
	m.uv1_scale = Vector3(uv.x, uv.y, 1)
	m.roughness = 1.0
	m.metallic_specular = 0.1
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	return m

func _box(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var b = MeshInstance3D.new()
	var mesh = BoxMesh.new()
	mesh.size = size
	b.mesh = mesh
	b.material_override = mat
	b.position = pos
	add_child(b)
	return b

func _quad(size: Vector2, pos: Vector3, mat: Material) -> MeshInstance3D:
	var q = MeshInstance3D.new()
	var mesh = QuadMesh.new()
	mesh.size = size
	q.mesh = mesh
	q.material_override = mat
	q.position = pos
	add_child(q)
	return q

func _build_arena():
	# Environment: very dark, a little warm depth fog
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.012, 0.01, 0.018)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.42, 0.3)
	env.ambient_light_energy = 0.18
	env.fog_enabled = true
	env.fog_light_color = Color(0.05, 0.04, 0.03)
	env.fog_density = 0.035
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we = WorldEnvironment.new()
	we.environment = env
	add_child(we)
	# The floor: Greed's gold bricks
	var floor_tex = _region_texture(PREVIEW_TEX, Rect2i(882, 244, 48, 32))
	var floor_size = Vector2(30, 18)
	var tile = Vector2(48, 32) * 4.0 * K
	var floor = MeshInstance3D.new()
	var plane = PlaneMesh.new()
	plane.size = floor_size
	floor.mesh = plane
	floor.material_override = _mat(floor_tex, Color(0.95, 0.85, 0.6), false, floor_size / tile)
	floor.position = Vector3(0, 0, -1.5)
	add_child(floor)
	# The golden alcove (stained-glass window) looming far behind SinDeath
	var alcove = _region_texture(PREVIEW_TEX, Rect2i(690, 35, 270, 215))
	_quad(Vector2(270, 215) * 4.0 * K, Vector3(1.5, 215 * 2.0 * K - 0.2, -8.5), _mat(alcove, Color(0.42, 0.38, 0.3), true))
	# Golden pillars around the arena
	var pillar = _mat(_region_texture(PREVIEW_TEX, Rect2i(752, 43, 16, 174)), Color(0.9, 0.78, 0.45))
	for p in [Vector3(-9.5, 0, -5.5), Vector3(-4.5, 0, -6.5), Vector3(6.5, 0, -6.5), Vector3(11, 0, -5), Vector3(-12, 0, -1), Vector3(13, 0, 0.5)]:
		_box(Vector3(0.9, 7.0, 0.9), p + Vector3(0, 3.5, 0), pillar)
	# The gate (Greed's golden bars) behind the party
	var gate = _mat(load(GLASS_TEX), Color(0.85, 0.7, 0.35))
	gate.cull_mode = BaseMaterial3D.CULL_DISABLED
	_quad(Vector2(54, 142) * 4.0 * K, Vector3(-7.5, 142 * 2.0 * K, -3.8), gate)
	# Gold piles around the edges
	var piles = [Rect2i(35, 34, 10, 12), Rect2i(67, 33, 10, 14), Rect2i(81, 34, 15, 13), Rect2i(82, 80, 13, 16), Rect2i(67, 17, 10, 14)]
	var spots = [Vector3(-8.5, 0, -2.6), Vector3(-6.2, 0, -4.6), Vector3(-10.5, 0, 1.5), Vector3(4.2, 0, -4.8), Vector3(8.4, 0, -3.2), Vector3(9.6, 0, 1.2), Vector3(-1.5, 0, -5.4), Vector3(6.0, 0, 3.4), Vector3(-7.0, 0, 3.6), Vector3(1.8, 0, -6.0)]
	var treasure = load(TREASURE_TEX)
	for i in spots.size():
		var g = Sprite3D.new()
		g.texture = treasure
		g.region_enabled = true
		g.region_rect = piles[i % piles.size()]
		g.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		g.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		g.shaded = false
		g.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		g.centered = false
		g.offset = Vector2(-g.region_rect.size.x / 2.0, 0)
		g.pixel_size = 0.07
		g.modulate = Color(0.55, 0.47, 0.3)
		g.position = spots[i]
		add_child(g)
	# The calf's gold pedestal (it stands on one in the 2D level too)
	var calf = scene.idol
	var calf_sprite = calf.get_node_or_null("Sprite")
	if calf_sprite:
		var r = calf_sprite.get_global_transform() * calf_sprite.get_rect()
		var h = (ground_y - r.end.y) * K
		if h > 0.05:
			_box(Vector3(r.size.x * K * 1.05, h, PEDESTAL_DEPTH), to_3d(Vector2(r.get_center().x, ground_y), lane(calf)) + Vector3(0, h / 2.0, 0),
				_mat(floor_tex, Color(0.95, 0.8, 0.45), false, Vector2(2, 0.6)))
	# Lights: a warm spotlight on the party, a dimmer cold one on the bosses
	var party_at = _party_center()
	party_light = SpotLight3D.new()
	party_light.light_color = Color(1.0, 0.9, 0.7)
	party_light.light_energy = 5.0
	party_light.spot_range = 14.0
	party_light.spot_angle = 26.0
	party_light.spot_attenuation = 0.8
	add_child(party_light)
	party_light.position = party_at + Vector3(0.3, 8.0, 0.4)
	party_light.look_at(party_at, Vector3.FORWARD)
	var boss_at = (pos_3d(scene.sindeath) + pos_3d(calf)) / 2.0
	enemy_light = SpotLight3D.new()
	enemy_light.light_color = Color(0.55, 0.65, 1.0)
	enemy_light.light_energy = 2.2
	enemy_light.spot_range = 16.0
	enemy_light.spot_angle = 30.0
	add_child(enemy_light)
	enemy_light.position = boss_at + Vector3(-0.5, 9.0, -1.0)
	enemy_light.look_at(boss_at, Vector3.FORWARD)
	burst_light = OmniLight3D.new()
	burst_light.light_color = Color(1.0, 0.85, 0.4)
	burst_light.light_energy = 0.0
	burst_light.omni_range = 7.0
	burst_light.position = pos_3d(calf, 1.0)
	add_child(burst_light)
	# Fake volumetric beams (additive cones) + a little dust in the party's beam
	party_beam = _beam(party_at, Color(1.0, 0.88, 0.62), 0.22, 1.9)
	enemy_beam = _beam(boss_at, Color(0.5, 0.62, 1.0), 0.12, 2.3)
	dust = CPUParticles3D.new()
	dust.amount = 16 if lite else 40
	dust.lifetime = 6.0
	dust.preprocess = 6.0
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	dust.emission_box_extents = Vector3(1.6, 3.0, 1.2)
	dust.direction = Vector3(0, -1, 0)
	dust.spread = 30.0
	dust.initial_velocity_min = 0.05
	dust.initial_velocity_max = 0.15
	dust.gravity = Vector3.ZERO
	dust.scale_amount_min = 0.6
	dust.scale_amount_max = 1.2
	var dot = QuadMesh.new()
	dot.size = Vector2(0.04, 0.04)
	var dm = StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dm.albedo_color = Color(1.0, 0.9, 0.6, 0.6)
	dm.render_priority = 127   # motes in the air, over the sprites
	dot.material = dm
	dust.mesh = dot
	dust.position = party_at + Vector3(0, 3.0, 0)
	add_child(dust)

const BEAM_SHADER = """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 beam_color : source_color = vec4(1.0, 0.9, 0.6, 1.0);
uniform float strength = 0.2;
varying float height;
void vertex() { height = VERTEX.y; }
void fragment() {
	float edge = pow(abs(dot(normalize(NORMAL), normalize(VIEW))), 1.6);
	float fall = clamp(0.5 - height / 8.0, 0.0, 1.0);
	float flicker = 0.9 + 0.1 * sin(TIME * 1.3 + height * 1.7);
	ALBEDO = beam_color.rgb;
	ALPHA = strength * edge * (0.25 + 0.75 * fall) * flicker;
}
"""

func _beam(at: Vector3, color: Color, strength: float, radius: float) -> MeshInstance3D:
	var cone = CylinderMesh.new()
	cone.top_radius = 0.18
	cone.bottom_radius = radius
	cone.height = 8.0
	cone.radial_segments = 20
	cone.rings = 1
	cone.cap_top = false
	cone.cap_bottom = false
	var shader = Shader.new()
	shader.code = BEAM_SHADER
	var m = ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("beam_color", color)
	m.set_shader_parameter("strength", strength)
	var b = MeshInstance3D.new()
	b.mesh = cone
	b.material_override = m
	b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.render_priority = -128   # before the sprites (they are drawn over it)
	b.position = at + Vector3(0, 4.0, 0)
	add_child(b)
	return b

func _party_center() -> Vector3:
	var sum = Vector3.ZERO
	var n = 0
	for c in _combatants():
		if _is_party(c) and c.is_visible_in_tree():
			sum += pos_3d(c)
			n += 1
	return sum / n if n > 0 else pos_3d(player)

func _boss() -> Vector3:
	if is_instance_valid(scene.sindeath) and scene.sindeath.visible:
		return pos_3d(scene.sindeath)
	if is_instance_valid(scene.mammon) and scene.mammon.visible:
		return pos_3d(scene.mammon) - Vector3(0, pos_3d(scene.mammon).y, 0)
	return pos_3d(scene.idol)


# ---------------- The camera ----------------

# A shot: "manifest", "party", "member", "enemy", "wide", "hit_enemy",
# "hit_party", "counter", "idol_zero", "victory". time > 0 = a short shot,
# then back to the turn's shot.
func set_shot(name: String, node = null, time := -1.0):
	if time > 0.0:
		if shot in ["idol_zero", "victory"] and shot_left > 0.0:
			return   # don't cut the big moments short
	else:
		base_shot = name
		base_node = node
		if shot_left > 0.0:
			return   # the short shot finishes first
	shot = name
	shot_node = node
	shot_left = time
	shot_time = 0.0

func shake(power := 0.12, time := 0.35):
	shake_power = max(shake_power, power)
	shake_left = max(shake_left, time)

func _shot_params(t: float) -> Array:
	var P = _party_center()
	var S = _boss()
	var I = pos_3d(scene.idol)
	var E = (S + I) / 2.0
	match shot:
		"manifest":
			var k = smoothstep(0.0, 4.0, t)
			var look = S + Vector3(0.2, 2.0, 0)
			return [S + Vector3(lerp(-0.4, -2.2, k), lerp(0.25, 0.9, k), lerp(8.5, 6.0, k)), look, lerp(58.0, 50.0, k)]
		"party":
			var look = P.lerp(E, 0.45) + Vector3(0, 1.2, 0)
			return [P + Vector3(-1.4 + 0.35 * sin(t * 0.25), 1.9, 7.4), look, 52.0]
		"member":
			var M = pos_3d(shot_node) if is_instance_valid(shot_node) else P
			return [M + Vector3(-2.2, 1.5, 4.6), M.lerp(E, 0.35) + Vector3(0, 1.2, 0), 50.0]
		"enemy":
			var look = S + Vector3(0, 1.8, 0)
			return [S + Vector3(-3.2 + 0.3 * sin(t * 0.3), 0.7, 6.2), look, 52.0]
		"hit_enemy":
			var T = pos_3d(shot_node) if is_instance_valid(shot_node) else S
			return [P + Vector3(-0.8, 1.7, 3.6), T + Vector3(0, 1.3, 0), 46.0]
		"hit_party":
			var T = pos_3d(shot_node) if is_instance_valid(shot_node) else P
			return [T + Vector3(3.6, 1.4, 4.8), T + Vector3(0.4, 1.0, 0), 48.0]
		"counter":
			var look = (pos_3d(scene.sindeath) + I) / 2.0 + Vector3(0, 1.5, 0)
			return [look + Vector3(0.6 - 0.8 * smoothstep(0.0, 3.0, t), -0.3, 7.6), look + Vector3(-0.6, 0, 0), 50.0]
		"idol_zero":
			var k = smoothstep(0.0, 3.5, t)
			return [I + Vector3(lerp(3.4, 2.9, k), 1.0, lerp(3.6, 3.0, k)), I + Vector3(-0.3, 0.8, 0), lerp(48.0, 42.0, k)]
		"victory":
			var look = P + Vector3(0, 1.0, 0)
			var yaw = -0.5 + t * 0.14
			return [look + Vector3(sin(yaw) * 5.2, 1.1 + t * 0.12, cos(yaw) * 5.2), look, 48.0]
		_:   # "wide": a slow orbit over the whole arena (idle)
			var M = P.lerp(E, 0.5) + Vector3(0, 1.4, 0)
			var yaw = deg_to_rad(-16.0 + 15.0 * sin(t * 0.11))
			return [M + Vector3(sin(yaw) * 9.6, 1.9 + 0.3 * sin(t * 0.07), cos(yaw) * 9.6), M, 50.0]

# One step of a critically damped spring from x towards target (velocity v),
# taking about smooth_time seconds, never faster than max_speed: [x, v]
static func _damp3(x: Vector3, target: Vector3, v: Vector3, smooth_time: float, max_speed: float, delta: float) -> Array:
	if delta <= 0.0:
		return [x, v]
	var omega = 2.0 / max(smooth_time, 0.01)
	var e = omega * delta
	var d = 1.0 / (1.0 + e + 0.48 * e * e + 0.235 * e * e * e)
	var change = (x - target).limit_length(max_speed * smooth_time)
	var goal = x - change
	var temp = (v + omega * change) * delta
	v = (v - omega * temp) * d
	var out = goal + (change + temp) * d
	if (target - x).dot(out - target) > 0.0:   # no overshoot
		out = target
		v = (out - target) / delta
	return [out, v]

func _snap_camera():
	cam_vel = Vector3.ZERO
	look_vel = Vector3.ZERO
	fov_vel = 0.0
	var p = _shot_params(0.0)
	cam_pos = p[0]
	cam_look = p[1]
	cam_fov = p[2]
	_apply_camera(0.0)

func _apply_camera(delta: float):
	camera.fov = cam_fov
	var offset = Vector3.ZERO
	if shake_left > 0.0:
		shake_left -= delta
		var a = shake_power * clamp(shake_left / 0.35, 0.0, 1.0)
		offset = Vector3(randf_range(-a, a), randf_range(-a, a) * 0.6, 0)
	camera.position = cam_pos + offset
	camera.look_at(cam_look + offset * 0.5, Vector3.UP)

func _process(delta):
	if not live:
		return
	scan_in -= delta
	if scan_in <= 0.0:
		scan_in = 0.25
		_scan()
	_events(delta)
	_lights(delta)
	shot_time += delta
	if shot_left > 0.0:
		shot_left -= delta
		if shot_left <= 0.0:
			shot_left = -1.0
			shot = base_shot
			shot_node = base_node
			shot_time = 0.0
	var p = _shot_params(shot_time)
	# Every change of shot is an eased move (a critically damped spring: it
	# speeds up gently, then settles), never a jump. Hits move a bit faster.
	var smooth = 0.8
	if shot in ["hit_enemy", "hit_party"]:
		smooth = 0.55
	elif shot in ["victory", "manifest", "wide"]:
		smooth = 1.3
	var before = cam_pos
	var a = _damp3(cam_pos, p[0], cam_vel, smooth, CAM_MAX_SPEED, delta)
	cam_pos = a[0]; cam_vel = a[1]
	var b = _damp3(cam_look, p[1], look_vel, smooth, CAM_MAX_SPEED * 1.5, delta)
	cam_look = b[0]; look_vel = b[1]
	var f = _damp3(Vector3(cam_fov, 0, 0), Vector3(p[2], 0, 0), Vector3(fov_vel, 0, 0), smooth, 60.0, delta)
	cam_fov = f[0].x; fov_vel = f[1].x
	if delta > 0.0:   # (for the tests: how fast / how suddenly the camera moved)
		var v = (cam_pos - before) / delta
		cam_max_speed = max(cam_max_speed, v.length())
		cam_max_accel = max(cam_max_accel, (v - cam_last_v).length() / delta)
		cam_last_v = v
	_apply_camera(delta)
	# (after the camera moved: no lag)
	_sync()
	for label in popups.keys():
		if is_instance_valid(label):
			_place_popup(label, delta)
		else:
			popups.erase(label)

# Hits, the counter, idling
func _events(delta):
	for c in _combatants():
		var hp = c.get("hp")
		if hp == null:
			continue
		var before = last_hp.get(c, hp)
		last_hp[c] = hp
		if hp < before - 0.01 and _tm().in_battle:
			var big = (before - hp) >= 0.12 * float(c.get("max_hp") if c.get("max_hp") else 100.0)
			if _is_party(c):
				set_shot("hit_party", c, 1.3)
			elif c != scene.mammon:
				set_shot("hit_enemy", c, 1.4)
			shake(0.16 if big else 0.06, 0.4 if big else 0.2)
	var cs = scene.counter_state
	if cs != counter_seen:
		if cs == "sliding":
			set_shot("counter", null, 30.0)   # until it's answered
		elif cs == "done":
			_idol_zero()
		elif counter_seen in ["sliding", "waiting"] and cs == "":
			shot_left = 0.01   # the counter hit you: back to the turn's shot
		counter_seen = cs
	if _tm().in_battle and _tm().is_players_turn() and shot_left <= 0.0:
		idle_for += delta
		if idle_for > 7.0 and base_shot == "party":
			set_shot("wide")   # thinking about a verse: drift around the arena
	else:
		idle_for = 0.0

func _idol_zero():
	shot_left = -1.0
	set_shot("idol_zero", null, 3.6)
	shake(0.2, 0.6)
	if is_instance_valid(flash):
		flash.color = Color(1.0, 0.88, 0.45, 0.65)
		create_tween().tween_property(flash, "color:a", 0.0, 0.9)
	burst_light.position = pos_3d(scene.idol, 1.0)
	var t = create_tween()
	t.tween_property(burst_light, "light_energy", 6.0, 0.15)
	t.tween_property(burst_light, "light_energy", 0.0, 1.6)

func _lights(_delta):
	var P = _party_center()
	if is_instance_valid(party_light):
		party_light.position = party_light.position.lerp(P + Vector3(0.3, 8.0, 0.4), 0.05)
		party_beam.position = party_light.position - Vector3(0.3, 4.0, 0.4)
		dust.position = party_beam.position - Vector3(0, 1.0, 0)

func _on_turn_started(who):
	idle_for = 0.0
	if who == player:
		set_shot("party")
	elif _is_party(who):
		set_shot("member", who)
	else:
		set_shot("enemy", who)

func _on_battle_ended():
	shot_left = -1.0
	set_shot("victory")


# ---------------- Fades ----------------

func _build_fade():
	fade_layer = CanvasLayer.new()
	fade_layer.layer = 9   # over the HUD, under the menus (10)
	add_child(fade_layer)
	fade = ColorRect.new()
	fade.color = Color(0, 0, 0, 0)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade_layer.add_child(fade)
	flash = ColorRect.new()
	flash.color = Color(1, 1, 1, 0)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade_layer.add_child(flash)
