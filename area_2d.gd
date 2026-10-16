extends Area2D

func _ready():
	body_entered.connect(_on_body_entered)

func _on_body_entered(body):
	if body.name == "CharacterBody2D":
		var prompt = get_parent().get_node("PromptLabel")
		if prompt:
			prompt.text = "Press Up to talk"
		var npc_sprite = get_parent().get_node("Sprite2D")
		if body.global_position.x < global_position.x:
			npc_sprite.flip_h = true
		else:
			npc_sprite.flip_h = false
