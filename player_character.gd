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
const COLLISION_SURFACE_SEPARATION_AMOUNT := 0.0001
const FLOOR_CHECK_WIGGLE_AMOUNT := 0.01

@export var move_speed := 5.0
@export var mouse_look_sensitivity := 1.0
@export var jump_velocity := 10.0
@export_range(0.0, 90.0, 0.001, "radians") var max_floor_angle := 45.0 * PI / 180.0
@export_range(0.0, 180.0, 0.001, "radians") var min_wall_angle := 80.0 * PI / 180.0
@export_range(0.0, 180.0, 0.001, "radians") var max_wall_angle := 135.0 * PI / 180.0
@export_range(0.0, 180.0, 0.001, "radians") var max_floor_stick_angle_change := 15.0 * PI / 180.0

@onready var look_yaw_pivot := %LookYawPivot as Node3D
@onready var look_pitch_pivot := %LookPitchPivot as Node3D
@onready var floor_edge_cast := %FloorEdgeCast as RayCast3D
@onready var debug_label := %DebugLabel as Label3D

var _up: Vector3 # The character's up vector
var _facing_basis: Basis # The direction the camera is facing, ignoring pitch
var _look_basis: Basis # The direction the camera is facing, including pitch
var _move_basis: Basis # The character's movement basis, might not be orthonormal when moving on a slope
var _inverse_move_basis: Basis
var _height := 0.98
var _is_on_floor := false
var _floor_contact_position: Vector3
var _floor_normal: Vector3
var _was_on_floor := false
var _prev_floor_normal: Vector3
var _prev_inverse_move_basis: Basis
var _basis_x_debug_arrow: DebugArrow
var _basis_y_debug_arrow: DebugArrow
var _basis_z_debug_arrow: DebugArrow
var _velocity_debug_arrow: DebugArrow
var _just_jumped := false


func _ready() -> void:
	_basis_x_debug_arrow = DebugArrowDrawer.draw_arrow(global_position + 0.5 * Vector3.UP, Vector3.ZERO, Color.RED, 1.0, -1.0, self)
	_basis_y_debug_arrow = DebugArrowDrawer.draw_arrow(global_position + 0.5 * Vector3.UP, Vector3.ZERO, Color.GREEN, 1.0, -1.0, self)
	_basis_z_debug_arrow = DebugArrowDrawer.draw_arrow(global_position + 0.5 * Vector3.UP, Vector3.ZERO, Color.BLUE, 1.0, -1.0, self)
	_velocity_debug_arrow = DebugArrowDrawer.draw_arrow(global_position + 0.5 * Vector3.UP, velocity, Color.YELLOW, 1.5, -1.0, self)


func _input(event: InputEvent) -> void:
	# Use the mouse to look around
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var look_change := Vector2(event.relative.x, -event.relative.y) * mouse_look_sensitivity # -x = look left / +x = look right / -y = look down / +y = look up
		# Look left/right
		look_yaw_pivot.rotation_degrees.y -= look_change.x
		# Look up/down
		look_pitch_pivot.rotation_degrees.x = clampf(look_pitch_pivot.rotation_degrees.x + look_change.y, -89.9, 89.9)


func _physics_process(delta: float) -> void:
	var global_position_at_frame_start := global_position
	_just_jumped = false
	_calculate_and_set_bases_and_vectors()
	_apply_movement_to_velocity()
	_apply_gravity_to_velocity(delta)
	_check_for_jump()
	_reset_floor()
	_move_in_multiple_steps(velocity * delta, true)
	_stick_to_floor()
	_draw_debug_arrows(global_position_at_frame_start)
	_draw_debug_info()


func _calculate_and_set_bases_and_vectors() -> void:
	_up = global_basis.y.normalized()
	_facing_basis = look_yaw_pivot.global_basis.orthonormalized()
	_look_basis = look_pitch_pivot.global_basis.orthonormalized()
	if _is_on_floor:
		var move_right := VectorUtils.project_vector_onto_slope(_facing_basis.x, _floor_normal, _up).normalized()
		var move_back := VectorUtils.project_vector_onto_slope(_facing_basis.z, _floor_normal, _up).normalized()
		_move_basis = Basis(move_right, _up, move_back)
	else:
		_move_basis = _facing_basis
	_inverse_move_basis = _move_basis.inverse()


func _apply_movement_to_velocity() -> void:
	if _is_on_floor:
		var move_input := Input.get_vector("move_left", "move_right", "move_backward", "move_forward") # Max 1.0 length
		var move_basis_velocity := _inverse_move_basis * velocity # Velocity taking into account the slope of the floor (if grounded)
		move_basis_velocity.x = move_basis_velocity.x * 0.99 + move_speed * move_input.x * 0.01
		move_basis_velocity.z = move_basis_velocity.z * 0.99 + move_speed * -move_input.y * 0.01
		velocity = _move_basis * move_basis_velocity
	
	
func _apply_gravity_to_velocity(delta: float) -> void:
	var gravity_vector := get_gravity() * delta
	# When on a floor, the character resists gravity that'd pull them down/up/across the slope of the floor
	if _is_on_floor:
		gravity_vector = gravity_vector.project(_floor_normal)
	velocity += gravity_vector


func _check_for_jump() -> void:
	if _is_on_floor and Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity
		_just_jumped = true


func _reset_floor() -> void:
	_was_on_floor = _is_on_floor
	_prev_floor_normal = _floor_normal
	_prev_inverse_move_basis = _inverse_move_basis
	_is_on_floor = false
	_floor_contact_position = Vector3.ZERO
	_floor_normal = Vector3.ZERO


func _set_floor(is_on_floor: bool, contact_position := Vector3.ZERO, normal := Vector3.ZERO) -> void:
	if _is_on_floor:
		_was_on_floor = _is_on_floor
		_prev_floor_normal = _floor_normal
		_prev_inverse_move_basis = _inverse_move_basis
	_is_on_floor = is_on_floor
	_floor_contact_position = contact_position
	_floor_normal = normal


func _move_in_multiple_steps(movement: Vector3, affects_velocity: bool) -> void:
	for i in range(MAX_MOVE_STEPS_PER_FRAME):
		# Try moving the full distance, get back the remaining movement
		movement = _move_in_one_step(movement, affects_velocity)
		# Stop when we're out of movement
		if movement.is_zero_approx():
			break


func _move_in_one_step(movement: Vector3, affects_velocity: bool) -> Vector3:
	if movement.is_zero_approx():
		print("Skipping movement since it's approximately zero")
		return Vector3.ZERO
	var movement_facing_direction := VectorUtils.project_vector_onto_plane(movement, _up).normalized()
	# Attempt to move the full distance
	var collision_info := move_and_collide(movement)
	# If there were no collisions it means we were able to move the full distance and there's no movement remaining
	if not collision_info:
		return Vector3.ZERO
	# If there are collisions, it means we weren't able to move the full distance
	var movement_remaining := collision_info.get_remainder()
	# Handle each collision
	for i in range(collision_info.get_collision_count()):
		var collision_surface_type := CollisionSurfaceType.NONE
		var collision_contact_position := collision_info.get_position(i) # global
		var collision_normal := collision_info.get_normal(i)
		#var collider_velocity := collision_info.get_collider_velocity(i)
		var collision_angle := collision_normal.angle_to(_up)
		var vector_from_feet_to_collision := collision_contact_position - global_position
		var height_of_collision := vector_from_feet_to_collision.dot(_up)
		var collision_movement_dot_product := collision_normal.dot(movement_remaining) # Positive if moving away from the surface
		var is_movement_away_from_surface := collision_movement_dot_product > 0.0
		var collision_velocity_dot_product := collision_normal.dot(velocity) # Positive if velocity is away from the surface
		var is_velocity_away_from_surface := collision_velocity_dot_product > 0.0
		# Cancel out movement towards the surface of the collision
		if not is_movement_away_from_surface:
			var movement_towards_surface := collision_movement_dot_product * collision_normal
			movement_remaining -= movement_towards_surface
			# Also apply a small amount of movement away from the surface of the collision, to separate them a bit
			movement_remaining += COLLISION_SURFACE_SEPARATION_AMOUNT * collision_normal
		# Check if this surface could qualify as a floor
		if collision_angle <= max_floor_angle and height_of_collision <= 0.5 * _height:
			# Normal floor stuff
			collision_surface_type = CollisionSurfaceType.FLOOR
			# Set this surface as the new floor
			_set_floor(true, collision_contact_position, collision_normal)
			_calculate_and_set_bases_and_vectors()
			if _was_on_floor and _floor_normal != _prev_floor_normal:
				var old_move_basis_velocity := _prev_inverse_move_basis * velocity
				var new_velocity := _move_basis * old_move_basis_velocity
				velocity = new_velocity
				#var new_move_basis_velocity := _inverse_move_basis * velocity
				#print("%s to %s" % [old_move_basis_velocity, new_move_basis_velocity])
				collision_velocity_dot_product = collision_normal.dot(velocity) # Positive if velocity is away from the surface
				is_velocity_away_from_surface = collision_velocity_dot_product > 0.0
			## Floors are treated as perfectly horizontal, so we override the collision normal
			#collision_normal = _up
			#collision_angle = 0.0 # 0°
			#collision_movement_dot_product = collision_normal.dot(movement_remaining)
			#is_movement_away_from_surface = collision_movement_dot_product > 0.0
			#collision_velocity_dot_product = collision_normal.dot(velocity)
			#is_velocity_away_from_surface = collision_velocity_dot_product > 0.0
		# Check if we're moving away from the surface, in which case this is an "incidental" collision
		elif is_movement_away_from_surface or is_velocity_away_from_surface:
			collision_surface_type = CollisionSurfaceType.INCIDENTAL
		# Check if this surface is too shallow to qualify as a wall, in which case it's a slope
		elif collision_angle < min_wall_angle:
			collision_surface_type = CollisionSurfaceType.SLOPE
		# Check if this surface is a wall
		elif collision_angle <= max_wall_angle:
			collision_surface_type = CollisionSurfaceType.WALL
			## Walls are treated as perfectly vertical, so we override the collision normal
			#collision_normal = VectorUtils.project_vector_onto_plane(collision_normal, _up).normalized()
			#collision_angle = PI / 2.0 # 90°
			#collision_movement_dot_product = collision_normal.dot(movement_remaining)
			#is_movement_away_from_surface = collision_movement_dot_product > 0.0
			#collision_velocity_dot_product = collision_normal.dot(velocity)
			#is_velocity_away_from_surface = collision_velocity_dot_product > 0.0
		# Otherwise this surface is a ceiling
		else:
			collision_surface_type = CollisionSurfaceType.CEILING
			## Ceilings are treated as perfectly horizontal, so we override the collision normal
			#collision_normal = -_up
			#collision_angle = PI # 180°
			#collision_movement_dot_product = collision_normal.dot(movement_remaining)
			#is_movement_away_from_surface = collision_movement_dot_product > 0.0
			#collision_velocity_dot_product = collision_normal.dot(velocity)
			#is_velocity_away_from_surface = collision_velocity_dot_product > 0.0
		# Cancel out velocity towards the surface of the collision
		#if collision_surface_type != CollisionSurfaceType.FLOOR:
		if affects_velocity and not is_velocity_away_from_surface:
			var velocity_towards_surface := collision_velocity_dot_product * collision_normal
			velocity -= velocity_towards_surface
			#DebugArrowDrawer.draw_arrow(collision_contact_position, -velocity_towards_surface, Color.RED, 0.5, 1.0)
		var debug_arrow_color: Color
		match collision_surface_type:
			CollisionSurfaceType.FLOOR: debug_arrow_color = Color.AQUA
			CollisionSurfaceType.SLOPE: debug_arrow_color = Color.HOT_PINK
			CollisionSurfaceType.WALL: debug_arrow_color = Color.SADDLE_BROWN
			CollisionSurfaceType.CEILING: debug_arrow_color = Color.ORANGE
			_: debug_arrow_color = Color.BLACK
		DebugArrowDrawer.draw_arrow(collision_contact_position, collision_normal * 0.25, debug_arrow_color, 0.5, 1.0)
	return movement_remaining


#func _handle_floor_collision(collision_contact_position: Vector3, collision_normal: Vector3, collider_velocity: Vector3) -> void:
	## Make sure the floor is within range
	#var floor_stand_position := _calculate_floor_stand_position(collision_contact_position, collision_normal)
	#var vector_from_floor_to_detection_end_point := _floor_detection_end_point.global_position - floor_stand_position
	#var is_within_detection_range := vector_from_floor_to_detection_end_point.dot(_up) <= 0.0
	#if not is_within_detection_range:
		#return
	## Figure out if we're moving away from the floor
	#var velocity_normal := velocity.project(collision_normal)
	#var surface_velocity_normal := collider_velocity.project(collider_velocity)
	#var total_velocity_normal := velocity_normal - surface_velocity_normal
	#var is_moving_away_from_collision := total_velocity_normal.dot(collision_normal) > 0.0
	## Figure out if the floor is above our feet
	#var vector_from_floor_to_feet := global_position - floor_stand_position
	#var is_floor_above_feet := vector_from_floor_to_feet.dot(_up) <= 0.0
	## Figure out if we could stand on the floor
	#var could_stand_on_floor := _was_standing_on_floor or (is_floor_above_feet and not is_moving_away_from_collision)
	## Figure out if it's closer to our feet than the other floor option
	#var is_higher_up_than_previous_floor := true
	#if _is_in_contact_with_floor:
		#var vector_from_previous_floor_to_feet := global_position - _floor_stand_position
		#var distance_from_previous_floor_to_feet := vector_from_previous_floor_to_feet.dot(_up)
		#var distance_from_floor_to_feet = vector_from_floor_to_feet.dot(_up)
		#is_higher_up_than_previous_floor = distance_from_floor_to_feet <= distance_from_previous_floor_to_feet
		##Debug.draw_arrow_between(_floor_stand_position + 0.5 * _up, floor_stand_position + 0.5 * _up, Color.GREEN if is_higher_up_than_previous_floor else Color.RED, 0.1)
	#if (could_stand_on_floor and (not _is_standing_on_floor or is_higher_up_than_previous_floor)) or (not could_stand_on_floor and not _is_standing_on_floor and is_higher_up_than_previous_floor):
		#_is_standing_on_floor = could_stand_on_floor
		#_is_in_contact_with_floor = true
		#_floor_contact_position = collision_contact_position
		#_floor_normal = collision_normal
		#_floor_velocity = collider_velocity
		#_floor_stand_position = floor_stand_position
	## Allow jumping even when we just graze a floor without ever standing on it
	#_floor_contact_jump_buffer.start()


#func _calculate_floor_stand_position(collision_contact_position: Vector3, collision_normal: Vector3) -> Vector3:
	#var vector_from_contact_to_feet := global_position - collision_contact_position
	#if vector_from_contact_to_feet.is_zero_approx():
		#return collision_contact_position
	#var vector_from_contact_to_feet_up_component := vector_from_contact_to_feet.project(_up)
	#var vector_from_contact_to_feet_towards_component := vector_from_contact_to_feet - vector_from_contact_to_feet_up_component
	#if vector_from_contact_to_feet_towards_component.is_zero_approx():
		#return collision_contact_position
	#var vector_from_contact_to_feet_perpendicular := _up.cross(vector_from_contact_to_feet_towards_component.normalized())
	#var normal_towards_feet := (collision_normal - collision_normal.project(vector_from_contact_to_feet_perpendicular)).normalized()
	#var vector_from_contact_to_stand_position := Utils.project_vector_onto_slope(vector_from_contact_to_feet_towards_component, normal_towards_feet, _up)
	#return collision_contact_position + vector_from_contact_to_stand_position


func _stick_to_floor() -> void:
	if _just_jumped:
		return
	if not _was_on_floor or _is_on_floor:
		return
	#print("STICKING")
	var movement := 1.0 * -_up
	var movement_facing_direction := VectorUtils.project_vector_onto_plane(movement, _up).normalized()
	var collision_info := move_and_collide(movement)
	if not collision_info:
		return
	#var movement_remaining := collision_info.get_remainder()
	var vector_moved := collision_info.get_travel()
	for i in range(collision_info.get_collision_count()):
		#var collision_surface_type := CollisionSurfaceType.NONE
		var collision_contact_position := collision_info.get_position(i) # global
		var collision_normal := collision_info.get_normal(i)
		#var collider_velocity := collision_info.get_collider_velocity(i)
		var collision_angle := collision_normal.angle_to(_up)
		var vector_from_feet_to_collision := collision_contact_position - global_position
		var height_of_collision := vector_from_feet_to_collision.dot(_up)
		# Check if this surface could qualify as a floor
		if collision_angle <= max_floor_angle and height_of_collision <= 0.5 * _height:
			# Check if this is an edge
			var original_floor_edge_cast_position := floor_edge_cast.global_position
			# TODO make sure target_position is global
			var forward_floor_check_start_position := collision_contact_position - 0.5 * floor_edge_cast.target_position + FLOOR_CHECK_WIGGLE_AMOUNT * movement_facing_direction
			#var backward_floor_check_start_position := collision_contact_position - 0.5 * floor_edge_cast.target_position - FLOOR_CHECK_WIGGLE_AMOUNT * movement_facing_direction
			floor_edge_cast.global_position = forward_floor_check_start_position
			floor_edge_cast.force_raycast_update()
			var found_forward_floor := false
			if not floor_edge_cast.is_colliding():
				print("Treated floor as an edge since no forward surface could be found°")
				continue
			if floor_edge_cast.is_colliding():
				var floor_edge_cast_contact_position := floor_edge_cast.get_collision_point()
				var floor_edge_cast_normal := floor_edge_cast.get_collision_normal()
				var angle := floor_edge_cast_normal.angle_to(collision_normal)
				if angle > max_floor_stick_angle_change:
					print("Treated floor as an edge since angle change is %d°" % [rad_to_deg(angle)])
					continue
				#if not is_zero_approx(angle):
					#print(angle)
				#if floor_edge_cast_normal == collision_normal:
				#found_forward_floor = true
				#var angle_between := collision_normal.angle_to(floor_edge_cast_normal)
				#if not is_zero_approx(angle_between):
					#print(angle_between)
			#if not found_forward_floor:
				#print("No forward floor")
			#floor_edge_cast.global_position = original_floor_edge_cast_position
			#_move_in_one_step(floor_cast.target_position, true) # TODO Might need to make sure target_position is in global space
			#for i in range(floor_cast.get_collision_count()):
				#var collision_contact_position := floor_cast.get_collision_point(i)
				#var collision_normal := floor_cast.get_collision_normal(i)
				##var collider_velocity := Utils.get_object_velocity(floor_cast.get_collider(i))
				##_handle_collision(collision_contact_position, collision_normal, collider_velocity)
				#print(collision_normal
			_set_floor(true, collision_contact_position, collision_normal)
			_calculate_and_set_bases_and_vectors()
			if _was_on_floor and _floor_normal != _prev_floor_normal:
				var old_move_basis_velocity := _prev_inverse_move_basis * velocity
				var new_velocity := _move_basis * old_move_basis_velocity
				velocity = new_velocity
				#var new_move_basis_velocity := _inverse_move_basis * velocity
			#print("STUCK")
			break
	if not _is_on_floor:
		move_and_collide(-vector_moved)


func _draw_debug_arrows(previous_global_position: Vector3) -> void:
	var move_basis_velocity := _inverse_move_basis * velocity
	_basis_x_debug_arrow.direction = _move_basis.x * (1.0 if move_basis_velocity.x >= 0.0 else -1.0)
	_basis_y_debug_arrow.direction = _move_basis.y * (1.0 if move_basis_velocity.y >= 0.0 else -1.0)
	_basis_z_debug_arrow.direction = _move_basis.z * (1.0 if move_basis_velocity.z >= 0.0 else -1.0)
	_basis_x_debug_arrow.length = 0.1 * abs(move_basis_velocity.x)
	_basis_y_debug_arrow.length = 0.1 * abs(move_basis_velocity.y)
	_basis_z_debug_arrow.length = 0.1 * abs(move_basis_velocity.z)
	_basis_x_debug_arrow.visible = not is_zero_approx(move_basis_velocity.x)
	_basis_y_debug_arrow.visible = not is_zero_approx(move_basis_velocity.y)
	_basis_z_debug_arrow.visible = not is_zero_approx(move_basis_velocity.z)
	var color: Color
	if _is_on_floor:
		color = Color.BLUE
	else:
		color = Color.RED
	DebugArrowDrawer.draw_arrow_between(previous_global_position, global_position, color, 0.5, 10.0)


func _draw_debug_info() -> void:
	var move_basis_velocity := _inverse_move_basis * velocity
	var speed := move_basis_velocity.length()
	var vspeed := absf(move_basis_velocity.y)
	var hspeed := Vector3(move_basis_velocity.x, 0.0, move_basis_velocity.z).length()
	debug_label.text = "speed=%f\nhspeed=%f\nvspeed=%f\nx=%f\ny=%f\nz=%f" % [speed, hspeed, vspeed, move_basis_velocity.x, move_basis_velocity.y, move_basis_velocity.z]
