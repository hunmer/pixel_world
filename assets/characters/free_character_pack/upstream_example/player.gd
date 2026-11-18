class_name Player
extends CharacterBody2D

@export_range(1.0, 1000.0, 1.0) var move_speed: float = 180.0

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D

var facing_direction := Vector2.DOWN


func _ready() -> void:
    _update_animation(Vector2.ZERO)


func _physics_process(_delta: float) -> void:
    var input_direction := Input.get_vector(
        &"move_left",
        &"move_right",
        &"move_up",
        &"move_down"
    )

    velocity = input_direction * move_speed
    move_and_slide()
    _update_animation(input_direction)


func _update_animation(direction: Vector2) -> void:
    if direction != Vector2.ZERO:
        facing_direction = direction

    var animation_name := &"run_down"
    animated_sprite.flip_h = false

    if absf(facing_direction.x) > absf(facing_direction.y):
        animation_name = &"run_left"
        animated_sprite.flip_h = facing_direction.x > 0.0
    elif facing_direction.y < 0.0:
        animation_name = &"run_up"

    if animated_sprite.animation != animation_name:
        animated_sprite.play(animation_name)

    if direction == Vector2.ZERO:
        animated_sprite.pause()
        animated_sprite.frame = 0
    else:
        animated_sprite.play()
