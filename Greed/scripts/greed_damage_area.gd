extends Area2D
# Port of Unity's DamageArea.cs: hurts the player on touch.
# Big damage (like 1000) = a deadly pit, so the level restarts.

const PopupText = preload("res://popup_text.gd")

@export var damage = 75
@export var hide_on_enter = false
@export var start_active = true


func _ready():
	body_entered.connect(_on_body_entered)
	if not start_active:
		hide_area()


func _on_body_entered(body):
	if not body.is_in_group("player") or not visible:
		return
	var taken = body.take_damage(damage)
	# (Baby Mode: nothing hurts - a pit still respawns you when you fall out)
	if not (GameSettings.baby_mode and taken <= 0.0):
		PopupText.spawn(body, "-" + str(snapped(taken, 0.1)), Color(1, 0.45, 0.4))
	if body.hp <= 0 or (GameSettings.baby_mode and damage >= SaveManager.MAX_HP):
		var level = owner if owner else get_tree().current_scene
		if level.has_method("player_fell"):
			level.player_fell()
	if hide_on_enter:
		hide_area()


func show_area():
	visible = true
	set_deferred("monitoring", true)


func hide_area():
	visible = false
	set_deferred("monitoring", false)
