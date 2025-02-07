# Autoloaded as MouseLockManager
extends Node


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("toggle_mouse_lock"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
