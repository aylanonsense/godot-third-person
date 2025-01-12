# Autoloaded as DebugArrowDrawer
extends Node


@export var debug_arrow_scene: PackedScene


func clear_debug_arrows() -> void:
	for child in get_children():
		if child is DebugArrow:
			child.queue_free()


func draw_arrow(pos: Vector3, normal: Vector3, color := Color.WHITE, thickness = 1.0, duration: float = -1.0, parent: Node = null) -> DebugArrow:
	return draw_arrow_between(pos, pos + normal, color, thickness, duration, parent)


func draw_arrow_between(from: Vector3, to: Vector3, color := Color.WHITE, thickness = 1.0, duration: float = -1.0, parent: Node = null) -> DebugArrow:
	var debug_arrow := debug_arrow_scene.instantiate() as DebugArrow
	debug_arrow.tail_position = from
	debug_arrow.head_position = to
	debug_arrow.color = color
	debug_arrow.thickness = thickness
	debug_arrow.temporary = duration >= 0.0
	debug_arrow.duration = duration
	if parent:
		parent.add_child(debug_arrow)
	else:
		add_child(debug_arrow)
	return debug_arrow
