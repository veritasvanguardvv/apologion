extends Node
# Targeting (autoload / singleton)
# --------------------------------
# Decides WHO a verse (typed, spoken or from a scroll) affects in a battle,
# and draws the target markers (UI/target-highlight.png) over them.
#
# DEFAULT (nothing chosen):
#   - attack verses hit ALL the enemies in the battle; the damage is SPLIT
#     between them (2 enemies = half each)
#   - healing verses heal you AND your party member; the healing is SPLIT
#     (each gets half of their share)
#   - status verses (Guard, Faith, Fear...) work like before
#
# CHOOSING A TARGET: on your turn press Alt (Option on a Mac) or click the
# "Target" button. Each press moves to the next choice:
#     All (default) -> Enemy 1 -> Enemy 2 -> You -> Party member -> All ...
# A single target gets the FULL damage / healing.
#   - Choosing an enemy only changes attacks (heals stay on You + Party).
#   - Choosing You or the party member only changes heals (attacks stay on
#     all enemies).
# Red markers = who your next attack hits. Green markers = who your next
# heal heals. Markers only show during YOUR turn.
# The choice goes back to the default after every turn of yours, so you never
# hit the wrong target by accident with an old choice next round.
#
# Enemy 1, Enemy 2... are numbered from left to right.

const MARKER_TEXTURE = "res://UI/target-highlight.png"

@export var attack_color = Color(1.0, 0.35, 0.3)   # marker colour on attack targets
@export var heal_color = Color(0.4, 1.0, 0.5)      # marker colour on heal targets
@export var marker_margin = 18.0                   # extra space around the body (pixels)
@export var pulse_speed = 5.0                      # how fast the markers "breathe"
@export var pulse_amount = 0.06                    # how much they grow/shrink (0.06 = 6%)

var chosen = null        # null = default, or the one combatant chosen with Alt
var layer: CanvasLayer
var markers = []         # pool of Sprite2D markers (reused every frame)
var marker_texture: Texture2D

signal target_changed(chosen_node)


func _ready():
	layer = CanvasLayer.new()
	layer.layer = 3   # above the level, under the HUD and speech bubbles
	add_child(layer)
	marker_texture = load(MARKER_TEXTURE)
	# A fresh choice every turn
	TurnManager.player_turn_finished.connect(reset)
	TurnManager.battle_started.connect(reset)
	TurnManager.battle_ended.connect(reset)


func reset():
	chosen = null
	target_changed.emit(null)


# Alt / Option = next target (only on your turn in a battle).
# AltGr on Spanish keyboards sends Ctrl+Alt (to type @, #...), so Alt
# together with Ctrl is ignored.
func _input(event):
	if event is InputEventKey and event.pressed and not event.echo and event.is_action("cycle_target") and not event.ctrl_pressed:
		cycle()


# Moves to the next choice. Returns the chosen node (null = back to default).
func cycle():
	if not TurnManager.is_players_turn():
		return chosen
	var options = get_options()
	var i = options.find(chosen)
	chosen = options[(i + 1) % options.size()]
	target_changed.emit(chosen)
	return chosen


# [null (= default), enemy 1, enemy 2, ..., you, party member]
# With only one enemy (or no party member) the single choice would be the
# same as the default, so it's left out.
func get_options() -> Array:
	var options = [null]
	var enemies = battle_enemies()
	if enemies.size() > 1:
		options.append_array(enemies)
	var party = party_members()
	if not party.is_empty():
		options.append(player())
		options.append_array(party)
	return options


# ---------------- Who gets hit / healed ----------------

func player():
	return get_tree().get_first_node_in_group("player")

# The party member travelling with you (or null)
func party_member():
	for member in get_tree().get_nodes_in_group("party"):
		if TurnManager._is_alive(member):
			return member
	return null

# Everyone in your party who is still standing (AI companion + phone players)
func party_members() -> Array:
	var list = []
	for member in get_tree().get_nodes_in_group("party"):
		if TurnManager._is_alive(member):
			list.append(member)
	return list

# Living enemies in the current battle, left to right
func battle_enemies() -> Array:
	var list = []
	for e in TurnManager.battle_enemies:
		if TurnManager._is_alive(e):
			list.append(e)
	list.sort_custom(func(a, b): return a.global_position.x < b.global_position.x)
	return list

func is_enemy(node) -> bool:
	return node != null and is_instance_valid(node) and node.is_in_group("enemies")

# Who an attack verse hits. use_choice = false for party members (they always
# use the default). Outside a battle: the nearest enemy, like before.
func attack_targets(use_choice := true) -> Array:
	if use_choice and is_enemy(chosen) and TurnManager._is_alive(chosen):
		return [chosen]
	var list = battle_enemies()
	if list.is_empty():
		var p = player()
		var nearest = p.get_nearest_enemy() if p else null
		if nearest:
			list.append(nearest)
	return list

# Who a healing verse heals.
func heal_targets(use_choice := true) -> Array:
	if use_choice and chosen != null and not is_enemy(chosen) and is_instance_valid(chosen):
		return [chosen]
	var list = []
	if player():
		list.append(player())
	list.append_array(party_members())   # AI companion + phone players
	return list


# ---------------- Markers ----------------

func _process(_delta):
	var wanted = []   # [node, color]
	if TurnManager.is_players_turn():
		for e in attack_targets():
			wanted.append([e, attack_color])
		for a in heal_targets():
			wanted.append([a, heal_color])
	# Make sure there are enough marker sprites, hide the extra ones
	while markers.size() < wanted.size():
		var sprite = Sprite2D.new()
		sprite.texture = marker_texture
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		layer.add_child(sprite)
		markers.append(sprite)
	var pulse = 1.0 + sin(Time.get_ticks_msec() / 1000.0 * pulse_speed) * pulse_amount
	for i in markers.size():
		var sprite = markers[i]
		sprite.visible = i < wanted.size()
		if sprite.visible:
			var rect = body_rect(wanted[i][0])
			sprite.position = rect.get_center()
			sprite.scale = (rect.size + Vector2.ONE * marker_margin * 2.0) / marker_texture.get_size() * pulse
			sprite.modulate = wanted[i][1]

# How many markers are on screen (for tests)
func visible_marker_count() -> int:
	var count = 0
	for sprite in markers:
		if sprite.visible:
			count += 1
	return count

# A combatant's body on the SCREEN (from its CollisionShape2D)
func body_rect(node) -> Rect2:
	var shape = node.get_node_or_null("CollisionShape2D")
	var size = Vector2(80, 80)
	var center = node.global_position
	if shape:
		center = shape.global_position
		if shape.shape is RectangleShape2D:
			size = shape.shape.size * shape.global_scale.abs()
	var to_screen = node.get_viewport().get_canvas_transform()
	var zoom = to_screen.get_scale().abs()
	return Rect2(to_screen * center - size * zoom / 2.0, size * zoom)
