extends CharacterBody2D
# Party member (used by pastor_ramuel.tscn and baana.tscn)
# ------------------------------------------
# Follows the player a moment behind them, and fights in turn-based battles
# (see turn_manager.gd). On his turn he recites a random verse from ALL the
# verses (he knows them all). His recital never discovers a verse for the
# player - the player still has to type it. The verse's effect is run by the player's own
# apply_verse_effects() (character_body_2d.gd), so it works like when the
# player types it, except:
#   - it does NOT use up the player's verse cycle (VerseManager isn't touched)
#   - lust damage is multiplied by damage_scale
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

@export_group("Following")
@export var follow_distance = 90.0     # how far behind the player he walks (pixels)
@export var follow_delay = 0.35        # he reacts this many seconds after the player moves
@export var move_speed = 200.0         # same as the player's normal speed
@export var catch_up_speed = 320.0     # used when he's far behind
@export var acceleration = 900.0       # how quickly he speeds up / eases to a stop
@export var jump_velocity = -450.0     # negative = up
@export var gravity = 980.0            # same as the player
@export var teleport_distance = 700.0  # if he's this far away (or falls in a pit) he pops back next to the player

@export_group("Fighting")
@export var battle_speed = 8           # lower than the player's 10, so he acts right after you
@export var damage_scale = 0.25        # 0.25 = a quarter of the verse's normal damage

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


func _ready():
	add_to_group("party")   # TurnManager puts everyone in "party" into battles
	bubble = preload("res://speech_bubble.gd").new()
	bubble.set_light_style()   # party members and the player have white bubbles
	bubble.target = self
	bubble.head_offset = Vector2(0, bubble_head_offset)
	bubble.max_width = bubble_max_width
	add_child(bubble)
	_update_animation(0.0)


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
		if direction != 0 and abs(dx) > 60.0:
			# How far the player is from him, in the direction he's walking
			var player_ahead = (player_pos.x - global_position.x) * direction
			if _gap_ahead(direction):
				if player_ahead > 150.0:
					# The player is on the other side: jump the gap at full speed
					velocity.y = jump_velocity
					velocity.x = direction * catch_up_speed
				else:
					# The spot behind the player is over a pit: wait at the edge
					velocity.x = 0
			elif is_on_wall() or player_pos.y < global_position.y - 120.0:
				# Something in the way, or the player is up higher
				velocity.y = jump_velocity
	# (in the air he keeps his speed so he can make it across gaps)
	
	move_and_slide()
	
	# Stuck far away or fell into a pit? Pop back next to the player.
	if global_position.distance_to(player_pos) > teleport_distance or global_position.y > player_pos.y + 250.0:
		global_position = Vector2(player_pos.x - follow_distance * delayed_facing, player_pos.y - 20.0)
		velocity = Vector2.ZERO
	
	_update_animation(delta)


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
	if not recite_random_verse():
		return _say("", "...")
	return bubble_time_left


# Picks a random verse (from all verses) and runs its effect on the nearest
# enemy in the current battle. Returns true if he recited.
func recite_random_verse() -> bool:
	if not _find_player():
		return false
	var target = null
	for enemy in TurnManager.battle_enemies:
		if TurnManager._is_alive(enemy):
			if target == null or global_position.distance_to(enemy.get_center()) < global_position.distance_to(target.get_center()):
				target = enemy
	if target == null:
		return false
	
	# Any verse at all. Nothing here calls VerseManager, so his recital does
	# NOT discover the verse for the player.
	if player.all_verses.is_empty():
		return false
	var verse = player.all_verses.pick_random()
	
	# Use the same language as the game so the effect matches
	var text = player.verse_body(verse)
	player.apply_verse_effects(text.to_lower(), target, damage_scale)
	
	print(display_name, " recites ", verse.ref)
	_say(VerseManager.ref_text(verse.ref), text.substr(0, 1).to_upper() + text.substr(1))
	recited.emit(verse.ref)
	return true


var bubble_time_left = 0.0

# Shows a speech bubble with the reference (title) and text above the head.
# Returns how many seconds it will stay up (longer text stays up longer).
func _say(title: String, text: String) -> float:
	bubble_time_left = clamp(bubble_time_per_char * (title.length() + text.length()), bubble_min_time, bubble_max_time)
	bubble.say(title, text, false, bubble_time_left)
	return bubble_time_left


func _process(delta):
	bubble_time_left = max(bubble_time_left - delta, 0.0)
