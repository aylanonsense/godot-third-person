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
const MIN_DISTANCE_TO_UPDATE_MOVEMENT_DIRECTION = 0.01
const FLOOR_SNAP_MOVE_DISTANCE := 0.1
const SURFACE_EDGE_CHECK_SCOOT_DISTANCE := 0.01
const MAX_CREVASSE_ANGLE := deg_to_rad(91.0) # Crevasses with too shallow of an angle don't count (180 = flat surfaces count as crevasses, 90 = a ditch with a right angle at the bottom, 0.1 = only allow super steep crevasse)
const MOVE_STEP_DEBUG_ARROW_COLORS: Array[Color] = [Color.RED, Color.ORANGE, Color.YELLOW, Color.GREEN, Color.BLUE, Color.PURPLE, Color.MAGENTA]

@export var _move_speed := 5.0
@export var _mouse_look_sensitivity := 1.0
@export var _jump_velocity := 5.0
@export_range(0.0, 90.0, 0.001, "radians") var _max_floor_angle := deg_to_rad(51.0)
@export_range(0.0, 180.0, 0.001, "radians") var _min_wall_angle := deg_to_rad(69.0)
@export_range(0.0, 180.0, 0.001, "radians") var _max_wall_angle := deg_to_rad(131.0)

@onready var camera: Camera3D = %Camera
@onready var _collision_shape: CollisionShape3D = %CollisionShape3D
@onready var _look_yaw_pivot: Node3D = %LookYawPivot
@onready var _look_pitch_pivot: Node3D = %LookPitchPivot
@onready var _surface_edge_ray_cast: SurfaceEdgeRayCast = %SurfaceEdgeRayCast

# Bases and vectors
var _up: Vector3 # The character's up vector
var _look_basis: Basis # The direction the camera is facing, including pitch
var _look_facing_basis: Basis # The direction the camera is facing, ignoring pitch
var _move_basis: Basis # The character's movement basis, might not be orthonormal when moving on a slope
var _inverse_move_basis: Basis
var _collider_height: float

# State
var _just_jumped := false
var _last_planar_movement_direction := Vector3.FORWARD

# Floor state
var _is_on_floor := false
var _was_on_floor_last_frame := false
var _floor_normal: Vector3
var _reused_floor_from_last_frame := false
var _was_previously_on_floor := false
var _previous_floor_normal: Vector3

# Debug
@onready var _previous_debug_position := global_position
var _debug_movement_steps_info := [] as Array[Dictionary]


func _ready() -> void:
	_collider_height = (_collision_shape.shape as CapsuleShape3D).height
	_calculate_and_set_bases_and_vectors()


func _input(event: InputEvent) -> void:
	# Use the mouse to look around
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and camera.current:
		var look_change := Vector2(event.relative.x, -event.relative.y) * _mouse_look_sensitivity # -x = look left / +x = look right / -y = look down / +y = look up
		# Look left/right
		_look_yaw_pivot.rotation_degrees.y -= look_change.x
		# Look up/down
		_look_pitch_pivot.rotation_degrees.x = clampf(_look_pitch_pivot.rotation_degrees.x + look_change.y, -89.9, 89.9)


func _physics_process(delta: float) -> void:
	# Reset debug information
	_debug_movement_steps_info.clear()
	# If we found a floor last frame, we reuse it for the time being as our current floor
	_was_on_floor_last_frame = _is_on_floor
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
	_just_jumped = _is_on_floor and Input.is_action_just_pressed("jump") and camera.current
	if _just_jumped:
		_is_on_floor = false
		_floor_normal = Vector3.ZERO
		_reused_floor_from_last_frame = false
	# Recalculate bases
	_calculate_and_set_bases_and_vectors()
	# Apply move input to velocity
	var move_percent := 0.10 if _is_on_floor else 0.01
	var move_input := Input.get_vector("move_left", "move_right", "move_backward", "move_forward") if camera.current else Vector2.ZERO # Max 1.0 length
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
	# Debug
	_draw_debug_info_and_arrows()


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
	var upward_facing_normals: Array[Vector3] = []
	var planar_movement := MathUtils.project_vector_onto_plane(movement, _up)
	if planar_movement.length() > MIN_DISTANCE_TO_UPDATE_MOVEMENT_DIRECTION:
		_last_planar_movement_direction = planar_movement.normalized()
	for step_index in range(MAX_MOVE_STEPS_PER_FRAME):
		# Stop when we're out of movement
		if movement.is_zero_approx():
			break
		# Record debug info for drawing arrows
		var _debug_info := {
			move_direction = movement.normalized(),
			move_distance = movement.length(),
			collisions = []
		}
		_debug_movement_steps_info.append(_debug_info)
		# Try moving the full distance
		var collision_info := move_and_collide(movement)
		# If there were no collisions, we'll take that to mean we were able to move the full distance and there's no movement remaining
		if not collision_info:
			break
		# If there are collisions, it means we weren't able to move the full distance
		var movement_remaining := collision_info.get_remainder()
		_debug_info.move_distance = collision_info.get_travel().length()
		# Handle each collision
		for collision_index in range(collision_info.get_collision_count()):
			var collision_surface_type := CollisionSurfaceType.NONE
			var collision_contact_position := collision_info.get_position(collision_index) # global
			var collision_normal := collision_info.get_normal(collision_index)
			var collision_angle := collision_normal.angle_to(_up)
			var vector_from_feet_to_collision := collision_contact_position - global_position
			var height_of_collision := vector_from_feet_to_collision.dot(_up)
			var collision_movement_dot_product := collision_normal.dot(movement_remaining) # Positive if moving away from the surface
			var is_movement_towards_surface := collision_movement_dot_product <= 0.0
			var collision_velocity_dot_product := collision_normal.dot(velocity) # Positive if velocity is away from the surface
			var is_velocity_towards_surface := collision_velocity_dot_product <= 0.0
			# Keep track of upward-facing normals
			if collision_normal.dot(_up) > 0.0:
				upward_facing_normals.append(collision_normal)
			# Check collision type, just for debug purposes right now
			_surface_edge_ray_cast.check_collision_type(collision_contact_position, collision_normal, MathUtils.project_vector_onto_plane(_last_planar_movement_direction, _up).normalized(), _up)
			# Figure out what type of surface this is, mostly based on the angle of collision
			if collision_angle <= _max_floor_angle and height_of_collision <= 0.5 * _collider_height:
				collision_surface_type = CollisionSurfaceType.FLOOR
			elif not is_movement_towards_surface or not is_velocity_towards_surface:
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
				is_movement_towards_surface = collision_movement_dot_product <= 0.0
				collision_velocity_dot_product = collision_normal.dot(velocity)
				is_velocity_towards_surface = collision_velocity_dot_product <= 0.0
			# Cancel out movement towards the surface of the collision
			if is_movement_towards_surface:
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
					is_velocity_towards_surface = collision_velocity_dot_product <= 0.0
			# Cancel out velocity towards the surface of the collision
			if is_velocity_towards_surface:
				var velocity_towards_surface := collision_velocity_dot_product * collision_normal
				velocity -= velocity_towards_surface
			# Record debug info about collisions for drawing arrows
			_debug_info.collisions.append({
				contact_position = collision_contact_position,
				normal = collision_normal,
				surface_type = collision_surface_type
			})
		# Continue with the remaining movement
		movement = movement_remaining
	# If we don't have a floor, we could be standing in a crevasse
	if (not _is_on_floor or _reused_floor_from_last_frame) and upward_facing_normals.size() >= 2:
		for i in range(upward_facing_normals.size()):
			for j in range(i + 1, upward_facing_normals.size()):
				# If we find two normals pointing towards one another, we pretend there's a floor
				if upward_facing_normals[i].angle_to(upward_facing_normals[j]) >= PI - MAX_CREVASSE_ANGLE:
					var collision_normal := _up
					_was_previously_on_floor = _is_on_floor
					_previous_floor_normal = _floor_normal
					_is_on_floor = true
					_floor_normal = collision_normal
					_reused_floor_from_last_frame = false
					var collision_velocity_dot_product := collision_normal.dot(velocity) # Positive if velocity is away from the surface
					var is_velocity_towards_surface := collision_velocity_dot_product <= 0.0
					if is_velocity_towards_surface:
						var velocity_towards_surface := collision_velocity_dot_product * collision_normal
						velocity -= velocity_towards_surface
					break
			if _is_on_floor and not _reused_floor_from_last_frame:
				break


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
	# Record debug info for drawing arrows
	var _debug_info := {
		move_direction = movement.normalized(),
		move_distance = collision_info.get_travel().length(),
		collisions = []
	}
	_debug_movement_steps_info.append(_debug_info)
	# Handle collisions
	for i in range(collision_info.get_collision_count()):
		var collision_contact_position := collision_info.get_position(i) # global
		var collision_normal := collision_info.get_normal(i)
		var collision_angle := collision_normal.angle_to(_up)
		var vector_from_feet_to_collision := collision_contact_position - global_position
		var height_of_collision := vector_from_feet_to_collision.dot(_up)
		# Check if we've moved off of a cliff
		_surface_edge_ray_cast.check_collision_type(collision_contact_position, collision_normal, MathUtils.project_vector_onto_plane(_last_planar_movement_direction, _up).normalized(), _up)
		if _surface_edge_ray_cast.is_edge_of_cliff():
			continue
		# TODO consider using the surface that SurfaceEdgeRayCast found as the floor normal
		# Check if this surface could qualify as a floor
		if not (collision_angle <= _max_floor_angle and height_of_collision <= 0.5 * _collider_height):
			continue
		# If the surface a little bit forward isn't horizontal enough to qualify as a floor, it means we moved off of a cliff
		var floor_edge_cast_normal := _surface_edge_ray_cast.get_collision_normal()
		var floor_edge_cast_angle := floor_edge_cast_normal.angle_to(_up)
		if not (floor_edge_cast_angle <= _max_floor_angle):
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
		var is_velocity_towards_surface := collision_velocity_dot_product <= 0.0
		if is_velocity_towards_surface:
			var velocity_towards_surface := collision_velocity_dot_product * collision_normal
			velocity -= velocity_towards_surface
		# Record debug info about collisions for drawing arrows
		_debug_info.collisions.append({
			contact_position = collision_contact_position,
			normal = collision_normal,
			surface_type = CollisionSurfaceType.FLOOR
		})
		# Only process the first floor we encounter
		break
	# Undo the movement if we didn't find any floor
	if not _is_on_floor or _reused_floor_from_last_frame:
		var undo_movement := -collision_info.get_travel()
		var collision_info_2 := move_and_collide(undo_movement)
		var _debug_info_2 := {
			move_direction = -movement.normalized(),
			move_distance = undo_movement.length() if not collision_info_2 else collision_info_2.get_travel().length(),
			collisions = []
		}
		_debug_movement_steps_info.append(_debug_info_2)


func _draw_debug_info_and_arrows() -> void:
	# Draw an arrow between the current and previous character positions
	var position_change_arrow_color: Color
	if _reused_floor_from_last_frame:
		position_change_arrow_color = Color.MEDIUM_SPRING_GREEN
	elif _is_on_floor:
		position_change_arrow_color = Color.MIDNIGHT_BLUE
	else:
		position_change_arrow_color = Color.MEDIUM_VIOLET_RED
	var new_debug_position = global_position + 0.05 * _up
	DebugArrowDrawer.draw_arrow_between(_previous_debug_position, new_debug_position, position_change_arrow_color, 0.1, 5.0)
	_previous_debug_position = new_debug_position
	# Draw arrows to show the individual move steps
	var previous_arrow_start_position := _get_global_center_position()
	for i in range(_debug_movement_steps_info.size() - 1, -1, -1):
		var debug_info := _debug_movement_steps_info[i]
		var arrow_direction := debug_info.move_direction as Vector3
		var arrow_length := 0.055 + 4.0 * (debug_info.move_distance as float)
		var arrow_color := MOVE_STEP_DEBUG_ARROW_COLORS[clampf(i, 0, MOVE_STEP_DEBUG_ARROW_COLORS.size())]
		var arrow_end := previous_arrow_start_position
		var arrow_start := arrow_end - arrow_length * arrow_direction
		DebugArrowDrawer.draw_arrow_between_for_frames(arrow_start, arrow_end, arrow_color, 0.25, 1)
		for collision in (debug_info.collisions as Array[Dictionary]):
			var angle := rad_to_deg(arrow_direction.angle_to(collision.normal))
			var offset := Vector3.ZERO
			if angle < 15.0 or angle > 165.0:
				offset = 0.01 * MathUtils.get_any_perpendicular_vector(arrow_direction)
			DebugArrowDrawer.draw_arrow_for_frames(arrow_end + offset, 0.1 * collision.normal, arrow_color, 0.1, 1)
			DebugArrowDrawer.draw_arrow_for_frames(collision.contact_position, 0.1 * collision.normal, arrow_color, 0.1, 1)
		previous_arrow_start_position = arrow_start
	DebugArrowDrawer.draw_arrow_for_frames(global_position + (_collider_height + 0.1) * _up, 0.15 * _last_planar_movement_direction, Color.BLACK, 1.0, 1)


func _get_global_center_position() -> Vector3:
	return global_position + 0.5 * _collider_height * _up
