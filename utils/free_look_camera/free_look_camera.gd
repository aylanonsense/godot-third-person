class_name FreeLookCamera
extends Camera3D


const SLOW_MOVE_SPEED := 0.25
const NORMAL_MOVE_SPEED := 2.5
const FAST_MOVE_SPEED := 10.0

static var instance: FreeLookCamera

@export var move_speed := 1.0
@export var mouse_look_sensitivity := 1.0
@export var pause_on_enter_free_look := true
@export var unpause_on_exit_free_look := true

var _previous_camera: Camera3D
var _previous_mouse_mode: Input.MouseMode
var _was_paused: bool


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _ready() -> void:
	_previous_mouse_mode = Input.mouse_mode
	_was_paused = get_tree().paused


func _input(event: InputEvent) -> void:
	# If this isn't the current camera or the mouse isn't captured, don't bother with mouse look
	if not current or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	# Look with the mouse
	if event is InputEventMouseMotion and current:
		var look_change := Vector2(event.relative.x, -event.relative.y) * mouse_look_sensitivity
		rotation_degrees = Vector3(
			clampf(rotation_degrees.x + look_change.y, -90.0, 90.0),
			rotation_degrees.y - look_change.x,
			0.0)


func _process(delta: float) -> void:
	# Toggle free look
	if Input.is_action_just_pressed("toggle_free_look_camera"):
		# Make this the current camera
		if not current:
			_previous_camera = get_viewport().get_camera_3d()
			_previous_mouse_mode = Input.mouse_mode
			_was_paused = get_tree().paused
			if _previous_camera:
				global_transform = _previous_camera.global_transform
			make_current()
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			if pause_on_enter_free_look:
				get_tree().paused = true
		# Return to the previous camera
		else:
			if _previous_camera:
				_previous_camera.make_current()
			else:
				clear_current(true)
			if unpause_on_exit_free_look and not _was_paused:
				get_tree().paused = false
			Input.mouse_mode = _previous_mouse_mode
	# If this isn't the current camera, don't bother moving it
	if not current:
		return
	# Calculate move direction
	var move_direction := Vector3(
		Input.get_axis("move_camera_left", "move_camera_right"),
		Input.get_axis("move_camera_down", "move_camera_up"),
		Input.get_axis("move_camera_forward", "move_camera_backward")).normalized()
	# Calculate move speed
	var camera_speed_input := Input.get_axis("slow_camera_down", "speed_camera_up")
	var move_speed_multiplier: float
	if camera_speed_input > 0.0:
		move_speed_multiplier = lerpf(NORMAL_MOVE_SPEED, FAST_MOVE_SPEED, camera_speed_input)
	elif camera_speed_input < 0.0:
		move_speed_multiplier = lerpf(NORMAL_MOVE_SPEED, SLOW_MOVE_SPEED, -camera_speed_input)
	else:
		move_speed_multiplier = NORMAL_MOVE_SPEED
	# Move the camera
	translate(move_speed_multiplier * move_speed * move_direction * delta)
