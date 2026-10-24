extends Area2D

func _ready():
	body_entered.connect(_on_body_entered)

func _on_body_entered(body):
	if body.name == "CharacterBody2D":
		var prompt = get_parent().get_node("PromptLabel")
		if prompt:
			# "Press Up to talk" on a computer, "Tap ^ to talk" on a phone
			prompt.text = GameSettings.control_prompt("Press %s to talk", "interact", "Tap ^ to talk", "Press Up to talk")
			prompt.set_meta("talk_prompt", true)
		var npc_sprite = get_parent().get_node("Sprite2D")
		if body.global_position.x < global_position.x:
			npc_sprite.flip_h = true
		else:
			npc_sprite.flip_h = false
