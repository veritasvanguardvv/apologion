extends RefCounted
# Keeps floating text (popups, speech bubbles, the 3D battle's HP bars) inside
# the screen, clear of the HUD: the player's corner (portrait, Run / Items, HP),
# the turn message at the top, the enemies' panel top-right, the Skip /
# Target buttons and the phone's touch buttons / joystick. All rects are in
# screen pixels (the CanvasLayer space).
#   HudLayout.fit(rect, viewport, others) -> the new top-left for rect
#   others = more rects to keep clear of (older popups, bubbles...)

const MARGIN = 10.0
const GAP = 6.0

static func _tm(vp: Viewport):
	return vp.get_tree().root.get_node_or_null("TurnManager") if vp and vp.is_inside_tree() else null

static func _shown(c) -> bool:
	return c is Control and is_instance_valid(c) and c.is_visible_in_tree() and c.size.x > 0.0

# The player's corner: portrait, Run / Items (and the Zeal timer), HP bar,
# the party's rows under it (party_hud.gd)
static func player_corner(vp: Viewport) -> Rect2:
	var r = Rect2()
	var tm = _tm(vp)
	var player = vp.get_tree().get_first_node_in_group("player") if vp.is_inside_tree() else null
	var parts = []
	if tm:
		parts += [tm.run_button, tm.items_button]
	if player:
		for n in ["portrait", "hp_bar", "party_hud"]:
			if n in player:
				parts.append(player.get(n))
		if "hp_bar" in player and is_instance_valid(player.hp_bar):
			parts.append(player.hp_bar.get_parent().get_node_or_null("TimerLabel"))
	for c in parts:
		if _shown(c):
			var cr = c.get_global_rect()
			r = cr if r.size == Vector2.ZERO else r.merge(cr)
	return r

static func blockers(vp: Viewport, with_title := true) -> Array:
	var list = []
	var corner = player_corner(vp)
	if corner.size != Vector2.ZERO:
		list.append(corner.grow(GAP))
	var tm = _tm(vp)
	if tm:
		if with_title and _shown(tm.turn_label) and tm.turn_label.text != "":
			list.append(title_rect(tm.turn_label).grow(GAP))
		if _shown(tm.enemy_hud):
			list.append(tm.enemy_hud.get_global_rect().grow(GAP))
		for b in [tm.skip_button, tm.target_button]:
			if _shown(b):
				list.append(b.get_global_rect().grow(GAP))
	# the phone's on-screen buttons and joystick (touch_controls.gd)
	var tc = vp.get_tree().root.get_node_or_null("TouchControls") if vp.is_inside_tree() else null
	if tc and tc.has_method("screen_rects"):
		for r in tc.screen_rects():
			list.append(r.grow(GAP))
	return list

# Where the turn message's text actually is (the label is wider than it)
static func title_rect(label: Label) -> Rect2:
	var r = label.get_global_rect()
	var font = label.get_theme_font("font")
	var fs = label.get_theme_font_size("font_size")
	var w = r.size.x
	if font and not label.autowrap_mode:
		w = min(w, font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 12.0)
	return Rect2(r.position.x + (r.size.x - w) / 2.0, r.position.y, w, r.size.y)

# A spot for rect: inside the screen (with a margin), not over the HUD or
# others. Moves it down past what it hits; if that runs off the bottom, above
# it instead; if neither fits, beside it.
static func fit(rect: Rect2, vp: Viewport, others := [], with_title := true) -> Vector2:
	var screen = vp.get_visible_rect().size
	var avoid = blockers(vp, with_title) + others
	var p = _clamp(rect.position, rect.size, screen)
	for i in 12:
		var hit = null
		for b in avoid:
			if Rect2(p, rect.size).intersects(b):
				hit = b
				break
		if hit == null:
			return p
		var down = Vector2(p.x, hit.end.y + GAP)
		var up = Vector2(p.x, hit.position.y - rect.size.y - GAP)
		if down.y + rect.size.y <= screen.y - MARGIN:
			p = down
		elif up.y >= MARGIN:
			p = up
		else:
			var left = Vector2(hit.position.x - rect.size.x - GAP, p.y)
			var right = Vector2(hit.end.x + GAP, p.y)
			p = left if left.x >= MARGIN else right
		p = _clamp(p, rect.size, screen)
	# boxed in (e.g. between the touch buttons and other popups): the nearest
	# free spot, else at least clear of the HUD / buttons
	for list in [avoid, blockers(vp, with_title)]:
		var best = _nearest_free(rect, screen, list)
		if best != null:
			return best
	return p

static func _nearest_free(rect: Rect2, screen: Vector2, avoid: Array):
	var start = _clamp(rect.position, rect.size, screen)
	var best = null
	var best_d = INF
	for dy in range(-int(screen.y), int(screen.y), 12):
		for dx in [0, -80, 80, -160, 160, -240, 240, -360, 360]:
			var q = _clamp(start + Vector2(dx, dy), rect.size, screen)
			var d = q.distance_squared_to(rect.position) + abs(dx) * 40.0   # prefer moving up / down
			if d >= best_d:
				continue
			var r = Rect2(q, rect.size)
			if avoid.all(func(b): return not r.intersects(b)):
				best = q
				best_d = d
	return best

static func _clamp(p: Vector2, size: Vector2, screen: Vector2) -> Vector2:
	p.x = clamp(p.x, MARGIN, max(MARGIN, screen.x - size.x - MARGIN))
	p.y = clamp(p.y, MARGIN, max(MARGIN, screen.y - size.y - MARGIN))
	return p

# The floating popups showing now (screen rects), oldest first
static func popup_rects(vp: Viewport, except = null) -> Array:
	var list = []
	if not vp.is_inside_tree():
		return list
	for l in vp.get_tree().get_nodes_in_group("float_popups"):
		if l != except and is_instance_valid(l) and l.is_visible_in_tree() and l.has_meta("screen_rect"):
			list.append(l.get_meta("screen_rect"))
	return list

static func bubble_rects(vp: Viewport, except = null) -> Array:
	var list = []
	if not vp.is_inside_tree():
		return list
	for b in vp.get_tree().get_nodes_in_group("speech_bubbles"):
		if b != except and b.is_showing():
			list.append(Rect2(b.panel.position, b.panel.size).grow(GAP))
	return list
