class_name PlayerCharacter
extends CharacterBody3D


enum CollisionSurfaceType {
	NONE = -1,
	INCIDENTAL = 0, # Moving away from surface
	FLOOR = 1,
	SLOPE = 2,
	WALL = 3,
	CEILING = 4
}

const MAX_MOVE_STEPS_PER_FRAME := 6
const COLLISION_SURFACE_SEPARATION_DISTANCE := 0.0001
const FLOOR_SNAP_MOVE_DISTANCE := 0.1
const FLOOR_SNAP_EDGE_CHECK_DISTANCE := 0.01

@export var _move_speed := 5.0
@export var _mouse_look_sensitivity := 1.0
@export var _jump_velocity := 10.0
@export_range(0.0, 90.0, 0.001, "radians") var _max_floor_angle := 45.0 * PI / 180.0
@export_range(0.0, 180.0, 0.001, "radians") var _min_wall_angle := 80.0 * PI / 180.0
@export_range(0.0, 180.0, 0.001, "radians") var _max_wall_angle := 135.0 * PI / 180.0
@export_range(0.0, 180.0, 0.001, "radians") var _max_floor_snap_angle_change := 15.0 * PI / 180.0

@onready var _collision_shape := %CollisionShape3D as CollisionShape3D
@onready var _look_yaw_pivot := %LookYawPivot as Node3D
@onready var _look_pitch_pivot := %LookPitchPivot as Node3D
@onready var _floor_snap_edge_cast := %FloorSnapEdgeCast as RayCast3D
@onready var _debug_label := %DebugLabel as Label3D

# Bases and vectors
var _up: Vector3 # The character's up vector
var _look_basis: Basis # The direction the camera is facing, including pitch
var _look_facing_basis: Basis # The direction the camera is facing, ignoring pitch
var _move_basis: Basis # The character's movement basis, might not be orthonormal when moving on a slope
var _inverse_move_basis: Basis
var _collider_height: float

# State
var _just_jumped := false
var _last_move_step_direction := Vector3.FORWARD

# Floor state
var _is_on_floor := false
var _was_on_floor_last_frame := false
var _floor_normal: Vector3
var _reused_floor_from_last_frame := false
var _was_previously_on_floor := false
var _previous_floor_normal: Vector3

# Debug
var _velocity_move_basis_x_debug_arrow: DebugArrow
var _velocity_move_basis_y_debug_arrow: DebugArrow
var _velocity_move_basis_z_debug_arrow: DebugArrow


func _ready() -> void:
	_collider_height = (_collision_shape.shape as CapsuleShape3D).height
	_calculate_and_set_bases_and_vectors()
	# Draw arrows for the character's velocity
	var arrow_position := global_position + _collider_height / 2.0 * _up
	_velocity_move_basis_x_debug_arrow = DebugArrowDrawer.draw_arrow(arrow_position, Vector3.ZERO, Color.RED, 1.0, -1.0, self)
	_velocity_move_basis_y_debug_arrow = DebugArrowDrawer.draw_arrow(arrow_position, Vector3.ZERO, Color.GREEN, 1.0, -1.0, self)
	_velocity_move_basis_z_debug_arrow = DebugArrowDrawer.draw_arrow(arrow_position, Vector3.ZERO, Color.BLUE, 1.0, -1.0, self)


func _input(event: InputEvent) -> void:
	# Use the mouse to look around
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var look_change := Vector2(event.relative.x, -event.relative.y) * _mouse_look_sensitivity # -x = look left / +x = look right / -y = look down / +y = look up
		# Look left/right
		_look_yaw_pivot.rotation_degrees.y -= look_change.x
		# Look up/down
		_look_pitch_pivot.rotation_degrees.x = clampf(_look_pitch_pivot.rotation_degrees.x + look_change.y, -89.9, 89.9)


func _physics_process(delta: float) -> void:
	var global_position_at_frame_start := global_position
	_was_on_floor_last_frame = _is_on_floor
	# If we found a floor last frame, we reuse it for the time being as our current floor
	if _is_on_floor and not _reused_floor_from_last_frame:
		_reused_floor_from_last_frame = true
		_was_previously_on_floor = true
		_previous_floor_normal = _floor_normal
	# Otherwise we assume we don't have a floor and didn't have a floor last frame
	else:
		_is_on_floor = false
		_floor_normal = Vector3.ZERO
		_reused_floor_from_last_frame = false
		_was_previously_on_floor = false
		_previous_floor_normal = Vector3.ZERO
	# Check for jump
	_just_jumped = _is_on_floor and Input.is_action_just_pressed("jump")
	if _just_jumped:
		_is_on_floor = false
		_floor_normal = Vector3.ZERO
		_reused_floor_from_last_frame = false
	# Recalculate bases
	_calculate_and_set_bases_and_vectors()
	# Apply move input to velocity
	var move_percent := 0.10 if _is_on_floor else 0.01
	var move_input := Input.get_vector("move_left", "move_right", "move_backward", "move_forward") # Max 1.0 length
	var move_basis_velocity := _inverse_move_basis * velocity # Velocity taking into account the slope of the floor (if grounded)
	move_basis_velocity.x = lerpf(move_basis_velocity.x, _move_speed * move_input.x, move_percent)
	move_basis_velocity.z = lerpf(move_basis_velocity.z, _move_speed * -move_input.y, move_percent)
	velocity = _move_basis * move_basis_velocity
	# Apply gravity to velocity
	if _just_jumped:
		velocity.y = _jump_velocity
	else:
		var gravity_vector := get_gravity() * delta
		if _is_on_floor:
			# When on a floor, the character resists gravity that'd pull them down/up/across the slope of the floor
			gravity_vector = gravity_vector.project(_floor_normal)
		velocity += gravity_vector
	# Move
	_move_in_multiple_steps(velocity * delta)
	_snap_to_floor()
	_draw_debug_info_and_arrows(global_position_at_frame_start)


func _calculate_and_set_bases_and_vectors() -> void:
	_up = global_basis.y.normalized()
	_look_basis = _look_pitch_pivot.global_basis.orthonormalized()
	_look_facing_basis = _look_yaw_pivot.global_basis.orthonormalized()
	if _is_on_floor:
		var right := MathUtils.project_vector_onto_slope(_look_facing_basis.x, _floor_normal, _up).normalized()
		var back := MathUtils.project_vector_onto_slope(_look_facing_basis.z, _floor_normal, _up).normalized()
		_move_basis = Basis(right, _up, back)
	else:
		_move_basis = _look_facing_basis
	_inverse_move_basis = _move_basis.inverse()


func _move_in_multiple_steps(movement: Vector3) -> void:
	for i in range(MAX_MOVE_STEPS_PER_FRAME):
		# Stop when we're out of movement
		if movement.is_zero_approx():
			return
		_last_move_step_direction = movement.normalized()
		# Try moving the full distance
		var collision_info := move_and_collide(movement)
		# If there were no collisions, we'll take that to mean we were able to move the full distance and there's no movement remaining
		if not collision_info:
			return
		# If there are collisions, it means we weren't able to move the full distance
		var movement_remaining := collision_info.get_remainder()
		# Handle each collision
		for j in range(collision_info.get_collision_count()):
			var collision_surface_type := CollisionSurfaceType.NONE
			var collision_contact_position := collision_info.get_position(j) # global
			var collision_normal := collision_info.get_normal(j)
			var collision_angle := collision_normal.angle_to(_up)
			var vector_from_feet_to_collision := collision_contact_position - global_position
			var height_of_collision := vector_from_feet_to_collision.dot(_up)
			var collision_movement_dot_product := collision_normal.dot(movement_remaining) # Positive if moving away from the surface
			var is_movement_away_from_surface := collision_movement_dot_product > 0.0
			var collision_velocity_dot_product := collision_normal.dot(velocity) # Positive if velocity is away from the surface
			var is_velocity_away_from_surface := collision_velocity_dot_product > 0.0
			# Figure out what type of surface this is, mostly based on the angle of collision
			if collision_angle <= _max_floor_angle and height_of_collision <= 0.5 * _collider_height:
				collision_surface_type = CollisionSurfaceType.FLOOR
			elif is_movement_away_from_surface or is_velocity_away_from_surface:
				collision_surface_type = CollisionSurfaceType.INCIDENTAL
			elif _min_wall_angle <= collision_angle and collision_angle <= _max_wall_angle and _is_on_floor:
				collision_surface_type = CollisionSurfaceType.WALL
			elif collision_angle > _max_wall_angle:
				collision_surface_type = CollisionSurfaceType.CEILING
			else:
				collision_surface_type = CollisionSurfaceType.SLOPE
			# While on a floor, walls are treated as being perpendicular to its slope, so we override the collision normal
			if collision_surface_type == CollisionSurfaceType.WALL:
				collision_normal = MathUtils.project_vector_onto_plane(collision_normal, _floor_normal).normalized()
				collision_movement_dot_product = collision_normal.dot(movement_remaining)
				is_movement_away_from_surface = collision_movement_dot_product > 0.0
				collision_velocity_dot_product = collision_normal.dot(velocity)
				is_velocity_away_from_surface = collision_velocity_dot_product > 0.0
			# Cancel out movement towards the surface of the collision
			if not is_movement_away_from_surface:
				var movement_towards_surface := collision_movement_dot_product * collision_normal
				movement_remaining -= movement_towards_surface
			# Apply a small amount of movement away from the surface of the collision, to separate them a bit
			movement_remaining += COLLISION_SURFACE_SEPARATION_DISTANCE * collision_normal
			# Update the floor
			if collision_surface_type == CollisionSurfaceType.FLOOR:
				# Set this surface as the new floor
				_was_previously_on_floor = _is_on_floor
				_previous_floor_normal = _floor_normal
				_is_on_floor = true
				_floor_normal = collision_normal
				_reused_floor_from_last_frame = false
				# Recalculate bases
				var previous_inverse_move_basis := _inverse_move_basis
				_calculate_and_set_bases_and_vectors()
				# If we move between floors, adjust velocity to match the new slope
				if _was_previously_on_floor and _previous_floor_normal != _floor_normal:
					var old_move_basis_velocity := previous_inverse_move_basis * velocity
					velocity = _move_basis * old_move_basis_velocity
					collision_velocity_dot_product = collision_normal.dot(velocity) # Positive if velocity is away from the surface
					is_velocity_away_from_surface = collision_velocity_dot_product > 0.0
			# Cancel out velocity towards the surface of the collision
			if not is_velocity_away_from_surface:
				var velocity_towards_surface := collision_velocity_dot_product * collision_normal
				velocity -= velocity_towards_surface
			# Draw a short-lived arrow on the point of contact
			var debug_arrow_color: Color
			match collision_surface_type:
				CollisionSurfaceType.FLOOR: debug_arrow_color = Color.AQUA
				CollisionSurfaceType.SLOPE: debug_arrow_color = Color.HOT_PINK
				CollisionSurfaceType.WALL: debug_arrow_color = Color.SADDLE_BROWN
				CollisionSurfaceType.CEILING: debug_arrow_color = Color.ORANGE
				_: debug_arrow_color = Color.BLACK
			DebugArrowDrawer.draw_arrow(collision_contact_position, collision_normal * 0.25, debug_arrow_color, 0.5, 1.0)
		# Continue with the remaining movement
		movement = movement_remaining


func _snap_to_floor() -> void:
	# Don't snap to the floor if we just jumped or already touched a floor this frame or haven't touched a floor in a while
	if _just_jumped or (_is_on_floor and not _reused_floor_from_last_frame) or (not _is_on_floor and not _was_on_floor_last_frame):
		return
	# Move straight down
	var movement := FLOOR_SNAP_MOVE_DISTANCE * -_up
	var collision_info := move_and_collide(movement)
	# If there were no collisions, just undo the movement--we couldn't find a floor
	if not collision_info:
		move_and_collide(-movement)
		return
	# Handle collisions
	for i in range(collision_info.get_collision_count()):
		var collision_contact_position := collision_info.get_position(i) # global
		var collision_normal := collision_info.get_normal(i)
		var collision_angle := collision_normal.angle_to(_up)
		var vector_from_feet_to_collision := collision_contact_position - global_position
		var height_of_collision := vector_from_feet_to_collision.dot(_up)
		# Check if this surface could qualify as a floor
		if not (collision_angle <= _max_floor_angle and height_of_collision <= 0.5 * _collider_height):
			continue
		# Check if this surface is an edge that we're falling off of
		var original_floor_snap_edge_cast_position := _floor_snap_edge_cast.global_position
		var floor_snap_edge_cast_vector := MathUtils.to_global_direction(_floor_snap_edge_cast, _floor_snap_edge_cast.target_position)
		var floor_snap_edge_cast_forward_start_position := collision_contact_position - 0.5 * floor_snap_edge_cast_vector + FLOOR_SNAP_EDGE_CHECK_DISTANCE * _last_move_step_direction
		_floor_snap_edge_cast.global_position = floor_snap_edge_cast_forward_start_position
		_floor_snap_edge_cast.force_raycast_update()
		_floor_snap_edge_cast.global_position = original_floor_snap_edge_cast_position
		# If no surface could be found a little bit forward, it means we moved off of a cliff and shouldn't snap to the edge
		if not _floor_snap_edge_cast.is_colliding():
			continue
		# If the surface a little bit forward from here is too different from the current floor, it probably means we moved off a cliff with a jutting-out edge
		var floor_edge_cast_normal := _floor_snap_edge_cast.get_collision_normal()
		var angle_between_floor_normal_and_edge_cast_normal := floor_edge_cast_normal.angle_to(collision_normal)
		if angle_between_floor_normal_and_edge_cast_normal > _max_floor_snap_angle_change:
			continue
		# Set this surface as the new floor
		_was_previously_on_floor = _is_on_floor
		_previous_floor_normal = _floor_normal
		_is_on_floor = true
		_floor_normal = collision_normal
		_reused_floor_from_last_frame = false
		# Recalculate bases
		var previous_inverse_move_basis := _inverse_move_basis
		_calculate_and_set_bases_and_vectors()
		# If we move between floors, adjust velocity to match the new slope
		if _was_previously_on_floor and _previous_floor_normal != _floor_normal:
			var old_move_basis_velocity := previous_inverse_move_basis * velocity
			velocity = _move_basis * old_move_basis_velocity
		# Cancel out velocity towards the surface of the collision
		var collision_velocity_dot_product := collision_normal.dot(velocity) # Positive if velocity is away from the surface
		var is_velocity_away_from_surface := collision_velocity_dot_product > 0.0
		if not is_velocity_away_from_surface:
			var velocity_towards_surface := collision_velocity_dot_product * collision_normal
			velocity -= velocity_towards_surface
		break
	# Undo the movement if we didn't find any floor
	if not _is_on_floor or _reused_floor_from_last_frame:
		move_and_collide(-collision_info.get_travel())


func _draw_debug_info_and_arrows(previous_global_position: Vector3) -> void:
	var color: Color
	if _reused_floor_from_last_frame:
		color = Color.BLUE_VIOLET
	elif _is_on_floor:
		color = Color.BLUE
	else:
		color = Color.RED
	DebugArrowDrawer.draw_arrow_between(previous_global_position, global_position, color, 0.5, 10.0)
	var move_basis_velocity := _inverse_move_basis * velocity
	_velocity_move_basis_x_debug_arrow.direction = _move_basis.x * MathUtils.sign_or_1(move_basis_velocity.x)
	_velocity_move_basis_y_debug_arrow.direction = _move_basis.y * MathUtils.sign_or_1(move_basis_velocity.y)
	_velocity_move_basis_z_debug_arrow.direction = _move_basis.z * MathUtils.sign_or_1(move_basis_velocity.z)
	_velocity_move_basis_x_debug_arrow.length = 0.1 * abs(move_basis_velocity.x)
	_velocity_move_basis_y_debug_arrow.length = 0.1 * abs(move_basis_velocity.y)
	_velocity_move_basis_z_debug_arrow.length = 0.1 * abs(move_basis_velocity.z)
	_velocity_move_basis_x_debug_arrow.visible = not is_zero_approx(move_basis_velocity.x)
	_velocity_move_basis_y_debug_arrow.visible = not is_zero_approx(move_basis_velocity.y)
	_velocity_move_basis_z_debug_arrow.visible = not is_zero_approx(move_basis_velocity.z)
	_debug_label.text = "speed=%f\nhspeed=%f\nvspeed=%f\nx=%f\ny=%f\nz=%f" % [move_basis_velocity.length(), Vector3(move_basis_velocity.x, 0.0, move_basis_velocity.z).length(), absf(move_basis_velocity.y), move_basis_velocity.x, move_basis_velocity.y, move_basis_velocity.z]
