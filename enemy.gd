extends CharacterBody2D

var max_hp = 100
var hp = 100

# --- Turn-based battles (see turn_manager.gd) ---
@export var display_name = ""      # shown as "<name>'s turn"; empty = use the node's name
@export var battle_speed = 5       # lower than the player (10) and Pastor Ramuel (8), so it acts last
# PLACEHOLDER ATTACK: enemies don't have real attacks yet, so on its turn the
# enemy just does a little damage to the player. Untick can_attack in the
# Inspector to make enemies skip their turn instead.
@export var can_attack = true
@export var attack_damage = 5

# Fear (Psalm 75:10): this enemy's attack is lowered for a few rounds.
# Recasting refreshes the duration (it doesn't stack).
@export var fear_reduction = 0.5   # 0.5 = attacks do half damage
@export var fear_rounds = 3
var fear_rounds_left = 0
var fear_label: Label              # "Attack 50% down (3)" above the HP bar

@onready var hp_bar = $EnemyHP

func _ready():
	# If this enemy was already beaten (in this play session or in a loaded
	# save), remove it so it stays defeated.
	if SaveManager.is_enemy_defeated(self):
		queue_free()
		return
	add_to_group("enemies")  # lets the player and party members find enemies
	hp_bar.value = hp
	if display_name == "":
		display_name = str(name)
	
	# Fear label, just above the HP bar
	fear_label = Label.new()
	fear_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fear_label.position = hp_bar.position + Vector2(0, -26)
	fear_label.size = Vector2(hp_bar.size.x, 24)
	fear_label.add_theme_color_override("font_color", Color(0.75, 0.55, 1.0))
	fear_label.add_theme_color_override("font_outline_color", Color.BLACK)
	fear_label.add_theme_constant_override("outline_size", 4)
	fear_label.visible = false
	add_child(fear_label)
	TurnManager.round_ended.connect(_on_round_ended)

func apply_fear():
	fear_rounds_left = fear_rounds
	_update_fear_label()
	print(display_name, " is afraid: attack -", int(fear_reduction * 100), "% for ", fear_rounds, " rounds")

func _on_round_ended():
	if fear_rounds_left > 0:
		fear_rounds_left -= 1
		_update_fear_label()

func _update_fear_label():
	fear_label.visible = fear_rounds_left > 0
	fear_label.text = "Attack %d%% down (%d)" % [int(fear_reduction * 100), fear_rounds_left]

# Called by TurnManager when it's this enemy's turn in a battle.
func take_turn():
	var player = get_tree().get_first_node_in_group("player")
	if can_attack and player and player.has_method("take_damage"):
		var damage = attack_damage
		if fear_rounds_left > 0:
			damage *= (1.0 - fear_reduction)   # Fear: weaker attack
		# take_damage returns the damage after the player's guard (Psalm 17:8),
		# so Fear and Guard together = 5 x 0.5 x 0.5 = 1.25
		var dealt = player.take_damage(damage)
		TurnManager.show_message("%s attacks! -%s HP" % [display_name, str(snapped(dealt, 0.1))])
		print(display_name, " attacks for ", dealt)
	else:
		TurnManager.show_message("%s waits..." % display_name)

# Where the enemy's body actually is. In some scenes the sprite and collision
# are moved away from the enemy's origin, so use the collision shape.
func get_center() -> Vector2:
	var shape = get_node_or_null("CollisionShape2D")
	return shape.global_position if shape else global_position

func take_damage(amount):
	hp = max(hp - amount, 0)
	hp_bar.value = hp
	if hp <= 0:
		SaveManager.mark_enemy_defeated(self)  # remember it for saving
		queue_free()  # enemy dies
		print("Enemy defeated")
