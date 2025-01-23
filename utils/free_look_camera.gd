class_name FreeLookCamera
extends Camera3D


const SLOW_MOVE_SPEED := 0.875
const NORMAL_MOVE_SPEED := 2.5
const FAST_MOVE_SPEED := 7.5

@export var move_speed := 1.0
@export var mouse_look_sensitivity := 1.0


func _input(event: InputEvent) -> void:
	# Look with the mouse
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and current:
		var look_change := Vector2(event.relative.x, -event.relative.y) * mouse_look_sensitivity
		rotation_degrees = Vector3(
			clampf(rotation_degrees.x + look_change.y, -90.0, 90.0),
			rotation_degrees.y - look_change.x,
			0.0
		)


func _process(delta: float) -> void:
	if not current:
		return
	# Figure out 3D camera move input
	var camera_move_input := Vector3.ZERO
	if Input.is_action_pressed("move_camera_forward"):
		camera_move_input += Vector3.FORWARD
	if Input.is_action_pressed("move_camera_backward"):
		camera_move_input += Vector3.BACK
	if Input.is_action_pressed("move_camera_left"):
		camera_move_input += Vector3.LEFT
	if Input.is_action_pressed("move_camera_right"):
		camera_move_input += Vector3.RIGHT
	if Input.is_action_pressed("move_camera_up"):
		camera_move_input += Vector3.UP
	if Input.is_action_pressed("move_camera_down"):
		camera_move_input += Vector3.DOWN
	camera_move_input = camera_move_input.normalized()
	# Figure out move speed
	var modified_move_speed := move_speed
	if Input.is_action_pressed("speed_camera_up") and not Input.is_action_pressed("slow_camera_down"):
		modified_move_speed *= FAST_MOVE_SPEED
	elif Input.is_action_pressed("slow_camera_down") and not Input.is_action_pressed("speed_camera_up"):
		modified_move_speed *= SLOW_MOVE_SPEED
	else:
		modified_move_speed *= NORMAL_MOVE_SPEED
	# Move the camera 
	translate(modified_move_speed * camera_move_input * delta)
