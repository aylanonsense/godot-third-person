class_name PlayerCharacter
extends CharacterBody3D


@export var move_speed := 5.0
@export var mouse_look_sensitivity := 1.0
@export var jump_velocity := 10.0

@onready var look_yaw_pivot := %LookYawPivot as Node3D
@onready var look_pitch_pivot := %LookPitchPivot as Node3D


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var look_change := Vector2(event.relative.x, -event.relative.y) * mouse_look_sensitivity # -x = look left / +x = look right / -y = look down / +y = look up
		look_yaw_pivot.rotation_degrees.y -= look_change.x
		look_pitch_pivot.rotation_degrees.x = clampf(look_pitch_pivot.rotation_degrees.x + look_change.y, -89.9, 89.9)


func _physics_process(delta: float) -> void:
	var move_vector := Input.get_vector("move_left", "move_right", "move_backward", "move_forward")
	velocity = look_yaw_pivot.global_basis * move_speed * Vector3(move_vector.x, 0.0, -move_vector.y) + velocity.y * up_direction
	velocity += get_gravity() * delta
	if is_on_floor() and Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity
	move_and_slide()
	if is_on_floor() and velocity.y < 0.0:
		velocity.y = 0.0
