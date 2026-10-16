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

# Called by TurnManager when it's this enemy's turn in a battle.
func take_turn():
	var player = get_tree().get_first_node_in_group("player")
	if can_attack and player and player.has_method("take_damage"):
		player.take_damage(attack_damage)
		TurnManager.show_message("%s attacks! -%d HP" % [display_name, attack_damage])
		print(display_name, " attacks for ", attack_damage)
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
