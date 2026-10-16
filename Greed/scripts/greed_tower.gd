extends Area2D
# Port of Unity's Tower.cs: the building fades a little while you're behind it.

@export var fade_alpha = 0.8
@export var fade_time = 1.0

var tween: Tween


func _ready():
	body_entered.connect(func(b): if b.is_in_group("player"): _fade(fade_alpha))
	body_exited.connect(func(b): if b.is_in_group("player"): _fade(1.0))


func _fade(a: float):
	if tween:
		tween.kill()
	tween = create_tween()
	tween.tween_property(self, "modulate:a", a, fade_time)
