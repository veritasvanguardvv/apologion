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
# HP: party members have their own health (small bar above the head).
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
	var target_x = delayed_pos.x - follow_distance * delayed_facing
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
		var moving_right = velocity.x > 0
		visual.scale.x = 1 if moving_right == sprite_faces_right else -1
	else:
		idle_sprite.frame = idle_first_frame + int(anim_time * idle_fps) % idle_frame_count


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


# Picks a random verse (from all verses) and runs its effect on the nearest
# enemy in the current battle. Returns true if he recited.
func recite_random_verse() -> bool:
	if not _find_player():
		return false
	if Targeting.battle_enemies().is_empty():
		return false
	
	# Any verse at all. Nothing here calls VerseManager, so his recital does
	# NOT discover the verse for the player.
	if player.all_verses.is_empty():
		return false
	# The player is at 50% HP or less: heal them first (a heal verse, all of
	# its healing on the player). No heal verse -> the usual random verse.
	var verse = pick_player_heal_verse() if player_needs_heal() else null
	var healing_player = verse != null
	if verse == null:
		verse = player.all_verses.pick_random()
	
	# Use the same language as the game so the effect matches
	var text = player.verse_body(verse)
	# Default targets (use_choice = false), 25% damage and 25% healing
	if healing_player:
		player.forced_heal_targets = [player]
	player.cast_verse(verse, damage_scale, false, false, damage_scale, self)
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
	var heals = player.all_verses.filter(func(v): return _heal_amount(v) > 0)
	if heals.is_empty():
		return null
	heals.sort_custom(func(a, b): return _heal_amount(a) > _heal_amount(b))
	return heals.slice(0, max(5, heals.size() / 4)).pick_random()

func _heal_amount(v) -> float:
	if v.get("set", "") == "sheet":
		return float(v.get("heal", 0))
	return float(v.get("heal", 0)) if v.get("type", "") == "heal" else 0.0

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

# Guard on a party member (a phone player can recite a Guard verse for any
# ally, see phone_verse): enemies do less damage for a few rounds.
var guard_rounds_left = 0
var guard_reduction = 0.5
var guard_tag: Label

func activate_guard(rounds := 3, reduction := 0.5):
	guard_rounds_left = rounds
	guard_reduction = reduction
	_update_guard_tag()
	PopupText.spawn(self, tr("Guard"), Color(0.6, 0.85, 1.0), Vector2(0, -80))

func _on_round_ended():
	if guard_rounds_left > 0:
		guard_rounds_left -= 1
		_update_guard_tag()

func _on_battle_over():
	guard_rounds_left = 0
	_update_guard_tag()

func _update_guard_tag():
	if guard_tag == null:
		guard_tag = Label.new()
		guard_tag.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
		guard_tag.add_theme_font_size_override("font_size", 14)
		guard_tag.position = Vector2(-hp_bar_width / 2.0, bubble_head_offset - 16)
		add_child(guard_tag)
	guard_tag.visible = guard_rounds_left > 0
	guard_tag.text = tr("Defense +%d%% (%d)") % [int(guard_reduction * 100), guard_rounds_left]

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
		return tr("%s was already used - recite your other %d verse(s) first (Tab to see them)") % [VerseManager.ref_text(verse.ref), PhoneServer.remaining_count(phone_slot)]
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
		# Full damage (1.0), can counter, default targets
		player.cast_verse(verse, 1.0, true, false, 1.0, self)
	print(display_name, " (phone) recites ", verse.ref, "" if my_turn else " (out of turn)")
	recited.emit(verse.ref)
	if my_turn:
		_end_phone_turn(bubble_time_left)
	return note


# Heal / Guard / Faith / Zeal, with no attack in it
static func is_support_verse(verse) -> bool:
	if verse.get("set", "") == "sheet":
		if not verse.get("sins", {}).is_empty() or verse.get("all_damage", 0) > 0:
			return false
		return verse.get("heal", 0) > 0 or verse.get("guard", false) or verse.get("zeal", false)
	return verse.get("type", "") in ["heal", "guard", "faith", "zeal"]


# A support verse's effect on ONE chosen party member (`who`: the player or a
# party member). Faith boosts the whole team's attacks (they all go through
# the player's cast_verse), Zeal is the player's run/jump boost.
func apply_support_verse(verse, who):
	var heal_pct = 0.0
	var guard = false
	var zeal = false
	var faith = false
	if verse.get("set", "") == "sheet":
		heal_pct = float(verse.get("heal", 0))
		guard = verse.get("guard", false)
		zeal = verse.get("zeal", false)
	else:
		match verse.type:
			"heal": heal_pct = float(verse.heal)
			"guard": guard = true
			"zeal": zeal = true
			"faith": faith = true
	if heal_pct > 0:
		player.heal_targets([who], heal_pct)
	if guard:
		if who == player:
			player.activate_guard()
		elif who.has_method("activate_guard"):
			who.activate_guard(player.guard_rounds, player.guard_reduction)
		if TurnManager.in_battle:
			TurnManager.show_message(tr("%s is guarded") % (PhoneServer.host_name() if who == player else tr(who.display_name)))
	if faith:
		player.activate_faith()
	if zeal:
		player._zeal_boost()

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
