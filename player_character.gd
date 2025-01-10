class_name PlayerCharacter
extends CharacterBody3D


@export var move_speed := 5.0
@export var mouse_look_sensitivity := 1.0

@onready var look_pivot := %LookPivot as Node3D


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var look_change := Vector2(event.relative.x, -event.relative.y) * mouse_look_sensitivity
		look_pivot.rotation_degrees.x = clampf(look_pivot.rotation_degrees.x + look_change.y, -89.9, 89.9)
		look_pivot.rotation_degrees.y -= look_change.x


func _physics_process(_delta: float) -> void:
	var move_vector := Input.get_vector("move_left", "move_right", "move_backward", "move_forward")
	var up := global_basis.y.normalized()
	var look_basis := look_pivot.global_basis.orthonormalized()
	var facing_back := look_basis.z
	var facing_right := up.cross(facing_back).normalized()
	facing_back = facing_right.cross(up)
	var facing_basis := Basis(facing_right, up, facing_back)
	velocity = facing_basis * move_speed * Vector3(move_vector.x, 0.0, -move_vector.y) + velocity.y * Vector3.UP
	move_and_slide()
