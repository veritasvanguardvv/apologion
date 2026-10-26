extends CharacterBody2D
# Party member (used by pastor_ramuel.tscn and baana.tscn)
# ------------------------------------------
# Follows the player a moment behind them, and fights in turn-based battles
# (see turn_manager.gd). On his turn he recites a random verse from ALL the
# verses (he knows them all). His recital never discovers a verse for the
# player - the player still has to type it. The verse's effect is run by the player's own
# cast_verse() (character_body_2d.gd), so it works like when the
# player types it, except:
#   - it does NOT use up the player's verse cycle (VerseManager isn't touched)
#   - attack damage AND healing are multiplied by damage_scale (25%)
#   - he always uses the default targets (all enemies / you + him, split),
#     never the one you chose with Alt (that's for your own verses)
#
# HP: party members have their own health, shown top-left under the player's
# (party_hud.gd: portrait + HP bar; nothing floats over their heads).
# Enemies sometimes attack them (party_target_chance in enemy.gd). At 0 HP
# they're knocked out: they skip their turns until a healing verse brings
# them back. Their HP is kept between levels and in the save, and goes back
# to full when a level is started fresh.
#
# Everything with @export can be changed in the Inspector when you click the
# party member's root node in pastor_ramuel.tscn (or in a level).
#
# Only one party member is with you at a time (see party_manager.gd).
#
# Sprites: two Sprite2D nodes under "Visual" - IdleSprite and WalkSprite.
# Only one is shown at a time. You can move/scale each one in the editor so
# they line up (the node's origin = where his feet touch the floor).

@export var display_name = "Pastor Ramuel"
# true = a friend controls this party member from their PHONE (see
# phone_server.gd and phone_player.tscn). On their battle turn they type or
# say a verse on the phone instead of the computer picking one.
@export var player_controlled = false
var phone_slot = 0              # 1, 2 or 3 (which phone player this is)

@export_group("Following")
@export var follow_distance = 90.0     # how far behind the player he walks (pixels)
@export var follow_delay = 0.35        # he reacts this many seconds after the player moves
@export var move_speed = 200.0         # same as the player's normal speed
@export var catch_up_speed = 320.0     # used when he's far behind
@export var acceleration = 900.0       # how quickly he speeds up / eases to a stop
# Pastor Ramuel never jumps (can_jump off). When he can't walk to the player (a gap, a ledge, a wall),
# falls behind or ends up off screen, he catches up WITHOUT fading (he's always
# fully solid): as soon as he's out of view he's moved to the floor just past
# the edge of the screen behind the player, and walks back in. If he's stuck
# where you can see him he waits (you'll usually walk on and leave him out of
# view a moment later); only after stuck_snap_time seconds (in view, or with no
# walkable way back in from off screen) does he simply step over beside the player.
@export var can_jump = false            # Baana (baana.tscn) still jumps gaps and ledges
@export var jump_velocity = -450.0     # (only with can_jump) negative = up
@export var stranded_time = 0.6        # seconds stuck before he catches up (once he's out of view)
@export var stuck_snap_time = 4.0      # stuck this long (and no hidden way in): he steps over next to the player anyway
@export var offscreen_margin = 70.0    # how far past the screen edge he's placed to walk back in
@export var gravity = 980.0            # same as the player
@export var teleport_distance = 700.0  # if he's this far away (or falls in a pit) he pops over next to the player

@export_group("Fighting")
@export var battle_speed = 8           # lower than the player's 10, so he acts right after you
@export var damage_scale = 0.25        # 0.25 = a quarter of the verse's normal damage (and healing)
@export var max_hp = 100
@export var hp_bar_width = 70.0        # the small health bar above the head

@export_group("Speech bubble")
@export var bubble_max_width = 340.0     # the bubble wraps text wider than this (pixels)
@export var bubble_min_time = 2.5        # shortest time the bubble stays up (seconds)
@export var bubble_time_per_char = 0.06  # extra time per letter, so long verses stay longer
@export var bubble_max_time = 6.0        # longest time the bubble stays up
@export var bubble_head_offset = -114.0   # where his head is, above his feet (pixels)

@export_group("Sprite")
@export var sprite_faces_right = true  # the Pastor art faces right
@export var idle_fps = 2.0             # idle animation speed (frames per second)
@export var walk_fps = 12.0            # walk animation speed
@export var idle_frame_count = 2       # frames used in Pastor_idle.png
@export var walk_frame_count = 12      # frames used in Pastor_walk.png (3 rows of 4)
@export var idle_first_frame = 0       # first idle frame in the sheet (Baana's sheet has idle frames at 3-4)
@export var walk_first_frame = 0       # first walk frame in the sheet

@export_group("Footsteps")
# A footstep sound every stride_length pixels he walks on the ground (about
# every 0.3 s at walking speed, quicker when he runs to catch up). Counting
# distance instead of animation frames means a step always plays while he
# moves, whatever the walk sheet looks like. Non-positional player (same
# volume wherever the camera is), on the SFX bus (the Settings slider).
# Only one step sound at a time, so they never stack.
@export var footsteps_enabled = false      # on for Pastor Ramuel (pastor_ramuel.tscn)
@export var stride_length = 60.0           # pixels per step (move_speed 200 x 0.3 s)
@export var footstep_volume_db = 0.0
@export var footstep_log = false           # print every step (bus, volume) to the Output panel
const FOOTSTEP_SOUNDS = [
	"res://General/Sounds/footsteps/footstep_01.wav", "res://General/Sounds/footsteps/footstep_02.wav",
	"res://General/Sounds/footsteps/footstep_03.wav", "res://General/Sounds/footsteps/footstep_04.wav",
	"res://General/Sounds/footsteps/footstep_05.wav", "res://General/Sounds/footsteps/footstep_06.wav",
	"res://General/Sounds/footsteps/footstep_07.wav", "res://General/Sounds/footsteps/footstep_08.wav",
	"res://General/Sounds/footsteps/footstep_09.wav", "res://General/Sounds/footsteps/footstep_10.wav",
]
var footstep_player: AudioStreamPlayer
var stride_left = 0.0           # pixels until the next step
var footsteps_played = 0        # (counted for the tests)

# Emitted every time he recites (handy for sound effects later)
signal recited(verse_ref)

var player = null
var trail = []               # recent player positions: [time, position, facing]
var clock = 0.0              # seconds since he appeared (game time)
var anim_time = 0.0

@onready var visual = $Visual
@onready var idle_sprite = $Visual/IdleSprite
@onready var walk_sprite = $Visual/WalkSprite
# Speech bubble (white, see speech_bubble.gd). Built in _ready.
var bubble
const PopupText = preload("res://popup_text.gd")
var hp = 100.0
var knocked_out = false
var member_id = ""            # "ramuel" / "baana" / "phone_1"... (see party_manager.gd)
var hp_bar: ProgressBar


func _ready():
	add_to_group("party")   # TurnManager puts everyone in "party" into battles
	if member_id == "":
		member_id = PartyManager.id_for_scene(scene_file_path)
	hp = PartyManager.get_hp(member_id, max_hp)
	_build_hp_bar()
	if player_controlled:
		_build_name_label()
	TurnManager.battle_ended.connect(_end_phone_turn.bind(0.0))
	TurnManager.round_ended.connect(_on_round_ended)
	TurnManager.battle_ended.connect(_on_battle_over)
	bubble = preload("res://speech_bubble.gd").new()
	bubble.set_light_style()   # party members and the player have white bubbles
	bubble.target = self
	bubble.head_offset = Vector2(0, bubble_head_offset)
	bubble.max_width = bubble_max_width
	add_child(bubble)
	if footsteps_enabled:
		_build_footsteps()
	_update_animation(0.0)


func _build_footsteps():
	var random = AudioStreamRandomizer.new()
	random.random_pitch = 1.08
	random.random_volume_offset_db = 1.0
	for path in FOOTSTEP_SOUNDS:
		var stream = load(path)
		if stream:
			random.add_stream(-1, stream)
		else:
			push_warning("Footstep sound missing: " + path)
	footstep_player = AudioStreamPlayer.new()
	footstep_player.name = "Footsteps"
	footstep_player.stream = random
	footstep_player.bus = "SFX"            # the SFX volume slider in Settings
	footstep_player.volume_db = footstep_volume_db
	footstep_player.max_polyphony = 1      # a new step cuts the last one off
	add_child(footstep_player)
	stride_left = stride_length * 0.5      # first step soon after he starts walking

# Called every physics frame: counts the distance he walks on the ground
func _update_footsteps(delta):
	if footstep_player == null:
		return
	var speed = abs(velocity.x)
	if not is_on_floor() or speed < 20.0 or knocked_out:
		stride_left = min(stride_left, stride_length * 0.5)   # standing/jumping: next step comes quickly once he walks again
		return
	stride_left -= speed * delta
	if stride_left <= 0.0:
		# longer strides when he runs to catch up (so the steps don't chatter)
		stride_left += stride_length * sqrt(max(1.0, speed / move_speed))
		_play_footstep()

func _play_footstep():
	footstep_player.play()
	footsteps_played += 1
	if footstep_log or footsteps_played == 1:
		var bus = AudioServer.get_bus_index(footstep_player.bus)
		print("[Footsteps] step %d: stream=%s bus=%s(#%d) bus_db=%.1f muted=%s master_db=%.1f master_muted=%s volume_db=%.1f playing=%s" % [
			footsteps_played, footstep_player.stream.streams_count if footstep_player.stream else 0,
			footstep_player.bus, bus, AudioServer.get_bus_volume_db(bus), AudioServer.is_bus_mute(bus),
			AudioServer.get_bus_volume_db(0), AudioServer.is_bus_mute(0), footstep_player.volume_db, footstep_player.playing])


# Finds the player once it exists (it's in the "player" group).
func _find_player():
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")
		trail.clear()
		if player:
			# Don't bump into the player
			add_collision_exception_with(player)
	return player


func _physics_process(delta):
	if not _find_player():
		return
	
	# --- Follow delay: remember where the player was a moment ago ---
	clock += delta
	var now = clock
	var facing = 1
	if trail.size() > 0:
		facing = trail[-1][2]
	if player.velocity.x > 0:
		facing = 1
	elif player.velocity.x < 0:
		facing = -1
	trail.append([now, player.get_body_center(), facing])
	# Drop entries older than follow_delay (keep the oldest one we still need)
	while trail.size() > 1 and trail[1][0] <= now - follow_delay:
		trail.pop_front()
	var delayed_pos = trail[0][1]
	var delayed_facing = trail[0][2]
	
	var player_pos = player.get_body_center()   # where the player is right now
	var target_x = delayed_pos.x - (_battle_distance() if TurnManager.in_battle else follow_distance) * delayed_facing
	var dx = target_x - global_position.x
	
	# Gravity, like the player
	if not is_on_floor():
		velocity.y += gravity * delta
	
	if is_on_floor():
		var desired = 0.0
		# (He keeps walking to his spot behind the player even during a battle,
		# so the party lines up; only the player is frozen.)
		if abs(dx) > 4.0:
			var top_speed = catch_up_speed if abs(dx) > 200.0 else move_speed
			# Slow down as he gets close, so he eases to a stop
			desired = sign(dx) * min(top_speed, abs(dx) * 4.0)
		velocity.x = move_toward(velocity.x, desired, acceleration * delta)
		
		var direction = sign(desired)
		var blocked = false
		if direction != 0 and abs(dx) > 60.0:
			var player_ahead = (player_pos.x - global_position.x) * direction
			if _gap_ahead(direction):
				if can_jump and player_ahead > 150.0:
					velocity.y = jump_velocity     # (Baana) jump the gap at full speed
					velocity.x = direction * catch_up_speed
				else:
					# A pit in front of him: he waits at the edge
					velocity.x = 0
					# (stranded if the player is on the other side)
					blocked = player_ahead > 150.0
			elif can_jump and (is_on_wall() or player_pos.y < global_position.y - 120.0):
				velocity.y = jump_velocity         # (Baana) over the obstacle / up to the player
			elif is_on_wall() and abs(get_real_velocity().x) < 10.0:
				blocked = true   # a wall or ledge in the way
		# The player is up on a ledge (or down below) and he can't get there
		if not can_jump and abs(player_pos.y - global_position.y) > 140.0 and abs(dx) > 60.0:
			blocked = true
		stranded_for = stranded_for + delta if blocked else 0.0
	# (in the air he only falls - he never jumps)
	
	move_and_slide()
	_update_footsteps(delta)
	
	# Stranded, too far, fell down a pit or simply out of view: catch up.
	# Never fades; he's only moved while you can't see him (see the top).
	var on_screen = _on_screen()
	offscreen_for = offscreen_for + delta if not on_screen else 0.0
	relocate_cooldown = max(relocate_cooldown - delta, 0.0)
	var needs_catch_up = stranded_for >= stranded_time or offscreen_for >= 1.0 \
			or global_position.distance_to(player_pos) > teleport_distance \
			or global_position.y > player_pos.y + 250.0
	stuck_for = stuck_for + delta if needs_catch_up else 0.0
	# Only when the player stands on solid ground (not mid-jump or falling)
	if needs_catch_up and relocate_cooldown <= 0.0 and player.is_on_floor():
		var spot = null
		if not on_screen:
			spot = _offscreen_spot_behind_player(delayed_facing)
		# Still stuck after stuck_snap_time (in view, or no walkable way in from
		# off screen, e.g. a pit right behind the player): step over beside them
		if spot == null and stuck_for >= stuck_snap_time:
			spot = _spot_near_player(delayed_facing)
		if spot != null:
			_move_to(spot)
	
	_update_animation(delta)
	if guard_shadow:
		guard_shadow.update(delta)   # (after the animation: it may hold the ducking frame)


# In a battle the party spreads out a bit more (one behind the other,
# battle_spacing apart - less with a big party), so everyone's own wings,
# bubble and status tag stay clear of the next one's.
@export var battle_spacing = 160.0
func _battle_distance() -> float:
	var members = get_tree().get_nodes_in_group("party")
	members.sort_custom(func(a, b): return a.follow_distance < b.follow_distance)
	var rank = members.find(self)
	var gap = clamp(640.0 / max(members.size(), 1), 90.0, battle_spacing)
	return max(follow_distance, gap * (rank + 1))

var stranded_for = 0.0
var offscreen_for = 0.0
var stuck_for = 0.0
var relocate_cooldown = 0.0
var catch_ups = 0      # how often he was moved over (for the tests)

func _on_screen() -> bool:
	var screen = get_viewport().get_visible_rect().grow(40)
	return screen.has_point(get_global_transform_with_canvas() * Vector2(0, -40))

# The part of the level the camera shows right now (world coordinates)
func _visible_world_rect() -> Rect2:
	var vp = get_viewport()
	return vp.get_canvas_transform().affine_inverse() * vp.get_visible_rect()

# Instantly moves him (no fade - he's always fully visible) and resets the
# follow state. Called while he's off screen, so nobody sees the move.
func _move_to(spot: Vector2):
	global_position = spot
	velocity = Vector2.ZERO
	trail.clear()
	stranded_for = 0.0
	offscreen_for = 0.0
	stuck_for = 0.0
	relocate_cooldown = 0.8
	catch_ups += 1
	visual.modulate.a = 1.0
	print(display_name, " catches up (walks in from off screen) at ", global_position)

# Floor height at x near height y (the top of the first floor below
# y - 150, within 400 px), or null.
func _floor_at(x: float, y: float):
	var from = Vector2(x, y - 150.0)
	var query = PhysicsRayQueryParameters2D.create(from, from + Vector2(0, 400))
	query.exclude = [get_rid(), player.get_rid()]
	query.collision_mask = collision_mask
	var hit = get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or hit.normal.y > -0.5:
		return null
	return hit.position.y

# A spot on the floor just past the edge of the screen behind the player
# (or ahead, if there's no way back there) from which he can WALK to the
# player: the floor in between has no gaps and no steps he can't walk up.
# null = no such spot right now (then he simply waits off screen).
func _offscreen_spot_behind_player(facing):
	var center = player.get_body_center()
	var feet = _floor_at(center.x, center.y)
	if feet == null:
		return null
	var view = _visible_world_rect()
	for dir in [-facing, facing]:
		var edge_x = view.position.x - offscreen_margin if dir < 0 else view.end.x + offscreen_margin
		var last_y = feet
		var x = center.x
		var ok = true
		var step = 25.0 * dir
		while (x - edge_x) * dir < 0.0:
			x += step
			if (x - edge_x) * dir > 0.0:
				x = edge_x
			var y = _floor_at(x, last_y)
			if y == null or abs(y - last_y) > 30.0:
				ok = false
				break
			last_y = y
		if ok:
			return Vector2(edge_x, last_y - 1.0)
	return null

# A spot on solid floor beside the player: behind them if there's floor
# there, else in front, else right where they stand. null = no floor there.
func _spot_near_player(facing):
	var center = player.get_body_center()
	var space = get_world_2d().direct_space_state
	for x in [center.x - follow_distance * facing, center.x + follow_distance * facing, center.x - 40.0 * facing, center.x]:
		var from = Vector2(x, center.y - 30.0)
		var query = PhysicsRayQueryParameters2D.create(from, from + Vector2(0, 220))
		query.exclude = [get_rid(), player.get_rid()]
		query.collision_mask = collision_mask
		var hit = space.intersect_ray(query)
		if not hit.is_empty() and hit.normal.y < -0.5 and hit.position.y < center.y + 80.0:   # level with the player's feet, not down a pit
			return hit.position - Vector2(0, 1)
	return null

# True if there's no floor a little way ahead of him.
func _gap_ahead(direction) -> bool:
	var from = global_position + Vector2(direction * 50.0, -20.0)
	var query = PhysicsRayQueryParameters2D.create(from, from + Vector2(0, 140))
	query.exclude = [get_rid(), player.get_rid()]
	query.collision_mask = collision_mask
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()


# Shows the walk or idle sprite and steps through its frames.
func _update_animation(delta):
	var walking = abs(velocity.x) > 5.0
	idle_sprite.visible = not walking
	walk_sprite.visible = walking
	anim_time += delta
	if walking:
		walk_sprite.frame = walk_first_frame + int(anim_time * walk_fps) % walk_frame_count
		# Mirror the whole Visual node so both sprites flip around his feet
		_face(1 if velocity.x > 0 else -1)
	else:
		idle_sprite.frame = idle_first_frame + int(anim_time * idle_fps) % idle_frame_count
		# Standing in a battle: face the enemies, like the player does. (He
		# backs up to his battle spot behind the player, so the last walking
		# direction would leave him looking away from the fight.)
		var toward = battle_facing()
		if toward != 0:
			_face(toward)

# 1 = look right, -1 = look left (mirrors the Visual node; the 3D boss view
# copies this flip from the 2D sprite)
func _face(dir: int):
	visual.scale.x = 1 if (dir > 0) == sprite_faces_right else -1

# Which way the enemies are during a battle: 1 = right, -1 = left, 0 = no
# battle (or no enemies left) - then he keeps his last walking direction.
func battle_facing() -> int:
	if not TurnManager.in_battle:
		return 0
	var enemies = Targeting.battle_enemies()
	if enemies.is_empty():
		return 0
	var x = 0.0
	for e in enemies:
		x += e.global_position.x
	x /= enemies.size()
	return 1 if x >= global_position.x else -1


# ---------------- Battle turns ----------------

# Called by TurnManager when it's his turn in a battle. Returns how long the
# speech bubble stays up, so TurnManager waits before the next turn.
func take_turn():
	if knocked_out:
		TurnManager.show_message(tr("%s is knocked out...") % display_name)
		return 0.0
	if not recite_random_verse():
		return _say("", "...")
	return bubble_time_left


# Picks a random ON-THEME verse and runs its effect on the nearest enemy in
# the current battle. Returns true if he recited. (See "Stay on theme" below:
# in the Greed level he only ever says Greed verses, never e.g. a Lust one.)
func recite_random_verse() -> bool:
	if not _find_player():
		return false
	if Targeting.battle_enemies().is_empty():
		return false
	
	# Nothing here calls VerseManager, so his recital does NOT discover the
	# verse for the player.
	if player.all_verses.is_empty():
		return false
	# The player is at 50% HP or less: heal them first (a heal verse, all of
	# its healing on the player). No heal verse -> the usual on-theme verse.
	var verse = pick_player_heal_verse() if player_needs_heal() else null
	var healing_player = verse != null
	if verse == null:
		verse = pick_attack_verse()
	if verse == null:
		return false   # nothing on theme (never a random off-theme verse)
	
	# Use the same language as the game so the effect matches
	var text = player.verse_body(verse)
	# Default targets (use_choice = false), 25% damage and 25% healing
	if healing_player:
		player.forced_heal_targets = [player]
	# (their attack: 25% of the verse, x their own Faith / Zeal)
	player.cast_verse(verse, damage_scale * attack_multiplier(), false, false, damage_scale, self)
	player.forced_heal_targets = []
	
	print(display_name, " recites ", verse.ref, " (healing you: you were at %d%%)" % roundi(100.0 * player.hp / player.max_hp) if healing_player else "")
	_say(VerseManager.ref_text(verse.ref), text.substr(0, 1).to_upper() + text.substr(1))
	recited.emit(verse.ref)
	return true


# ---------------- Heal the player first ----------------
# On his turn, if the player's HP is at or below heal_player_below (50%),
# Ramuel / Baana recite a HEAL verse on the player instead of a random one.
# Above 50% they never pick one on purpose (no heal spam). Phone players are
# people: they choose for themselves.
@export var heal_player_below = 0.5

func player_needs_heal() -> bool:
	return _find_player() and player.max_hp > 0 and player.hp > 0 and player.hp <= player.max_hp * heal_player_below

# A verse that heals (and never costs HP). The strongest heals are picked
# most: a random one among the top heals.
func pick_player_heal_verse():
	var sins = battle_theme_sins()
	var heals = player.all_verses.filter(func(v): return _heal_amount(v) > 0 and _theme_ok_for_heal(v, sins))
	if heals.is_empty():
		return null
	heals.sort_custom(func(a, b): return _heal_amount(a) > _heal_amount(b))
	return heals.slice(0, max(5, heals.size() / 4)).pick_random()

func _heal_amount(v) -> float:
	if v.get("set", "") == "sheet":
		return float(v.get("heal", 0))
	return float(v.get("heal", 0)) if v.get("type", "") == "heal" else 0.0

# ---------------- Stay on theme ----------------
# AI party members (Pastor, Ramuel, Baana) only say verses that fit the fight:
#   - On a sin level (Greed.tscn, Sloth.tscn, Lust.tscn, Gluttony.tscn...) the
#     level's sin: in the Greed level ONLY Greed verses, never a Lust one.
#   - Elsewhere (Endless...) the sin(s) of the enemies he's attacking.
#   - No sin at all (e.g. only atheist goats in Endless): a Universal verse
#     ("All Sin" damage, not about any one sin).
# A verse "is" a sin's verse when that sin is its strongest one on the sheet
# (ties count), so a mostly-Lust verse with a small Greed % is NOT a Greed verse.
# His heal-the-player verses are healing verses that aren't about another sin.

# The sins his verses must be about right now ([] = no sin: Universal only)
func battle_theme_sins() -> Array:
	var sin = player.level_sin() if player and player.has_method("level_sin") else ""
	if sin != "":
		return [sin]
	var out = []
	for e in Targeting.attack_targets(false):
		if is_instance_valid(e) and e.has_method("enemy_sins"):
			for t in e.enemy_sins():
				if t in preload("res://character_body_2d.gd").SINS and not t in out:
					out.append(t)
	return out

# The verse's main sin(s): its strongest sin % (ties -> several), or for a
# built-in verse its type if that's a sin. [] = not about any sin.
static func verse_main_sins(v) -> Array:
	var out = []
	if v.get("set", "") == "sheet":
		var sins: Dictionary = v.get("sins", {})
		var best = 0.0
		for s in sins:
			best = max(best, float(sins[s]))
		if best > 0:
			for s in sins:
				if float(sins[s]) == best:
					out.append(s)
		return out
	var t = v.get("type", "")
	if t in preload("res://character_body_2d.gd").SINS:
		out.append(t)
	return out

# Every sin % the verse has (built-in: its type if it's a sin)
static func verse_any_sins(v) -> Array:
	if v.get("set", "") == "sheet":
		var out = []
		for s in v.get("sins", {}):
			if float(v.sins[s]) > 0:
				out.append(s)
		return out
	return verse_main_sins(v)

# An attack verse he may say: its main sin is one of `sins`. With no sins
# (unthemed fight): a Universal verse that isn't about any sin.
static func is_on_theme_attack(v, sins: Array) -> bool:
	if sins.is_empty():
		var universal = float(v.get("all_damage", 0)) > 0 or v.get("type", "") == "all"
		return universal and verse_any_sins(v).is_empty()
	for s in verse_main_sins(v):
		if s in sins:
			return true
	return false

# A heal verse he may say: not about any sin, or about the fight's sin
static func _theme_ok_for_heal(v, sins: Array) -> bool:
	var main = verse_main_sins(v)
	if main.is_empty():
		return verse_any_sins(v).is_empty() or sins.is_empty()
	for s in main:
		if s in sins:
			return true
	return false

# His attack verse: a random on-theme one, preferring ones that actually hurt
# who he's hitting (e.g. the few Greed verses that hurt SinDeath). Falls back
# to a Universal verse if the theme has none - never an off-theme verse.
func pick_attack_verse():
	var sins = battle_theme_sins()
	var pool = player.all_verses.filter(func(v): return is_on_theme_attack(v, sins) and not _hurts_caster(v))
	if pool.is_empty():
		pool = player.all_verses.filter(func(v): return is_on_theme_attack(v, []) and not _hurts_caster(v))
	if pool.is_empty():
		return null
	var targets = Targeting.attack_targets(false)
	if not targets.is_empty() and player.has_method("verse_damage_against"):
		var hurting = pool.filter(func(v):
			for e in targets:
				if is_instance_valid(e) and player.verse_damage_against(v, e) > 0:
					return true
			return false)
		if not hurting.is_empty():
			pool = hurting
	return pool.pick_random()

# A sheet verse with a negative heal costs the caster HP (he avoids those)
static func _hurts_caster(v) -> bool:
	return v.get("set", "") == "sheet" and float(v.get("heal", 0)) < 0


var bubble_time_left = 0.0

# Shows a speech bubble with the reference (title) and text above the head.
# Returns how many seconds it will stay up (longer text stays up longer).
func _say(title: String, text: String) -> float:
	bubble_time_left = clamp(bubble_time_per_char * (title.length() + text.length()), bubble_min_time, bubble_max_time)
	bubble.say(title, text, false, bubble_time_left)
	return bubble_time_left


func _process(delta):
	bubble_time_left = max(bubble_time_left - delta, 0.0)
	_process_phone_turn(delta)


# ---------------- Health ----------------

func _build_hp_bar():
	hp_bar = ProgressBar.new()
	hp_bar.name = "HPBar"
	hp_bar.show_percentage = false
	hp_bar.max_value = max_hp
	hp_bar.size = Vector2(hp_bar_width, 10)
	hp_bar.position = Vector2(-hp_bar_width / 2.0, bubble_head_offset + 4)
	var fill = StyleBoxFlat.new()
	fill.bg_color = Color(0.35, 0.85, 0.4)
	hp_bar.add_theme_stylebox_override("fill", fill)
	var back = StyleBoxFlat.new()
	back.bg_color = Color(0.1, 0.1, 0.1, 0.8)
	hp_bar.add_theme_stylebox_override("background", back)
	# Not drawn over the head any more: the party's HP shows in the top-left
	# HUD (party_hud.gd). The bar is kept (hidden) as their HP's value holder.
	hp_bar.visible = false
	add_child(hp_bar)
	_update_hp()

var base_modulate = null   # the Visual's own tint (Baana is golden)

func _update_hp():
	hp_bar.value = hp
	knocked_out = hp <= 0.0
	# Knocked out: darker and lying down (never see-through)
	if base_modulate == null:
		base_modulate = visual.modulate
	visual.modulate = base_modulate.darkened(0.45) if knocked_out else base_modulate
	visual.modulate.a = 1.0
	visual.rotation_degrees = 90.0 if knocked_out else 0.0
	PartyManager.set_hp(member_id, hp)

# ---------------- Their own statuses ----------------
# Every party member (Ramuel, Baana, each phone player) has their OWN Guard,
# Faith, Wisdom and Zeal, like the player (character_body_2d.gd): from the
# verses they recite, or a support verse a phone player aims at them.
#   Guard  = enemies do guard_reduction less damage to them (+ their wings)
#   Faith  = their attack +%, Zeal = their attack +/-% (a negative Zeal up is
#            a penalty), see attack_multiplier()
#   Wisdom = the chance to dodge an enemy's hit (at most the player's evasion_max)
# Each lasts 3 battle rounds; a battle's end clears them. They show in a
# small tag over the head (status_tag), the player's own in the HUD row.
var guard_rounds_left = 0
var guard_reduction = 0.5
var guard_rounds = 3
var guard_fx: AnimatedSprite2D   # the same wings/dome animation as the player's
var faith_bonus = 0.0            # 0.5 = +50% attack
var faith_rounds_left = 0
var wisdom = 0.0                 # 0..100 (%)
var wisdom_rounds_left = 0
var zeal = 0.0                   # -75..100 (%)
var zeal_rounds_left = 0
const STATUS_ROUNDS = 3
var status_tag: Label
var dodges = 0                   # (counted for the tests)

func activate_guard(rounds := 3, reduction := 0.5):
	guard_rounds_left = rounds
	guard_rounds = rounds
	guard_reduction = reduction
	# Their own pair of wings (sized to them), played once, then see-through while
	# the guard lasts (like the player's, character_body_2d.gd)
	if guard_fx == null:
		_build_guard_fx()
	_update_status_tag()
	guard_fx.visible = true
	guard_fx.modulate.a = player.guard_play_opacity if _find_player() else 0.8   # (the player's wing opacities)
	guard_fx.frame = 0
	guard_fx.play("guard")
	print(display_name, ": Guard up for ", rounds, " rounds")

func activate_faith(amount := 0.5):
	var cap = player.faith_max if _find_player() else 1.0
	faith_bonus = min((faith_bonus if faith_rounds_left > 0 else 0.0) + amount, cap)
	faith_rounds_left = STATUS_ROUNDS
	_update_status_tag()
	print(display_name, ": Faith attack +", int(faith_bonus * 100), "%")

func add_wisdom(amount: float):
	var cap = player.wisdom_max if _find_player() else 100.0
	wisdom = min((wisdom if wisdom_rounds_left > 0 else 0.0) + amount, cap)
	wisdom_rounds_left = STATUS_ROUNDS
	_update_status_tag()
	print(display_name, ": Wisdom ", int(wisdom), "%")

func add_zeal(pct: float):
	var lo = player.zeal_min if _find_player() else -75.0
	var hi = player.zeal_max if player else 100.0
	zeal = clamp((zeal if zeal_rounds_left > 0 else 0.0) + pct, lo, hi)
	zeal_rounds_left = STATUS_ROUNDS if zeal != 0.0 else 0
	_update_status_tag()
	print(display_name, ": Zeal ", int(zeal), "%")

# Their attack verses' damage: 1 + Faith + Zeal
func attack_multiplier() -> float:
	return max(1.0 + faith_bonus + zeal / 100.0, 0.0)

# Their dodge chance (0..1): the wisdom %, at most the player's evasion_max
func evasion_chance() -> float:
	var cap = player.evasion_max if _find_player() else 75.0
	return min(wisdom, cap) / 100.0

var dodge_override = -1.0   # (tests: 1 = always dodge, 0 = never)

# An enemy's attack on them: their Wisdom may dodge it. -1 = dodged.
func enemy_hit(amount) -> float:
	var roll_ok = randf() < evasion_chance() if dodge_override < 0 else dodge_override >= 1.0
	if amount > 0 and roll_ok:
		dodges += 1
		PopupText.spawn(self, tr("Dodged!"), Color(0.6, 0.95, 1.0), Vector2(0, -60))
		print(display_name, " dodged (wisdom ", int(wisdom), "%)")
		return -1.0
	return take_damage(amount)

func _on_round_ended():
	if guard_rounds_left > 0:
		guard_rounds_left -= 1
	if faith_rounds_left > 0:
		faith_rounds_left -= 1
		if faith_rounds_left == 0:
			faith_bonus = 0.0
	if wisdom_rounds_left > 0:
		wisdom_rounds_left -= 1
		if wisdom_rounds_left == 0:
			wisdom = 0.0
	if zeal_rounds_left > 0:
		zeal_rounds_left -= 1
		if zeal_rounds_left == 0:
			zeal = 0.0
	_update_status_tag()

# Their statuses, for the bench (party_manager.gd switch_in): whoever is
# switched out keeps them for if they come back in this battle
func battle_status() -> Dictionary:
	return {
		guard_rounds_left = guard_rounds_left, guard_rounds = guard_rounds, guard_reduction = guard_reduction,
		faith_bonus = faith_bonus, faith_rounds_left = faith_rounds_left,
		wisdom = wisdom, wisdom_rounds_left = wisdom_rounds_left,
		zeal = zeal, zeal_rounds_left = zeal_rounds_left,
	}

func restore_battle_status(st: Dictionary):
	faith_bonus = st.faith_bonus; faith_rounds_left = st.faith_rounds_left
	wisdom = st.wisdom; wisdom_rounds_left = st.wisdom_rounds_left
	zeal = st.zeal; zeal_rounds_left = st.zeal_rounds_left
	if st.guard_rounds_left > 0:
		activate_guard(st.guard_rounds_left, st.guard_reduction)   # (their wings come back)
		guard_rounds = st.guard_rounds
	_update_status_tag()

func save_hp():
	PartyManager.set_hp(member_id, hp)

# Look at the enemies right away (a member switched in mid-battle)
func face_battle():
	var toward = battle_facing()
	if toward != 0:
		_face(toward)

func _on_battle_over():
	guard_rounds_left = 0
	faith_rounds_left = 0; faith_bonus = 0.0
	wisdom_rounds_left = 0; wisdom = 0.0
	zeal_rounds_left = 0; zeal = 0.0
	_update_status_tag()

# The labels of what they have now ("Guard +50%", "Faith +50%", "Zeal -50%"...)
func status_labels() -> Array:
	var out = []
	if guard_rounds_left > 0:
		out.append(tr("Guard +%d%%") % roundi(guard_reduction * 100))
	if faith_rounds_left > 0:
		out.append(tr("Faith +%d%%") % roundi(faith_bonus * 100))
	if wisdom_rounds_left > 0 and wisdom > 0:
		out.append(tr("Wisdom +%d%%") % roundi(wisdom))
	if zeal_rounds_left > 0:
		out.append(player.zeal_text(zeal) if _find_player() else "%+d%%" % roundi(zeal))
	return out

# Guardeffect.png (12 frames of 78x78), sized to this member's body the way
# the player's wings are sized to the player: the same scale for the same
# body size (a phone sheep gets exactly the player's wings), bigger or
# smaller for a bigger or smaller body. Its scale never changes after that
# (played, lingering, see-through).
func _build_guard_fx():
	var sheet = load("res://Guardeffect.png")
	var frames = SpriteFrames.new()
	frames.add_animation("guard")
	frames.set_animation_loop("guard", false)
	frames.set_animation_speed("guard", 12.0)
	for i in 12:
		var atlas = AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = Rect2(i * 78, 0, 78, 78)
		frames.add_frame("guard", atlas)
	guard_fx = AnimatedSprite2D.new()
	guard_fx.name = "GuardFx"
	guard_fx.sprite_frames = frames
	guard_fx.offset = Vector2(-11, -11)   # the dome is drawn a bit right/down of the frame centre
	var body = _visible_body_rect(idle_sprite, self)
	if body.size == Vector2.ZERO:
		body = Rect2(Vector2(-40, -90), Vector2(80, 90))
	# The player's wings: their scale and where they sit on the player's body
	var scale_px = 4.0            # (wings px per frame px, for an 80 px body)
	var host_off = Vector2(0, -0.05)
	var host_size = 80.0
	if _find_player() and player.guard_fx:
		var host_sprite = player.get_node_or_null("Sprite2D")
		var hb = _visible_body_rect(host_sprite, player) if host_sprite else Rect2()
		if hb.size != Vector2.ZERO:
			var gs = player.global_transform.get_scale()
			host_size = sqrt(hb.size.x * hb.size.y) * gs.x
			scale_px = player.guard_fx.scale.x * gs.x
			host_off = (player.guard_fx.position - hb.get_center()) / Vector2(hb.size.y, hb.size.y)
	var my_scale = global_transform.get_scale().x
	var my_size = sqrt(body.size.x * body.size.y) * my_scale
	guard_fx.scale = Vector2.ONE * scale_px * (my_size / host_size) / my_scale
	guard_fx.position = body.get_center() + host_off * body.size.y
	guard_fx_ratio = my_size / host_size
	guard_fx.z_index = 5
	guard_fx.visible = false
	guard_fx.animation_finished.connect(func():
		if guard_rounds_left > 0:
			guard_fx.modulate.a = player.guard_linger_opacity if _find_player() else 0.35   # see-through, same size and frame
		else:
			guard_fx.visible = false)
	add_child(guard_fx)
	guard_shadow = GuardShadow.new(guard_fx, [idle_sprite, walk_sprite])
var guard_fx_ratio = 1.0   # (their wings / the player's, for the tests)
const GuardShadow = preload("res://guard_shadow.gd")
var guard_shadow   # the shadow their wings cast over them (guard_shadow.gd)

# The box of a sprite's visible (non-transparent) pixels, in `space`'s
# coordinates (the sprite PNGs have empty margins)
static func _visible_body_rect(sprite, space: Node2D) -> Rect2:
	if sprite == null or not (sprite is Sprite2D) or sprite.texture == null:
		return Rect2()
	var r: Rect2 = sprite.get_rect()   # (one frame of a sprite sheet)
	var img: Image = sprite.texture.get_image()
	if img:
		if img.is_compressed():
			img.decompress()
		# the pixels of the frame shown (its cell of the sheet / its region)
		var cell = Rect2i(sprite.region_rect) if sprite.region_enabled else Rect2i(Vector2i.ZERO, img.get_size())
		if not sprite.region_enabled:
			var fs = img.get_size() / Vector2i(max(sprite.hframes, 1), max(sprite.vframes, 1))
			cell = Rect2i(Vector2i(sprite.frame_coords) * fs, fs)
		var used = img.get_region(cell).get_used_rect()
		if used.size.x > 0:
			r = Rect2(r.position + Vector2(used.position), Vector2(used.size))
	var xf: Transform2D = space.global_transform.affine_inverse() * sprite.global_transform
	return Rect2(xf * r.position, Vector2.ZERO).expand(xf * r.end).abs()

# Their statuses over the head, small: "Guard +50%  Faith +50%" (two a line),
# over the HP bar (and the phone player's name). Mirrored in the 3D view.
func _update_status_tag():
	if guard_rounds_left <= 0 and guard_fx:
		guard_fx.visible = false   # guard over: the wings go
	var labels = status_labels()
	if status_tag == null:
		if labels.is_empty():
			return
		status_tag = Label.new()
		status_tag.name = "StatusTag"
		status_tag.z_index = 6   # (over the wings)
		status_tag.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		status_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		status_tag.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		status_tag.add_theme_color_override("font_color", Color(0.75, 0.88, 1.0))
		status_tag.add_theme_color_override("font_outline_color", Color.BLACK)
		status_tag.add_theme_constant_override("outline_size", 4)
		status_tag.add_theme_font_size_override("font_size", 13)
		add_child(status_tag)
	status_tag.visible = not labels.is_empty()
	var rows = []
	for i in range(0, labels.size(), 2):
		rows.append("  ".join(labels.slice(i, i + 2)))
	status_tag.text = "\n".join(rows)
	var h = 17.0 * max(rows.size(), 1)
	var top = bubble_head_offset - (26 if player_controlled else 2)   # over the name / the HP bar
	if guard_rounds_left > 0 and guard_fx:   # (and over their wings)
		top = min(top, guard_fx.position.y - (player.GUARD_DOME_HEIGHT - player.GUARD_DOME_BOTTOM + 2.0) * guard_fx.scale.y if player else top)
	status_tag.size = Vector2(220, h)
	status_tag.position = Vector2(-110, top - h)
	status_tag.add_theme_color_override("font_color", Color(1.0, 0.65, 0.6) if zeal_rounds_left > 0 and zeal < 0 else Color(0.75, 0.88, 1.0))

# Returns the damage taken (less while guarded).
func take_damage(amount) -> float:
	if guard_rounds_left > 0:
		amount *= (1.0 - guard_reduction)
	var before = hp
	hp = max(hp - amount, 0.0)
	_update_hp()
	PopupText.spawn(self, "-" + str(snapped(before - hp, 0.1)), Color(1, 0.45, 0.4), Vector2(0, -60))
	if knocked_out:
		print(display_name, " is knocked out")
	return before - hp

# Returns how much was really healed. Healing a knocked-out member revives them.
func heal(amount) -> float:
	var before = hp
	hp = min(hp + amount, max_hp)
	_update_hp()
	PopupText.spawn(self, "+" + str(snapped(hp - before, 0.1)), Color(0.45, 1.0, 0.5), Vector2(0, -60))
	return hp - before


# ---------------- Phone players (player_controlled = true) ----------------
# Their turn: TurnManager calls take_phone_turn() and WAITS until the phone
# sends a verse (or "skip"), the time runs out, or they disconnect.
#   - Same verse matching as the computer (character_body_2d.gd).
#   - They share the host's DISCOVERED verses (the team's verse list grows
#     together), but each phone player has their OWN verse cycle, so one
#     person using Psalm 17:8 doesn't block it for everybody else.
#   - Their verses do FULL damage/healing (damage_scale is only for the
#     computer-controlled companions): a real person is playing.
#   - They use the default targets (all enemies / whole party, split).

signal phone_turn_done(wait_time)
var waiting_for_phone = false
var phone_time_left = 0.0
var name_label: Label

func take_phone_turn():
	if knocked_out:
		TurnManager.show_message(tr("%s is knocked out...") % display_name)
		return 0.0
	if not PhoneServer.is_slot_connected(phone_slot):
		TurnManager.show_message(tr("%s is disconnected - turn skipped") % display_name)
		return 0.5
	waiting_for_phone = true
	phone_time_left = PhoneServer.turn_timeout
	TurnManager.show_message(tr("%s's turn - waiting for their phone") % display_name)
	var wait = await phone_turn_done
	waiting_for_phone = false
	return wait

func _end_phone_turn(wait: float):
	if waiting_for_phone:
		waiting_for_phone = false
		phone_turn_done.emit(wait)

# Called by PhoneServer when the phone sends a verse. Returns "" if it was
# recited, or a message for the phone (already translated).
# On their turn any verse works. Out of turn (anyone else's turn in a battle)
# SUPPORT verses work right away - heals, Guard, Faith (attack up), Zeal -
# at most one per battle round per phone player (PhoneServer.support_ready).
# `target` = index in PhoneServer.party_nodes() (-1 = themselves): who a
# heal / Guard goes to.
func phone_verse(text: String, target := -1) -> String:
	if not _find_player():
		return tr("Wait for your turn!")
	var my_turn = waiting_for_phone
	if not my_turn and not TurnManager.in_battle:
		return tr("Verses work in battles, on your turn")
	if knocked_out:
		return tr("You're knocked out - someone has to heal you first")
	var lower = text.to_lower().strip_edges()
	if player._is_enemy_verse(lower):
		return tr("That's an enemy's verse - you can't use it")
	var verse = player._find_verse(lower)
	if verse == null:
		return tr("That's not a verse you know - try again")
	var support = is_support_verse(verse)
	if not my_turn:
		if not support:
			return tr("Attack verses wait for your turn - heal, Guard and buff verses work any time")
		if not PhoneServer.support_ready(phone_slot):
			return tr("You already helped this round - wait for the next round")
	var note = ""
	if VerseManager.discover(verse.ref):   # shared with the whole team
		verse.discovered = true
		note = tr("New verse discovered: %s!") % VerseManager.ref_text(verse.ref)
	if not PhoneServer.can_use_verse(phone_slot, verse.ref):
		return preload("res://character_body_2d.gd").already_used_text() % [VerseManager.ref_text(verse.ref), PhoneServer.remaining_count(phone_slot)]
	PhoneServer.mark_verse_used(phone_slot, verse.ref)
	var body = player.verse_body(verse)
	_say(VerseManager.ref_text(verse.ref), body.substr(0, 1).to_upper() + body.substr(1))
	if support:
		var who = PhoneServer.party_node(target)
		if who == null:
			who = self
		apply_support_verse(verse, who)
		if not my_turn:
			PhoneServer.mark_support_used(phone_slot)
			TurnManager.show_message(tr("%s helps out of turn: %s") % [display_name, VerseManager.ref_text(verse.ref)])
	else:
		# Full damage x their own Faith / Zeal, can counter, default targets.
		# Its statuses (an attack + Guard verse...) go to the reciter.
		player.cast_verse(verse, attack_multiplier(), true, false, 1.0, self)
	print(display_name, " (phone) recites ", verse.ref, "" if my_turn else " (out of turn)")
	recited.emit(verse.ref)
	if my_turn:
		_end_phone_turn(bubble_time_left)
	return note


# Heal / Guard / Faith / Wisdom / Zeal, with no attack in it
static func is_support_verse(verse) -> bool:
	if verse.get("set", "") == "sheet":
		if not verse.get("sins", {}).is_empty() or verse.get("all_damage", 0) > 0:
			return false
		return verse.get("heal", 0) > 0 or verse.get("guard", false) or verse.get("zeal", false) \
			or float(verse.get("faith", 0)) > 0 or float(verse.get("wisdom", 0)) > 0
	return verse.get("type", "") in ["heal", "guard", "faith", "zeal"]


# A support verse's effect on ONE chosen party member (`who`: the player or a
# party member): the heal and every status of the verse (Guard + Wisdom,
# heal + Guard + Faith...) go to `who` - their own Guard (with their own
# wings), Faith, Wisdom and Zeal.
func apply_support_verse(verse, who):
	var heal_pct = 0.0
	if verse.get("set", "") == "sheet" or verse.type == "heal":
		heal_pct = float(verse.get("heal", 0))
	if heal_pct > 0:
		player.heal_targets([who], heal_pct)
	var labels = player.apply_verse_statuses(verse, who)
	if player.verse_statuses(verse).has("guard") and TurnManager.in_battle:
		TurnManager.show_message(tr("%s is guarded") % (PhoneServer.host_name() if who == player else tr(who.display_name)))
	return labels

func phone_skip() -> bool:
	if not waiting_for_phone:
		return false
	TurnManager.show_message(tr("%s skipped their turn") % display_name)
	_end_phone_turn(0.5)
	return true

func _process_phone_turn(delta):
	if waiting_for_phone:
		phone_time_left -= delta
		if phone_time_left <= 0.0:
			TurnManager.show_message(tr("%s ran out of time - turn skipped") % display_name)
			_end_phone_turn(0.5)
		elif not PhoneServer.is_slot_connected(phone_slot):
			TurnManager.show_message(tr("%s is disconnected - turn skipped") % display_name)
			_end_phone_turn(0.5)

func _exit_tree():
	_end_phone_turn(0.0)   # never leave a battle waiting for a removed player

# The friend's name above the head
func _build_name_label():
	name_label = Label.new()
	name_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.size = Vector2(160, 22)
	name_label.position = Vector2(-80, bubble_head_offset - 26)
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.add_theme_color_override("font_outline_color", Color.BLACK)
	name_label.add_theme_constant_override("outline_size", 5)
	add_child(name_label)
	update_name_label()

func update_name_label():
	if name_label == null:
		return
	var connected = PhoneServer.is_slot_connected(phone_slot)
	name_label.text = display_name + ("" if connected else " (" + tr("disconnected") + ")")
	name_label.add_theme_color_override("font_color", visual.modulate.lightened(0.3) if connected else Color(0.7, 0.7, 0.7))
