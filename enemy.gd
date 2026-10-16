extends CharacterBody2D

var max_hp = 100
var hp = 100
@onready var hp_bar = $EnemyHP

func _ready():
	# If this enemy was already beaten (in this play session or in a loaded
	# save), remove it so it stays defeated.
	if SaveManager.is_enemy_defeated(self):
		queue_free()
		return
	add_to_group("enemies")  # lets the player and party members find enemies
	hp_bar.value = hp

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
