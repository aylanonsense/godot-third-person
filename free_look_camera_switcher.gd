class_name FreeLookCameraSwitcher
extends Node


@export var player_character: PlayerCharacter
@export var free_look_camera: FreeLookCamera
@export var pause_on_toggle_free_look_on := false
@export var unpause_on_toggle_free_look_off := false


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("toggle_free_look_camera"):
		if not free_look_camera.current:
			free_look_camera.make_current()
			free_look_camera.global_transform = player_character.camera.global_transform
			if pause_on_toggle_free_look_on:
				get_tree().paused = true
		else:
			player_character.camera.make_current()
			if unpause_on_toggle_free_look_off:
				get_tree().paused = false
