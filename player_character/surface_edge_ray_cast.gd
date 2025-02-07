class_name SurfaceEdgeRayCast
extends RayCast3D
## A ray cast for detecting the edges of surfaces.


enum CollisionType {
	NONE = -1,
	FLAT_SURFACE = 0,
	EDGE_OF_SURFACE = 1,
	STEP_UP_TO_SURFACE = 2,
	STEP_DOWN_TO_SURFACE = 3,
	EDGE_OF_CLIFF = 4
}

const SCOOT_DISTANCE := 0.01
const MAX_FLAT_SURFACE_ANGLE := deg_to_rad(0.1)

@export var step_up_height_target: Node3D
@export var draw_debug_arrows := false

var _collision_type := CollisionType.NONE
var _edge_contact_point: Vector3
var _edge_normal: Vector3
var _surface_contact_point: Vector3
var _surface_normal: Vector3


func check_collision_type(contact_point: Vector3, normal: Vector3, scoot_direction: Vector3, up: Vector3) -> void:
	# Start by assuming we're on a cliff (no surface detected)
	_collision_type = CollisionType.EDGE_OF_CLIFF
	_edge_contact_point = contact_point
	_edge_normal = normal
	_surface_contact_point = Vector3.ZERO
	_surface_normal = Vector3.ZERO
	# Perform a raycast, but scoot it slightly "ahead" of the contact position to check for surfaces
	var original_global_position := global_position
	var position_above_original_contact_point := global_position + MathUtils.project_vector_onto_plane(contact_point - global_position, up) 
	global_position = position_above_original_contact_point + SCOOT_DISTANCE * scoot_direction
	force_raycast_update()
	# If we get a hit, that's our surface
	if is_colliding():
		_surface_contact_point = get_collision_point()
		_surface_normal = get_collision_normal()
		# If the surface is high enough to require stepping up, it's a step up
		if (_surface_contact_point - step_up_height_target.global_position).dot(up) >= 0.0:
			_collision_type = CollisionType.STEP_UP_TO_SURFACE
		# If the surface and edge are right next to each other, we're either on an edge or a flat surface
		elif _surface_contact_point.distance_to(_edge_contact_point) <= 2.0 * SCOOT_DISTANCE:
			_collision_type = CollisionType.FLAT_SURFACE if _surface_normal.angle_to(normal) <= MAX_FLAT_SURFACE_ANGLE else CollisionType.EDGE_OF_SURFACE
		# Otherwise the surface must be a step down
		else:
			_collision_type = CollisionType.STEP_DOWN_TO_SURFACE
	if draw_debug_arrows:
		if is_edge_of_cliff():
			DebugArrowDrawer.draw_arrow_for_frames(global_position, MathUtils.to_global_direction(target_position, self), Color.DIM_GRAY, 0.1, 1)
		else:
			var color: Color
			match _collision_type:
				CollisionType.FLAT_SURFACE: color = Color.FOREST_GREEN
				CollisionType.EDGE_OF_SURFACE: color = Color.DEEP_PINK
				CollisionType.STEP_UP_TO_SURFACE: color = Color.TOMATO
				CollisionType.STEP_DOWN_TO_SURFACE: color = Color.DODGER_BLUE
			DebugArrowDrawer.draw_arrow_for_frames(get_surface_contact_point(), 0.25 * get_surface_normal(), color, 0.2, 1)
	global_position = original_global_position


func get_collision_type() -> CollisionType:
	return _collision_type


func is_flat_surface() -> bool:
	return _collision_type == CollisionType.FLAT_SURFACE


func is_edge_of_surface() -> bool:
	return _collision_type == CollisionType.EDGE_OF_SURFACE


func is_step_up_to_surface() -> bool:
	return _collision_type == CollisionType.STEP_UP_TO_SURFACE


func is_step_down_to_surface() -> bool:
	return _collision_type == CollisionType.STEP_DOWN_TO_SURFACE


func is_edge_of_cliff() -> bool:
	return _collision_type == CollisionType.EDGE_OF_CLIFF


func get_edge_contact_point() -> Vector3:
	return _edge_contact_point


func get_edge_normal() -> Vector3:
	return _edge_normal


func get_surface_contact_point() -> Vector3:
	return _surface_contact_point


func get_surface_normal() -> Vector3:
	return _surface_normal
