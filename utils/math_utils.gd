class_name MathUtils


static func sign_or_1(value: float):
	var x := signf(value)
	return 1.0 if x == 0.0 else x


static func project_vector_onto_slope(vector: Vector3, slope_normal: Vector3, up: Vector3 = Vector3.UP) -> Vector3:
	# If the "slope" is perfectly horizontal (releative to the up vector) the calculation is pretty trivial
	if slope_normal.dot(up) >= 1.0:
		return vector
	# Calculate properties of the slope
	var perpendicular_to_slope := up.cross(slope_normal).normalized() # Runs perpendicular to the slope (left/right)
	var parallel_down_slope := perpendicular_to_slope.cross(slope_normal).normalized() # Runs down the slope
	var parallel_down_slope_vertical_component := parallel_down_slope.project(up)
	var parallel_down_slope_horizontal_component := parallel_down_slope - parallel_down_slope_vertical_component
	# Work out where the vector is on the slope
	var vector_perpendicular_to_slope := vector.project(perpendicular_to_slope)
	var vector_not_perpendicular_to_slope := vector - vector_perpendicular_to_slope
	var vector_parallel_to_slope := (vector_not_perpendicular_to_slope.length() / parallel_down_slope_horizontal_component.length()) * parallel_down_slope * (1.0 if vector.dot(parallel_down_slope) >= 0.0 else -1.0)
	return vector_parallel_to_slope + vector_perpendicular_to_slope


static func project_vector_onto_plane(vector: Vector3, plane_normal: Vector3) -> Vector3:
	return vector - vector.project(plane_normal)


static func to_global_direction(local_direction: Vector3, node: Node3D) -> Vector3:
	return node.to_global(local_direction) - node.global_position


static func to_local_direction(global_direction: Vector3, node: Node3D) -> Vector3:
	return node.to_local(node.global_position + global_direction)


static func get_any_perpendicular_vector(vector: Vector3) -> Vector3:
	var angle_to_up := vector.angle_to(Vector3.UP)
	if angle_to_up < 15.0 or angle_to_up > 165.0:
		return vector.cross(Vector3.FORWARD).normalized()
	else:
		return vector.cross(Vector3.UP).normalized()
