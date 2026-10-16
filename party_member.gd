extends CharacterBody2D
# Party member (used by pastor_ramuel.tscn)
# ------------------------------------------
# Follows the player, and every few seconds recites a random verse the player
# has discovered when an enemy is close enough. The verse's effect is run by
# the player's own apply_verse_effects() (character_body_2d.gd), so it works
# exactly like when the player types it, except:
#   - it does NOT use up the player's verse cycle (VerseManager isn't touched)
#   - lust damage is multiplied by damage_scale
#
# Everything with @export can be changed in the Inspector when you click the
# party member's root node in pastor_ramuel.tscn (or in a level).
#
# Animations: the AnimatedSprite2D needs two animations called "walk" and
# "idle" (edit them in the SpriteFrames panel at the bottom of the editor).

@export_group("Following")
@export var follow_distance = 90.0     # how far behind the player he walks (pixels)
@export var move_speed = 200.0         # same as the player's normal speed
@export var catch_up_speed = 320.0     # used when he's far behind
@export var jump_velocity = -450.0     # negative = up
@export var gravity = 980.0            # same as the player
@export var teleport_distance = 700.0  # if he's this far away (or falls in a pit) he pops back next to the player

@export_group("Fighting")
@export var recite_interval = 7.0      # seconds between recitals
@export var attack_range = 600.0       # only recites when an enemy is this close to him (pixels)
@export var damage_scale = 0.5         # 0.5 = half the verse's normal damage, 1.0 = full damage
@export var speech_duration = 2.0      # how long the speech label stays up (seconds)

@export_group("Sprite")
@export var sprite_faces_right = true  # set false if the art faces left

# Emitted every time he recites (handy for sound effects later)
signal recited(verse_ref)

var player = null
var player_facing = 1        # 1 = player last moved right, -1 = left
var recite_timer = 0.0
var speech_id = 0

@onready var anim = $AnimatedSprite2D
@onready var speech_label = $SpeechLabel


func _ready():
	speech_label.visible = false
	anim.play("idle")


# Finds the player once it exists (it's in the "player" group).
func _find_player():
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")
		if player:
			# Don't bump into the player
			add_collision_exception_with(player)
	return player


# Where the player's body really is (in Sloth the player's sprite and
# collision are moved away from the player's origin, so use the shape).
func _player_center() -> Vector2:
	var shape = player.get_node_or_null("CollisionShape2D")
	return shape.global_position if shape else player.global_position


func _physics_process(delta):
	if not _find_player():
		return
	
	# Remember which way the player is going, so we stay behind them
	if player.velocity.x > 0:
		player_facing = 1
	elif player.velocity.x < 0:
		player_facing = -1
	
	var player_pos = _player_center()
	var target_x = player_pos.x - follow_distance * player_facing
	var dx = target_x - global_position.x
	
	# Gravity, like the player
	if not is_on_floor():
		velocity.y += gravity * delta
	
	# Walk toward the spot behind the player (only steer while on the floor;
	# in the air he keeps his speed so he can make it across gaps)
	var direction = 0
	if abs(dx) > 10.0:
		direction = sign(dx)
	if is_on_floor():
		if direction != 0:
			var speed = catch_up_speed if abs(dx) > 200.0 else move_speed
			velocity.x = direction * speed
		else:
			velocity.x = move_toward(velocity.x, 0, move_speed)
		
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
			elif is_on_wall() or player_pos.y < global_position.y - 80.0:
				# Something in the way, or the player is up higher
				velocity.y = jump_velocity
	
	move_and_slide()
	
	# Stuck far away or fell into a pit? Pop back next to the player.
	if global_position.distance_to(player_pos) > teleport_distance or global_position.y > player_pos.y + 200.0:
		global_position = Vector2(target_x, player_pos.y - 20.0)
		velocity = Vector2.ZERO
	
	_update_animation()
	_update_reciting(delta)


# True if there's no floor a little way ahead of him.
func _gap_ahead(direction) -> bool:
	var from = global_position + Vector2(direction * 50.0, 0)
	var query = PhysicsRayQueryParameters2D.create(from, from + Vector2(0, 120))
	query.exclude = [get_rid(), player.get_rid()]
	query.collision_mask = collision_mask
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()


func _update_animation():
	if abs(velocity.x) > 1.0:
		anim.play("walk")
		# flip_h flips the picture; which way is "flipped" depends on the art
		anim.flip_h = (velocity.x < 0) == sprite_faces_right
	else:
		anim.play("idle")


# ---------------- Reciting verses ----------------

func _update_reciting(delta):
	recite_timer += delta
	if recite_timer < recite_interval:
		return
	# Ready to recite. Only do it if an enemy is in range; otherwise stay ready
	# so he recites as soon as one comes close.
	if recite_random_verse():
		recite_timer = 0.0


# Picks a random discovered verse and runs its effect on the nearest enemy
# in range. Returns true if he recited.
func recite_random_verse() -> bool:
	if not _find_player():
		return false
	var target = player.get_nearest_enemy(global_position, attack_range)
	if target == null:
		return false
	
	# Only verses the player has discovered (see verse_manager.gd)
	var known = []
	for v in player.all_verses:
		if VerseManager.is_discovered(v.ref):
			known.append(v)
	if known.is_empty():
		return false
	var verse = known.pick_random()
	
	# Use the same language as the player so the effect matches
	var text = verse.en
	if player.language == "es" and verse.has("es"):
		text = verse.es
	player.apply_verse_effects(text.to_lower(), target, damage_scale)
	
	print("Pastor Ramuel recites ", verse.ref)
	_say(verse.ref + "!")
	recited.emit(verse.ref)
	return true


# Shows text above his head for speech_duration seconds.
func _say(text: String):
	speech_id += 1
	var my_id = speech_id
	speech_label.text = text
	speech_label.visible = true
	await get_tree().create_timer(speech_duration).timeout
	if my_id == speech_id and is_instance_valid(speech_label):
		speech_label.visible = false
