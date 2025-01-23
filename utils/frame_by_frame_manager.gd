# Autoloaded as FrameByFrameManager
extends Node


var _is_advancing_one_physics_tick := false
var _has_advanced_one_physics_tick := false


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("pause"):
		get_tree().paused = not get_tree().paused
	elif Input.is_action_just_pressed("frame_step"):
		_is_advancing_one_physics_tick = true
		_has_advanced_one_physics_tick = false
		get_tree().paused = false
	elif _is_advancing_one_physics_tick and _has_advanced_one_physics_tick:
		_is_advancing_one_physics_tick = false
		_has_advanced_one_physics_tick = false
		get_tree().paused = true


func _physics_process(_delta: float) -> void:
	if not get_tree().paused:
		_has_advanced_one_physics_tick = true
