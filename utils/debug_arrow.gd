@tool
class_name DebugArrow
extends Node3D


const DEFAULT_HEAD_LENGTH := 0.2
const DEFAULT_TAIL_LENGTH := 0.8

@export var color := Color.WHITE:
	get:
		if _needs_to_apply_color:
			return _target_color
		elif not _material:
			return Color.WHITE
		return _material.albedo_color
	set(value):
		_target_color = value
		_needs_to_apply_color = true
		_try_applying_color()
@export var temporary: bool = false:
	set(value):
		temporary = value
		notify_property_list_changed()
		if not Engine.is_editor_hint():
			_needs_to_reset_death_timer = true
			_try_resetting_death_timer()
@export var duration := 1.0:
	set(value):
		duration = value
		if not Engine.is_editor_hint():
			_needs_to_reset_death_timer = true
			_try_resetting_death_timer()
@export var length := 1.0:
	get:
		if _needs_to_apply_length:
			return _target_length
		if not is_instance_valid(head):
			return 1.0
		return absf(head.position.z)
	set(value):
		_target_length = maxf(0.0, value)
		_needs_to_apply_length = true
		_try_applying_length_thickness_and_direction()
@export var thickness := 1.0:
	get:
		if _needs_to_apply_thickness:
			return _target_thickness
		if not is_instance_valid(tail):
			return 1.0
		return (tail.scale.x + tail.scale.y) / 2.0
	set(value):
		_target_thickness = value
		_needs_to_apply_thickness = true
		_try_applying_length_thickness_and_direction()
var direction: Vector3:
	get:
		if _needs_to_apply_direction:
			return _target_direction
		if not is_inside_tree():
			return Vector3.FORWARD
		return -global_basis.z.normalized()
	set(value):
		_target_direction = value.normalized()
		_needs_to_apply_direction = true
		_try_applying_length_thickness_and_direction()
var vector: Vector3:
	get:
		return direction * length
	set(value):
		_target_length = value.length()
		_needs_to_apply_length = true
		_target_direction = value.normalized()
		_needs_to_apply_direction = true
		_try_applying_length_thickness_and_direction()
var head_position: Vector3:
	get:
		return tail_position + direction * length
	set(value):
		_target_length = tail_position.distance_to(value)
		_needs_to_apply_length = true
		_target_direction = tail_position.direction_to(value)
		_needs_to_apply_direction = true
		_try_applying_length_thickness_and_direction()
var tail_position: Vector3:
	get:
		if _needs_to_apply_position:
			return _target_position
		if not is_inside_tree():
			return Vector3.ZERO
		return position
	set(value):
		_target_position = value
		_needs_to_apply_position = true
		_try_applying_position()

@onready var head := %Head as Node3D
@onready var tail := %Tail as Node3D
@onready var head_mesh := %HeadMesh as Node3D
@onready var tail_mesh := %TailMesh as Node3D
@onready var death_timer := %DeathTimer as Timer

var _material: Material
var _needs_to_apply_position := false
var _target_position := Vector3.ZERO
var _needs_to_apply_length := false
var _target_length := 0.0
var _needs_to_apply_thickness := false
var _target_thickness := 0.0
var _needs_to_apply_direction := false
var _target_direction := Vector3.FORWARD
var _needs_to_apply_color := false
var _target_color := Color.WHITE
var _needs_to_reset_death_timer := false


func _ready():
	_material = head_mesh.material_override
	if Engine.is_editor_hint():
		_material = _material.duplicate()
		head_mesh.material_override = _material
		tail_mesh.material_override = _material
	_try_resetting_death_timer()
	_refresh()


func _process(_delta: float) -> void:
	_refresh()


func _refresh() -> void:
	if _needs_to_apply_position:
		_try_applying_position()
	if _needs_to_apply_length or _needs_to_apply_thickness or _needs_to_apply_direction:
		_try_applying_length_thickness_and_direction()
	if _needs_to_apply_color:
		_try_applying_color()
	if _needs_to_reset_death_timer:
		_try_resetting_death_timer()


func _try_applying_position() -> void:
	if not is_inside_tree():
		return
	position = _target_position
	_needs_to_apply_position = false
	_target_position = Vector3.ZERO


func _try_applying_length_thickness_and_direction() -> void:
	if not is_inside_tree():
		return
	# Collect target parameters
	var target_length := length
	var target_direction := direction
	if target_length < 0.0:
		target_length = -target_length
		target_direction = -target_direction
	if target_direction.is_zero_approx():
		target_direction = Vector3.FORWARD
	# Apply length/thickness
	var head_length := minf(target_length, thickness * DEFAULT_HEAD_LENGTH)
	var tail_length := target_length - head_length
	var head_horizontal_scale := head_length / DEFAULT_HEAD_LENGTH
	var tail_horizontal_scale := tail_length / DEFAULT_TAIL_LENGTH
	head.position = tail.position + Vector3.FORWARD * target_length
	head.scale = Vector3(thickness, thickness, head_horizontal_scale)
	head.visible = head_horizontal_scale > 0.0 and thickness > 0.0
	tail.scale = Vector3(thickness, thickness, tail_horizontal_scale)
	tail.visible = tail_horizontal_scale > 0.0 and thickness > 0.0
	# Apply direction
	var look_target := global_position + target_direction
	var dot_product := target_direction.dot(Vector3.UP)
	if global_position != look_target:
		look_at(look_target, Vector3.UP if -0.999 < dot_product and dot_product < 0.999 else Vector3.FORWARD)
	# Reset target parameters
	_needs_to_apply_length = false
	_target_length = 0.0
	_needs_to_apply_thickness = false
	_target_thickness = 0.0
	_needs_to_apply_direction = false
	_target_direction = Vector3.FORWARD


func _try_applying_color() -> void:
	if not is_inside_tree():
		return
	_material.albedo_color = _target_color
	_needs_to_apply_color = false
	_target_color = Color.WHITE


func _try_resetting_death_timer() -> void:
	if not is_inside_tree():
		return
	if not Engine.is_editor_hint():
		if not temporary or duration < 0.0:
			death_timer.stop()
		else:
			death_timer.wait_time = duration
			death_timer.start()
	_needs_to_reset_death_timer = false


func _on_death_timer_timeout() -> void:
	if not Engine.is_editor_hint() and temporary and duration >= 0.0:
		queue_free()


func _validate_property(property: Dictionary) -> void:
	match property.name:
		"duration":
			property.usage = PROPERTY_USAGE_DEFAULT if temporary else PROPERTY_USAGE_NO_EDITOR
