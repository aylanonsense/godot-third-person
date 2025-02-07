# Autoloaded as FrameStepper
extends Node


var is_stepping_frame_by_frame := false:
	get(): return is_stepping_frame_by_frame
var _has_stepped_forward_one_frame := false


func _process(_delta: float) -> void:
	# Toggle pause
	if Input.is_action_just_pressed("pause"):
		get_tree().paused = not get_tree().paused
	# Step one frame forward
	elif Input.is_action_just_pressed("frame_step"):
		is_stepping_frame_by_frame = true
		_has_stepped_forward_one_frame = false
		get_tree().paused = false


func _physics_process(_delta: float) -> void:
	if is_stepping_frame_by_frame and not get_tree().paused:
		# Let one physics tick pass so that everything can update
		if not _has_stepped_forward_one_frame:
			_has_stepped_forward_one_frame = true
		# Then pause again at the start of the next physics tick
		else:
			is_stepping_frame_by_frame = false
			_has_stepped_forward_one_frame = false
			get_tree().paused = true
